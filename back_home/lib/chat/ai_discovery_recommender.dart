import 'dart:math';

import 'ai_models.dart';
import 'discovery_browse_history.dart';

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

/// Keeps the browsing path stable, then falls back to random repeat visits.
class AiDiscoveryDeck {
  AiDiscoveryDeck({AiDiscoveryRecommender? recommender})
    : _recommender = recommender ?? AiDiscoveryRecommender();
  final AiDiscoveryRecommender _recommender;
  final _history = DiscoveryBrowseHistory(repeat: true);

  int get currentIndex => _history.currentIndex;
  String? move(int delta) => _history.move(delta);

  List<AiCharacter> resolve({
    required List<AiCharacter> candidates,
    required List<AiCharacter> knownCharacters,
    required Map<String, AiCharacterInteraction> interactions,
    String? currentId,
  }) {
    final byId = {
      for (final character in knownCharacters) character.id: character,
      for (final character in candidates) character.id: character,
    };
    final ids = _history.resolve(
      candidates: candidates.map((character) => character.id),
      available: byId.keys,
      currentId: currentId,
      orderUnseen: (unseen) => _recommender
          .order(
            candidates: unseen.map((id) => byId[id]!).toList(),
            knownCharacters: knownCharacters,
            interactions: interactions,
          )
          .map((character) => character.id)
          .toList(),
    );
    return ids.map((id) => byId[id]!).toList();
  }

  void reset() => _history.reset();
}
