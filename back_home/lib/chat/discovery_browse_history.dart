import 'dart:math';

/// A session's fixed browsing path plus one reserved next-card preview.
/// Favorites and conversations affect new recommendations, never this path.
class DiscoveryBrowseHistory {
  DiscoveryBrowseHistory({this.repeat = false, Random? random})
    : _random = random ?? Random();

  final bool repeat;
  final Random _random;
  final _ids = <String>[];
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  /// Track the visit, rather than looking up its profile ID: a repeating feed
  /// may contain the same person at several different points in its history.
  String? move(int delta) {
    final next = _currentIndex + delta;
    if (next < 0 || next >= _ids.length) return null;
    _currentIndex = next;
    return _ids[next];
  }

  List<String> resolve({
    required Iterable<String> candidates,
    required Iterable<String> available,
    required List<String> Function(List<String>) orderUnseen,
    String? currentId,
  }) {
    final availableIds = available.toSet();
    // Only a truly unavailable/deleted profile leaves the browsing path.
    final removedBefore = _ids
        .take(_currentIndex)
        .where((id) => !availableIds.contains(id))
        .length;
    _ids.removeWhere((id) => !availableIds.contains(id));
    _currentIndex = max(0, min(_currentIndex - removedBefore, _ids.length - 1));
    final eligible = candidates.toSet().intersection(availableIds);

    void appendNext() {
      final unseen = eligible.difference(_ids.toSet()).toList();
      if (unseen.isNotEmpty) {
        _ids.add(orderUnseen(unseen).first);
      } else if (repeat && availableIds.isNotEmpty) {
        // Once fresh recommendations run out, include saved profiles too.
        // Avoid showing the current person twice in a row when possible.
        final pool = availableIds
            .where((id) => _ids.isEmpty || id != _ids.last)
            .toList();
        if (pool.isEmpty) pool.addAll(availableIds);
        _ids.add(pool[_random.nextInt(pool.length)]);
      }
    }

    if (currentId != null &&
        availableIds.contains(currentId) &&
        !_ids.contains(currentId)) {
      _ids.add(currentId);
    }
    if (_ids.isEmpty) appendNext();
    if (currentId == null) {
      _currentIndex = 0;
    } else if (_ids.isNotEmpty && _ids[_currentIndex] != currentId) {
      final foundIndex = _ids.indexOf(currentId);
      _currentIndex = foundIndex < 0 ? 0 : foundIndex;
    }
    // Reserve the preview before swiping. Keep it even if preferences change
    // mid-gesture, so the revealed person is always the one entered next.
    if (_ids.isNotEmpty && _currentIndex == _ids.length - 1) appendNext();
    return List.unmodifiable(_ids);
  }

  void reset() {
    _ids.clear();
    _currentIndex = 0;
  }
}
