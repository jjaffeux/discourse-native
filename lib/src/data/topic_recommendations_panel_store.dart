import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import 'serial_operation_queue.dart';

/// Per-forum topic-recommendations panel persistence.
abstract interface class TopicRecommendationsPanelPersistence {
  Future<bool?> readCollapsed({required String siteUrl});

  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  });
}

final class SharedPreferencesTopicRecommendationsPanelPersistence
    implements TopicRecommendationsPanelPersistence {
  const SharedPreferencesTopicRecommendationsPanelPersistence();

  static const String _keyPrefix =
      'discourse_native.topic_recommendations_panel_collapsed';

  @override
  Future<bool?> readCollapsed({required String siteUrl}) async =>
      (await SharedPreferences.getInstance()).getBool(_key(siteUrl));

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  }) async =>
      (await SharedPreferences.getInstance()).setBool(_key(siteUrl), collapsed);

  static String _key(String siteUrl) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}';
}

/// Remembers whether the reader collapsed more topics on each forum.
///
/// This is optional presentation state. Storage failures leave the panel open
/// and never prevent a topic from being read.
final class TopicRecommendationsPanelStore {
  const TopicRecommendationsPanelStore({
    TopicRecommendationsPanelPersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesTopicRecommendationsPanelPersistence();

  final TopicRecommendationsPanelPersistence _persistence;
  static final SerialOperationQueue _operations = SerialOperationQueue();
  static final Map<_TopicPanelOperationKey, int> _pendingWrites = {};

  Future<bool> read({required String siteUrl}) {
    final key = _TopicPanelOperationKey(_persistence, siteUrl);
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

  Future<bool> _read(String siteUrl) async {
    try {
      return await _persistence.readCollapsed(siteUrl: siteUrl) ?? false;
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'topicRecommendationsPanel.readCollapsed');
      return false;
    }
  }

  Future<void> write({required String siteUrl, required bool collapsed}) async {
    final key = _TopicPanelOperationKey(_persistence, siteUrl);
    _pendingWrites.update(key, (count) => count + 1, ifAbsent: () => 1);
    try {
      await _operations.run<void>(
        owner: _persistence,
        key: siteUrl,
        operation: () => _persist(siteUrl: siteUrl, collapsed: collapsed),
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
    required bool collapsed,
  }) async {
    try {
      final saved = await _persistence.writeCollapsed(
        siteUrl: siteUrl,
        collapsed: collapsed,
      );
      if (!saved) {
        throw StateError(
          'Could not persist topic recommendations panel state.',
        );
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'topicRecommendationsPanel.writeCollapsed');
    }
  }

  static void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'storage',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }
}

final class _TopicPanelOperationKey {
  const _TopicPanelOperationKey(this.owner, this.siteUrl);

  final Object owner;
  final String siteUrl;

  @override
  bool operator ==(Object other) =>
      other is _TopicPanelOperationKey &&
      identical(owner, other.owner) &&
      siteUrl == other.siteUrl;

  @override
  int get hashCode => Object.hash(identityHashCode(owner), siteUrl);
}
