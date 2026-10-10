import 'dart:async';

import 'package:flutter/widgets.dart';

/// Shares live history between the front card and its neighbouring previews.
/// Each conversation retains its own last snapshot when it leaves the deck.
class DiscoveryConversationCache<T> {
  DiscoveryConversationCache({required this.watch, this.capacity = 24});

  final Stream<List<T>> Function(String id) watch;
  final int capacity;
  final _entries = <String, _ConversationEntry<T>>{};
  final _preloaded = <String, _ConversationEntry<T>>{};

  /// Keep both swipe directions ready, including the neighbour not currently
  /// painted underneath the front card. Only this small window stays live.
  void preload(Iterable<String> conversationIds) {
    final ids = conversationIds.toSet();
    for (final id in ids) {
      _preloaded.putIfAbsent(id, () => _retain(id));
    }
    for (final id in _preloaded.keys.toList()) {
      if (!ids.contains(id)) _release(_preloaded.remove(id)!);
    }
  }

  _ConversationEntry<T> _retain(String id) {
    final entry = _entries.remove(id) ?? _ConversationEntry<T>();
    _entries[id] = entry;
    entry.retain(() => watch(id));
    // Keep only a bounded history of inactive cards; active cards stay live.
    for (final key in _entries.keys.toList()) {
      if (_entries.length <= capacity) break;
      if (_entries[key]!.references == 0) {
        _entries.remove(key)!.dispose();
      }
    }
    return entry;
  }

  void _release(_ConversationEntry<T> entry) => entry.release();

  void dispose() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    _preloaded.clear();
  }
}

class _ConversationEntry<T> extends ValueNotifier<List<T>> {
  _ConversationEntry() : super(<T>[]);

  int references = 0;
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<List<T>>? _subscription;

  void retain(Stream<List<T>> Function() watch) {
    if (references++ != 0 || _subscription != null) return;
    final generation = ++_generation;
    _subscription = watch().listen(
      (messages) {
        if (!_disposed && generation == _generation) {
          value = List<T>.unmodifiable(messages);
        }
      },
      // Keep the last good snapshot on a transient error. A conversation
      // without a history (including a not-yet-created Human chat) stays empty.
      onError: (Object _) {},
    );
  }

  void release() {
    if (_disposed || --references != 0) return;
    // A preview can move to the front in this same build. Keep its listener
    // through that handoff instead of reconnecting to Firestore mid-swipe.
    scheduleMicrotask(() {
      if (_disposed || references != 0) return;
      ++_generation;
      _subscription?.cancel();
      _subscription = null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _subscription?.cancel();
    super.dispose();
  }
}

class DiscoveryConversation<T> extends StatefulWidget {
  const DiscoveryConversation({
    super.key,
    required this.cache,
    required this.conversationId,
    required this.builder,
  });

  final DiscoveryConversationCache<T> cache;
  final String conversationId;
  final Widget Function(BuildContext context, List<T> messages) builder;

  @override
  State<DiscoveryConversation<T>> createState() =>
      _DiscoveryConversationState<T>();
}

class _DiscoveryConversationState<T> extends State<DiscoveryConversation<T>> {
  late _ConversationEntry<T> _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.cache._retain(widget.conversationId);
  }

  @override
  void didUpdateWidget(covariant DiscoveryConversation<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache != widget.cache ||
        oldWidget.conversationId != widget.conversationId) {
      oldWidget.cache._release(_entry);
      _entry = widget.cache._retain(widget.conversationId);
    }
  }

  @override
  void dispose() {
    widget.cache._release(_entry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<T>>(
    valueListenable: _entry,
    builder: (context, messages, _) => widget.builder(context, messages),
  );
}
