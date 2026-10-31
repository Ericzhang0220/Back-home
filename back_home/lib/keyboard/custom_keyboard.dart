import 'package:flutter/material.dart';

import '../chat/ai_models.dart';
import 'keyboard_catalog.dart';

const customKeyboardPrice = 60;
const customKeyboardAttempts = 3;

/// A purchase retains every result, even after the user saves a favorite.
class CustomKeyboardProject {
  const CustomKeyboardProject({
    required this.id,
    required this.characterId,
    required this.characterName,
    required this.background,
    required this.colorValue,
    this.results = const [],
    this.selectedId,
  });

  factory CustomKeyboardProject.forCharacter(
    String id,
    AiCharacter character,
  ) => CustomKeyboardProject(
    id: id,
    characterId: character.id,
    characterName: character.name,
    background:
        '${character.personality}\n${character.introduction}\n'
        '${character.preview}\n${character.discoveryTags.join(', ')}',
    colorValue: character.colorValue,
  );

  final String id;
  final String characterId;
  final String characterName;
  final String background;
  final int colorValue;
  final List<CustomKeyboardResult> results;
  final String? selectedId;
  int get remaining => customKeyboardAttempts - results.length;
  CustomKeyboardResult? get selected {
    for (final result in results) {
      if (result.skin.id == selectedId) return result;
    }
    return null;
  }

  CustomKeyboardProject withResult(CustomKeyboardResult result) =>
      CustomKeyboardProject(
        id: id,
        characterId: characterId,
        characterName: characterName,
        background: background,
        colorValue: colorValue,
        results: List.unmodifiable([...results, result]),
        selectedId: selectedId,
      );

  CustomKeyboardProject select(String resultId) => CustomKeyboardProject(
    id: id,
    characterId: characterId,
    characterName: characterName,
    background: background,
    colorValue: colorValue,
    results: results,
    selectedId: resultId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'characterId': characterId,
    'characterName': characterName,
    'background': background,
    'color': colorValue,
    'selected': selectedId,
    'results': results.map((result) => result.toJson()).toList(),
  };

  factory CustomKeyboardProject.fromJson(Map<String, dynamic> data) {
    final results = (data['results'] as List)
        .map(
          (item) => CustomKeyboardResult.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    if (results.length > customKeyboardAttempts) {
      throw const FormatException('Too many keyboard results');
    }
    return CustomKeyboardProject(
      id: data['id'] as String,
      characterId: data['characterId'] as String,
      characterName: data['characterName'] as String,
      background: data['background'] as String,
      colorValue: data['color'] as int,
      results: List.unmodifiable(results),
      selectedId: data['selected'] as String?,
    );
  }
}

class CustomKeyboardResult {
  const CustomKeyboardResult({required this.skin, required this.style});
  final KeyboardSkin skin;
  final String style;

  Map<String, dynamic> toJson() => {
    'id': skin.id,
    'name': skin.name,
    'accent': skin.accent.toARGB32(),
    'base': skin.base.toARGB32(),
    'ink': skin.ink.toARGB32(),
    'radius': skin.radius,
    'style': style,
  };

  factory CustomKeyboardResult.fromJson(Map<String, dynamic> data) =>
      CustomKeyboardResult(
        style: data['style'] as String,
        skin: KeyboardSkin(
          data['id'] as String,
          data['name'] as String,
          'Custom',
          Color(data['accent'] as int),
          Color(data['base'] as int),
          Color(data['ink'] as int),
          Icons.auto_awesome_rounded,
          0,
          (data['radius'] as num).toDouble(),
        ),
      );
}

/// Offline procedural theme generation. Character background and the requested
/// style both seed the artwork; explicit style colors take priority. No portrait
/// or typed chat message is used, and no image-generation service is required.
CustomKeyboardResult generateCustomKeyboard(
  CustomKeyboardProject project,
  String style,
) {
  final attempt = project.results.length + 1;
  final request = style.toLowerCase();
  final background = project.background.toLowerCase();
  var seed = 17;
  for (final unit in '${project.id}|$background|$request|$attempt'.codeUnits) {
    seed = (seed * 31 + unit) & 0x7fffffff;
  }
  const colors = <String, Color>{
    'red|红': Color(0xFFE89591),
    'pink|rose|粉|玫瑰': Color(0xFFF3A8C6),
    'orange|sunset|橙|日落': Color(0xFFF5B27F),
    'gold|yellow|honey|金|黄': Color(0xFFF0CD88),
    'green|forest|garden|plant|绿|森林|植物': Color(0xFFA6C79E),
    'blue|ocean|sea|rain|蓝|海|雨': Color(0xFF9ECFE9),
    'purple|violet|lavender|紫|薰衣草': Color(0xFFC6AFF0),
  };
  Color? requestedColor(String text) {
    for (final entry in colors.entries) {
      if (entry.key.split('|').any(text.contains)) return entry.value;
    }
    return null;
  }

  final source =
      requestedColor(request) ??
      requestedColor(background) ??
      Color(project.colorValue);
  final hsv = HSVColor.fromColor(source);
  final hue = (hsv.hue + (attempt - 2) * 9) % 360;
  final light =
      RegExp('light|pastel|cream|白|浅|奶油').hasMatch(request) &&
      !RegExp('dark|midnight|深|暗|黑').hasMatch(request);
  final base = HSVColor.fromAHSV(
    1,
    hue,
    light ? 0.12 : 0.35,
    light ? 0.95 : 0.20,
  ).toColor();
  final accent = HSVColor.fromAHSV(
    1,
    hue,
    light ? 0.56 : 0.30,
    light ? 0.44 : 0.94,
  ).toColor();
  final radius = RegExp('sharp|square|方|直角').hasMatch(request)
      ? 6.0
      : 12.0 + seed % 9;
  return CustomKeyboardResult(
    style: style.trim(),
    skin: KeyboardSkin(
      '${project.id}-$attempt-$seed',
      '${project.characterName} · $attempt',
      'Custom',
      accent,
      base,
      light ? const Color(0xFF293238) : const Color(0xFFF8F4FF),
      Icons.auto_awesome_rounded,
      0,
      radius,
    ),
  );
}
