import 'dart:convert';
import 'dart:io';

import 'package:back_home/chat/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final brief =
      jsonDecode(
            File('docs/character-expansion-2026-11.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final characters = (brief['characters'] as List).cast<Map<String, dynamic>>();
  final ids = characters.map((c) => c['id'] as String).toSet();

  test(
    'November adds ten adult men and ten adult women to the existing fifty',
    () {
      final additions = AiCharacter.presets
          .where((c) => ids.contains(c.id))
          .toList();
      expect(additions, hasLength(20));
      expect(additions.where((c) => c.gender == 'male'), hasLength(10));
      expect(additions.where((c) => c.gender == 'female'), hasLength(10));
      expect(
        AiCharacter.presets.where((c) => !ids.contains(c.id)),
        hasLength(50),
      );
      for (final character in characters) {
        expect(character['age'] as int, greaterThanOrEqualTo(18));
        expect(character['distinctiveDifference'] as String, isNotEmpty);
      }
      expect(AiCharacter.presets.map((c) => c.id).toSet(), hasLength(70));
      expect(AiCharacter.presets.map((c) => c.publicId).toSet(), hasLength(70));
    },
  );

  test('complete persona voices fit the server prompt without truncation', () {
    for (final brief in characters) {
      final character = AiCharacter.presets.singleWhere(
        (c) => c.id == brief['id'],
      );
      expect(character.personality, brief['personality']);
      expect(
        character.personality.length,
        lessThanOrEqualTo(400),
        reason: character.name,
      );
      expect(character.introduction, brief['introduction']);
      expect(character.preview, brief['preview']);
      expect(character.gender, brief['gender']);
      expect(character.discoveryTags, brief['tags']);
      expect(
        character.portraitAsset,
        'assets/ai_characters/${character.id}.png',
      );
      expect(AiCharacter.introducedInCatalogVersion(character.id), 5);
      final legacyCopy = AiCharacter.fromData(
        id: character.id,
        data: {'name': character.name},
      );
      expect(legacyCopy.gender, character.gender);
      expect(legacyCopy.discoveryTags, character.discoveryTags);
    }
    expect(AiCharacter.introducedInCatalogVersion('ethan-miller'), 1);
    expect(AiCharacter.introducedInCatalogVersion('theo-bennett'), 4);
  });
}
