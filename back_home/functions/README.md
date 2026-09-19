# Back Home Cloud Functions

Two callables power the Chat tab's **AI** and **Tutor** pages, and a third
moderates Hall posters before publication.

| Callable | Used by | Payload |
| --- | --- | --- |
| `askTutor` | Tutor page | `{ "sessionId": "..." }` |
| `chatWithCharacter` | AI companion chats | `{ "characterId": "..." }` |
| `submitHallPost` | Hall create/edit flow | `{ "topic": "...", "message": "...", "mood": "...", "postId"?: "..." }` |

The two chat callables return `{ "text": "...", "model": "gpt-4o-mini" }`.

## Hall poster moderation

`submitHallPost` sends the topic, mood, and poster text to OpenAI's
`omni-moderation-latest` model before any new content is written publicly.
Approved posters are written to `posts/{postId}` by the Admin SDK. Flagged
posters are not published; instead, the author receives a `postRejected`
notification with the flagged safety categories. An edit is handled the same
way, so the last approved version stays visible when a proposed edit fails.

Firestore rules block direct client creation and content edits. Clients retain
access only to the existing like and thread interaction fields.

## How a turn works

The callables are **not** stateless prompt relays — they read and write the
conversation themselves:

1. The client appends the user's turn to Firestore.
2. The client calls the function with just the session/character id.
3. The function reads the last 16 messages from Firestore, calls OpenAI, and
   writes the assistant turn back.
4. The client's snapshot listener renders the reply.

This means the transcript sent to the model is server-controlled. Security
rules only let a client create messages with `role: 'user'`, so a client cannot
forge assistant turns or poison the model's context.

## Firestore layout

```
users/{uid}/aiCharacters/{characterId}          name, personality, iconKey, ...
users/{uid}/aiChats/{characterId}               lastMessage, updatedAt
users/{uid}/aiChats/{characterId}/messages/{id} role, text, createdAt
users/{uid}/tutorSessions/{sessionId}           title, subtitle, updatedAt
users/{uid}/tutorSessions/{id}/messages/{id}    role, text, createdAt
users/{uid}/private/aiUsage                     server-only rate-limit counter
```

## Setup

Requires the **Blaze** plan — Cloud Functions v2 cannot deploy on Spark.

```sh
# 1. Store the OpenAI key as a secret (never commit it)
firebase functions:secrets:set OPENAI_API_KEY

# 2. Deploy
cd back_home
firebase deploy --only functions
```

Review `../firestore.rules` before deploying it — it replaces the project's
current rules wholesale:

```sh
firebase deploy --only firestore:rules
```

## Configuration

| Setting | Where | Default |
| --- | --- | --- |
| Model | `OPENAI_MODEL` env param | `gpt-4o-mini` |
| Hall moderation model | `MODERATION_MODEL` in `index.js` | `omni-moderation-latest` |
| Daily messages per user | `DAILY_MESSAGE_LIMIT` in `index.js` | `150` |
| Daily Hall reviews per user | `DAILY_POST_MODERATION_LIMIT` in `index.js` | `50` |
| Context window | `HISTORY_LIMIT` in `index.js` | `16` messages |
| Max reply length | `MAX_OUTPUT_TOKENS` in `index.js` | `420` tokens |
| Max concurrent instances | `maxInstances` in `index.js` | `10` |

`OPENAI_MODEL` is a Firebase param, so it is set through a dotenv file in this
directory rather than a CLI flag. To switch models, create `functions/.env`:

```
OPENAI_MODEL=gpt-4o
```

Use `.env.back-home-7cf17` instead to scope the value to a single project.
Leaving the file out keeps the `gpt-4o-mini` default. Never put the API key in
these files — it belongs in Secret Manager via `functions:secrets:set`.

Note: `index.js` sends `max_tokens` and `temperature`, which the GPT-4o and
GPT-4.1 families accept. Reasoning models (o-series, GPT-5) reject both and
want `max_completion_tokens` instead, so switching to one means editing
`completeChat` as well as the env var.

## Cost controls

Because Blaze bills real money, the functions ship with three guards:

- **Per-user daily cap** — a transactional counter in
  `users/{uid}/private/aiUsage`, closed off to clients by security rules.
- **`maxInstances: 10`** — bounds concurrency so a bug or abuse spike cannot
  fan out indefinitely.
- **Bounded context and output** — 16 messages in, 420 tokens out, so a single
  turn's cost cannot grow with conversation length.

Consider also setting a budget alert on the GCP project, and a hard usage limit
on the OpenAI key itself.

## Local development

```sh
cd functions
npm install
npm run lint
firebase emulators:start --only functions,firestore
```
