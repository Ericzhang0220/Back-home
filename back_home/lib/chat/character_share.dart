import 'ai_models.dart';

class SharedAiCharacter {
  const SharedAiCharacter(this.character);
  final AiCharacter character;

  static SharedAiCharacter? fromData(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['personality'] is! String) {
      return null;
    }
    final data = Map<String, dynamic>.from(value);
    // A received card never grants authorship or edit access.
    data['isCustom'] = false;
    data['isFriend'] = false;
    return SharedAiCharacter(AiCharacter.fromData(id: data['id'], data: data));
  }
}

class CharacterShareRecipient {
  const CharacterShareRecipient({
    required this.id,
    required this.name,
    required this.isAi,
    this.photoUrl,
    this.portraitAsset,
    this.character,
  });
  final String id;
  final String name;
  final bool isAi;
  final String? photoUrl;
  final String? portraitAsset;
  final AiCharacter? character;
}
