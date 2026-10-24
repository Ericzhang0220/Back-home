# Character keyboards

Room → Shop → Keyboards contains 20 working Flutter keyboard skins inspired by
the original character portraits. `output/keyboards/20-keyboards-overview.jpg`
is the review sheet; the same folder contains the individual numbered PNGs.
The keyboard artwork, transparent keys, borders and motifs are rendered in
Flutter; letters remain real interactive controls rather than a flattened image.

## Buying and applying

- Mia's Glasshouse Whisper is the free starter keyboard, initially applied to
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
flutter test tool/render_keyboard_catalog_test.dart
flutter test test/keyboard_editing_test.dart test/keyboard_store_test.dart \
  test/character_keyboard_test.dart test/keyboard_shop_test.dart
```

The standalone shop demo uses disposable in-memory preferences and never
charges the real account. Device builds must be restarted to load the new
assets. Browser and widget checks do not replace iPhone/Android touch, IME and
accessibility testing before release.
