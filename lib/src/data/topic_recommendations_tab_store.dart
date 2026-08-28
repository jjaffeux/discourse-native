import 'package:shared_preferences/shared_preferences.dart';

import '../plugin_api/topic_recommendation_source.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

/// Per-forum more-topics tab persistence.
abstract interface class TopicRecommendationsTabPersistence {
  /// Reads the raw value so the store can apply the installed source codecs.
  Future<String?> readStoredSourceId({required String siteUrl});

  Future<bool> writeTab({
    required String siteUrl,
    required TopicRecommendationSourceId sourceId,
  });
}

final class SharedPreferencesTopicRecommendationsTabPersistence
    implements TopicRecommendationsTabPersistence {
  const SharedPreferencesTopicRecommendationsTabPersistence();

  static const String _keyPrefix = 'discourse_native.topic_recommendations_tab';

  @override
  Future<String?> readStoredSourceId({required String siteUrl}) async =>
      (await SharedPreferences.getInstance()).getString(_key(siteUrl));

  @override
  Future<bool> writeTab({
    required String siteUrl,
    required TopicRecommendationSourceId sourceId,
  }) async => (await SharedPreferences.getInstance()).setString(
    _key(siteUrl),
    sourceId.value,
  );

  static String _key(String siteUrl) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}';
}

/// Remembers the reader's last recommendation source on each forum.
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
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  Future<TopicRecommendationSourceId> read({
    required String siteUrl,
    TopicRecommendationSourceMigrationRegistry sourceMigrations =
        const EmptyTopicRecommendationSourceMigrationRegistry(),
  }) => _operations.read(
    owner: _persistence,
    key: siteUrl,
    operation: () => _read(siteUrl, sourceMigrations),
  );

  Future<TopicRecommendationSourceId> _read(
    String siteUrl,
    TopicRecommendationSourceMigrationRegistry sourceMigrations,
  ) async {
    try {
      return _sourceIdFromStoredValue(
            await _persistence.readStoredSourceId(siteUrl: siteUrl),
            sourceMigrations,
          ) ??
          coreSuggestedTopicRecommendationSourceId;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'topicRecommendationsTab.readTab',
      );
      return coreSuggestedTopicRecommendationSourceId;
    }
  }

  Future<void> write({
    required String siteUrl,
    required TopicRecommendationSourceId sourceId,
  }) => _operations.write<void>(
    owner: _persistence,
    key: siteUrl,
    operation: () => _persist(siteUrl: siteUrl, sourceId: sourceId),
  );

  Future<void> _persist({
    required String siteUrl,
    required TopicRecommendationSourceId sourceId,
  }) async {
    try {
      final saved = await _persistence.writeTab(
        siteUrl: siteUrl,
        sourceId: sourceId,
      );
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

TopicRecommendationSourceId? _sourceIdFromStoredValue(
  String? value,
  TopicRecommendationSourceMigrationRegistry sourceMigrations,
) {
  if (value == null) return null;

  // Versions before recommendation contributions persisted enum names. Map
  // core's own value here; optional sources resolve their aliases through the
  // installed codec registry.
  if (value == coreSuggestedTopicRecommendationLegacyStoredId) {
    return coreSuggestedTopicRecommendationSourceId;
  }

  final sourceId = TopicRecommendationSourceId(value);
  if (sourceId.isNamespaced) return sourceId;
  return sourceMigrations.migrateLegacyStoredId(value);
}
