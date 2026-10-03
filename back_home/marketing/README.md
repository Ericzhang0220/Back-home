# Back Home marketing website

Static English landing page matching the app’s cream and clay palette. Uses the existing room screenshot, describes implemented app features, and includes a local, unsaved mood preview. No Firebase SDK, account sign-in, analytics, or build step is needed.

## Preview

From the repository root:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory marketing/public
```

Visit http://127.0.0.1:4173.

## Firebase Hosting

The root `firebase.json` serves **only** `marketing/public`. Existing Functions, Firestore, and Flutter configuration is preserved. No catch-all rewrite is needed; missing pages receive the custom 404.

From the repository root, with a functioning Firebase CLI authenticated to the existing project:

```sh
firebase deploy --only hosting --project back-home-7cf17
```

This updates the project's default Hosting site. If it already contains another website, first use a separate Hosting site and target rather than replacing it.

Expected default URL after a successful deployment:

https://back-home-7cf17.web.app

The live homepage URL can be used as the app’s Marketing URL in App Store Connect. A custom domain can also be configured in Firebase Hosting.

## Before a store launch

- Replace the download FAQ with the actual App Store link when available; no fake download action is included.
- Add verified support contact details and a privacy policy separately if needed for store submission. This homepage does not substitute for either.
- Edit copy in `public/index.html` and presentation in `public/styles.css`.

The included room image is copied from `assets/room/room_start.png`; it reflects that supplied screenshot rather than claiming to be a current live session.
