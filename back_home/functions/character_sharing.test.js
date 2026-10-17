"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createCharacterSharing } = require("./character_sharing");

class Store {
  constructor() { this.docs = new Map(); }
  collection(path) { return new Ref(this, path); }
  async runTransaction(handler) {
    const writes = [];
    const result = await handler({
      get: (ref) => ref.get(),
      set: (ref, data, options) => writes.push([ref.path, data, options]),
    });
    for (const [path, data, options] of writes) {
      const previous = this.docs.get(path) || {};
      const next = options?.merge ? { ...previous } : {};
      for (const [key, value] of Object.entries(data)) {
        next[key] = value?.increment ? (previous[key] || 0) + value.increment : value;
      }
      this.docs.set(path, next);
    }
    return result;
  }
}
class Ref {
  constructor(store, path) { this.store = store; this.path = path; this.id = path.split("/").pop(); }
  doc(id) { return new Ref(this.store, `${this.path}/${id}`); }
  collection(id) { return this.doc(id); }
  async get() {
    const data = this.store.docs.get(this.path);
    return { exists: data !== undefined, data: () => data, get: (key) => data?.[key] };
  }
}
class ShareError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function fixture() {
  const db = new Store();
  db.docs.set("users/alice/aiCharacters/ava", {
    name: "Ava", personality: "Creative", isCustom: true,
    authorUid: "alice", avatarUrl: "https://example.test/ava.png",
  });
  db.docs.set("users/alice/aiCharacters/noah", { name: "Noah", personality: "Witty" });
  db.docs.set("users/bob", { displayName: "Bob" });
  const api = createCharacterSharing({
    db, HttpsError: ShareError,
    FieldValue: { serverTimestamp: () => "now", increment: (n) => ({ increment: n }) },
    readId: (value) => {
      if (typeof value !== "string" || !value || value.includes("/")) throw new ShareError("invalid-argument", "bad id");
      return value;
    },
    readString: (value, max) => typeof value === "string" ? value.trim().slice(0, max) : "",
  });
  return { db, api };
}
const request = (kind, target, requestId = "one") => ({
  characterId: "ava", recipientKind: kind, recipientId: target, requestId,
});

test("human share is a card without any transcript or public publication", async () => {
  const { db, api } = fixture();
  db.docs.set("users/alice/aiChats/ava/messages/private", { text: "Private history" });
  await api.share("alice", request("human", "bob"));
  const message = db.docs.get("chats/alice_bob/messages/intro_alice");
  assert.equal(message.text, "");
  assert.equal(message.sharedCharacter.name, "Ava");
  assert.equal(message.sharedCharacter.isCustom, false);
  assert.equal(message.sharedCharacter.authorUid, "alice");
  assert.equal(JSON.stringify(message).includes("Private history"), false);
  assert.equal([...db.docs.keys()].some((key) => key.startsWith("publicAiCharacters")), false);
});

test("retry is idempotent; sharing obeys one unanswered human message", async () => {
  const { db, api } = fixture();
  await api.share("alice", request("human", "bob"));
  const count = db.docs.size;
  await api.share("alice", request("human", "bob"));
  assert.equal(db.docs.size, count);
  await assert.rejects(api.share("alice", request("human", "bob", "two")), { code: "failed-precondition" });
  db.docs.get("chats/alice_bob").senderUids.push("bob");
  await api.share("alice", request("human", "bob", "two"));
  assert.ok(db.docs.has("chats/alice_bob/messages/share_two"));
});

test("existing unanswered text also prevents sharing a second opening message", async () => {
  const { db, api } = fixture();
  db.docs.set("chats/alice_bob", { participantUids: ["alice", "bob"], senderUids: ["alice"] });
  db.docs.set("chats/alice_bob/messages/intro_alice", { senderUid: "alice", text: "Hi" });
  await assert.rejects(api.share("alice", request("human", "bob")), { code: "failed-precondition" });
  assert.equal(db.docs.get("chats/alice_bob/messages/intro_alice").text, "Hi");
});

test("AI share writes one turn, is idempotent and reads only sender's own history", async () => {
  const { db, api } = fixture();
  await api.share("alice", request("ai", "noah"));
  await api.share("alice", request("ai", "noah"));
  const message = db.docs.get("users/alice/aiChats/noah/messages/share_one");
  assert.equal(message.text, "");
  assert.equal(db.docs.get("users/alice/aiChats/noah").userMessageCount, 1);
  assert.equal(message.role, "user");
  const context = await api.context("alice", [message], async (ref) => {
    assert.equal(ref.path, "users/alice/aiChats/ava/messages");
    return [{ role: "assistant", text: "Hello Alice" }];
  });
  assert.equal(context.character.name, "Ava");
  assert.deepEqual(context.recentConversation, [{ role: "assistant", text: "Hello Alice" }]);
  const missing = await api.context("bob", [message], async () => { throw new Error("must not read Alice's history"); });
  assert.deepEqual(missing.recentConversation, []);
});

test("card-only shares retain a model turn without adding visible boilerplate", async () => {
  const { db, api } = fixture();
  await api.share("alice", request("ai", "noah"));
  const message = db.docs.get("users/alice/aiChats/noah/messages/share_one");
  assert.equal(message.text, "");
  assert.equal(api.messageText(message.text, message.sharedCharacter), "[Shared AI character card: Ava]");
  assert.equal(api.messageText("", null), "");
  assert.equal(api.messageText("Meet Ava", message.sharedCharacter), "Meet Ava");
});

test("forwarding preserves only the sender's optional note", async () => {
  const { db, api } = fixture();
  for (const [kind, id] of [["ai", "noah"], ["human", "bob"]]) {
    await api.share("alice", { ...request(kind, id), note: "  Meet Ava  " });
  }
  assert.equal(db.docs.get("users/alice/aiChats/noah/messages/share_one").text, "Meet Ava");
  assert.equal(db.docs.get("chats/alice_bob/messages/intro_alice").text, "Meet Ava");
});

test("receiving a card creates an independent non-editable AI and no copied messages", async () => {
  const { db, api } = fixture();
  await api.share("alice", request("human", "bob"));
  await api.adopt("bob", { chatId: "alice_bob", messageId: "intro_alice" });
  const received = db.docs.get("users/bob/aiCharacters/ava");
  assert.equal(received.name, "Ava");
  assert.equal(received.isCustom, false);
  assert.equal(received.isFriend, true);
  assert.equal(received.isPublic, false);
  assert.equal([...db.docs.keys()].some((key) => key.startsWith("users/bob/aiChats/ava/messages/")), false);
  await assert.rejects(api.adopt("eve", { chatId: "alice_bob", messageId: "intro_alice" }), { code: "permission-denied" });
});

test("opening a card preserves an existing recipient character and history", async () => {
  const { db, api } = fixture();
  await api.share("alice", request("human", "bob"));
  db.docs.set("users/bob/aiCharacters/ava", { name: "My Ava", isCustom: true, authorUid: "bob", avatarUrl: "my-photo" });
  db.docs.set("users/bob/aiChats/ava/messages/old", { text: "Keep" });
  await api.adopt("bob", { chatId: "alice_bob", messageId: "intro_alice" });
  assert.equal(db.docs.get("users/bob/aiCharacters/ava").name, "My Ava");
  assert.equal(db.docs.get("users/bob/aiCharacters/ava").isCustom, true);
  assert.equal(db.docs.get("users/bob/aiCharacters/ava").avatarUrl, "my-photo");
  assert.equal(db.docs.get("users/bob/aiChats/ava/messages/old").text, "Keep");
});

test("sender cannot share another account's private character, target itself or missing recipient", async () => {
  const { api } = fixture();
  await assert.rejects(api.share("bob", request("human", "alice")), { code: "not-found" });
  await assert.rejects(api.share("alice", request("ai", "ava")), { code: "invalid-argument" });
  await assert.rejects(api.share("alice", request("human", "alice")), { code: "invalid-argument" });
  await assert.rejects(api.share("alice", request("human", "missing")), { code: "not-found" });
});
