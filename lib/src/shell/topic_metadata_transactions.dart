import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/site_lifecycle.dart';
import '../data/topic_composer_queries_api.dart';
import '../data/topic_mutations_api.dart';
import '../data/write_credential.dart';
import '../data/write_failure.dart';
import '../models/topic.dart';
import 'topic_data_owner.dart';

sealed class _TopicMetadataCommand {
  const _TopicMetadataCommand();

  String get staleMessage => switch (this) {
    _TopicTitleCommand() => appL10n.theForumChangedBeforeTheTitleSaved,
    _TopicCategoryCommand() => appL10n.theForumChangedBeforeTheCategorySaved,
    _TopicTagsCommand() => appL10n.theSiteChangedBeforeTagsWereSaved,
  };
}

final class _TopicTitleCommand extends _TopicMetadataCommand {
  const _TopicTitleCommand(this.title, this.originalTitle);

  final String title;
  final String originalTitle;
}

final class _TopicCategoryCommand extends _TopicMetadataCommand {
  _TopicCategoryCommand(this.title, this.categoryId, Iterable<TopicTag> tags)
    : originalTags = List.unmodifiable(tags);

  final String title;
  final int categoryId;
  final List<TopicTag> originalTags;
}

final class _TopicTagsCommand extends _TopicMetadataCommand {
  _TopicTagsCommand(Iterable<TopicTag> tags) : tags = List.unmodifiable(tags);

  final List<TopicTag> tags;
}

final class TopicMetadataTransactions {
  TopicMetadataTransactions({
    required this._lifecycle,
    required this._credentialForWrite,
    required this._topics,
    required this._composerQueries,
    required this._maxTagSearchResults,
    required this._topicData,
    required this._retitle,
    required this._updateTopicRouteMetadata,
    required this._applyTopicTags,
    required this._changed,
  });

  final SiteLifecycle _lifecycle;
  final Future<WriteCredential> Function(
    String siteUrl, {
    required SiteLease lease,
  })
  _credentialForWrite;
  final TopicMutationsApi _topics;
  final TopicComposerQueriesApi _composerQueries;
  final int Function(String siteUrl) _maxTagSearchResults;
  final TopicDataOwner _topicData;
  final void Function(String siteUrl, int topicId, String fallbackTitle)
  _retitle;
  final void Function(
    String siteUrl,
    int topicId,
    String title,
    int? categoryId,
  )
  _updateTopicRouteMetadata;
  final void Function(String siteUrl, int topicId, List<TopicTag> tags)
  _applyTopicTags;
  final void Function() _changed;

  Future<String?> saveTitle({
    required String siteUrl,
    required int topicId,
    required String title,
    required String originalTitle,
  }) => _saveTopicMetadata(
    siteUrl: siteUrl,
    topicId: topicId,
    command: _TopicTitleCommand(title, originalTitle),
  );

  Future<String?> saveCategory({
    required String siteUrl,
    required int topicId,
    required String title,
    required int categoryId,
    required Iterable<TopicTag> tags,
  }) => _saveTopicMetadata(
    siteUrl: siteUrl,
    topicId: topicId,
    command: _TopicCategoryCommand(title, categoryId, tags),
  );

  Future<String?> saveTags({
    required String siteUrl,
    required int topicId,
    required Iterable<TopicTag> tags,
  }) => _saveTopicMetadata(
    siteUrl: siteUrl,
    topicId: topicId,
    command: _TopicTagsCommand(tags),
  );
  Future<String?> _saveTopicMetadata({
    required String siteUrl,
    required int topicId,
    required _TopicMetadataCommand command,
  }) async {
    final lease = _lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return command.staleMessage;
    if (credential.failure case final failure?) return failure.message;

    final TopicUpdate update;
    try {
      final request = credential.request!;
      switch (command) {
        case _TopicTitleCommand(:final title, :final originalTitle):
          update = await request.run(
            () => _topics.updateTopic(
              siteUrl: siteUrl,
              apiKey: credential.apiKey!,
              topicId: topicId,
              title: title,
              originalTitle: originalTitle,
            ),
          );
        case _TopicCategoryCommand(
          :final title,
          :final categoryId,
          :final originalTags,
        ):
          final tags = await _tagsAllowedInCategory(
            siteUrl: siteUrl,
            credential: request,
            categoryId: categoryId,
            selected: originalTags,
          );
          if (!lease.isCurrent) return command.staleMessage;
          final response = await request.run(
            () => _topics.updateTopic(
              siteUrl: siteUrl,
              apiKey: credential.apiKey!,
              topicId: topicId,
              title: title,
              originalTitle: title,
              categoryId: categoryId,
              tags: tags,
              originalTags: originalTags,
            ),
          );
          update = TopicUpdate(tags: response.tags ?? tags);
        case _TopicTagsCommand(:final tags):
          await request.run(
            () => _topics.updateTopicTags(
              siteUrl: siteUrl,
              apiKey: credential.apiKey!,
              topicId: topicId,
              tags: tags,
            ),
          );
          update = const TopicUpdate();
      }
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return command.staleMessage;

    lease.commit(() {
      switch (command) {
        case _TopicTitleCommand(:final title):
          final stored = update.title ?? title;
          _topicData
              .forLease(siteUrl, lease)
              ?.projectAcceptedMetadata(
                topicId,
                title: stored,
                localizedTitle: update.localizedTitle,
              );
          _retitle(siteUrl, topicId, stored);
        case _TopicCategoryCommand(:final title, :final categoryId):
          _topicData
              .forLease(siteUrl, lease)
              ?.projectAcceptedMetadata(
                topicId,
                categoryId: categoryId,
                tags: update.tags,
              );
          _updateTopicRouteMetadata(siteUrl, topicId, title, categoryId);
        case _TopicTagsCommand(:final tags):
          _applyTopicTags(siteUrl, topicId, tags);
      }
      _changed();
    });
    return null;
  }

  Future<List<TopicTag>> _tagsAllowedInCategory({
    required String siteUrl,
    required AccountRequestCredentials credential,
    required int categoryId,
    required List<TopicTag> selected,
  }) async {
    if (selected.isEmpty) return selected;
    final kept = <TopicTag>[];
    const parallelTags = 3;
    for (var start = 0; start < selected.length; start += parallelTags) {
      try {
        final matches = await Future.wait([
          for (final tag in selected.skip(start).take(parallelTags))
            credential.run(() async {
              final result = await _composerQueries.searchTopicTags(
                siteUrl: siteUrl,
                apiKey: credential.apiKey!,
                term: tag.name,
                categoryId: categoryId,
                selectedTagIds: selected
                    .map((item) => item.id)
                    .whereType<int>()
                    .where((id) => id != tag.id),
                limit: _maxTagSearchResults(
                  siteUrl,
                ).clamp(1, TopicTagSearch.maximumResults),
              );
              return result.allowedMatch(tag);
            }),
        ]);
        kept.addAll(matches.nonNulls);
      } catch (_) {
        return selected;
      }
    }
    return List.unmodifiable(kept);
  }
}
