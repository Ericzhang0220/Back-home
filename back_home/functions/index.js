"use strict";

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const OpenAI = require("openai");

initializeApp();

const db = getFirestore();

const openaiApiKey = defineSecret("OPENAI_API_KEY");
const openaiModel = defineString("OPENAI_MODEL", { default: "gpt-4o-mini" });

/** Conversation turns sent to the model as context. */
const HISTORY_LIMIT = 16;
/** Hard cap on a single user message, in characters. */
const MAX_MESSAGE_CHARS = 2000;
/** Assistant replies are kept short — this is a phone-sized chat UI. */
const MAX_OUTPUT_TOKENS = 420;
/** Per-user model calls allowed per calendar day (UTC). */
const DAILY_MESSAGE_LIMIT = 150;

const SAFETY_RULES = [
  "You are not a therapist, doctor, crisis counselor, or emergency service, and you never claim to be.",
  "If the user mentions self-harm, suicide, abuse, or immediate danger, gently and directly encourage them to contact local emergency services or a trusted adult right now. Do not attempt to counsel them through it yourself.",
  "Never give medical, legal, or financial advice. Point toward a qualified human instead.",
  "Keep replies under 150 words unless the user explicitly asks for more detail.",
].join(" ");

const TUTOR_SYSTEM_PROMPT = [
  "You are the Back Home tutor, helping a student think through schoolwork and everyday stress.",
  "Be warm, concrete, and practical. Help the student turn vague overwhelm into a small, specific next step.",
  "Prefer asking one clarifying question over guessing. When you explain something academic, show the reasoning rather than only the answer, so the student actually learns it.",
  SAFETY_RULES,
].join(" ");

const commonOptions = {
  region: "us-central1",
  secrets: [openaiApiKey],
  timeoutSeconds: 60,
  memory: "256MiB",
  // Caps runaway concurrency so a bug or abuse spike cannot run up an
  // unbounded bill on the Blaze plan.
  maxInstances: 10,
};

/**
 * Tutor chat. Reads the conversation from Firestore, asks OpenAI for the next
 * turn, then writes the reply back so every client streaming the session sees
 * it without a second round trip.
 */
exports.askTutor = onCall(commonOptions, async (request) => {
  const uid = requireAuth(request);
  const sessionId = readId(request.data?.sessionId, "sessionId");

  const sessionRef = db
    .collection("users")
    .doc(uid)
    .collection("tutorSessions")
    .doc(sessionId);

  const sessionSnapshot = await sessionRef.get();
  if (!sessionSnapshot.exists) {
    throw new HttpsError("not-found", "That tutor session does not exist.");
  }

  const messagesRef = sessionRef.collection("messages");
  const history = await readHistory(messagesRef);

  if (history.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "Send a message before asking the tutor to reply.",
    );
  }

  const title = readString(sessionSnapshot.get("title"), 120);
  const systemPrompt = title
    ? `${TUTOR_SYSTEM_PROMPT}\n\nThe student titled this conversation: "${title}".`
    : TUTOR_SYSTEM_PROMPT;

  const text = await completeChat({ uid, systemPrompt, history });

  await writeAssistantReply({ messagesRef, parentRef: sessionRef, text });

  return { text, model: openaiModel.value() };
});

/**
 * Companion-character chat. Same shape as askTutor, but the persona comes from
 * the character document the user created or was seeded with.
 */
exports.chatWithCharacter = onCall(commonOptions, async (request) => {
  const uid = requireAuth(request);
  const characterId = readId(request.data?.characterId, "characterId");

  const userRef = db.collection("users").doc(uid);
  const characterRef = userRef.collection("aiCharacters").doc(characterId);
  const chatRef = userRef.collection("aiChats").doc(characterId);

  const characterSnapshot = await characterRef.get();
  if (!characterSnapshot.exists) {
    throw new HttpsError("not-found", "That AI character does not exist.");
  }

  const messagesRef = chatRef.collection("messages");
  const history = await readHistory(messagesRef);

  if (history.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "Send a message before asking for a reply.",
    );
  }

  const name = readString(characterSnapshot.get("name"), 60) || "Companion";
  // The persona is user-authored, so it is treated as untrusted content: it
  // shapes tone only, and the safety rules are stated after it so they win.
  const personality =
    readString(characterSnapshot.get("personality"), 400) ||
    "a warm, steady friend";

  const systemPrompt = [
    `You are ${name}, a supportive AI companion inside the Back Home app, which helps students feel less alone.`,
    `Your personality: ${personality}.`,
    "Stay in character in tone and warmth, but never in a way that overrides the rules below.",
    "Talk like a friend texting back: short, natural, specific. Ask about them rather than lecturing.",
    SAFETY_RULES,
  ].join(" ");

  const text = await completeChat({ uid, systemPrompt, history });

  await writeAssistantReply({
    messagesRef,
    parentRef: chatRef,
    text,
    parentExtras: { characterId, characterName: name },
  });

  return { text, model: openaiModel.value() };
});

/** Sends the conversation to OpenAI and returns the reply text. */
async function completeChat({ uid, systemPrompt, history }) {
  await enforceDailyLimit(uid);

  const client = new OpenAI({
    apiKey: openaiApiKey.value(),
    maxRetries: 2,
  });

  const model = openaiModel.value();

  let completion;
  try {
    completion = await client.chat.completions.create({
      model,
      temperature: 0.8,
      max_tokens: MAX_OUTPUT_TOKENS,
      messages: [
        { role: "system", content: systemPrompt },
        ...history.map((message) => ({
          role: message.role,
          content: message.text,
        })),
      ],
    });
  } catch (error) {
    logger.error("OpenAI request failed", {
      status: error?.status,
      type: error?.type,
      message: error?.message,
    });

    if (error?.status === 429) {
      throw new HttpsError(
        "resource-exhausted",
        "The AI is busy right now. Try again in a moment.",
      );
    }
    if (error?.status === 401 || error?.status === 403) {
      throw new HttpsError(
        "failed-precondition",
        "The OpenAI API key is missing or invalid.",
      );
    }
    throw new HttpsError(
      "internal",
      "Could not reach the AI right now. Please try again.",
    );
  }

  const text = readString(completion.choices?.[0]?.message?.content, 4000);

  if (!text) {
    logger.error("OpenAI returned an empty completion", {
      finishReason: completion.choices?.[0]?.finish_reason,
    });
    throw new HttpsError("internal", "The AI returned an empty response.");
  }

  return text;
}

/**
 * Increments the caller's daily counter and rejects once they pass the cap.
 * Runs in a transaction so parallel sends cannot slip past the limit. The
 * counter lives under users/{uid}/private, which security rules close off to
 * clients entirely.
 */
async function enforceDailyLimit(uid) {
  const usageRef = db
    .collection("users")
    .doc(uid)
    .collection("private")
    .doc("aiUsage");

  const today = new Date().toISOString().slice(0, 10);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(usageRef);
    const isSameDay = snapshot.exists && snapshot.get("day") === today;
    const count = isSameDay ? snapshot.get("count") || 0 : 0;

    if (count >= DAILY_MESSAGE_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "You have reached today's AI message limit. It resets tomorrow.",
      );
    }

    transaction.set(
      usageRef,
      { day: today, count: count + 1, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });
}

/** Reads the trailing window of a conversation in chronological order. */
async function readHistory(messagesRef) {
  const snapshot = await messagesRef
    .orderBy("createdAt", "desc")
    .limit(HISTORY_LIMIT)
    .get();

  return snapshot.docs
    .reverse()
    .map((doc) => ({
      role: doc.get("role") === "assistant" ? "assistant" : "user",
      text: readString(doc.get("text"), MAX_MESSAGE_CHARS),
    }))
    .filter((message) => message.text.length > 0);
}

/** Persists the reply and refreshes the parent doc's preview fields. */
async function writeAssistantReply({
  messagesRef,
  parentRef,
  text,
  parentExtras = {},
}) {
  const batch = db.batch();

  batch.set(messagesRef.doc(), {
    role: "assistant",
    text,
    createdAt: FieldValue.serverTimestamp(),
  });

  batch.set(
    parentRef,
    {
      ...parentExtras,
      lastMessage: text.slice(0, 200),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await batch.commit();
}

function requireAuth(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to use the AI chats.");
  }
  return uid;
}

function readId(value, field) {
  const id = readString(value, 200);
  // Firestore document ids cannot contain slashes; rejecting them also stops
  // a caller from walking out of their own subtree via a crafted id.
  if (!id || id.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return id;
}

function readString(value, maxLength) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, maxLength);
}
