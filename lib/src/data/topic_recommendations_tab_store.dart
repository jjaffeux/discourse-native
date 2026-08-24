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
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  Future<TopicRecommendationsTab> read({required String siteUrl}) => _operations
      .read(owner: _persistence, key: siteUrl, operation: () => _read(siteUrl));

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
  }) => _operations.write<void>(
    owner: _persistence,
    key: siteUrl,
    operation: () => _persist(siteUrl: siteUrl, tab: tab),
  );

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
