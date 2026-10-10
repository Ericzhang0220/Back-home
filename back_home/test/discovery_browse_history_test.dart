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
      expect(resolve('c', preferLast: true), ['a', 'b', 'd', 'c']);
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
      for (final id in ids.reversed) {
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
          currentId: id,
        );
        expect(restored.map((c) => c.id), ids);
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
}
