import 'package:back_home/keyboard/keyboard_editing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('offline pinyin resolves phrases and consumes a sentence in parts', () async {
    final editing = KeyboardEditing()..lexicon = await PinyinLexicon.load();
    addTearDown(editing.dispose);
    for (final key in 'nihao'.split('')) { editing.key(key); }
    expect(editing.value.text, 'nihao');
    expect(editing.value.composing, const TextRange(start: 0, end: 5));
    editing.choose(editing.candidates.firstWhere((item) => item.text == '你好'));
    expect(editing.value.text, '你好');
    expect(editing.pinyin, '');
    expect(editing.value.composing, TextRange.empty);
    for (final key in 'wojintianhenkaixin'.split('')) { editing.key(key); }
    editing.choose(editing.candidates.firstWhere((item) => item.text == '我'));
    expect(editing.pinyin, 'jintianhenkaixin');
    editing.choose(editing.candidates.firstWhere((item) => item.text == '今天'));
    editing.choose(editing.candidates.firstWhere((item) => item.text == '很'));
    editing.choose(editing.candidates.firstWhere((item) => item.text == '开心'));
    expect(editing.value.text, '你好我今天很开心');
    expect(editing.value.selection.extentOffset, editing.value.text.length);
  });

  test('selection replacement and grapheme deletion preserve surrounding text', () {
    final editing = KeyboardEditing(initial: const TextEditingValue(text: 'abcdef', selection: TextSelection(baseOffset: 1, extentOffset: 5)))..chinese = false;
    addTearDown(editing.dispose);
    editing.key('X');
    expect(editing.value.text, 'aXf');
    editing.key('👨‍👩‍👧‍👦');
    editing.backspace();
    expect(editing.value.text, 'aXf');
    editing.sync(const TextEditingValue(text: 'e\u0301', selection: TextSelection.collapsed(offset: 2)));
    editing.backspace();
    expect(editing.value.text, '');
  });

  test('deleting composition does not remove previously committed Chinese', () async {
    final editing = KeyboardEditing(initial: const TextEditingValue(text: '你好', selection: TextSelection.collapsed(offset: 2)))..lexicon = await PinyinLexicon.load();
    addTearDown(editing.dispose);
    editing.key('n'); editing.key('i');
    editing.backspace();
    expect(editing.value.text, '你好n');
    editing.backspace();
    expect(editing.value.text, '你好');
    expect(editing.pinyin, '');
    editing.backspace();
    expect(editing.value.text, '你');
  });
}
