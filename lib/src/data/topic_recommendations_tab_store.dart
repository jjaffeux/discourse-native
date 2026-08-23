import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

/// Which list the more-topics footer shows when both are available.
enum TopicRecommendationsTab {
  suggested,
  related;

  static TopicRecommendationsTab? byName(String? name) => switch (name) {
    'suggested' => TopicRecommendationsTab.suggested,
    'related' => TopicRecommendationsTab.related,
    _ => null,
  };
}

/// Per-forum more-topics tab persistence.
abstract interface class TopicRecommendationsTabPersistence {
  Future<TopicRecommendationsTab?> readTab({required String siteUrl});

  Future<bool> writeTab({
    required String siteUrl,
    required TopicRecommendationsTab tab,
  });
}

final class SharedPreferencesTopicRecommendationsTabPersistence
    implements TopicRecommendationsTabPersistence {
  const SharedPreferencesTopicRecommendationsTabPersistence();

  static const String _keyPrefix = 'discourse_native.topic_recommendations_tab';

  @override
  Future<TopicRecommendationsTab?> readTab({required String siteUrl}) async =>
      TopicRecommendationsTab.byName(
        (await SharedPreferences.getInstance()).getString(_key(siteUrl)),
      );

  @override
  Future<bool> writeTab({
    required String siteUrl,
    required TopicRecommendationsTab tab,
  }) async => (await SharedPreferences.getInstance()).setString(
    _key(siteUrl),
    tab.name,
  );

  static String _key(String siteUrl) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}';
}

/// Remembers whether the reader last read suggested or related topics on each
/// forum.
///
/// This is optional presentation state. Storage failures fall back to the
/// core suggested list and never prevent a topic from being read.
final class TopicRecommendationsTabStore {
  const TopicRecommendationsTabStore({
    TopicRecommendationsTabPersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesTopicRecommendationsTabPersistence();

  final TopicRecommendationsTabPersistence _persistence;
  static final SerialOperationQueue _operations = SerialOperationQueue();
  static final Map<_TopicTabOperationKey, int> _pendingWrites = {};

  Future<TopicRecommendationsTab> read({required String siteUrl}) {
    final key = _TopicTabOperationKey(_persistence, siteUrl);
    // Most reads are fire-and-forget presentation hydration. Keep those reads
    // out of the write queue unless there is actually an earlier write to
    // observe; this also means an abandoned reader can never strand saves.
    if ((_pendingWrites[key] ?? 0) == 0) return _read(siteUrl);
    return _operations.run(
      owner: _persistence,
      key: siteUrl,
      operation: () => _read(siteUrl),
    );
  }

  Future<TopicRecommendationsTab> _read(String siteUrl) async {
    try {
      return await _persistence.readTab(siteUrl: siteUrl) ??
          TopicRecommendationsTab.suggested;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'topicRecommendationsTab.readTab',
      );
      return TopicRecommendationsTab.suggested;
    }
  }

  Future<void> write({
    required String siteUrl,
    required TopicRecommendationsTab tab,
  }) async {
    final key = _TopicTabOperationKey(_persistence, siteUrl);
    _pendingWrites.update(key, (count) => count + 1, ifAbsent: () => 1);
    try {
      await _operations.run<void>(
        owner: _persistence,
        key: siteUrl,
        operation: () => _persist(siteUrl: siteUrl, tab: tab),
      );
    } finally {
      final remaining = _pendingWrites[key]! - 1;
      if (remaining == 0) {
        _pendingWrites.remove(key);
      } else {
        _pendingWrites[key] = remaining;
      }
    }
  }

  Future<void> _persist({
    required String siteUrl,
    required TopicRecommendationsTab tab,
  }) async {
    try {
      final saved = await _persistence.writeTab(siteUrl: siteUrl, tab: tab);
      if (!saved) {
        throw StateError('Could not persist the more topics tab.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'topicRecommendationsTab.writeTab',
      );
    }
  }
}

final class _TopicTabOperationKey {
  const _TopicTabOperationKey(this.owner, this.siteUrl);

  final Object owner;
  final String siteUrl;

  @override
  bool operator ==(Object other) =>
      other is _TopicTabOperationKey &&
      identical(owner, other.owner) &&
      siteUrl == other.siteUrl;

  @override
  int get hashCode => Object.hash(identityHashCode(owner), siteUrl);
}
