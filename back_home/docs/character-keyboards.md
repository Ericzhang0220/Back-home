# Keyboard themes and custom keyboards

Room → Shop → Keyboards contains 20 abstract Flutter keyboard themes and a
separate **A keyboard for your own AI** purchase card at the top. Regular themes
use procedural light, color and motifs, without preset character photos or names.
Chat portrait overrides are ignored by the keyboard panel. Legacy theme IDs are
retained internally so existing purchases and the free starter survive upgrades.
Letters remain real interactive controls rather than a flattened image.

## Custom keyboards

- Select an AI the signed-in user created; built-in presets and characters
  authored by other users are excluded. Accounts without a custom AI see a
  prompt to create one in Chat. Character loading failures have a retry action.
- The current price is **60 Likes for one keyboard and up to three generations**.
  The purchase confirmation states the price and allowance before charging.
- Each result combines a snapshot of the AI's personality, introduction, preview,
  tags and palette with the user's style description. The current generator is
  **local and procedural**, not a remote AI image service: it creates abstract
  artwork, interprets color/light/dark/key-shape keywords (including common
  Chinese keywords), and uses both background and description to seed variation.
  Arbitrary illustration requests are not supported. No portraits are generated.
- Generate and Regenerate show the remaining allowance. All results remain
  visible, including after two generations. After multiple generations the user
  must explicitly select a result before Save is enabled. A fourth generation
  is rejected by the store, including on repeated taps.
- Save persists one chosen keyboard in the account's on-device inventory and
  **My custom keyboards**, applies the selected scope, and keeps all alternatives
  for future comparison. This is local app storage, not a Photos-library export
  or a cloud/public marketplace listing. Saving early preserves unused attempts;
  changing the saved favorite from the same purchase is free and replaces its
  previous selection. A separate new purchase creates another keyboard.
- Purchase, attempts and selections commit with the wallet in the same local
  record. Failed writes roll back the corresponding change. Closing the screen
  or restarting the app preserves purchased attempts and generated alternatives.

## Buying and applying

- Glasshouse Whisper is the free starter keyboard, initially applied to
  AI chats. The other 19 keyboards currently cost 26–34 of the existing Likes.
- Each preview supports typing before purchase. Buy/apply asks for **AI chats
  only** or **All app pages**. AI includes character discovery, direct AI chats
  and Tutor. All pages means editable fields inside Chet; it does not install
  an iOS keyboard extension or affect other apps.
- Owned skins can be reapplied or change scope without another charge. Shop
  also offers a persistent switch back to the system keyboard. The keyboard
  toolbar's system-keyboard button switches only the current input session.
- Password fields remain native so device password/autofill support is retained.
- Ownership, scope, active skin and the shared Likes wallet are stored together
  in one local SharedPreferences record per signed-in account. Concurrent shop
  purchases are locked; a failed purchase save rolls back the debit and grant.
  This uses the existing local Likes economy, not money, StoreKit, a server-side
  ledger, or cross-device purchase restoration.

## Input

`AppKeyboardHost` uses Flutter's public `TextInputControl` interface and preserves
the existing editable fields, controllers, formatters, selection and submission
callbacks. Synthetic MediaQuery keyboard insets keep composers above the custom
panel. The keyboard supports English, shift/caps lock, simplified Chinese
pinyin candidates, symbols, emoji, selection replacement and grapheme-aware
deletion. Chinese phrase input supports choosing the longest matching prefix
and continuing the remaining spelling. It is an initial offline IME, without
system-level dictation, handwriting, personalized prediction or full-sentence
language modeling; users can switch back to their device keyboard.

Pinyin data is bundled from Rime's Apache-2.0 `rime-pinyin-simp` dictionary:
38,999 spellings and 57,774 candidates after sorting and limiting each spelling
to 32 candidates. See `third_party/rime-pinyin-simp/` for provenance and license.
The SIL OFL-1.1 Noto Sans SC font is bundled for offline Chinese glyphs; see
`third_party/noto-cjk/`. No typed text is sent to a service by the keyboard.

## Preview and checks

```sh
flutter run -d web-server --web-port 8766 -t tool/keyboard_preview.dart
flutter test tool/render_keyboard_catalog_test.dart tool/render_custom_keyboard_test.dart
flutter test test/keyboard_editing_test.dart test/keyboard_store_test.dart \
  test/character_keyboard_test.dart test/keyboard_shop_test.dart \
  test/custom_keyboard_test.dart
```

The standalone shop demo includes a sample user-created AI and uses disposable
in-memory preferences; purchases never charge the real account. The custom
render tool exports setup, result-comparison and saved-store PNGs under
`output/keyboards/`. Device builds must be restarted to load the new
assets. Browser and widget checks do not replace iPhone/Android touch, IME and
accessibility testing before release.
