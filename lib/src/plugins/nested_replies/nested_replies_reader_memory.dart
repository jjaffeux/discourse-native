import 'package:discourse_native/discourse_plugin_contracts.dart'
    show elapsedSince;
import 'package:flutter/foundation.dart';

import 'nested_replies_controller.dart';

/// The session owner clears reference-only reader snapshots on account retirement.
final class NestedRepliesReaderMemory extends ChangeNotifier {
  NestedRepliesReaderMemory({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _entries =
      <Object, ({NestedRepliesReaderSnapshot value, DateTime savedAt})>{};
  final Map<(String, int), int> _revisions = {};

  int revision(String siteUrl, int topicId) =>
      _revisions[(siteUrl, topicId)] ?? 0;

  void invalidateTopic(String siteUrl, int topicId) {
    final key = (siteUrl, topicId);
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    _entries.removeWhere(
      (_, entry) =>
          entry.value.siteUrl == siteUrl && entry.value.topicId == topicId,
    );
    notifyListeners();
  }

  void forgetSite(String siteUrl) {
    _entries.removeWhere((_, entry) => entry.value.siteUrl == siteUrl);
    _revisions.removeWhere((key, _) => key.$1 == siteUrl);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _revisions.clear();
    notifyListeners();
  }

  NestedRepliesReaderSnapshot? restore(Object key) {
    final saved = _entries.remove(key);
    if (saved == null) return null;
    final (value: snapshot, :savedAt) = saved;
    if (snapshot.revision != revision(snapshot.siteUrl, snapshot.topicId) ||
        elapsedSince(savedAt, now: _clock()) > const Duration(minutes: 10)) {
      return null;
    }
    _entries[key] = saved;
    return snapshot;
  }

  void remember(Object key, NestedRepliesReaderSnapshot entry) {
    final savedAt = _clock();
    _entries.remove(key);
    _entries[key] = (value: entry, savedAt: savedAt);
    while (_entries.length > 15 ||
        _entries.values.fold<int>(
              0,
              (sum, entry) => sum + entry.value.snapshot.nodeCount,
            ) >
            20000) {
      _entries.remove(_entries.keys.first);
    }
  }
}

final class NestedRepliesReaderSnapshot {
  const NestedRepliesReaderSnapshot({
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
}
