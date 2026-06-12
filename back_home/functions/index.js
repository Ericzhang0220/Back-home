"use strict";

const { initializeApp } = require("firebase-admin/app");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

initializeApp();

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const defaultModel = "gemini-3.1-flash-lite";

exports.askTutor = onCall(
  {
    region: "us-central1",
    secrets: [geminiApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    const sessionTitle = readString(request.data?.sessionTitle, 120);
    const messages = readMessages(request.data?.messages);

    if (messages.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "askTutor requires at least one message.",
      );
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "GEMINI_API_KEY has not been configured.",
      );
    }

    const model = process.env.GEMINI_MODEL || defaultModel;
    const response = await callGemini({
      apiKey,
      model,
      sessionTitle,
      messages,
    });

    return {
      text: response,
      model,
    };
  },
);

async function callGemini({ apiKey, model, sessionTitle, messages }) {
  const url =
    "https://generativelanguage.googleapis.com/v1beta/models/" +
    `${encodeURIComponent(model)}:generateContent?key=${apiKey}`;

  const body = {
    systemInstruction: {
      parts: [
        {
          text:
            "You are the Back Home tutor. Be warm, concise, and practical. " +
            "Help the student turn vague stress into concrete next steps. " +
            "Do not claim to be a therapist, doctor, or emergency service. " +
            "If the user mentions immediate danger or self-harm, encourage " +
            "them to contact local emergency help or a trusted person now.",
        },
      ],
    },
    contents: messages.map((message) => ({
      role: message.role === "assistant" ? "model" : "user",
      parts: [{ text: message.text }],
    })),
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 420,
    },
  };

  if (sessionTitle) {
    body.contents.unshift({
      role: "user",
      parts: [{ text: `Conversation topic: ${sessionTitle}` }],
    });
  }

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const json = await response.json().catch(() => ({}));

  if (!response.ok) {
    logger.error("Gemini request failed", {
      status: response.status,
      message: json?.error?.message,
    });
    throw new HttpsError(
      "internal",
      "Gemini request failed. Check function logs for details.",
    );
  }

  const text = json?.candidates?.[0]?.content?.parts
    ?.map((part) => part.text)
    .filter(Boolean)
    .join("\n")
    .trim();

  if (!text) {
    logger.error("Gemini response did not include text", { response: json });
    throw new HttpsError("internal", "Gemini returned an empty response.");
  }

  return text;
}

function readMessages(value) {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "messages must be an array.");
  }

  return value.slice(-12).map((item, index) => {
    const role = readString(item?.role, 20);
    const text = readString(item?.text, 2000);

    if (role !== "user" && role !== "assistant") {
      throw new HttpsError(
        "invalid-argument",
        `messages[${index}].role must be user or assistant.`,
      );
    }

    if (!text) {
      throw new HttpsError(
        "invalid-argument",
        `messages[${index}].text is required.`,
      );
    }

    return { role, text };
  });
}

function readString(value, maxLength) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, maxLength);
}
