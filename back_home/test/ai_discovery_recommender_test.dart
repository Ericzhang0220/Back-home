import 'dart:math';

import 'package:back_home/chat/ai_discovery_recommender.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

AiCharacter character(
  String id, {
  String gender = 'unspecified',
  List<String> tags = const [],
}) => AiCharacter.fromData(
  id: id,
  data: {'name': id, 'gender': gender, 'tags': tags},
);

void main() {
  const presets = AiCharacter.presets;

  test(
    'untagged custom personas resolve English and Chinese interests without substring mistakes',
    () {
      final english = AiCharacter.fromData(
        id: 'english',
        data: {
          'isCustom': true,
          'personality': 'Independent, gentle, and loves guitar.',
        },
      );
      expect(
        english.discoveryTags,
        containsAll(['independent', 'caring', 'guitar']),
      );
      final chinese = AiCharacter.fromData(
        id: 'chinese',
        data: {'isCustom': true, 'personality': '温柔体贴，喜欢阅读小说和弹钢琴。'},
      );
      expect(chinese.discoveryTags, containsAll(['caring', 'book', 'music']));
      final smart = AiCharacter.fromData(
        id: 'smart',
        data: {'isCustom': true, 'personality': 'Smart and dependable.'},
      );
      expect(smart.discoveryTags, isNot(contains('palette')));
      expect(smart.gender, 'unspecified');
    },
  );

  test('cold start shuffles the entire mixed catalog without gender bias', () {
    final recommender = AiDiscoveryRecommender(random: Random(42));
    var maleFirst = 0;
    final firstIds = <String>{};
    for (var i = 0; i < 1000; i++) {
      final deck = recommender.order(
        candidates: presets,
        knownCharacters: presets,
        interactions: const {},
      );
      expect(deck.map((c) => c.id).toSet().length, presets.length);
      firstIds.add(deck.first.id);
      if (deck.first.gender == 'male') maleFirst++;
    }
    expect(firstIds.length, 20);
    expect(maleFirst, inInclusiveRange(450, 550));
  });

  test(
    'a few messages or automatic chat friendships do not establish a preference',
    () {
      final baseline = AiDiscoveryRecommender(random: Random(9)).order(
        candidates: presets,
        knownCharacters: presets,
        interactions: const {},
      );
      final sparse = AiDiscoveryRecommender(random: Random(9)).order(
        candidates: presets,
        knownCharacters: presets,
        interactions: const {
          'olivia-parker': AiCharacterInteraction(userMessageCount: 3),
        },
      );
      expect(sparse.map((c) => c.id), baseline.map((c) => c.id));
    },
  );

  test(
    'sustained conversation favors the matching gender but keeps all others',
    () {
      final candidates = presets.where((c) => c.id != 'olivia-parker').toList();
      final recommender = AiDiscoveryRecommender(random: Random(25));
      var femaleFirst = 0;
      for (var i = 0; i < 1000; i++) {
        final deck = recommender.order(
          candidates: candidates,
          knownCharacters: presets,
          interactions: const {
            'olivia-parker': AiCharacterInteraction(userMessageCount: 30),
          },
        );
        expect(deck.length, candidates.length);
        expect(deck.any((c) => c.gender == 'male'), isTrue);
        if (deck.first.gender == 'female') femaleFirst++;
      }
      expect(femaleFirst, greaterThan(600));
      expect(femaleFirst, lessThan(900));
    },
  );

  test('interests affect recommendation even without a gender preference', () {
    final reader = character('reader', tags: ['book']);
    final candidates = [
      character('read-a', tags: ['book']),
      character('read-b', tags: ['book']),
      character('hike-a', tags: ['hiking']),
      character('hike-b', tags: ['hiking']),
    ];
    final recommender = AiDiscoveryRecommender(random: Random(12));
    var readingFirst = 0;
    for (var i = 0; i < 1000; i++) {
      final deck = recommender.order(
        candidates: candidates,
        knownCharacters: [...candidates, reader],
        interactions: const {
          'reader': AiCharacterInteraction(userMessageCount: 12),
        },
      );
      if (deck.first.discoveryTags.contains('book')) readingFirst++;
    }
    expect(readingFirst, greaterThan(650));
    expect(readingFirst, lessThan(900));
  });

  test(
    'three explicit favorites can establish a preference without conversation',
    () {
      final recommender = AiDiscoveryRecommender(random: Random(5));
      var femaleFirst = 0;
      for (var i = 0; i < 1000; i++) {
        final deck = recommender.order(
          candidates: presets,
          knownCharacters: presets,
          interactions: const {
            'olivia-parker': AiCharacterInteraction(isFavorite: true),
            'mia-anderson': AiCharacterInteraction(isFavorite: true),
            'grace-miller': AiCharacterInteraction(isFavorite: true),
          },
        );
        if (deck.first.gender == 'female') femaleFirst++;
      }
      expect(femaleFirst, greaterThan(600));
    },
  );

  test('deleted or unknown characters cannot manufacture a preference', () {
    final baseline = AiDiscoveryRecommender(random: Random(7)).order(
      candidates: presets,
      knownCharacters: presets,
      interactions: const {},
    );
    final unknown = AiDiscoveryRecommender(random: Random(7)).order(
      candidates: presets,
      knownCharacters: presets,
      interactions: const {
        'deleted': AiCharacterInteraction(
          userMessageCount: 99999,
          isFavorite: true,
        ),
        'ethan-miller': AiCharacterInteraction(userMessageCount: -100),
      },
    );
    expect(unknown.map((c) => c.id), baseline.map((c) => c.id));
  });

  test(
    'message rebuilds keep the current deck stable; removal does not reshuffle neighbours',
    () {
      final deck = AiDiscoveryDeck(
        recommender: AiDiscoveryRecommender(random: Random(2)),
      );
      final initial = deck.resolve(
        candidates: presets,
        knownCharacters: presets,
        interactions: const {},
      );
      final updated = deck.resolve(
        candidates: presets,
        knownCharacters: presets,
        interactions: const {
          'olivia-parker': AiCharacterInteraction(userMessageCount: 60),
        },
      );
      expect(updated.map((c) => c.id), initial.map((c) => c.id));
      final remaining = deck.resolve(
        candidates: presets.where((c) => c.id != initial[1].id).toList(),
        knownCharacters: presets,
        interactions: const {},
      );
      expect(
        remaining.map((c) => c.id),
        initial.where((c) => c.id != initial[1].id).map((c) => c.id),
      );
      deck.startNewCycle();
      final next = deck.resolve(
        candidates: presets,
        knownCharacters: presets,
        interactions: const {
          'olivia-parker': AiCharacterInteraction(userMessageCount: 60),
        },
      );
      expect(next.map((c) => c.id), isNot(initial.map((c) => c.id)));
      expect(next.map((c) => c.id).toSet().length, 20);
    },
  );

  test('old preset documents resolve authored genders and tags locally', () {
    expect(presets.where((c) => c.gender == 'male').length, 10);
    expect(presets.where((c) => c.gender == 'female').length, 10);
    final restored = AiCharacter.fromData(
      id: 'olivia-parker',
      data: {'name': 'Olivia'},
    );
    expect(restored.gender, 'female');
    expect(restored.discoveryTags, contains('book'));
  });

  test('public adoption retains photo, gender and tags', () {
    final original = AiCharacter.fromData(
      id: 'custom-photo',
      data: {
        'name': 'Luna',
        'isCustom': true,
        'gender': 'female',
        'tags': ['book', 'calm'],
        'avatarUrl': 'https://example.com/luna.png',
      },
    );
    final shared = AiCharacter.fromData(
      id: original.id,
      data: original.toPublicTemplate(authorUid: 'author'),
    );
    final adopted = AiCharacter.fromData(
      id: original.id,
      data: {...shared.toFirestore(), 'isCustom': false},
    );
    expect(adopted.avatarUrl, original.avatarUrl);
    expect(adopted.gender, original.gender);
    expect(adopted.discoveryTags, original.discoveryTags);
  });
}
