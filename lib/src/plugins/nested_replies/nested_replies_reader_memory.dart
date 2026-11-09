part of 'nested_replies_reader.dart';

/// The session owner clears reference-only reader snapshots on account retirement.
final class NestedRepliesReaderMemory extends ChangeNotifier {
  NestedRepliesReaderMemory({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<Object, _RememberedReader> _entries = {};
  final Map<(String, int), int> _revisions = {};

  int revision(String siteUrl, int topicId) =>
      _revisions[(siteUrl, topicId)] ?? 0;

  void invalidateTopic(String siteUrl, int topicId) {
    final key = (siteUrl, topicId);
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    _entries.removeWhere(
      (_, entry) => entry.siteUrl == siteUrl && entry.topicId == topicId,
    );
    notifyListeners();
  }

  void forgetSite(String siteUrl) {
    _entries.removeWhere((_, entry) => entry.siteUrl == siteUrl);
    _revisions.removeWhere((key, _) => key.$1 == siteUrl);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _revisions.clear();
    notifyListeners();
  }

  _RememberedReader? _take(Object key) {
    final entry = _entries.remove(key);
    if (entry == null ||
        entry.revision != revision(entry.siteUrl, entry.topicId) ||
        elapsedSince(entry.saved, now: _clock()) >
            const Duration(minutes: 10)) {
      return null;
    }
    _entries[key] = entry;
    return entry;
  }

  void _put(Object key, _RememberedReader entry) {
    entry.saved = _clock();
    _entries.remove(key);
    _entries[key] = entry;
    while (_entries.length > 15 ||
        _entries.values.fold<int>(
              0,
              (sum, value) => sum + value.snapshot.nodeCount,
            ) >
            20000) {
      _entries.remove(_entries.keys.first);
    }
  }
}

final class _RememberedReader {
  _RememberedReader({
    required this.siteUrl,
    required this.offset,
    required this.collapsed,
    required this.topicId,
    required this.revision,
    required this.snapshot,
    this.anchor,
    this.anchorOffset,
  });
  final String siteUrl;
  final int topicId;
  final int revision;
  final NestedRepliesSnapshot snapshot;
  final double offset;
  final Set<int> collapsed;
  final int? anchor;
  final double? anchorOffset;
  late DateTime saved;
}
