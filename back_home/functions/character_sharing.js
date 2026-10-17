"use strict";

// All source documents and transcripts are scoped to the authenticated sender.
// Human recipients receive a character snapshot, never the sender's transcript.
function createCharacterSharing({ db, FieldValue, HttpsError, readId, readString }) {
  const user = (uid) => db.collection("users").doc(uid);
  const character = (uid, id) => user(uid).collection("aiCharacters").doc(id);
  const fail = (code, message) => { throw new HttpsError(code, message); };
  const chatId = (a, b) => [a, b].sort().join("_");

  function cardFor(id, data, uid) {
    return {
      id,
      name: readString(data.name, 60) || "Companion",
      personality: readString(data.personality, 400),
      introduction: readString(data.introduction, 1000),
      preview: readString(data.preview, 200),
      iconKey: readString(data.iconKey, 40) || "heart",
      colorValue: Number.isInteger(data.colorValue) ? data.colorValue : 0xfff5c7cc,
      gender: ["male", "female"].includes(data.gender) ? data.gender : "unspecified",
      tags: Array.isArray(data.tags) ? data.tags.filter((t) => typeof t === "string").slice(0, 20) : [],
      avatarUrl: readString(data.avatarUrl, 4096) || null,
      authorUid: readString(data.authorUid, 128) || (data.isCustom ? uid : null),
      isCustom: false,
      isPublic: false,
    };
  }

  async function share(uid, input) {
    const sourceId = readId(input?.characterId, "characterId");
    const targetId = readId(input?.recipientId, "recipientId");
    const requestId = readId(input?.requestId, "requestId");
    const isAi = input?.recipientKind === "ai";
    if (!["ai", "human"].includes(input?.recipientKind) ||
        (isAi ? targetId === sourceId : targetId === uid)) {
      fail("invalid-argument", "Choose another AI or person.");
    }
    const sourceRef = character(uid, sourceId);
    const targetRef = isAi ? character(uid, targetId) : user(targetId);
    const parent = isAi ? user(uid).collection("aiChats").doc(targetId) :
      db.collection("chats").doc(chatId(uid, targetId));
    return db.runTransaction(async (tx) => {
      const [source, target, chat] = await Promise.all([
        tx.get(sourceRef), tx.get(targetRef), tx.get(parent),
      ]);
      if (!source.exists || !target.exists) fail("not-found", "Character or recipient is no longer available.");
      const senders = Array.isArray(chat.get("senderUids")) ? chat.get("senderUids") : [];
      if (!isAi && chat.exists &&
          (![uid, targetId].every((id) => chat.get("participantUids")?.includes(id)) ||
          chat.get("participantUids")?.length !== 2)) {
        fail("permission-denied", "That conversation is unavailable.");
      }
      const opening = !isAi && !senders.includes(targetId);
      const messageRef = parent.collection("messages").doc(opening ? `intro_${uid}` : `share_${requestId}`);
      const existing = await tx.get(messageRef);
      if (existing.exists) {
        if (existing.get("shareRequestId") === requestId) return { messageId: messageRef.id };
        fail("failed-precondition", "You can send one message until they write back.");
      }
      if (opening && senders.includes(uid)) {
        fail("failed-precondition", "You can send one message until they write back.");
      }
      const card = cardFor(sourceId, source.data(), uid);
      const note = readString(input?.note, 2000);
      // The card is the message. Only an explicitly typed note appears below it.
      const text = note;
      tx.set(messageRef, {
        ...(isAi ? { role: "user" } : { senderUid: uid }),
        text, sharedCharacter: card, shareRequestId: requestId,
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.set(parent, {
        ...(isAi ? {
          characterId: targetId, isHidden: false,
          userMessageCount: FieldValue.increment(1),
        } : {
          participantUids: [uid, targetId].sort(),
          senderUids: [...new Set([...senders, uid])].sort(),
        }),
        lastMessage: `[AI card] ${card.name}${note ? ` · ${note}` : ""}`.slice(0, 200),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      if (isAi) tx.set(targetRef, { isFriend: true }, { merge: true });
      return { messageId: messageRef.id };
    });
  }

  async function adopt(uid, input) {
    const id = readId(input?.chatId, "chatId");
    const messageId = readId(input?.messageId, "messageId");
    const parent = db.collection("chats").doc(id);
    return db.runTransaction(async (tx) => {
      const chat = await tx.get(parent);
      if (!chat.exists || !chat.get("participantUids")?.includes(uid)) {
        fail("permission-denied", "You cannot open that card.");
      }
      const message = await tx.get(parent.collection("messages").doc(messageId));
      const card = message.get("sharedCharacter");
      if (!card || typeof card.id !== "string") fail("not-found", "That character card is unavailable.");
      const ref = character(uid, readId(card.id, "characterId"));
      const existing = await tx.get(ref);
      if (!existing.exists) {
        const data = { ...card };
        delete data.id;
        tx.set(ref, {
          ...data, isCustom: false, isFriend: true, isPublic: false,
          createdAt: FieldValue.serverTimestamp(),
        });
      } else {
        // Never overwrite the recipient's own edits, avatar or authorship.
        tx.set(ref, { isFriend: true }, { merge: true });
      }
      tx.set(user(uid).collection("aiChats").doc(card.id), {
        characterId: card.id, isHidden: false,
      }, { merge: true });
      return { characterId: card.id };
    });
  }

  async function context(uid, history, readHistory) {
    const shared = [...history].reverse().find((m) => m.role === "user" && m.sharedCharacter)?.sharedCharacter;
    if (!shared) return null;
    const sourceId = readId(shared.id, "characterId");
    const source = await character(uid, sourceId).get();
    const transcript = source.exists ? await readHistory(
      user(uid).collection("aiChats").doc(sourceId).collection("messages"),
    ) : [];
    return {
      character: { name: shared.name, personality: shared.personality },
      // Only this caller's conversation. No access to other users' histories.
      recentConversation: transcript.map((m) => ({ role: m.role, text: m.text })),
    };
  }

  // The model still needs a user turn for a card-only share. This description
  // exists only in model history, never as an extra visible chat message.
  function messageText(text, sharedCharacter) {
    return text || (sharedCharacter ?
      `[Shared AI character card: ${readString(sharedCharacter.name, 60) || "Companion"}]` : "");
  }

  return { share, adopt, context, messageText };
}

module.exports = { createCharacterSharing };
