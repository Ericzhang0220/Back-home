import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PinyinCandidate {
  const PinyinCandidate(this.text, this.consumed, this.weight);
  final String text;
  final int consumed;
  final int weight;
}

/// Bundled, offline dictionary. Neither drafts nor key presses leave the app.
class PinyinLexicon {
  PinyinLexicon(this.words);
  final Map<String, List<(String, int)>> words;
  final _cache = <String, List<PinyinCandidate>>{};
  static Future<PinyinLexicon>? _loading;
  static PinyinLexicon? cached;
  static Future<PinyinLexicon> load() => _loading ??= _load();
  static Future<PinyinLexicon> _load() async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/keyboard/pinyin.json'))
            as Map<String, dynamic>;
    return cached = PinyinLexicon(
      raw.map(
        (key, value) => MapEntry(key, [
          for (final entry in value as List)
            ((entry as List)[0] as String, entry[1] as int),
        ]),
      ),
    );
  }

  List<PinyinCandidate> candidates(String spelling) {
    final query = spelling.toLowerCase().replaceAll("'", '');
    if (query.isEmpty) return [];
    if (_cache.containsKey(query)) return _cache[query]!;
    final result = <PinyinCandidate>[];
    // Prefer whole phrases, then the longest complete initial syllables.
    for (var end = query.length; end > 0; end--) {
      final exact = words[query.substring(0, end)];
      if (exact == null) continue;
      result.addAll(exact.map((e) => PinyinCandidate(e.$1, end, e.$2)));
      if (result.length >= 24) break;
    }
    // Prefix completion is useful for a syllable that is still being typed.
    if (result.length < 8 && query.length <= 8) {
      final completions = <PinyinCandidate>[];
      for (final entry in words.entries) {
        if (entry.key.startsWith(query) && entry.key != query) {
          for (final word in entry.value.take(2)) {
            completions.add(PinyinCandidate(word.$1, query.length, word.$2));
          }
        }
      }
      completions.sort((a, b) => b.weight.compareTo(a.weight));
      result.addAll(completions.take(16));
    }
    final seen = <String>{};
    final found = result.where((item) => seen.add(item.text)).take(24).toList();
    if (_cache.length >= 64) _cache.remove(_cache.keys.first);
    return _cache[query] = found;
  }
}

class KeyboardEditing extends ChangeNotifier {
  KeyboardEditing({
    this.onEdit,
    TextEditingValue initial = TextEditingValue.empty,
  }) : value = initial;
  final ValueChanged<TextEditingValue>? onEdit;
  TextEditingValue value;
  PinyinLexicon? lexicon;
  bool chinese = true;
  bool shifted = false;
  bool capsLock = false;
  bool symbols = false;
  bool emoji = false;
  String pinyin = '';
  List<PinyinCandidate> get candidates => lexicon?.candidates(pinyin) ?? [];

  void sync(TextEditingValue next) {
    if (next == value) return;
    if (next.text != value.text ||
        next.selection != value.selection ||
        next.composing != value.composing) {
      pinyin = '';
    }
    value = next;
    notifyListeners();
  }

  void _publish(TextEditingValue next) {
    value = next;
    onEdit?.call(next);
    notifyListeners();
  }

  TextRange get _replacement {
    if (pinyin.isNotEmpty &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return value.composing;
    }
    final selection = value.selection;
    return selection.isValid && selection.end <= value.text.length
        ? TextRange(start: selection.start, end: selection.end)
        : TextRange.collapsed(value.text.length);
  }

  void _replace(String text, {int? composingOffset}) {
    final range = _replacement;
    final next = value.text.replaceRange(range.start, range.end, text);
    _publish(
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: range.start + text.length),
        composing: composingOffset == null
            ? TextRange.empty
            : TextRange(
                start: range.start + composingOffset,
                end: range.start + text.length,
              ),
      ),
    );
  }

  void key(String key) {
    if (chinese && !symbols && !emoji && RegExp(r'^[a-z]$').hasMatch(key)) {
      final next = pinyin + key;
      _replace(next, composingOffset: 0);
      pinyin = next;
      notifyListeners();
      return;
    }
    commitComposition();
    _replace(shifted ? key.toUpperCase() : key);
    if (!capsLock) shifted = false;
    notifyListeners();
  }

  void choose(PinyinCandidate candidate) {
    if (pinyin.isEmpty) return;
    final rest = pinyin.substring(candidate.consumed.clamp(0, pinyin.length));
    _replace(
      candidate.text + rest,
      composingOffset: rest.isEmpty ? null : candidate.text.length,
    );
    pinyin = rest;
    notifyListeners();
  }

  void commitComposition() {
    if (pinyin.isEmpty) return;
    pinyin = '';
    _publish(value.copyWith(composing: TextRange.empty));
  }

  void commitBestCandidate() {
    while (pinyin.isNotEmpty && candidates.isNotEmpty) {
      choose(candidates.first);
    }
    commitComposition();
  }

  void space() {
    final suggestions = candidates;
    if (pinyin.isNotEmpty && suggestions.isNotEmpty) {
      choose(suggestions.first);
    } else {
      commitComposition();
      _replace(' ');
    }
  }

  void backspace() {
    if (pinyin.isNotEmpty) {
      final remaining = pinyin.substring(0, pinyin.length - 1);
      _replace(remaining, composingOffset: remaining.isEmpty ? null : 0);
      pinyin = remaining;
      notifyListeners();
      return;
    }
    final range = _replacement;
    if (!range.isCollapsed) {
      _replace('');
      return;
    }
    if (range.start == 0) return;
    final previous = value.text.substring(0, range.start).characters.last;
    _publish(
      TextEditingValue(
        text: value.text.replaceRange(
          range.start - previous.length,
          range.end,
          '',
        ),
        selection: TextSelection.collapsed(
          offset: range.start - previous.length,
        ),
      ),
    );
  }

  void toggleLanguage() {
    commitComposition();
    chinese = !chinese;
    symbols = false;
    emoji = false;
    notifyListeners();
  }

  void toggleSymbols() {
    commitComposition();
    symbols = !symbols;
    emoji = false;
    notifyListeners();
  }

  void toggleEmoji() {
    commitComposition();
    emoji = !emoji;
    symbols = false;
    notifyListeners();
  }

  void shift({bool lock = false}) {
    shifted = lock ? true : !shifted;
    capsLock = lock ? !capsLock : false;
    notifyListeners();
  }
}
