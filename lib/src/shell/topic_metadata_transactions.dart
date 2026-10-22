part of 'shell_controller.dart';

sealed class _TopicMetadataCommand {
  const _TopicMetadataCommand();

  String get staleMessage => switch (this) {
    _TopicTitleCommand() => appL10n.theForumChangedBeforeTheTitleSaved,
    _TopicCategoryCommand() => appL10n.theForumChangedBeforeTheCategorySaved,
    _TopicTagsCommand() => appL10n.theSiteChangedBeforeTagsWereSaved,
  };

  String get diagnosticOperation => switch (this) {
    _TopicTitleCommand() => 'topic.editTitle',
    _TopicCategoryCommand() => 'topic.editCategory',
    _TopicTagsCommand() => 'topicSidebar.editTopicTags',
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

extension _TopicMetadataTransactions on ShellController {
  Future<String?> _saveTopicMetadata({
    required String siteUrl,
    required int topicId,
    required _TopicMetadataCommand command,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return command.staleMessage;
    if (credential.failure case final failure?) return failure.message;

    final TopicUpdate update;
    try {
      final request = credential.request!;
      switch (command) {
        case _TopicTitleCommand(:final title, :final originalTitle):
          update = await request.run(
            () => api.topicMutations.updateTopic(
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
            () => api.topicMutations.updateTopic(
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
            () => api.topicMutations.updateTopicTags(
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
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, command.diagnosticOperation);
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return command.staleMessage;

    lease.commit(() {
      switch (command) {
        case _TopicTitleCommand(:final title):
          final stored = update.title ?? title;
          store.update<TopicDetail>(
            siteUrl,
            topicId,
            (topic) => topic.copyWith(title: stored),
          );
          store.update<Topic>(
            siteUrl,
            topicId,
            (topic) => topic.copyWith(title: stored),
          );
          _retitle(siteUrl, topicId, stored);
        case _TopicCategoryCommand(:final title, :final categoryId):
          store.update<TopicDetail>(
            siteUrl,
            topicId,
            (topic) =>
                topic.copyWith(categoryId: categoryId, tags: update.tags),
          );
          store.update<Topic>(
            siteUrl,
            topicId,
            (topic) =>
                topic.copyWith(categoryId: categoryId, tags: update.tags),
          );
          _updateTopicRouteMetadata(siteUrl, topicId, title, categoryId);
        case _TopicTagsCommand(:final tags):
          _applyTopicTags(siteUrl, topicId, tags);
      }
      _notify();
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
    for (final tag in selected) {
      try {
        final result = await credential.run(
          () => api.topicComposerQueries.searchTopicTags(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            term: tag.name,
            categoryId: categoryId,
            selectedTagIds: selected.map((item) => item.id).whereType<int>(),
            limit: siteConfigFor(
              siteUrl,
            ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
          ),
        );
        final match = result.results
            .where(
              (item) =>
                  item.id == tag.id ||
                  item.name.toLowerCase() == tag.name.toLowerCase(),
            )
            .firstOrNull;
        if (!result.isForbidden && match != null && !match.disabled) {
          kept.add(match);
        }
      } catch (_) {
        return selected;
      }
    }
    return List.unmodifiable(kept);
  }
}
