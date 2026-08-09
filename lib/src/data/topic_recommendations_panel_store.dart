import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';

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

  Future<bool> read({required String siteUrl}) async {
    try {
      return await _persistence.readCollapsed(siteUrl: siteUrl) ?? false;
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'topicRecommendationsPanel.readCollapsed');
      return false;
    }
  }

  Future<void> write({required String siteUrl, required bool collapsed}) async {
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
