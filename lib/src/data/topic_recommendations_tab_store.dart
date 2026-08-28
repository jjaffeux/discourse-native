import 'package:shared_preferences/shared_preferences.dart';

import '../plugin_api/topic_recommendation_source.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

/// Per-forum more-topics tab persistence.
abstract interface class TopicRecommendationsTabPersistence {
  Future<TopicRecommendationSourceId?> readTab({required String siteUrl});

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
  Future<TopicRecommendationSourceId?> readTab({
    required String siteUrl,
  }) async => _sourceIdFromStoredValue(
    (await SharedPreferences.getInstance()).getString(_key(siteUrl)),
  );

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

  Future<TopicRecommendationSourceId> read({required String siteUrl}) =>
      _operations.read(
        owner: _persistence,
        key: siteUrl,
        operation: () => _read(siteUrl),
      );

  Future<TopicRecommendationSourceId> _read(String siteUrl) async {
    try {
      return await _persistence.readTab(siteUrl: siteUrl) ??
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

TopicRecommendationSourceId? _sourceIdFromStoredValue(String? value) {
  if (value == null) return null;

  // Versions before recommendation contributions persisted enum names. Map
  // those once at the storage boundary; all new values are stable source ids.
  if (value == 'suggested') return coreSuggestedTopicRecommendationSourceId;
  if (value == 'related') {
    return const TopicRecommendationSourceId('discourse-ai/related');
  }

  final sourceId = TopicRecommendationSourceId(value);
  return sourceId.isNamespaced ? sourceId : null;
}
