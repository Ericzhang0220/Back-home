import 'dart:math';

import 'ai_models.dart';

class AiCharacterInteraction {
  const AiCharacterInteraction({
    this.userMessageCount = 0,
    this.isFavorite = false,
    this.isChatHidden = false,
  });
  final int userMessageCount;
  final bool isFavorite;
  final bool isChatHidden;
}

/// Weighted sampling without replacement. Early decks are uniformly shuffled;
/// established preferences increase sampling weight while exploration remains.
class AiDiscoveryRecommender {
  AiDiscoveryRecommender({Random? random}) : _random = random ?? Random();
  final Random _random;
  static const minimumMessages = 12;
  static const minimumFavorites = 3;

  List<AiCharacter> order({
    required List<AiCharacter> candidates,
    required List<AiCharacter> knownCharacters,
    required Map<String, AiCharacterInteraction> interactions,
  }) {
    final profile = _profile(knownCharacters, interactions);
    if (profile.isEmpty) return [...candidates]..shuffle(_random);
    final ranked = candidates.map((character) {
      final score = _affinity(character, profile);
      // The base 1.0 weight reserves exploration. Maximum preference weight
      // is 4.0, so other genders and interests never disappear from the deck.
      final weight = 1 + 3 * score;
      final key = -log(1 - _random.nextDouble()) / weight;
      return (character: character, key: key);
    }).toList()..sort((a, b) => a.key.compareTo(b.key));
    return ranked.map((entry) => entry.character).toList();
  }

  Map<String, double> _profile(
    List<AiCharacter> characters,
    Map<String, AiCharacterInteraction> interactions,
  ) {
    final known = {for (final character in characters) character.id: character};
    var messages = 0;
    var favorites = 0;
    final scores = <String, double>{};
    for (final entry in interactions.entries) {
      final character = known[entry.key];
      if (character == null) continue;
      final count = max(0, entry.value.userMessageCount);
      messages += count;
      if (entry.value.isFavorite) favorites++;
      // Log scaling prevents one very long thread from overwhelming all
      // the other characters the person also enjoys.
      final strength = log(1 + count) + (entry.value.isFavorite ? 1.5 : 0);
      if (strength == 0) continue;
      if (character.gender != 'unspecified') {
        scores.update(
          'gender:${character.gender}',
          (v) => v + strength,
          ifAbsent: () => strength,
        );
      }
      for (final tag in character.discoveryTags.toSet()) {
        scores.update(
          'tag:$tag',
          (v) => v + strength,
          ifAbsent: () => strength,
        );
      }
    }
    return messages < minimumMessages && favorites < minimumFavorites
        ? const {}
        : scores;
  }

  double _affinity(AiCharacter character, Map<String, double> scores) {
    final totalGender =
        (scores['gender:male'] ?? 0) + (scores['gender:female'] ?? 0);
    final genderScore = totalGender == 0 || character.gender == 'unspecified'
        ? 0.0
        : (scores['gender:${character.gender}'] ?? 0) / totalGender;
    final tagScores = scores.entries
        .where((e) => e.key.startsWith('tag:'))
        .map((e) => e.value);
    final maxTag = tagScores.isEmpty ? 0.0 : tagScores.reduce(max);
    final matchingTags = character.discoveryTags.map(
      (tag) => scores['tag:$tag'] ?? 0.0,
    );
    final tagScore = maxTag == 0 || matchingTags.isEmpty
        ? 0.0
        : matchingTags.reduce((a, b) => a + b) / matchingTags.length / maxTag;
    return (0.5 * genderScore + 0.5 * tagScore).clamp(0.0, 1.0);
  }
}

/// Keeps an already visible card and its neighbours stable while message
/// streams rebuild. New preference data is applied at the next deck cycle.
class AiDiscoveryDeck {
  AiDiscoveryDeck({AiDiscoveryRecommender? recommender})
    : _recommender = recommender ?? AiDiscoveryRecommender();
  final AiDiscoveryRecommender _recommender;
  List<String> _ids = [];

  List<AiCharacter> resolve({
    required List<AiCharacter> candidates,
    required List<AiCharacter> knownCharacters,
    required Map<String, AiCharacterInteraction> interactions,
  }) {
    final byId = {for (final character in candidates) character.id: character};
    _ids.removeWhere((id) => !byId.containsKey(id));
    final additions = candidates.where((c) => !_ids.contains(c.id)).toList();
    _ids.addAll(
      _recommender
          .order(
            candidates: additions,
            knownCharacters: knownCharacters,
            interactions: interactions,
          )
          .map((c) => c.id),
    );
    return _ids.map((id) => byId[id]!).toList();
  }

  void startNewCycle() => _ids = [];
}
