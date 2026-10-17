import 'package:back_home/chat/character_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'received card preserves identity, photo and personality without edit rights',
    () {
      final share = SharedAiCharacter.fromData({
        'id': 'shared',
        'name': 'Ava',
        'personality': 'Creative',
        'isCustom': true,
        'authorUid': 'me',
        'avatarUrl': 'https://example.test/photo',
      })!;
      expect(share.character.name, 'Ava');
      expect(share.character.personality, 'Creative');
      expect(share.character.avatarUrl, 'https://example.test/photo');
      expect(share.character.id, 'shared');
      expect(share.character.canEditBy('me'), isFalse);
      expect(share.character.isFriend, isFalse);
    },
  );
  test('old text messages and malformed cards remain readable', () {
    expect(SharedAiCharacter.fromData(null), isNull);
    expect(SharedAiCharacter.fromData('not a card'), isNull);
    expect(SharedAiCharacter.fromData({'name': 'Ava'}), isNull);
    expect(
      SharedAiCharacter.fromData({
        'id': 'x',
        'name': 123,
        'personality': 'Kind',
      }),
      isNull,
    );
  });
}
