# Back Home Cloud Functions

## Tutor LLM

`askTutor` is a callable Firebase Function used by the Tutor chat screen. It
calls the Gemini API with the latest Tutor conversation messages and returns:

```json
{
  "text": "Tutor response text",
  "model": "gemini-3.1-flash-lite"
}
```

Before deploying, configure the Gemini API key as a Firebase secret:

```sh
firebase functions:secrets:set GEMINI_API_KEY
```

Deploy only functions:

```sh
firebase deploy --only functions
```

The function uses `gemini-3.1-flash-lite` by default. To override it, set the
`GEMINI_MODEL` environment variable for the function runtime.

The Flutter client includes a local placeholder fallback, so the Tutor frontend
still works while this function is undeployed or missing its Gemini secret.
