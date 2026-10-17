import 'dart:math';

import 'package:back_home/chat/ai_discovery_recommender.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/chat/discovery_browse_history.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreferenceOrder extends AiDiscoveryRecommender {
  final requested = <List<String>>[];

  @override
  List<AiCharacter> order({
    required List<AiCharacter> candidates,
    required List<AiCharacter> knownCharacters,
    required Map<String, AiCharacterInteraction> interactions,
  }) {
    requested.add(candidates.map((c) => c.id).toList());
    final ordered = [...candidates]..sort((a, b) => a.id.compareTo(b.id));
    return interactions.isEmpty ? ordered : ordered.reversed.toList();
  }
}

void main() {
  test(
    'preferences change new recommendations, never a reserved swipe target',
    () {
      final order = _PreferenceOrder();
      final deck = AiDiscoveryDeck(recommender: order);
      final characters = [
        for (final id in ['a', 'b', 'c', 'd'])
          AiCharacter.fromData(id: id, data: {'name': id}),
      ];
      List<String> resolve(String currentId, {bool preferLast = false}) => deck
          .resolve(
            candidates: characters,
            knownCharacters: characters,
            currentId: currentId,
            interactions: preferLast
                ? const {'a': AiCharacterInteraction(userMessageCount: 30)}
                : const {},
          )
          .map((c) => c.id)
          .toList();

      expect(resolve('a'), ['a', 'b']);
      expect(resolve('a', preferLast: true), ['a', 'b']);
      expect(order.requested.length, 1);
      expect(resolve('b', preferLast: true), ['a', 'b', 'd']);
      expect(order.requested.last, ['c', 'd']);
      expect(resolve('a'), ['a', 'b', 'd']);
      expect(resolve('b'), ['a', 'b', 'd']);
      expect(resolve('d'), ['a', 'b', 'd', 'c']);
      final repeated = resolve('c', preferLast: true);
      expect(repeated.take(4), ['a', 'b', 'd', 'c']);
      expect(repeated.length, 5);
      expect(repeated.last, isNot('c'));
      expect(resolve('c'), repeated);
      expect(order.requested.length, 3);
    },
  );

  test(
    'the full AI catalog can be retraced after chats, likes and exhaustion',
    () {
      final deck = AiDiscoveryDeck();
      const characters = AiCharacter.presets;
      var path = deck.resolve(
        candidates: characters,
        knownCharacters: characters,
        interactions: const {},
      );
      for (var index = 1; index < characters.length; index++) {
        path = deck.resolve(
          candidates: characters,
          knownCharacters: characters,
          interactions: const {},
          currentId: path[index].id,
        );
      }
      final ids = path.map((c) => c.id).toList();
      expect(ids.toSet().length, characters.length);
      expect(ids.length, characters.length + 1);
      expect(deck.currentIndex, characters.length - 1);
      for (var index = characters.length - 1; index >= 0; index--) {
        if (index < characters.length - 1) {
          expect(deck.move(-1), ids[index]);
        }
        final restored = deck.resolve(
          // All profiles now have conversations and are no longer candidates.
          candidates: const [],
          knownCharacters: characters,
          interactions: {
            for (final id in ids)
              id: const AiCharacterInteraction(
                userMessageCount: 30,
                isFavorite: true,
              ),
          },
          currentId: ids[index],
        );
        expect(restored.map((c) => c.id), ids);
        expect(deck.currentIndex, index);
      }
    },
  );

  test('Human history survives candidate reordering and adding friends', () {
    final history = DiscoveryBrowseHistory();
    const available = ['a', 'b', 'c', 'd'];
    List<String> resolve(String current, List<String> candidates) =>
        history.resolve(
          candidates: candidates,
          available: available,
          currentId: current,
          orderUnseen: (ids) => ids,
        );
    expect(resolve('a', available), ['a', 'b']);
    expect(resolve('b', ['d', 'c']), ['a', 'b', 'd']);
    expect(resolve('a', ['c', 'd']), ['a', 'b', 'd']);
    expect(resolve('d', ['c']), ['a', 'b', 'd', 'c']);
    expect(resolve('c', []), ['a', 'b', 'd', 'c']);
  });

  test(
    'new arrivals extend the path, and account reset forgets old history',
    () {
      final history = DiscoveryBrowseHistory();
      List<String> resolve(List<String> ids, String current) => history.resolve(
        candidates: ids,
        available: ids,
        currentId: current,
        orderUnseen: (ids) => ids,
      );
      expect(resolve(['a', 'b'], 'a'), ['a', 'b']);
      expect(resolve(['a', 'b'], 'b'), ['a', 'b']);
      expect(resolve(['c', 'a', 'b'], 'b'), ['a', 'b', 'c']);
      expect(resolve(['b', 'c', 'a'], 'a'), ['a', 'b', 'c']);
      history.reset();
      expect(resolve(['x', 'y'], 'x'), ['x', 'y']);
    },
  );

  test(
    'random repeats continue indefinitely and retain the exact return path',
    () {
      final history = DiscoveryBrowseHistory(repeat: true, random: Random(42));
      const available = ['a', 'b', 'c'];
      List<String> resolve(String? current) => history.resolve(
        candidates: available,
        available: available,
        currentId: current,
        orderUnseen: (ids) => ids,
      );
      var path = resolve(null);
      for (var visit = 0; visit < 200; visit++) {
        expect(history.currentIndex, visit);
        expect(path.length, visit + 2);
        expect(path[visit + 1], isNot(path[visit]));
        final reserved = path[visit + 1];
        expect(resolve(path[visit]), path);
        expect(history.move(1), reserved);
        path = resolve(reserved);
      }
      expect(path.take(3), available);
      for (var visit = 199; visit >= 0; visit--) {
        expect(history.move(-1), path[visit]);
        expect(resolve(path[visit]), path);
        expect(history.currentIndex, visit);
      }
      expect(history.move(-1), isNull);
      for (var visit = 1; visit <= 200; visit++) {
        expect(history.move(1), path[visit]);
        expect(resolve(path[visit]), path);
        expect(history.currentIndex, visit);
      }
    },
  );

  test('saved profiles remain eligible when fresh recommendations run out', () {
    final history = DiscoveryBrowseHistory(repeat: true, random: Random(4));
    List<String> resolve(String? current) => history.resolve(
      candidates: const [],
      available: const ['saved-a', 'saved-b', 'saved-c'],
      currentId: current,
      orderUnseen: (_) => throw StateError('No unseen candidates'),
    );
    var path = resolve(null);
    final seen = <String>{path.first};
    for (var i = 0; i < 50; i++) {
      final id = history.move(1)!;
      seen.add(id);
      path = resolve(id);
      expect(path.length, i + 3);
    }
    expect(seen, {'saved-a', 'saved-b', 'saved-c'});
  });

  test('a single available profile still has a distinct next visit', () {
    final history = DiscoveryBrowseHistory(repeat: true);
    List<String> resolve(String? current) => history.resolve(
      candidates: const [],
      available: const ['only'],
      currentId: current,
      orderUnseen: (ids) => ids,
    );
    expect(resolve(null), ['only', 'only']);
    for (var i = 1; i <= 10; i++) {
      expect(history.move(1), 'only');
      expect(resolve('only').length, i + 2);
      expect(history.currentIndex, i);
    }
    expect(history.move(-1), 'only');
    expect(history.currentIndex, 9);
  });

  test('new arrivals take priority after a reserved random preview', () {
    final history = DiscoveryBrowseHistory(repeat: true);
    List<String> resolve(List<String> ids, String? current) => history.resolve(
      candidates: ids,
      available: ids,
      currentId: current,
      orderUnseen: (ids) => ids,
    );
    expect(resolve(['a', 'b'], 'a'), ['a', 'b']);
    expect(history.move(1), 'b');
    expect(resolve(['a', 'b'], 'b'), ['a', 'b', 'a']);
    expect(resolve(['a', 'b', 'c'], 'b'), ['a', 'b', 'a']);
    expect(history.move(1), 'a');
    expect(resolve(['a', 'b', 'c'], 'a'), ['a', 'b', 'a', 'c']);
  });

  test(
    'deleted profiles are removed from repeat visits and an empty catalog is safe',
    () {
      final history = DiscoveryBrowseHistory(repeat: true);
      List<String> resolve(List<String> ids, String? current) =>
          history.resolve(
            candidates: ids,
            available: ids,
            currentId: current,
            orderUnseen: (ids) => ids,
          );
      resolve(['a', 'b'], 'a');
      history.move(1);
      resolve(['a', 'b'], 'b');
      history.move(1);
      resolve(['a', 'b'], 'a');
      expect(resolve(['a'], 'a'), ['a', 'a', 'a']);
      expect(history.currentIndex, 1);
      expect(resolve([], 'a'), isEmpty);
      expect(history.currentIndex, 0);
      expect(history.move(1), isNull);
      expect(resolve(['new'], null), ['new', 'new']);
    },
  );
}
