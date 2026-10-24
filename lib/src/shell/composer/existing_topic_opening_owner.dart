import '../../data/account_request_session.dart';
import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import '../../data/store.dart';
import '../../models/content_route.dart';
import '../../models/post.dart';
import '../../models/topic.dart';
import '../../models/user_draft.dart';
import 'controller.dart';
import 'draft_coordinator.dart';

abstract interface class ExistingTopicOpeningReader {
  bool isCurrentRoute(ContentRoute route);
}

final class ExistingTopicOpeningOrigin {
  const ExistingTopicOpeningOrigin({
    required this.siteUrl,
    required this.lease,
    required this.tabId,
    required this.reader,
    required this.route,
    required this.topic,
    required this.canReply,
  });

  final String siteUrl;
  final SiteLease lease;
  final String? tabId;
  final ExistingTopicOpeningReader reader;
  final ContentRoute route;
  final TopicDetail? topic;
  final bool canReply;

  bool get isCurrent => lease.isCurrent && reader.isCurrentRoute(route);
}

abstract interface class ExistingTopicOpeningEditors {
  ComposerController? get selectedComposer;
  Iterable<ComposerController> forSite(String siteUrl);
  bool owns(ComposerController composer);
}

sealed class ReplyOpeningPlan {
  const ReplyOpeningPlan(this.origin, this.target);

  final ExistingTopicOpeningOrigin origin;
  final ReplyComposerTarget target;
}

final class ReuseReplyOpeningPlan extends ReplyOpeningPlan {
  const ReuseReplyOpeningPlan(super.origin, super.target, this.composer);

  final ComposerController composer;
}

final class CreateReplyOpeningPlan extends ReplyOpeningPlan {
  const CreateReplyOpeningPlan(super.origin, super.target, this.listedDraft);

  final UserDraft? listedDraft;
}

final class QuoteOpeningPlan {
  const QuoteOpeningPlan._(this.origin, this.composer, this.reply);

  final ExistingTopicOpeningOrigin origin;
  final ComposerController? composer;
  final ReplyOpeningPlan? reply;
}

final class EditOpeningPlan {
  const EditOpeningPlan._(
    this.origin,
    this.target,
    this.post,
    this.minimumRequiredTags,
    this.focusText,
  );

  final ExistingTopicOpeningOrigin origin;
  final PostEditingComposerTarget target;
  final Post post;
  final int minimumRequiredTags;
  final String? focusText;
}

/// Opening policy and continuations retain the original account and editor.
final class ExistingTopicComposerOpeningOwner {
  ExistingTopicComposerOpeningOwner({
    required this._editors,
    required this._store,
    required this._drafts,
    required this._credentials,
    required this._content,
  });

  final ExistingTopicOpeningEditors _editors;
  final Store _store;
  final ComposerDraftCoordinator _drafts;
  final SiteApiKeyReader _credentials;
  final TopicContentApi _content;
  bool _disposed = false;

  ReplyOpeningPlan? prepareReply(
    ExistingTopicOpeningOrigin origin, {
    int? replyToPostNumber,
    String? replyToUsername,
    bool? replyingToWhisper,
    UserDraft? listedDraft,
  }) {
    final topicId = origin.route.topicId;
    if (_disposed || !origin.isCurrent || !origin.canReply || topicId == null) {
      return null;
    }
    final target = ReplyComposerTarget(
      siteUrl: origin.siteUrl,
      tabId: origin.tabId,
      topicId: topicId,
      slug: origin.route.slug ?? '',
      topicTitle: origin.topic?.title ?? origin.route.title,
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
      replyingToWhisper:
          replyingToWhisper ?? _replyTargetsWhisper(origin, replyToPostNumber),
      privateMessageTopic: origin.topic?.privateMessage ?? false,
    );
    final existing =
        _editors.forSite(origin.siteUrl).where((composer) {
          final target = composer.target;
          return target is ReplyComposerTarget && target.topicId == topicId;
        }).firstOrNull ??
        _editors.selectedComposer;
    if (existing?.discarding == true) return null;
    if (existing != null &&
        !existing.closing &&
        _isReplyFor(existing, origin)) {
      return ReuseReplyOpeningPlan(origin, target, existing);
    }
    return CreateReplyOpeningPlan(origin, target, listedDraft);
  }

  bool _replyTargetsWhisper(
    ExistingTopicOpeningOrigin origin,
    int? postNumber,
  ) {
    if (postNumber == null) return false;
    for (final id in origin.topic?.stream ?? const <int>[]) {
      final post = _store.read<Post>(origin.siteUrl, id);
      if (post?.postNumber == postNumber) return post!.isWhisper;
    }
    return false;
  }

  bool _isReplyFor(
    ComposerController? composer,
    ExistingTopicOpeningOrigin origin,
  ) {
    final target = composer?.target;
    return target is ReplyComposerTarget &&
        target.topicId == origin.route.topicId &&
        target.siteUrl == origin.siteUrl;
  }

  bool _owns(ExistingTopicOpeningOrigin origin, ComposerController composer) =>
      !_disposed &&
      origin.lease.isCurrent &&
      _editors.owns(composer) &&
      !composer.isDisposed;

  void reuseReply(ReuseReplyOpeningPlan plan) {
    if (!_owns(plan.origin, plan.composer)) return;
    plan.composer.retarget(
      replyToPostNumber: plan.target.replyToPostNumber,
      replyToUsername: plan.target.replyToUsername,
      replyingToWhisper: plan.target.replyingToWhisper,
    );
    if (_owns(plan.origin, plan.composer)) plan.composer.focus.requestFocus();
  }

  void startReply(CreateReplyOpeningPlan plan, ComposerController composer) {
    if (!_owns(plan.origin, composer)) return;
    _drafts.startRestore(composer, listedDraft: plan.listedDraft);
  }

  QuoteOpeningPlan? prepareQuote(
    ExistingTopicOpeningOrigin origin,
    Post post,
    String quote,
  ) {
    if (_disposed ||
        !origin.isCurrent ||
        !origin.canReply ||
        quote.trim().isEmpty) {
      return null;
    }
    final composer = _editors.selectedComposer;
    if (_isReplyFor(composer, origin)) {
      return QuoteOpeningPlan._(origin, composer, null);
    }
    final reply = prepareReply(
      origin,
      replyToPostNumber: post.postNumber == 1 ? null : post.postNumber,
      replyToUsername: post.postNumber == 1 ? null : post.username,
      replyingToWhisper: post.postNumber != 1 && post.isWhisper,
    );
    return reply == null ? null : QuoteOpeningPlan._(origin, null, reply);
  }

  Future<void> insertQuote(
    QuoteOpeningPlan plan,
    ComposerController composer,
    String quote,
  ) async {
    final restore = _editors.owns(composer)
        ? _drafts.restoreTaskFor(composer)
        : null;
    if (restore != null) {
      try {
        await restore;
      } catch (_) {}
    }
    if (!_owns(plan.origin, composer) || !plan.origin.isCurrent) return;
    if (!composer.insertBlock(expectedValue: composer.value, markdown: quote)) {
      return;
    }
    if (_owns(plan.origin, composer)) composer.focus.requestFocus();
  }

  EditOpeningPlan? prepareEdit(
    ExistingTopicOpeningOrigin origin,
    Post post, {
    TopicCategory? category,
    String? focusText,
  }) {
    final topicId = origin.route.topicId;
    if (_disposed || !origin.isCurrent || topicId == null || !post.canEdit) {
      return null;
    }
    final detail = origin.topic;
    final editsTopic = post.postNumber == 1 && detail?.canEdit == true;
    // original_title uses the stored title before any route display text.
    final title = detail?.title ?? origin.route.title;
    final target = editsTopic
        ? TopicEditComposerTarget(
            siteUrl: origin.siteUrl,
            tabId: origin.tabId,
            topicId: topicId,
            slug: origin.route.slug ?? '',
            topicTitle: title,
            editingPostId: post.id,
            initialCategoryId: detail?.categoryId,
            initialTags: detail?.tags ?? const [],
            privateMessageTopic: detail?.privateMessage ?? false,
          )
        : PostEditComposerTarget(
            siteUrl: origin.siteUrl,
            tabId: origin.tabId,
            topicId: topicId,
            slug: origin.route.slug ?? '',
            topicTitle: title,
            editingPostId: post.id,
            editingPostNumber: post.postNumber,
            privateMessageTopic: detail?.privateMessage ?? false,
          );
    return EditOpeningPlan._(
      origin,
      target,
      post,
      editsTopic ? category?.minimumRequiredTags ?? 0 : 0,
      focusText,
    );
  }

  Future<void> loadEditBody(
    EditOpeningPlan plan,
    ComposerController composer,
  ) async {
    final origin = plan.origin;
    if (!_owns(origin, composer)) return;
    final target = plan.target;
    final post = plan.post;
    if (post.raw case final raw?) {
      composer.loadedBody(
        raw,
        caretOffset: _editCaretOffset(raw, plan.focusText),
      );
      return;
    }
    composer.beginLoadingBody();
    if (!_owns(origin, composer)) return;
    try {
      final credential = await AccountRequestSession(
        target.siteUrl,
        origin.lease,
      ).keyCredentials(_credentials);
      if (!_owns(origin, composer)) return;
      final fetched = await credential.run(
        () => _content.posts(
          siteUrl: target.siteUrl,
          topicId: target.topicId,
          ids: [post.id],
          includeRaw: true,
          apiKey: credential.apiKey,
        ),
      );
      if (!_owns(origin, composer)) return;
      final raw = fetched.firstWhere((p) => p.id == post.id).raw;
      if (raw == null) {
        composer.bodyLoadFailed();
      } else {
        composer.loadedBody(
          raw,
          caretOffset: _editCaretOffset(raw, plan.focusText),
        );
      }
    } catch (_) {
      if (_owns(origin, composer)) composer.bodyLoadFailed();
    }
  }

  void dispose() => _disposed = true;

  static int? _editCaretOffset(String raw, String? focusText) {
    final selection = focusText?.trim();
    if (selection == null || selection.isEmpty) return null;
    final firstLine = selection
        .split(RegExp(r'[\r\n]'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim()
        .replaceFirst(RegExp(r'^\*\s+'), '');
    if (firstLine.isEmpty) return 0;

    var match = raw.indexOf(firstLine);
    if (match < 0) {
      match = _plainQuoteCharacters(
        raw,
      ).indexOf(_plainQuoteCharacters(firstLine));
    }
    return match < 0 ? 0 : raw.lastIndexOf('\n', match - 1) + 1;
  }

  static String _plainQuoteCharacters(String value) =>
      value.replaceAll(RegExp('[“”]'), '"').replaceAll(RegExp('[‘’]'), "'");
}
