import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';

import '../../data/account_request_session.dart';
import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import '../../models/composer_draft.dart';
import '../../models/content_route.dart';
import '../../models/discourse_user.dart';
import '../../models/list_link.dart';
import '../../models/post.dart';
import '../../models/topic.dart';
import '../../models/user_draft.dart';
import 'controller.dart';
import 'draft_coordinator.dart';

/// Captured navigation facts for one new-topic opening attempt.
final class NewTopicOpeningOrigin {
  const NewTopicOpeningOrigin({
    required this.siteUrl,
    required this.lease,
    required this.tabId,
    required this.feedId,
    required this.content,
    required this.route,
    required this.defaultFeedId,
    required this.revealContent,
    required this.hasSourceRoute,
  });

  final String siteUrl;
  final SiteLease lease;
  final String tabId;
  final String feedId;
  final ContentRoute? content;
  final ContentRoute route;
  final String defaultFeedId;
  final bool revealContent;
  final bool hasSourceRoute;
}

final class NewTopicOpeningPlan {
  const NewTopicOpeningPlan({
    required this.origin,
    required this.target,
    required this.link,
    required this.category,
    required this.placeholderCategory,
    required this.listedDraft,
  });

  final NewTopicOpeningOrigin origin;
  final NewTopicComposerTarget target;
  final ListLink? link;
  final TopicCategory? category;
  final TopicCategory? placeholderCategory;
  final UserDraft? listedDraft;
}

/// The registry and navigation retain authority over editor presentation.
abstract interface class ComposerOpeningPresentation {
  ComposerController? get selectedComposer;
  bool get canCreateTopicHere;
  bool owns(ComposerController composer);
  bool isCurrentOrigin(NewTopicOpeningOrigin origin);
  Future<void>? confirmReplacement(ComposerController composer);
  void publishOpening();
}

/// Canonical taxonomy and capability caches stay with their existing owners.
abstract interface class ComposerOpeningMetadata {
  TopicCategory? categoryFor(String siteUrl, int? categoryId);
  List<TopicCategory> categoriesFor(String siteUrl);
  void mergeCategories(String siteUrl, List<TopicCategory> categories);
  void Function(List<TopicCategory>) captureCategoryRead(String siteUrl);
  Future<void> ensureForOpening(String siteUrl);
  TopicComposerCapabilities capabilitiesFor(String siteUrl);
  Future<TopicTagSearch> searchTags(ComposerController composer, String term);
}

final class PrivateMessageOpeningOrigin {
  const PrivateMessageOpeningOrigin({
    required this.siteUrl,
    required this.tabId,
    required this.feedId,
    required this.route,
    required this.user,
  });

  final String siteUrl;
  final String? tabId;
  final String? feedId;
  final ContentRoute? route;
  final DiscourseUser? user;
}

final class ContinuationOpeningOrigin {
  const ContinuationOpeningOrigin({
    required this.siteUrl,
    required this.lease,
    required this.tabId,
    required this.topic,
  });

  final String siteUrl;
  final SiteLease lease;
  final String tabId;
  final TopicDetail topic;
}

final class ContinuationOpeningSource {
  const ContinuationOpeningSource(this.topic, this.user);

  final TopicDetail topic;
  final DiscourseUser? user;
}

final class ContinuationOpeningPlan {
  const ContinuationOpeningPlan(
    this.origin,
    this.target,
    this.minimumRequiredTags,
  );

  final ContinuationOpeningOrigin origin;
  final ComposerTarget target;
  final int minimumRequiredTags;
}

abstract interface class ComposerCreationPresentation {
  Iterable<ComposerController> retainedForSite(String siteUrl);
  void selectComposer(ComposerController composer);
  ContinuationOpeningSource? continuationSource(
    ContinuationOpeningOrigin origin,
  );
}

final class _ComposerSetupSession {
  _ComposerSetupSession(this.composer, this.lease)
    : siteUrl = composer.target.siteUrl,
      draftKey = composer.target.draftKey;

  final ComposerController composer;
  final SiteLease lease;
  final String siteUrl;
  final String draftKey;

  bool isCurrent(ComposerOpeningPresentation presentation) =>
      lease.isCurrent &&
      presentation.owns(composer) &&
      !composer.isDisposed &&
      composer.target.siteUrl == siteUrl &&
      composer.target.draftKey == draftKey;
}

/// Owns opening admission and delayed setup for exact account/editor lifetimes.
final class ComposerOpeningOwner {
  ComposerOpeningOwner({
    required this._presentation,
    required this._creation,
    required this._metadata,
    required this._drafts,
    required this._credentials,
    required this._categories,
    required this._queries,
  });

  final ComposerOpeningPresentation _presentation;
  final ComposerCreationPresentation _creation;
  final ComposerOpeningMetadata _metadata;
  final ComposerDraftCoordinator _drafts;
  final SiteApiKeyReader _credentials;
  final CategoryQueriesApi _categories;
  final TopicComposerQueriesApi _queries;
  bool _disposed = false;

  Future<bool> prepareReplacement() async {
    final existing = _presentation.selectedComposer;
    if (existing == null) return true;
    if (existing.closing || existing.hasPendingOperation) {
      return false;
    }
    if (existing.canSaveDraft && !await _drafts.finishRestore(existing)) {
      return false;
    }
    if (!identical(_presentation.selectedComposer, existing) ||
        existing.closing ||
        existing.hasPendingOperation) {
      return false;
    }
    if (existing.canSaveDraft) return true;
    if (!existing.hasChanges &&
        !existing.metadataChanged &&
        !existing.hasUnappliedDraft) {
      return true;
    }
    final confirmation = _presentation.confirmReplacement(existing);
    if (confirmation == null) return false;
    await confirmation;
    return existing.isDisposed && _presentation.selectedComposer == null;
  }

  PrivateMessageComposerTarget? preparePrivateMessage({
    required String siteUrl,
    required PrivateMessageOpeningOrigin? origin,
    required String targetRecipients,
    bool? groupMessageable,
  }) {
    final user = origin?.user;
    // A messageable group can admit a reader who cannot start general messages.
    if (_disposed ||
        origin == null ||
        origin.siteUrl != siteUrl ||
        user == null ||
        !(groupMessageable ?? user.canSendPrivateMessages) ||
        origin.route?.isTopic != false ||
        origin.tabId == null ||
        origin.feedId == null) {
      return null;
    }
    final held = _creation
        .retainedForSite(siteUrl)
        .where(
          (composer) =>
              composer.target.isPrivateMessage &&
              composer.canSaveDraft &&
              composer.target.draftKey ==
                  ComposerDraft.newPrivateMessageDraftKey,
        )
        .firstOrNull;
    if (held != null) {
      if (held.closing || held.hasPendingOperation) return null;
      if (!identical(held, _presentation.selectedComposer)) {
        _creation.selectComposer(held);
      }
    }
    return PrivateMessageComposerTarget(
      siteUrl: siteUrl,
      tabId: origin.tabId!,
      topicTitle: appL10n.newMessage,
      originFeedId: origin.feedId!,
      targetRecipients: targetRecipients
          .split(',')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .join(','),
    );
  }

  void startPrivateMessage(ComposerController composer) {
    _drafts.startRestore(composer);
    if (composer.target.targetRecipients?.isNotEmpty == true) {
      composer.requestFocus();
    }
  }

  static bool canContinue(TopicDetail topic, DiscourseUser? user) =>
      topic.canReplyAsNewTopic &&
      (!topic.privateMessage || user?.canSendPrivateMessages == true);

  ContinuationOpeningSource? _continuationSource(
    ContinuationOpeningOrigin origin,
  ) {
    if (_disposed || !origin.lease.isCurrent) return null;
    final source = _creation.continuationSource(origin);
    // The source link must never escape a private conversation.
    if (source == null ||
        source.topic.privateMessage != origin.topic.privateMessage ||
        !canContinue(source.topic, source.user)) {
      return null;
    }
    return source;
  }

  Future<ContinuationOpeningPlan?> prepareContinuation(
    ContinuationOpeningOrigin origin, {
    required String continuation,
    required String Function(String base) allocateDraftKey,
  }) async {
    if (continuation.trim().isEmpty || _continuationSource(origin) == null) {
      return null;
    }
    if (!origin.topic.privateMessage) {
      await _metadata.ensureForOpening(origin.siteUrl);
      if (_continuationSource(origin) == null) return null;
    }
    if (!await prepareReplacement()) return null;
    final source = _continuationSource(origin);
    if (source == null) return null;
    final ComposerTarget target;
    var minimumRequiredTags = 0;
    if (source.topic.privateMessage) {
      final username = source.user?.username.toLowerCase();
      final others = [
        for (final name in source.topic.allowedMessageUsers)
          if (name.toLowerCase() != username) name,
        ...source.topic.allowedMessageGroups,
      ];
      target = PrivateMessageComposerTarget(
        siteUrl: origin.siteUrl,
        tabId: origin.tabId,
        topicTitle: appL10n.newMessage,
        originTopicId: origin.topic.id,
        draftKey: allocateDraftKey(ComposerDraft.newPrivateMessageDraftKey),
        targetRecipients:
            (others.isEmpty ? source.topic.allowedMessageUsers : others).join(
              ',',
            ),
      );
    } else {
      final category = _metadata
          .categoriesFor(origin.siteUrl)
          .where(
            (item) => item.id == origin.topic.categoryId && item.canCreateTopic,
          )
          .firstOrNull;
      minimumRequiredTags = category?.minimumRequiredTags ?? 0;
      target = NewTopicComposerTarget(
        siteUrl: origin.siteUrl,
        tabId: origin.tabId,
        topicTitle: appL10n.newTopic,
        originTopicId: origin.topic.id,
        draftKey: allocateDraftKey(ComposerDraft.newTopicDraftKey),
        initialCategoryId: category?.id,
      );
    }
    return ContinuationOpeningPlan(origin, target, minimumRequiredTags);
  }

  bool isCurrentContinuation(ContinuationOpeningPlan plan) =>
      _continuationSource(plan.origin) != null;

  void startContinuation(
    ContinuationOpeningPlan plan,
    ComposerController composer,
    String continuation,
  ) {
    _drafts.startNewDraft(composer);
    if (!isCurrentContinuation(plan) || !_presentation.owns(composer)) {
      return;
    }
    if (!composer.text.text.contains(continuation.trim())) {
      composer.prependBlock(continuation);
    }
    composer.focus.requestFocus();
  }

  Future<NewTopicOpeningPlan?> prepareNewTopic(
    NewTopicOpeningOrigin origin, {
    required String Function() allocateDraftKey,
    required String Function() topicTitle,
    UserDraft? listedDraft,
  }) async {
    if (!await prepareReplacement() ||
        _disposed ||
        !origin.lease.isCurrent ||
        !_presentation.isCurrentOrigin(origin)) {
      return null;
    }
    final route = origin.route;
    final path = route.feedPath;
    final link = path == null
        ? null
        : ListLink.parse(path.replaceFirst(RegExp(r'\.json$'), ''));
    final canCreateHere = _presentation.canCreateTopicHere;
    final originFeedId = origin.revealContent && !canCreateHere
        ? origin.defaultFeedId
        : origin.feedId;
    final categoryId = canCreateHere || origin.hasSourceRoute
        ? route.categoryId
        : null;
    var category = _metadata.categoryFor(origin.siteUrl, categoryId);
    final needsLookup = categoryId != null && category == null;
    if (category == null &&
        categoryId != null &&
        link?.kind == ListKind.category) {
      final color = route.color?.toARGB32();
      category = TopicCategory(
        id: categoryId,
        name: route.title,
        color: color == null
            ? '888888'
            : (color & 0x00ffffff)
                  .toRadixString(16)
                  .padLeft(6, '0')
                  .toUpperCase(),
        slug: link!.slug,
      );
    }
    if (needsLookup && category != null) {
      _metadata.mergeCategories(origin.siteUrl, [category]);
    }
    return NewTopicOpeningPlan(
      origin: origin,
      target: NewTopicComposerTarget(
        siteUrl: origin.siteUrl,
        tabId: origin.tabId,
        topicTitle: topicTitle(),
        draftKey: listedDraft?.key ?? allocateDraftKey(),
        originFeedId: originFeedId,
        initialCategoryId: categoryId,
      ),
      link: link,
      category: category,
      placeholderCategory: needsLookup ? category : null,
      listedDraft: listedDraft,
    );
  }

  bool isCurrent(NewTopicOpeningPlan plan) =>
      !_disposed &&
      plan.origin.lease.isCurrent &&
      _presentation.isCurrentOrigin(plan.origin);

  Future<void> start(NewTopicOpeningPlan plan, ComposerController composer) {
    if (plan.listedDraft == null) {
      _drafts.startNewDraft(composer);
    } else {
      _drafts.startRestore(composer, listedDraft: plan.listedDraft);
    }
    return _enrich(_ComposerSetupSession(composer, plan.origin.lease), plan);
  }

  void dispose() {
    _disposed = true;
  }

  Future<void> _enrich(
    _ComposerSetupSession session,
    NewTopicOpeningPlan plan,
  ) async {
    final composer = session.composer;
    final siteUrl = session.siteUrl;
    final lease = session.lease;
    final link = plan.link;
    final categoryId = plan.target.initialCategoryId;
    final placeholderCategory = plan.placeholderCategory;
    bool isCurrent() => !_disposed && session.isCurrent(_presentation);

    await _metadata.ensureForOpening(siteUrl);
    if (!isCurrent()) return;

    AccountRequestCredentials? requestCredentials;
    var credentialsRead = false;
    Future<AccountRequestCredentials?> readCredentials() async {
      if (credentialsRead) return requestCredentials;
      credentialsRead = true;
      try {
        final credential = await AccountRequestSession(
          siteUrl,
          lease,
        ).keyCredentials(_credentials);
        if (!isCurrent() || credential.apiKey == null) return null;
        return requestCredentials = credential;
      } catch (_) {
        return null;
      }
    }

    final loadedCategory = _metadata.categoryFor(siteUrl, categoryId);
    final stillHasPlaceholder =
        placeholderCategory != null &&
        identical(loadedCategory, placeholderCategory);
    if (categoryId != null && (loadedCategory == null || stillHasPlaceholder)) {
      final publishCategories = _metadata.captureCategoryRead(siteUrl);
      final credential = await readCredentials();
      if (!isCurrent()) return;
      if (credential != null) {
        try {
          final found = await credential.run(
            () => _categories.findCategories(
              siteUrl: siteUrl,
              ids: [categoryId],
              apiKey: credential.apiKey!,
            ),
          );
          if (!isCurrent()) return;
          if (found.isNotEmpty) {
            publishCategories(found);
            _presentation.publishOpening();
          }
        } catch (_) {}
      }
    }
    if (!isCurrent()) return;

    final capabilities = _metadata.capabilitiesFor(siteUrl);
    if (link?.kind == ListKind.tag && capabilities.canTagTopics) {
      final tagLink = link!;
      final credential = await readCredentials();
      if (!isCurrent()) return;
      if (credential != null) {
        try {
          final result = await credential.run(
            () => _queries.searchTopicTags(
              siteUrl: siteUrl,
              apiKey: credential.apiKey!,
              term: tagLink.slug,
              categoryId: categoryId,
            ),
          );
          if (!isCurrent()) return;
          final exact = result.results.where(
            (tag) =>
                tag.id == tagLink.id ||
                tag.name.toLowerCase() == tagLink.slug.toLowerCase() ||
                tag.slug?.toLowerCase() == tagLink.slug.toLowerCase(),
          );
          if (exact.isNotEmpty && !exact.first.disabled) {
            composer.applyInitialTagsIfUntouched([exact.first]);
          }
        } catch (_) {}
      }
    }
    if (!isCurrent()) return;

    composer.setMinimumRequiredTags(
      _metadata
              .categoryFor(siteUrl, composer.categoryId)
              ?.minimumRequiredTags ??
          0,
    );
    unawaited(_applyInitialTemplateAfterDraftRestore(composer, isCurrent));
  }

  Future<void> _applyInitialTemplateAfterDraftRestore(
    ComposerController composer,
    bool Function() isCurrent,
  ) async {
    final restore = _drafts.restoreTaskFor(composer);
    if (restore == null) return;
    try {
      if (!await restore) return;
    } catch (_) {
      return;
    }
    if (!isCurrent()) return;
    composer.applyInitialTopicTemplateIfUntouched(
      _metadata
          .categoryFor(composer.target.siteUrl, composer.categoryId)
          ?.topicTemplate,
    );
  }

  Future<void> changeCategory(
    ComposerController composer,
    int? categoryId,
  ) async {
    final categories = _metadata.categoriesFor(composer.target.siteUrl);
    TopicCategory? find(int? id) =>
        categories.where((category) => category.id == id).firstOrNull;
    final previous = find(composer.categoryId);
    final category = find(categoryId);
    composer.setCategory(
      categoryId,
      minimumRequiredTags: category?.minimumRequiredTags ?? 0,
    );
    composer.applyTopicTemplate(
      category?.topicTemplate,
      replacing: previous?.topicTemplate,
    );
    validateSelection:
    while (_presentation.owns(composer) && composer.categoryId == categoryId) {
      final selectedTags = composer.tags;
      if (selectedTags.isEmpty) return;
      final kept = <TopicTag>[];
      for (final selected in selectedTags) {
        try {
          final result = await _metadata.searchTags(composer, selected.name);
          if (!_presentation.owns(composer) ||
              composer.categoryId != categoryId) {
            return;
          }
          if (!identical(composer.tags, selectedTags)) {
            continue validateSelection;
          }
          final match = result.results
              .where(
                (tag) =>
                    tag.id == selected.id ||
                    tag.name.toLowerCase() == selected.name.toLowerCase(),
              )
              .firstOrNull;
          if (!result.isForbidden && match != null && !match.disabled) {
            kept.add(match);
          }
        } catch (_) {
          return;
        }
      }
      if (kept.length != selectedTags.length) {
        composer.setTags(kept);
        composer.showTagRemovalNotice(categoryName: category?.name);
      }
      return;
    }
  }
}
