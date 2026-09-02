// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/site_config.dart';
import '../models/topic_tag.dart';
import '../plugin_api/composer_syntax.dart';
import '../plugin_api/emoji_usage.dart';
import '../plugin_api/hashtag_kind.dart';
import '../plugin_api/plugin_data.dart';
import 'composer_autocomplete.dart';
import 'composer_galleries.dart';
import 'composer_images.dart';
import 'composer_marks.dart';
import 'composer_pills.dart';
import 'composer_quotes.dart';
import 'composer_triggers.dart';
import 'markdown_editing_controller.dart';
import 'markdown_highlight.dart';

enum ComposerMode {
  reply,
  newTopic,
  privateMessage,
  postEdit,
  topicEdit,
  categoryEdit,
  tagsEdit,
  plugin,
}

@immutable
final class ComposerTargetKind {
  const ComposerTargetKind({required this.owner, required this.name});

  final PluginId owner;
  final String name;

  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is ComposerTargetKind && other.owner == owner && other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => id;
}

enum ComposerUploadDisposition { insertMarkdown, retainAttachment }

@immutable
final class ComposerValidationContext {
  const ComposerValidationContext({
    required this.raw,
    required this.completedUploadCount,
  });

  final String raw;
  final int completedUploadCount;
}

typedef ComposerTargetValidator =
    bool Function(ComposerValidationContext context);

@immutable
final class ComposerTargetPolicy {
  const ComposerTargetPolicy({
    required this.kind,
    required this.draftKey,
    required this.uploadType,
    required this.uploadDisposition,
    required this.uploadsEnabled,
    required this.supportsEditing,
    required this.validate,
    required this.emojiUsageContext,
    this.mentionTopicId,
  });

  final ComposerTargetKind kind;
  final String draftKey;
  final ComposerUploadType uploadType;
  final ComposerUploadDisposition uploadDisposition;
  final bool uploadsEnabled;
  final bool supportsEditing;
  final EmojiUsageContext emojiUsageContext;
  final int? mentionTopicId;
  final ComposerTargetValidator validate;
}

@immutable
final class ComposerTargetRequest {
  const ComposerTargetRequest({
    required this.kind,
    required this.siteUrl,
    required this.title,
    this.data = const {},
  });

  final ComposerTargetKind kind;
  final String siteUrl;
  final String title;
  final Map<String, Object?> data;
}

@immutable
class ComposerTarget {
  const ComposerTarget({
    required this.siteUrl,
    required this.topicId,
    required this.slug,
    required this.topicTitle,
    this.tabId,
    this.replyToPostNumber,
    this.replyToUsername,
    this.replyingToWhisper = false,
    this.editingPostId,
    this.editingPostNumber,
    ComposerMode? mode,
    this.originFeedId,
    this.originTopicId,
    this.initialCategoryId,
    this.initialTags = const [],
    this.targetRecipients,
  }) : policy = null,
       data = const {},
       mode =
           mode ??
           (editingPostId == null ? ComposerMode.reply : ComposerMode.postEdit),
       assert(mode != ComposerMode.plugin),
       assert(mode != ComposerMode.privateMessage || targetRecipients != null);

  const ComposerTarget.plugin({
    required this.siteUrl,
    required this.topicTitle,
    required this.policy,
    this.data = const {},
  }) : tabId = null,
       topicId = 0,
       slug = '',
       mode = ComposerMode.plugin,
       originFeedId = null,
       originTopicId = null,
       initialCategoryId = null,
       initialTags = const [],
       targetRecipients = null,
       replyToPostNumber = null,
       replyToUsername = null,
       replyingToWhisper = false,
       editingPostId = null,
       editingPostNumber = null;

  final String siteUrl;
  final String? tabId;
  final int topicId;
  final String slug;
  final String topicTitle;
  final ComposerMode mode;
  final ComposerTargetPolicy? policy;
  final Map<String, Object?> data;
  final String? originFeedId;
  final int? originTopicId;
  final int? initialCategoryId;
  final List<TopicTag> initialTags;
  final String? targetRecipients;

  final int? replyToPostNumber;

  final String? replyToUsername;

  final bool replyingToWhisper;

  final int? editingPostId;

  final int? editingPostNumber;

  bool get isEdit => switch (mode) {
    ComposerMode.postEdit ||
    ComposerMode.topicEdit ||
    ComposerMode.categoryEdit ||
    ComposerMode.tagsEdit => true,
    _ => false,
  };
  bool get isNewTopic => mode == ComposerMode.newTopic;
  bool get isPrivateMessage => mode == ComposerMode.privateMessage;
  bool get createsTopic => isNewTopic || isPrivateMessage;
  bool get editsTopicMetadata => mode == ComposerMode.topicEdit;
  bool get isCategoryEdit => mode == ComposerMode.categoryEdit;
  bool get isTagsEdit => mode == ComposerMode.tagsEdit;
  bool get isTaxonomyEdit => isCategoryEdit || isTagsEdit;
  bool get isPlugin => mode == ComposerMode.plugin;

  String get draftKey => switch (mode) {
    ComposerMode.newTopic => ComposerDraft.newTopicDraftKey,
    ComposerMode.privateMessage => ComposerDraft.newPrivateMessageDraftKey,
    ComposerMode.plugin => policy!.draftKey,
    _ => 'topic_$topicId',
  };

  ComposerTarget replyingTo(
    int? postNumber,
    String? username, {
    bool replyingToWhisper = false,
  }) {
    if (isPlugin) return this;
    return ComposerTarget(
      siteUrl: siteUrl,
      tabId: tabId,
      topicId: topicId,
      slug: slug,
      topicTitle: topicTitle,
      replyToPostNumber: postNumber,
      replyToUsername: username,
      replyingToWhisper: replyingToWhisper,
      mode: mode,
      originFeedId: originFeedId,
      originTopicId: originTopicId,
      initialCategoryId: initialCategoryId,
      initialTags: initialTags,
      targetRecipients: targetRecipients,
    );
  }
}

@immutable
class ComposerDraftSave {
  const ComposerDraftSave({
    required this.target,
    required this.draft,
    required this.sequence,
    required this.localOnly,
    required this.isCurrent,
  });

  final ComposerTarget target;
  final ComposerDraft draft;
  final int sequence;
  final bool localOnly;
  final bool Function() isCurrent;
}

class _PendingDraft {
  const _PendingDraft({
    required this.target,
    required this.draft,
    required this.revision,
  });

  final ComposerTarget target;
  final ComposerDraft draft;
  final int revision;
}

class TypingClock {
  TypingClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const Duration _pause = Duration(seconds: 5);

  final DateTime Function() _now;
  Duration _elapsed = Duration.zero;
  DateTime? _last;

  Duration get elapsed => _elapsed;

  void tick() {
    final now = _now();
    final last = _last;
    if (last != null) {
      final since = now.difference(last);
      if (since >= Duration.zero && since <= _pause) _elapsed += since;
    }
    _last = now;
  }

  void reset() {
    _elapsed = Duration.zero;
    _last = null;
  }
}

enum ComposerState { editing, submitting, checking, unresolved }

enum DraftStatus { clean, saving, saved, failing }

class ComposerController extends ChangeNotifier implements ComposerEditorHost {
  ComposerController(
    this._target, {
    this.onSaveDraft,
    this.onStageDraft,
    ComposerSearch? search,
    this.onEmojiAccepted,
    String Function(String name)? resolveEmoji,
    ComposerPills? pills,
    PluginHashtagPresentationResolver? pluginHashtagPresentation,
    ComposerQuoteContentsFormatter? formatQuoteContents,
    List<ComposerSyntaxPolicy> syntaxPolicies = const [],
    this.pluginStateReader,
    this.isCurrentComposer,
    this.imageUploader,
    ComposerUploadUrlResolver? resolveUploadUrls,
    this.canUploadImage,
    this.simultaneousUploads = 15,
    bool enableAutoGridImages = true,
    bool enableMarkdownLinkify = true,
    List<String> markdownLinkifyTlds = SiteConfig.defaultMarkdownLinkifyTlds,
    int maxImageWidth = 690,
    int maxImageHeight = 500,
    int minimumRequiredTags = 0,
    DateTime Function()? now,
  }) : _enableAutoGridImages = enableAutoGridImages,
       text = MarkdownEditingController(
         imageSiteUrl: _target.siteUrl,
         resolveEmoji: resolveEmoji,
         pills: pills,
         pluginHashtagPresentation: pluginHashtagPresentation,
         formatQuoteContents: formatQuoteContents,
         syntaxPolicies: syntaxPolicies,
         resolveUploadUrls: resolveUploadUrls,
         enableMarkdownLinkify: enableMarkdownLinkify,
         markdownLinkifyTlds: markdownLinkifyTlds,
         maxImageWidth: maxImageWidth,
         maxImageHeight: maxImageHeight,
         enableImageGalleries: !_target.isPlugin,
       ),
       autocomplete = ComposerAutocomplete(search: search),
       _typing = TypingClock(now: now),
       _now = now ?? DateTime.now,
       _openedAt = (now ?? DateTime.now)(),
       title = TextEditingController(
         text: _target.editsTopicMetadata ? _target.topicTitle : '',
       ),
       _categoryId = _target.initialCategoryId,
       _tags = List.unmodifiable(_target.initialTags),
       _originalTitle = _target.editsTopicMetadata ? _target.topicTitle : '',
       _originalCategoryId = _target.initialCategoryId,
       _originalTags = List.unmodifiable(_target.initialTags),
       _whisper = _target.replyingToWhisper,
       _minimumRequiredTags = minimumRequiredTags {
    text.addListener(_onTextChanged);
    title.addListener(_onMetadataChanged);
    _recomputeCanSubmit();
  }

  static const Duration draftDebounce = Duration(seconds: 2);

  static const Duration draftMaxWait = Duration(seconds: 15);

  static const int maxDraftFailures = 5;

  final void Function(String code)? onEmojiAccepted;

  static Object _safeDiagnosticError(Object error) => switch (error) {
    WriteException() => WriteException(
      error.failure,
      statusCode: error.statusCode,
      retryAfter: error.retryAfter,
    ),
    DraftWriteException() => const DraftWriteException(),
    _ => error,
  };

  final Future<int?> Function(ComposerDraftSave save)? onSaveDraft;
  final Future<void> Function(ComposerDraftSave save)? onStageDraft;

  final ComposerImageUploader? imageUploader;
  final bool Function(String filename)? canUploadImage;
  final int simultaneousUploads;
  bool _enableAutoGridImages;
  bool get enableAutoGridImages => _enableAutoGridImages;

  void updateEnableAutoGridImages(bool value) {
    _enableAutoGridImages = value;
    if (value) return;
    for (final pending in _pendingUploads.values) {
      if (pending.destination == _ComposerUploadDestination.newGallery) {
        pending.destination = _ComposerUploadDestination.standalone;
      }
    }
  }

  void updateMarkdownLinkify({
    required bool enabled,
    required List<String> tlds,
  }) => text.updateMarkdownLinkify(enabled: enabled, tlds: tlds);

  final ComposerPluginStateReader? pluginStateReader;
  final bool Function()? isCurrentComposer;

  final MarkdownEditingController text;
  final TextEditingController title;

  int? _categoryId;
  int? get categoryId => _categoryId;

  List<TopicTag> _tags;
  List<TopicTag> get tags => _tags;

  bool _whisper;
  bool get whisper => _whisper;

  void setWhisper(bool value) {
    if (_disposed ||
        _target.createsTopic ||
        _target.isEdit ||
        _target.isPlugin) {
      return;
    }
    if (_target.replyingToWhisper) value = true;
    if (_whisper == value) return;
    _whisper = value;
    _draftRevision++;
    _scheduleDraft();
    _notify();
  }

  void toggleWhisper() => setWhisper(!_whisper);

  String _originalTitle;
  int? _originalCategoryId;
  List<TopicTag> _originalTags;
  int _minimumRequiredTags;
  String get originalTitle => _originalTitle;
  List<TopicTag> get originalTags => _originalTags;

  bool get metadataChanged =>
      title.text.trim() != _originalTitle.trim() ||
      _categoryId != _originalCategoryId ||
      !listEquals(_tags, _originalTags);

  /// Core treats whitespace-only differences as unchanged when deciding
  /// whether Discard needs confirmation.
  bool get hasChanges =>
      text.text.trim() != (_originalRaw ?? '').trim() ||
      ((_target.createsTopic || _target.editsTopicMetadata) &&
          title.text.trim() != _originalTitle.trim());

  bool get canSaveDraft => onSaveDraft != null;

  int get draftRevision => _draftRevision;

  bool _hasUnappliedDraft = false;
  bool get hasUnappliedDraft => _hasUnappliedDraft;
  bool _unappliedDraftOverwritten = false;
  bool get unappliedDraftOverwritten => _unappliedDraftOverwritten;
  ComposerDraft? _unappliedDraft;
  ComposerDraft? get unappliedDraft => _unappliedDraft;
  bool _unappliedDraftWasLocal = false;
  bool get unappliedDraftWasLocal => _unappliedDraftWasLocal;
  bool get protectsUnappliedDraft =>
      _hasUnappliedDraft && !_unappliedDraftOverwritten;

  void protectUnappliedDraft(ComposerDraft draft, {required bool wasLocal}) {
    if (_disposed) return;
    _hasUnappliedDraft = true;
    _unappliedDraft = draft;
    _unappliedDraftWasLocal = wasLocal;
  }

  void unappliedDraftWasOverwritten() {
    if (_disposed || !_hasUnappliedDraft) return;
    _unappliedDraftOverwritten = true;
  }

  bool canRestoreDraft(ComposerDraft draft) =>
      !_disposed &&
      (!_target.isPrivateMessage ||
          (draft.archetypeId == ComposerDraft.privateMessageArchetype &&
              draft.recipients?.trim() == _target.targetRecipients?.trim()));

  bool _discarding = false;
  bool get discarding => _discarding;

  bool _discardPromptOpen = false;

  bool beginDiscardPrompt() {
    if (_disposed || _discarding || _discardPromptOpen) return false;
    _discardPromptOpen = true;
    return true;
  }

  void finishDiscardPrompt() {
    _discardPromptOpen = false;
  }

  int? beginDiscard() {
    if (_disposed ||
        _discarding ||
        (_state != ComposerState.editing &&
            _state != ComposerState.unresolved)) {
      return null;
    }
    _discarding = true;
    _notify();
    return _draftRevision;
  }

  bool discardRevisionIsCurrent(int revision) =>
      !_disposed && revision == _draftRevision;

  void finishDiscard() {
    if (_disposed || !_discarding) return;
    _discarding = false;
    _notify();
  }

  String? get taxonomyValidationMessage => _tags.length < _minimumRequiredTags
      ? 'Choose at least $_minimumRequiredTags tags for this category.'
      : null;

  void setCategory(int? value, {int minimumRequiredTags = 0}) {
    if (_disposed ||
        (value == _categoryId && minimumRequiredTags == _minimumRequiredTags)) {
      return;
    }
    _categoryId = value;
    _minimumRequiredTags = minimumRequiredTags;
    _onMetadataChanged();
  }

  void setMinimumRequiredTags(int value) {
    if (_disposed || value == _minimumRequiredTags) return;
    _minimumRequiredTags = value;
    _recomputeCanSubmit();
    _notify();
  }

  void setTags(Iterable<TopicTag> value) {
    final next = List<TopicTag>.unmodifiable(value);
    if (_disposed || listEquals(next, _tags)) return;
    _tags = next;
    _onMetadataChanged();
  }

  void metadataSettled() {
    _originalTitle = title.text.trim();
    _originalCategoryId = _categoryId;
    _originalTags = _tags;
    _recomputeCanSubmit();
    _notify();
  }

  final FocusNode focus = FocusNode();

  int get fieldGeneration => _fieldGeneration;
  int _fieldGeneration = 0;

  final ComposerAutocomplete autocomplete;

  final TypingClock _typing;
  final DateTime Function() _now;
  DateTime _openedAt;

  ComposerTarget _target;
  ComposerTarget get target => _target;

  @override
  String get siteUrl => _target.siteUrl;

  @override
  bool get isPluginTarget => _target.isPlugin;

  @override
  TextEditingValue get value => text.value;

  @override
  bool get isCurrent => !_disposed && (isCurrentComposer?.call() ?? true);

  @override
  bool get isEdit => _target.isEdit;

  @override
  PluginData get siteSettings =>
      pluginStateReader?.call().siteSettings ?? PluginData.none;

  @override
  T? syntaxPolicy<T extends ComposerSyntaxPolicy>(ComposerSyntaxKind kind) {
    for (final policy in text.syntaxPolicies) {
      if (policy.kind == kind && policy is T) return policy;
    }
    return null;
  }

  @override
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  }) {
    if (!isCurrent || text.value != expectedValue) return false;
    text.value = value;
    return true;
  }

  @override
  bool commitText({
    required String expectedText,
    required TextEditingValue value,
  }) {
    if (_disposed || text.text != expectedText) return false;
    text.value = value;
    return true;
  }

  @override
  void requestFocus() => focus.requestFocus();

  ComposerState _state = ComposerState.editing;
  ComposerState get state => _state;

  bool get submitting => _state == ComposerState.submitting;

  bool get canRecheck => _state == ComposerState.unresolved;

  WriteException? _error;

  WriteException? get error => _error;

  String? _notice;

  String? get notice => _notice;

  void showNotice(String? message) {
    if (_disposed) return;
    _notice = message;
    _notify();
  }

  final List<ComposerUploadItem> _uploads = [];
  final Map<int, _PendingComposerUpload> _pendingUploads = {};
  int _nextUploadId = 0;
  int _nextUploadBatch = 0;

  List<ComposerUploadItem> get uploads => List.unmodifiable(_uploads);
  List<ComposerUploadResult> get completedUploads => List.unmodifiable(
    _uploads
        .where((upload) => upload.status == ComposerUploadStatus.completed)
        .map((upload) => upload.result)
        .nonNulls,
  );
  bool get hasActiveUploads => _uploads.any(
    (upload) =>
        upload.status == ComposerUploadStatus.uploading ||
        upload.status == ComposerUploadStatus.retrying,
  );

  void addImages(Iterable<ComposerUploadFile> files, int offset) {
    final gallery = _galleryAtContentOffset(offset);
    _addImages(
      files,
      offset,
      gallery: gallery,
      forceStandalone:
          gallery == null && _isInsideUnprojectedGridLikeBlock(offset),
    );
  }

  void addImagesToGallery(
    Iterable<ComposerUploadFile> files,
    ComposerImageGalleryBlock gallery,
  ) {
    final queued = files.toList();
    if (queued.isEmpty) return;
    final current = _resolveGalleryIdentity(gallery);
    if (current != null) {
      _addImages(queued, current.contentEnd, gallery: current);
      return;
    }

    // A picker can outlive the projection which opened it. The files have
    // already been chosen at this point, so a stale widget must not turn that
    // choice into a no-op. Keep the upload, but do not silently create a new
    // gallery in place of one the author changed or removed.
    showNotice('That gallery changed, so the images will be added outside it.');
    _addImages(
      queued,
      _formerGalleryMemberSequenceEnd(gallery) ??
          gallery.start.clamp(0, text.text.length),
      forceStandalone: true,
    );
  }

  void _addImages(
    Iterable<ComposerUploadFile> files,
    int offset, {
    ComposerImageGalleryBlock? gallery,
    bool forceStandalone = false,
  }) {
    if (_disposed || imageUploader == null) return;
    final all = files.toList();
    final valid = all
        .where((file) => canUploadImage?.call(file.name) ?? true)
        .toList();
    final rejected = all.length - valid.length;
    if (rejected > 0) {
      showNotice(
        rejected == 1
            ? 'That file type is not allowed for images on this site.'
            : '$rejected file types are not allowed for images on this site.',
      );
    }
    if (valid.isEmpty) return;
    if (simultaneousUploads > 0 && valid.length > simultaneousUploads) {
      final limit = simultaneousUploads == 1
          ? 'one image'
          : '$simultaneousUploads images';
      showNotice('Upload at most $limit at a time.');
      return;
    }

    final batch = _nextUploadBatch++;
    final insertsMarkdown =
        _target.policy?.uploadDisposition !=
        ComposerUploadDisposition.retainAttachment;
    final galleryTarget = gallery == null
        ? null
        : _galleryUploadTargetFor(gallery);
    final destination = gallery != null
        ? _ComposerUploadDestination.gallery
        : !forceStandalone &&
              insertsMarkdown &&
              !_target.isPlugin &&
              enableAutoGridImages &&
              valid.length >= 3
        ? _ComposerUploadDestination.newGallery
        : _ComposerUploadDestination.standalone;
    final anchor = (gallery?.contentEnd ?? offset).clamp(0, text.text.length);
    for (var order = 0; order < valid.length; order++) {
      final id = _nextUploadId++;
      final file = valid[order];
      _pendingUploads[id] = _PendingComposerUpload(
        batch: batch,
        order: order,
        anchor: anchor,
        launchAnchor: anchor,
        destination: destination,
        launchDestination: destination,
        galleryTarget: galleryTarget,
      );
      _uploads.add(
        ComposerUploadItem(
          id: id,
          file: file,
          progress: 0,
          status: ComposerUploadStatus.uploading,
        ),
      );
      _startUpload(id);
    }
    _recomputeCanSubmit();
    _notify();
  }

  void retryUpload(int id) {
    final index = _uploadIndex(id);
    final pending = _pendingUploads[id];
    if (_disposed || index < 0 || pending == null) return;
    // A retry is a transition out of the terminal failed state. Starting one
    // for an already active row loses its abort trigger and lets two requests
    // race to decide which result is inserted.
    if (_uploads[index].status != ComposerUploadStatus.failed ||
        !pending.failed) {
      return;
    }
    pending.abort = Completer<void>();
    pending.result = null;
    pending.failed = false;
    _uploads[index] = _uploads[index].copyWith(
      progress: 0,
      status: ComposerUploadStatus.retrying,
      clearError: true,
      clearResult: true,
    );
    _startUpload(id);
    _recomputeCanSubmit();
    _notify();
  }

  void cancelUpload(int id) {
    final pending = _pendingUploads.remove(id);
    if (pending != null && !pending.abort.isCompleted) pending.abort.complete();
    _uploads.removeWhere((upload) => upload.id == id);
    if (pending != null) _flushReadyUploads(pending.batch);
    _recomputeCanSubmit();
    _notify();
  }

  void removeUpload(int id) => cancelUpload(id);

  void _startUpload(int id) {
    final uploader = imageUploader;
    final pending = _pendingUploads[id];
    final index = _uploadIndex(id);
    if (uploader == null || pending == null || index < 0) return;
    final file = _uploads[index].file;
    unawaited(
      Future<ComposerUploadResult>.sync(
        () => uploader(
          file,
          abortTrigger: pending.abort.future,
          onProgress: (progress) {
            if (_disposed || !_pendingUploads.containsKey(id)) return;
            final current = _uploadIndex(id);
            if (current < 0) return;
            final previous = _uploads[current].progress;
            _uploads[current] = _uploads[current].copyWith(
              progress: progress.clamp(previous, 1),
            );
            _notify();
          },
        ),
      ).then(
        (result) {
          if (_disposed || !_pendingUploads.containsKey(id)) return;
          pending.result = result;
          text.cacheImageUrl(result.shortUrl, result.previewUrl);
          _flushReadyUploads(pending.batch);
        },
        onError: (Object error) {
          if (_disposed || !_pendingUploads.containsKey(id)) return;
          pending.failed = true;
          final current = _uploadIndex(id);
          if (current < 0) return;
          _uploads[current] = _uploads[current].copyWith(
            status: ComposerUploadStatus.failed,
            error: switch (error) {
              ComposerUploadException(:final message) => message,
              _ => "Couldn't upload ${file.name}.",
            },
          );
          _flushReadyUploads(pending.batch);
          _recomputeCanSubmit();
          _notify();
        },
      ),
    );
  }

  void _flushReadyUploads(int batch) {
    while (true) {
      final waiting =
          _pendingUploads.entries
              .where((entry) => entry.value.batch == batch)
              .toList()
            ..sort((a, b) => a.value.order.compareTo(b.value.order));
      if (waiting.isEmpty) break;
      final first = waiting.where((entry) => !entry.value.failed).firstOrNull;
      if (first == null) break;
      final result = first.value.result;
      if (result == null) break;

      if (_target.policy?.uploadDisposition ==
          ComposerUploadDisposition.retainAttachment) {
        _pendingUploads.remove(first.key);
        final uploadIndex = _uploadIndex(first.key);
        if (uploadIndex >= 0) {
          _uploads[uploadIndex] = _uploads[uploadIndex].copyWith(
            progress: 1,
            status: ComposerUploadStatus.completed,
            result: result,
            clearError: true,
          );
        }
        continue;
      }

      final earlierFailed = waiting
          .where(
            (entry) =>
                entry.value.failed && entry.value.order < first.value.order,
          )
          .map((entry) => entry.value)
          .toList();
      var insertionOffset = first.value.anchor;
      final markdown = uploadImageMarkdown(result);
      var destination = first.value.destination;
      if (destination == _ComposerUploadDestination.newGallery &&
          _isInsideUnprojectedGridLikeBlock(insertionOffset)) {
        // The source can change while the picker/upload is open. Once the
        // anchor is surrounded by any grid-like raw block, creating another
        // wrapper would produce nested BBCode which neither composer can edit
        // losslessly.
        destination = _ComposerUploadDestination.standalone;
        for (final entry in waiting) {
          entry.value.destination = destination;
        }
      } else if (destination == _ComposerUploadDestination.gallery) {
        final currentGallery = _resolvePendingUploadGallery(first.value);
        if (currentGallery == null) {
          // The gallery may have been explicitly unwrapped, dissolved, or
          // changed into mixed raw content while an upload was in flight. Do
          // not recreate it behind the author's back.
          final target = first.value.galleryTarget;
          if (target == null) {
            for (final entry in waiting) {
              entry.value.destination = _ComposerUploadDestination.standalone;
            }
          } else {
            _demoteGalleryUploadTarget(
              target,
              fallbackAnchor: first.value.anchor,
            );
          }
          destination = _ComposerUploadDestination.standalone;
          insertionOffset = first.value.anchor;
        } else {
          insertionOffset = _galleryInsertionOffset(
            first.value,
            currentGallery,
          );
        }
      }

      final insertion = switch (destination) {
        _ComposerUploadDestination.newGallery => _galleryBlockInsertion(
          text.text,
          insertionOffset,
          markdown,
        ),
        _ComposerUploadDestination.gallery => _imageBlockInsertion(
          text.text,
          insertionOffset,
          markdown,
        ),
        _ComposerUploadDestination.standalone => _imageBlockInsertion(
          text.text,
          insertionOffset,
          markdown,
        ),
      };
      final earlierLaneUploads = _pendingUploads.values
          .where(
            (pending) =>
                pending.batch < first.value.batch &&
                _sameUploadLane(pending, first.value),
          )
          .toList();
      _pendingUploads.remove(first.key);
      _uploads.removeWhere((upload) => upload.id == first.key);
      _insertAt(insertionOffset, insertion);

      // A later request is allowed to finish first, but it must not steal the
      // document slot reserved by an older request. Generic anchor movement
      // shifts those older slots after this insertion; restore the boundary
      // so an active upload or a retry still lands before the later result.
      for (final pending in earlierLaneUploads) {
        if (pending.anchor > insertionOffset) {
          pending.anchor = insertionOffset;
        }
      }

      if (destination == _ComposerUploadDestination.newGallery) {
        final beforeLength =
            insertionOffset > 0 && text.text[insertionOffset - 1] != '\n'
            ? 1
            : 0;
        final contentStart = insertionOffset + beforeLength + '[grid]\n'.length;
        final contentEnd = contentStart + markdown.length + 1;
        final created = _galleryAtContentOffset(contentStart);
        final target = created == null
            ? null
            : _PendingGalleryUploadTarget(created);
        for (final entry in _pendingUploads.entries.where(
          (entry) => entry.value.batch == batch,
        )) {
          entry.value.destination = _ComposerUploadDestination.gallery;
          entry.value.galleryTarget = target;
          entry.value.anchor = entry.value.order < first.value.order
              ? contentStart
              : contentEnd;
        }
      } else if (destination == _ComposerUploadDestination.gallery) {
        final target = first.value.galleryTarget;
        if (target != null) {
          final updated = _galleryAtContentOffset(insertionOffset);
          if (updated != null) target.gallery = updated;
        }
      }
      // A failed earlier item still owns the slot before what just landed. Its
      // anchor moved with the text insertion like every other pending upload;
      // put it back at the boundary so a later retry restores drop order.
      for (final pending in earlierFailed) {
        if (destination != _ComposerUploadDestination.newGallery) {
          // A failed slot in a newly-created gallery may already be anchored
          // before members inserted by an earlier flush. Never move it later
          // merely because another later result just arrived.
          if (pending.anchor > insertionOffset) {
            pending.anchor = insertionOffset;
          }
        }
      }
    }
    _recomputeCanSubmit();
    _notify();
  }

  static bool _sameUploadLane(
    _PendingComposerUpload left,
    _PendingComposerUpload right,
  ) {
    if (left.galleryTarget != null &&
        identical(left.galleryTarget, right.galleryTarget)) {
      return true;
    }
    if (left.launchDestination != right.launchDestination) return false;
    if (left.launchDestination == _ComposerUploadDestination.gallery) {
      return false;
    }
    return left.launchAnchor == right.launchAnchor ||
        left.anchor == right.anchor;
  }

  int _uploadIndex(int id) => _uploads.indexWhere((upload) => upload.id == id);

  void _insertAt(int offset, String insertion) {
    final old = text.value;
    final at = offset.clamp(0, old.text.length);
    final uploadAnchors = [
      for (final pending in _pendingUploads.values) (pending, pending.anchor),
    ];
    int move(int value) => value < at ? value : value + insertion.length;
    text.value = old.copyWith(
      text: old.text.replaceRange(at, at, insertion),
      selection: old.selection.isValid
          ? TextSelection(
              baseOffset: move(old.selection.baseOffset),
              extentOffset: move(old.selection.extentOffset),
            )
          : TextSelection.collapsed(offset: at + insertion.length),
      composing: TextRange.empty,
    );
    // [_onTextChanged] has to infer an arbitrary edit from a before/after
    // diff. When an insertion starts with the same newline already at [at],
    // that inference can place the common prefix beyond the true boundary and
    // leave peer uploads behind. This call knows the exact edit, so restore
    // the unambiguous transform after the listener has run.
    for (final (pending, anchor) in uploadAnchors) {
      pending.anchor = move(anchor);
    }
  }

  static String _imageBlockInsertion(
    String source,
    int offset,
    String markdown,
  ) {
    final at = offset.clamp(0, source.length);
    final before = at > 0 && source[at - 1] != '\n' ? '\n' : '';
    final after = at < source.length && source[at] != '\n' ? '\n' : '';
    return '$before$markdown$after';
  }

  static String _galleryBlockInsertion(
    String source,
    int offset,
    String markdown,
  ) {
    final at = offset.clamp(0, source.length);
    final before = at > 0 && source[at - 1] != '\n' ? '\n' : '';
    final after = at < source.length && source[at] != '\n' ? '\n' : '';
    return '$before[grid]\n$markdown\n[/grid]$after';
  }

  Timer? _wait;
  bool _rateLimited = false;

  bool get rateLimited => _rateLimited;

  void toggleMark(ComposerMark mark) {
    if (_disposed ||
        selectionTouchesComposerQuote(text.quoteBlocks, text.selection)) {
      return;
    }
    text.value = toggleMarkdownMark(text.value, mark.marker);
  }

  void toggleSelectedInlineCode() {
    final selection = text.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    toggleMark(ComposerMark.inlineCode);
  }

  void insertText(String insertion) {
    if (_disposed || insertion.isEmpty) return;
    final old = text.value;
    final selection = old.selection.isValid
        ? old.selection
        : TextSelection.collapsed(offset: old.text.length);
    final start = selection.start;
    text.value = old.copyWith(
      text: old.text.replaceRange(start, selection.end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
      composing: TextRange.empty,
    );
  }

  void insertEmoji(String bareCode) {
    if (_disposed) return;
    final code = bareCode
        .replaceFirst(RegExp(r'^:'), '')
        .replaceFirst(RegExp(r':$'), '');
    if (!RegExp(r'^[A-Za-z0-9_+\-]+(?::t[2-6])?$').hasMatch(code)) return;

    final old = text.value;
    final selection = old.selection.isValid
        ? old.selection
        : TextSelection.collapsed(offset: old.text.length);
    var start = selection.start;
    final end = selection.end;
    var insertion = ':$code:';

    if (selection.isCollapsed) {
      final before = old.text.substring(0, start);
      final partial = RegExp(r':[A-Za-z0-9_+\-]*$').firstMatch(before);
      if (partial != null && _emojiSigilOpensWord(before, partial.start)) {
        start = partial.start;
      } else if (start > 0 && !RegExp(r'\s').hasMatch(old.text[start - 1])) {
        insertion = ' $insertion';
      }
    } else if (start > 0 && !RegExp(r'\s').hasMatch(old.text[start - 1])) {
      insertion = ' $insertion';
    }

    text.value = old.copyWith(
      text: old.text.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
      composing: TextRange.empty,
    );
    autocomplete.close();
  }

  static bool _emojiSigilOpensWord(String text, int sigil) {
    if (sigil == 0) return true;
    return RegExp(r'''[\s([{<"'`]''').hasMatch(text[sigil - 1]);
  }

  @override
  bool insertBlock({
    required TextEditingValue expectedValue,
    required String markdown,
  }) {
    if (!isCurrent || text.value != expectedValue || markdown.trim().isEmpty) {
      return false;
    }
    _insertBlock(markdown);
    return true;
  }

  void _insertBlock(String markdown) {
    final old = text.value;
    final selection = old.selection.isValid
        ? old.selection
        : TextSelection.collapsed(offset: old.text.length);
    final before = old.text.substring(0, selection.start);
    final after = old.text.substring(selection.end);
    final block = markdown.trim();
    final insertion =
        '${_separatorAfter(before)}$block${_separatorBefore(after)}';

    text.value = old.copyWith(
      text: old.text.replaceRange(selection.start, selection.end, insertion),
      selection: TextSelection.collapsed(
        offset: selection.start + insertion.length,
      ),
      composing: TextRange.empty,
    );
  }

  void prependBlock(String markdown) {
    if (_disposed || markdown.trim().isEmpty) return;
    text.selection = const TextSelection.collapsed(offset: 0);
    _insertBlock(markdown);
  }

  static String _separatorAfter(String before) {
    if (before.isEmpty || before.endsWith('\n\n')) return '';
    return before.endsWith('\n') ? '\n' : '\n\n';
  }

  static String _separatorBefore(String after) {
    if (after.isEmpty) return '\n\n';
    if (after.startsWith('\n\n')) return '';
    return after.startsWith('\n') ? '\n' : '\n\n';
  }

  void setImageAlt(ComposerImageBlock image, String alt) {
    _replaceImage(image, image.toMarkdown(alt: alt.trim()));
  }

  void setImageScale(ComposerImageBlock image, int scale) {
    var width = image.width;
    var height = image.height;
    if (width == null || height == null) {
      final natural = text.naturalImageSize(image);
      if (natural == null || natural.isEmpty) return;
      final ratio = [
        text.maxImageWidth / natural.width,
        text.maxImageHeight / natural.height,
        1.0,
      ].reduce((a, b) => a < b ? a : b);
      width = (natural.width * ratio).floor();
      height = (natural.height * ratio).floor();
    }
    _replaceImage(
      image,
      image.toMarkdown(width: width, height: height, scale: scale),
    );
  }

  ComposerImageGalleryBlock? galleryForImage(ComposerImageBlock image) {
    if (_target.isPlugin || !_stillContainsImage(image)) return null;
    for (final gallery in parseComposerImageGalleries(text.text)) {
      if (gallery.images.any(
        (candidate) =>
            candidate.start == image.start &&
            candidate.end == image.end &&
            candidate.source == image.source,
      )) {
        return gallery;
      }
    }
    return null;
  }

  List<ComposerImageBlock> get standaloneImages {
    if (_target.isPlugin) return List.unmodifiable(text.imageBlocks);
    final galleries = parseComposerImageGalleries(text.text);
    return List.unmodifiable([
      for (final image in text.imageBlocks)
        if (!galleries.any(
          (gallery) => gallery.images.any(
            (member) =>
                member.start == image.start &&
                member.end == image.end &&
                member.source == image.source,
          ),
        ))
          image,
    ]);
  }

  void setGalleryMode(
    ComposerImageGalleryBlock gallery,
    ComposerGalleryMode mode,
  ) {
    final current = _currentGallery(gallery);
    if (current == null || current.mode == mode) return;
    final opening = mode == ComposerGalleryMode.carousel
        ? '[grid mode=carousel]'
        : '[grid]';
    _replaceGallery(
      current,
      '$opening${current.source.substring(current.contentStart - current.start)}',
    );
  }

  void unwrapGallery(ComposerImageGalleryBlock gallery) {
    final current = _currentGallery(gallery);
    if (current == null) return;
    _replaceGallery(
      current,
      current.images.map((image) => image.source).join('\n'),
      preservePendingTarget: false,
    );
  }

  void removeGallery(ComposerImageGalleryBlock gallery) {
    _replaceGallery(gallery, '', preservePendingTarget: false);
  }

  void moveImageOutOfGallery(
    ComposerImageGalleryBlock gallery,
    ComposerImageBlock image,
  ) {
    final current = _currentGallery(gallery);
    if (current == null) return;
    final member = current.images
        .where(
          (candidate) =>
              candidate.start == image.start &&
              candidate.end == image.end &&
              candidate.source == image.source,
        )
        .firstOrNull;
    if (member == null) return;
    final remaining = current.images
        .where((candidate) => candidate != member)
        .toList();
    final replacement = remaining.isEmpty
        ? member.source
        : '${_galleryMarkdown(current.mode, remaining)}\n${member.source}';
    _replaceGallery(
      current,
      replacement,
      preservePendingTarget: remaining.isNotEmpty,
    );
  }

  void reorderGalleryImage(
    ComposerImageGalleryBlock gallery,
    ComposerImageBlock image,
    int newIndex,
  ) {
    final current = _currentGallery(gallery);
    if (current == null || current.images.length < 2) return;
    final oldIndex = current.images.indexWhere(
      (candidate) =>
          candidate.start == image.start &&
          candidate.end == image.end &&
          candidate.source == image.source,
    );
    if (oldIndex < 0 || newIndex < 0 || newIndex >= current.images.length) {
      return;
    }
    if (oldIndex == newIndex) return;

    final reordered = current.images.toList();
    final member = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, member);
    _replaceGallery(current, _galleryMarkdown(current.mode, reordered));
  }

  void addExistingImagesToGallery(
    ComposerImageGalleryBlock gallery,
    Iterable<ComposerImageBlock> images,
  ) {
    final current = _resolveGalleryIdentity(gallery);
    if (current == null) return;
    final requestedImages = images.toList();
    if (requestedImages.isEmpty) return;
    final available = {
      for (final image in standaloneImages) image.start: image,
    };
    final selected = <ComposerImageBlock>[];
    final seen = <int>{};
    for (final requested in requestedImages) {
      final candidate = available[requested.start];
      if (candidate == null ||
          candidate.end != requested.end ||
          candidate.source != requested.source ||
          !seen.add(candidate.start)) {
        return;
      }
      selected.add(candidate);
    }
    selected.sort((a, b) => a.start.compareTo(b.start));

    final affectedUploads = _pendingUploadsForGallery(current);
    final replacement = _galleryMarkdown(current.mode, [
      ...current.images,
      ...selected,
    ]);
    final edits = <_ComposerTextReplacement>[
      _ComposerTextReplacement(current.start, current.end, replacement),
      for (final image in selected)
        _ComposerTextReplacement(image.start, image.end, ''),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final old = text.value;
    final buffer = StringBuffer();
    var cursor = 0;
    var galleryStart = current.start;
    var galleryEnd = current.start + replacement.length;
    for (final edit in edits) {
      if (edit.start < cursor) return;
      buffer.write(old.text.substring(cursor, edit.start));
      final replacementStart = buffer.length;
      buffer.write(edit.replacement);
      if (edit.start == current.start && edit.end == current.end) {
        galleryStart = replacementStart;
        galleryEnd = replacementStart + edit.replacement.length;
      }
      cursor = edit.end;
    }
    buffer.write(old.text.substring(cursor));
    text.value = old.copyWith(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: galleryEnd),
      composing: TextRange.empty,
    );
    final updated = parseComposerImageGalleries(
      text.text,
    ).where((candidate) => candidate.start == galleryStart).firstOrNull;
    _retargetPendingGalleryUploads(
      affectedUploads,
      updated,
      fallbackAnchor: galleryEnd,
    );
  }

  void removeImage(ComposerImageBlock image) {
    final gallery = galleryForImage(image);
    if (gallery == null) {
      _replaceImage(image, '');
      return;
    }
    final remaining = gallery.images
        .where(
          (candidate) =>
              candidate.start != image.start ||
              candidate.end != image.end ||
              candidate.source != image.source,
        )
        .toList();
    _replaceGallery(
      gallery,
      remaining.isEmpty ? '' : _galleryMarkdown(gallery.mode, remaining),
      preservePendingTarget: remaining.isNotEmpty,
    );
  }

  void removeQuote(ComposerQuoteBlock quote) => _replaceQuote(quote, '');

  void _replaceQuote(ComposerQuoteBlock quote, String replacement) {
    if (_disposed ||
        quote.start < 0 ||
        quote.end > text.text.length ||
        text.text.substring(quote.start, quote.end) != quote.source) {
      return;
    }
    final old = text.value;
    text.value = old.copyWith(
      text: old.text.replaceRange(quote.start, quote.end, replacement),
      selection: TextSelection.collapsed(
        offset: quote.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
  }

  void _replaceImage(ComposerImageBlock image, String replacement) {
    if (_disposed ||
        image.start < 0 ||
        image.end > text.text.length ||
        text.text.substring(image.start, image.end) != image.source) {
      return;
    }
    final old = text.value;
    text.value = old.copyWith(
      text: old.text.replaceRange(image.start, image.end, replacement),
      selection: TextSelection.collapsed(
        offset: image.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
  }

  bool _stillContainsImage(ComposerImageBlock image) =>
      !_disposed &&
      image.start >= 0 &&
      image.end <= text.text.length &&
      image.start <= image.end &&
      text.text.substring(image.start, image.end) == image.source;

  ComposerImageGalleryBlock? _currentGallery(
    ComposerImageGalleryBlock gallery,
  ) {
    if (_disposed ||
        _target.isPlugin ||
        gallery.start < 0 ||
        gallery.end > text.text.length ||
        gallery.start > gallery.end ||
        text.text.substring(gallery.start, gallery.end) != gallery.source) {
      return null;
    }
    return parseComposerImageGalleries(text.text)
        .where(
          (candidate) =>
              candidate.start == gallery.start &&
              candidate.end == gallery.end &&
              candidate.source == gallery.source,
        )
        .firstOrNull;
  }

  ComposerImageGalleryBlock? _galleryAtContentOffset(int offset) =>
      _target.isPlugin
      ? null
      : parseComposerImageGalleries(text.text)
            .where(
              (gallery) =>
                  offset >= gallery.contentStart &&
                  offset <= gallery.contentEnd,
            )
            .firstOrNull;

  _PendingGalleryUploadTarget _galleryUploadTargetFor(
    ComposerImageGalleryBlock gallery,
  ) {
    final seen = <_PendingGalleryUploadTarget>{};
    for (final pending in _pendingUploads.values) {
      final target = pending.galleryTarget;
      if (target == null || target.demoted || !seen.add(target)) continue;
      final current = _resolveGalleryIdentity(
        target.gallery,
        anchor: pending.anchor,
      );
      if (current != null) {
        target.gallery = current;
        if (_sameGallery(current, gallery)) return target;
      }
    }
    return _PendingGalleryUploadTarget(gallery);
  }

  ComposerImageGalleryBlock? _resolveGalleryIdentity(
    ComposerImageGalleryBlock captured, {
    int? anchor,
  }) {
    if (_disposed || _target.isPlugin) return null;
    final galleries = parseComposerImageGalleries(text.text);
    final exact = galleries
        .where((candidate) => _sameGallery(candidate, captured))
        .firstOrNull;
    if (exact != null) return exact;

    final sameSource = galleries
        .where((candidate) => candidate.source == captured.source)
        .toList();
    if (sameSource.length == 1) return sameSource.single;

    final memberUrls = captured.images.map((image) => image.url).toSet();
    if (memberUrls.isNotEmpty) {
      var bestScore = 0;
      ComposerImageGalleryBlock? best;
      var tied = false;
      for (final candidate in galleries) {
        final score = candidate.images
            .map((image) => image.url)
            .toSet()
            .intersection(memberUrls)
            .length;
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
          tied = false;
        } else if (score != 0 && score == bestScore) {
          tied = true;
        }
      }
      if (best != null && !tied) return best;
    }

    if (anchor != null) {
      final anchored = galleries
          .where(
            (candidate) =>
                anchor >= candidate.contentStart &&
                anchor <= candidate.contentEnd,
          )
          .toList();
      if (anchored.length == 1) return anchored.single;
    }

    // An empty gallery has no member URL with which to survive an opening-tag
    // edit. Its start is the only conservative identity available.
    if (captured.images.isEmpty) {
      final atSameStart = galleries
          .where((candidate) => candidate.start == captured.start)
          .toList();
      if (atSameStart.length == 1) return atSameStart.single;
    }
    return null;
  }

  int? _formerGalleryMemberSequenceEnd(ComposerImageGalleryBlock captured) {
    if (captured.images.isEmpty) return null;
    final current = text.imageBlocks;
    final matches = <int>[];
    for (
      var start = 0;
      start + captured.images.length <= current.length;
      start++
    ) {
      var matchesSequence = true;
      for (var index = 0; index < captured.images.length; index++) {
        final candidate = current[start + index];
        if (candidate.source != captured.images[index].source ||
            (index > 0 &&
                text.text
                    .substring(current[start + index - 1].end, candidate.start)
                    .trim()
                    .isNotEmpty)) {
          matchesSequence = false;
          break;
        }
      }
      if (matchesSequence) {
        matches.add(current[start + captured.images.length - 1].end);
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  ComposerImageGalleryBlock? _resolvePendingUploadGallery(
    _PendingComposerUpload pending,
  ) {
    final target = pending.galleryTarget;
    if (target == null) return _galleryAtContentOffset(pending.anchor);
    if (target.demoted) return null;
    final current = _resolveGalleryIdentity(
      target.gallery,
      anchor: pending.anchor,
    );
    if (current != null) target.gallery = current;
    return current;
  }

  static bool _sameGallery(
    ComposerImageGalleryBlock left,
    ComposerImageGalleryBlock right,
  ) =>
      left.start == right.start &&
      left.end == right.end &&
      left.source == right.source;

  int _galleryInsertionOffset(
    _PendingComposerUpload pending,
    ComposerImageGalleryBlock gallery,
  ) {
    final anchor = pending.anchor;
    if (anchor >= gallery.contentStart &&
        anchor <= gallery.contentEnd &&
        !gallery.images.any(
          (image) => anchor > image.start && anchor < image.end,
        )) {
      return anchor;
    }
    return gallery.contentEnd;
  }

  List<_PendingComposerUpload> _pendingUploadsForGallery(
    ComposerImageGalleryBlock gallery,
  ) {
    final affected = <_PendingComposerUpload>[];
    for (final pending in _pendingUploads.values) {
      if (pending.destination != _ComposerUploadDestination.gallery) continue;
      final current = _resolvePendingUploadGallery(pending);
      if (current != null && _sameGallery(current, gallery)) {
        affected.add(pending);
      }
    }
    return affected;
  }

  void _retargetPendingGalleryUploads(
    Iterable<_PendingComposerUpload> affected,
    ComposerImageGalleryBlock? updated, {
    required int fallbackAnchor,
  }) {
    final direct = affected.toSet();
    if (direct.isEmpty) return;
    final targets = <_PendingGalleryUploadTarget>{};
    for (final pending in direct) {
      final target = pending.galleryTarget;
      if (target != null) targets.add(target);
    }
    final anchor = (updated?.contentEnd ?? fallbackAnchor).clamp(
      0,
      text.text.length,
    );
    for (final target in targets) {
      if (updated == null) {
        target.demoted = true;
      } else {
        target.gallery = updated;
      }
    }
    for (final pending in _pendingUploads.values) {
      if (!direct.contains(pending) &&
          (pending.galleryTarget == null ||
              !targets.contains(pending.galleryTarget))) {
        continue;
      }
      pending.anchor = anchor;
      pending.destination = updated == null
          ? _ComposerUploadDestination.standalone
          : _ComposerUploadDestination.gallery;
    }
  }

  void _demoteGalleryUploadTarget(
    _PendingGalleryUploadTarget target, {
    required int fallbackAnchor,
  }) {
    target.demoted = true;
    final anchor = fallbackAnchor.clamp(0, text.text.length);
    for (final pending in _pendingUploads.values) {
      if (!identical(pending.galleryTarget, target)) continue;
      pending.destination = _ComposerUploadDestination.standalone;
      pending.anchor = anchor;
    }
  }

  bool _isInsideUnprojectedGridLikeBlock(int offset) {
    if (_target.isPlugin) return false;
    final source = text.text;
    if (source.isEmpty || !source.toLowerCase().contains('[grid')) {
      return false;
    }
    final at = offset.clamp(0, source.length);
    final code = CodeRanges.of(scanMarkdown(source));
    final images = parseComposerImages(source, codeRanges: code);
    final openings = <int>[];
    final marker = RegExp(r'\[(/?)grid\b', caseSensitive: false);
    var imageIndex = 0;

    bool isEscaped(int start) {
      var backslashes = 0;
      for (
        var index = start - 1;
        index >= 0 && source[index] == r'\';
        index--
      ) {
        backslashes++;
      }
      return backslashes.isOdd;
    }

    bool rangeContains(int start, int end, {required bool closed}) =>
        at > start && (closed ? at < end : at <= end);

    for (final match in marker.allMatches(source)) {
      while (imageIndex < images.length &&
          images[imageIndex].end <= match.start) {
        imageIndex++;
      }
      final insideImage =
          imageIndex < images.length &&
          images[imageIndex].start <= match.start &&
          match.start < images[imageIndex].end;
      if (code.contains(match.start) || insideImage || isEscaped(match.start)) {
        continue;
      }
      final newline = source.indexOf('\n', match.end);
      final bracket = source.indexOf(']', match.end);
      final complete = bracket >= 0 && (newline < 0 || bracket < newline);
      final closing = match.group(1) == '/';
      if (!closing) {
        openings.add(match.start);
        continue;
      }
      if (!complete || openings.isEmpty) continue;
      final start = openings.removeLast();
      if (rangeContains(start, bracket + 1, closed: true)) return true;
    }
    for (final start in openings) {
      if (rangeContains(start, source.length, closed: false)) return true;
    }
    return false;
  }

  void _replaceGallery(
    ComposerImageGalleryBlock gallery,
    String replacement, {
    bool preservePendingTarget = true,
  }) {
    final current = _currentGallery(gallery);
    if (current == null) return;
    final affectedUploads = _pendingUploadsForGallery(current);
    final old = text.value;
    text.value = old.copyWith(
      text: old.text.replaceRange(current.start, current.end, replacement),
      selection: TextSelection.collapsed(
        offset: current.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
    final updated = preservePendingTarget
        ? parseComposerImageGalleries(
            text.text,
          ).where((candidate) => candidate.start == current.start).firstOrNull
        : null;
    _retargetPendingGalleryUploads(
      affectedUploads,
      updated,
      fallbackAnchor: current.start + replacement.length,
    );
  }

  static String _galleryMarkdown(
    ComposerGalleryMode mode,
    Iterable<ComposerImageBlock> images,
  ) {
    final opening = mode == ComposerGalleryMode.carousel
        ? '[grid mode=carousel]'
        : '[grid]';
    final members = images.map((image) => image.source).join('\n');
    return members.isEmpty
        ? '$opening\n[/grid]'
        : '$opening\n$members\n[/grid]';
  }

  void acceptSuggestion(ComposerSuggestion suggestion) {
    if (_disposed || suggestion.action != null) return;
    final open = autocomplete.trigger;
    if (open == null) return;

    text.value = applyComposerCompletion(text.value, open, suggestion.value);
    autocomplete.close();
    if (suggestion.kind == ComposerTriggerKind.emoji) {
      onEmojiAccepted?.call(suggestion.value);
    }
  }

  bool get isDisposed => _disposed;

  void closeEmojiAutocomplete() {
    if (_disposed || autocomplete.trigger?.kind != ComposerTriggerKind.emoji) {
      return;
    }
    autocomplete.close();
  }

  bool _canSubmit = false;

  bool _loadingBody = false;

  @override
  bool get loadingBody => _loadingBody;

  String? _originalRaw;

  @override
  String? get originalRaw => _originalRaw;

  bool _missingEditBody = false;

  bool get canSubmit =>
      _canSubmit &&
      _state == ComposerState.editing &&
      !_rateLimited &&
      !_loadingBody &&
      !_missingEditBody &&
      !hasActiveUploads;

  void beginLoadingBody() {
    if (_disposed) return;
    _loadingBody = true;
    _notify();
  }

  void loadedBody(String raw) {
    if (_disposed) return;
    _loadingBody = false;
    _missingEditBody = false;
    _originalRaw = raw.trim();
    _replaceDocument(
      TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      ),
    );
    _notify();
  }

  void bodyLoadFailed() {
    if (_disposed) return;
    _loadingBody = false;
    _missingEditBody = true;
    _error = const WriteException(WriteFailure.unreachable);
    _notify();
  }

  Duration get typingDuration => _typing.elapsed;
  Duration get openDuration => _now().difference(_openedAt);

  String get raw => text.text.trim();

  int draftSequence = 0;

  Timer? _draftTimer;
  DateTime? _lastDraftSaveAt;
  int _draftFailures = 0;
  bool _draftsGaveUp = false;
  bool _localDraftFailed = false;
  int _draftRevision = 0;
  _PendingDraft? _queuedDraft;
  Future<void>? _draftSaveTask;

  DraftStatus _draftStatus = DraftStatus.clean;
  DraftStatus get draftStatus => _draftStatus;

  bool get draftsGaveUp => _draftsGaveUp;

  bool get localDraftFailed => _localDraftFailed;

  bool get draftPending =>
      (_draftTimer?.isActive ?? false) || _queuedDraft != null;

  bool get draftPersistencePending => draftPending || _draftSaveTask != null;

  ComposerDraft get draft => ComposerDraft(
    reply: text.text,
    action: _target.isPrivateMessage
        ? ComposerDraft.privateMessageAction
        : _target.isNewTopic
        ? ComposerDraft.createTopicAction
        : ComposerDraft.replyAction,
    title: _target.createsTopic ? title.text : null,
    categoryId: _target.isNewTopic ? _categoryId : null,
    tags: _target.isNewTopic ? _tags : const [],
    archetypeId: _target.isPrivateMessage
        ? ComposerDraft.privateMessageArchetype
        : ComposerDraft.regularArchetype,
    recipients: _target.isPrivateMessage ? _target.targetRecipients : null,
    replyToPostNumber: _target.replyToPostNumber,
    replyToUsername: _target.replyToUsername,
    whisper: _whisper,
    typingTime: typingDuration,
    composerTime: openDuration,
  );

  bool restore(ComposerDraft draft) {
    if (_disposed || text.text.isNotEmpty || title.text.isNotEmpty) {
      return false;
    }
    if (!canRestoreDraft(draft)) return false;
    _replaceDocument(
      TextEditingValue(
        text: draft.reply,
        selection: TextSelection.collapsed(offset: draft.reply.length),
      ),
    );
    if (_target.createsTopic) {
      _replaceMetadata(
        titleValue: draft.title ?? '',
        // An existing draft without a category should not erase the category
        // supplied by the list from which the composer was opened.
        categoryId: _target.isNewTopic ? draft.categoryId ?? _categoryId : null,
        tags: _target.isNewTopic ? draft.tags : const [],
      );
    }
    _whisper = draft.whisper || _target.replyingToWhisper;
    _draftStatus = DraftStatus.clean;
    _localDraftFailed = false;
    _notify();
    return true;
  }

  void draftSettled() {
    _draftTimer?.cancel();
    _queuedDraft = null;
    _draftRevision++;
    _draftFailures = 0;
    _draftsGaveUp = false;
    _localDraftFailed = false;
    _draftStatus = DraftStatus.clean;
  }

  Future<void> flushDraft() {
    _draftTimer?.cancel();
    return _enqueueDraft();
  }

  Future<void> finishDraftSaves() async {
    final shouldFlush =
        (_draftTimer?.isActive ?? false) || _queuedDraft != null;
    _draftTimer?.cancel();
    if (shouldFlush) {
      await _enqueueDraft();
      return;
    }
    final running = _draftSaveTask;
    if (running != null) await running;
  }

  Future<void> finishInFlightDraftSaveForDiscard() async {
    _draftTimer?.cancel();
    _queuedDraft = null;
    final running = _draftSaveTask;
    if (running != null) await running;
  }

  void _scheduleDraft() {
    // Scheduled even once the remote sync has given up: the save then writes
    // the local copy only — see `_saveDraft` — which is what the panel's
    // "kept on this device only" promises.
    // A submit the site could not confirm leaves the field editable; what is
    // typed after it must survive a close or a quit like any other text. A
    // submit still out, or being checked, must not race the site clearing
    // the draft it is about to turn into a post.
    if (onSaveDraft == null ||
        _disposed ||
        (_state != ComposerState.editing &&
            _state != ComposerState.unresolved)) {
      return;
    }
    _draftTimer?.cancel();

    final last = _lastDraftSaveAt;
    if (last != null && _now().difference(last) >= draftMaxWait) {
      unawaited(_enqueueDraft());
      return;
    }
    _draftTimer = Timer(draftDebounce, () => unawaited(_enqueueDraft()));
  }

  Future<void> _enqueueDraft() {
    final save = onSaveDraft;
    if (_disposed || save == null) return Future.value();

    _draftTimer?.cancel();
    _lastDraftSaveAt = _now();
    _queuedDraft = _PendingDraft(
      target: _target,
      draft: draft,
      revision: _draftRevision,
    );

    final running = _draftSaveTask;
    if (running != null) {
      final stage = onStageDraft;
      final pending = _queuedDraft;
      if (stage != null && pending != null) {
        unawaited(_stageDraft(stage, pending));
      }
      return running;
    }

    return _draftSaveTask = _drainDrafts(save);
  }

  Future<void> _stageDraft(
    Future<void> Function(ComposerDraftSave save) stage,
    _PendingDraft pending,
  ) async {
    try {
      await stage(_draftSaveRequest(pending));
    } catch (_) {
      // The regular save path retries the same local write and owns the
      // visible failure state. This eager write exists only so a newer queued
      // revision is durable while an older remote request is blocked.
    }
  }

  Future<void> _drainDrafts(
    Future<int?> Function(ComposerDraftSave save) save,
  ) async {
    try {
      while (true) {
        final pending = _queuedDraft;
        if (pending == null) break;
        _queuedDraft = null;
        await _saveDraft(save, pending);
      }
    } finally {
      _draftSaveTask = null;
    }
  }

  Future<void> _saveDraft(
    Future<int?> Function(ComposerDraftSave save) save,
    _PendingDraft pending,
  ) async {
    final request = _draftSaveRequest(pending);

    if (request.localOnly) {
      // The site is not being asked again, but the local copy is still
      // written — the shell sees [draftsGaveUp] and stops after it. The
      // status is left as it was: the site still does not have the text.
      try {
        await save(request);
        if (!_disposed && request.isCurrent()) _localDraftFailed = false;
      } catch (error, stackTrace) {
        if (!_disposed && request.isCurrent()) {
          // DraftStore reports the original storage exception before wrapping
          // it. Reporting that wrapper here would both duplicate the failure
          // and risk retaining a nested cause supplied by another backend.
          if (error is! DraftWriteException) {
            DiagnosticsSink.current.reportError(
              _safeDiagnosticError(error),
              stackTrace,
              operation: 'draft.saveLocal',
              source: 'composer',
              handled: true,
              degraded: true,
            );
          }
          _localDraftFailed = error is DraftWriteException;
        }
      }
      _notify();
      return;
    }

    _draftStatus = DraftStatus.saving;
    _localDraftFailed = false;
    _notify();

    try {
      final sequence = await save(request);
      if (sequence != null) draftSequence = sequence;
      _draftFailures = 0;
      if (!_disposed && request.isCurrent()) {
        _localDraftFailed = false;
        _draftStatus = DraftStatus.saved;
      }
    } catch (error, stackTrace) {
      _draftFailures++;
      // No immediate retry: the next keystroke reschedules, which throttles
      // this to the speed someone types rather than the speed of a loop.
      if (_draftFailures >= maxDraftFailures) _draftsGaveUp = true;
      if (!_disposed && request.isCurrent()) {
        if (error is! DraftWriteException) {
          DiagnosticsSink.current.reportError(
            _safeDiagnosticError(error),
            stackTrace,
            operation: 'draft.save',
            source: 'composer',
            handled: true,
            degraded: true,
          );
        }
        _localDraftFailed = error is DraftWriteException;
        _draftStatus = DraftStatus.failing;
      }
    }
    _notify();
  }

  ComposerDraftSave _draftSaveRequest(_PendingDraft pending) =>
      ComposerDraftSave(
        target: pending.target,
        draft: pending.draft,
        sequence: draftSequence,
        localOnly: _draftsGaveUp,
        isCurrent: () => pending.revision == _draftRevision,
      );

  /// Points the reply at another post. The draft records the reply target,
  /// so the change advances the draft revision and schedules a save like any
  /// other draft field; a draft being restored passes [recordDraft] false,
  /// since the target is the draft's own.
  void retarget({
    int? replyToPostNumber,
    String? replyToUsername,
    bool replyingToWhisper = false,
    bool recordDraft = true,
  }) {
    // A submit already out was built from the target as it stood; the reply
    // it will create must not change underneath it.
    if (_disposed || _discarding || _state == ComposerState.submitting) return;
    final next = _target.replyingTo(
      replyToPostNumber,
      replyToUsername,
      replyingToWhisper: replyingToWhisper,
    );
    final whisper = replyingToWhisper || _whisper;
    if (next.replyToPostNumber == _target.replyToPostNumber &&
        next.replyToUsername == _target.replyToUsername &&
        next.replyingToWhisper == _target.replyingToWhisper &&
        whisper == _whisper) {
      return;
    }
    _target = next;
    _whisper = whisper;
    if (recordDraft) {
      _draftRevision++;
      _scheduleDraft();
    }
    _notify();
  }

  void beginSubmit() {
    if (_disposed) return;
    _state = ComposerState.submitting;
    _error = null;
    _notice = null;
    _notify();
  }

  void failed(WriteException error) {
    if (_disposed) return;
    _state = ComposerState.editing;
    _error = error;
    if (error.failure == WriteFailure.rateLimited) _holdFor(error.retryAfter);
    _notify();
  }

  void checking() {
    if (_disposed) return;
    _state = ComposerState.checking;
    _error = null;
    _notice = 'Checking whether that posted…';
    _notify();
  }

  void checkedNotPosted(WriteException error) {
    if (_disposed) return;
    _state = ComposerState.editing;
    _notice = null;
    _error = error;
    _notify();
  }

  void unresolved() {
    if (_disposed) return;
    _state = ComposerState.unresolved;
    _error = null;
    _notice =
        'That may have posted — the site could not be reached to check. '
        'Check again before sending it a second time.';
    _notify();
  }

  void _holdFor(Duration? wait) {
    _wait?.cancel();
    if (wait == null || wait <= Duration.zero) return;

    _rateLimited = true;
    // One timer for the whole wait, not a per-second tick: a repeating timer
    // buys a countdown and costs a rebuild a second, and a pending one fails
    // every widget test that does not know to wait it out.
    _wait = Timer(wait, () {
      _rateLimited = false;
      _notify();
    });
  }

  void enqueued(String? message) {
    if (_disposed) return;
    draftSettled();
    _state = ComposerState.editing;
    _error = null;
    _notice =
        message ?? 'Your reply was sent for review, so it is not posted yet.';
    _replaceDocument(TextEditingValue.empty);
    if (_target.createsTopic) {
      _replaceMetadata(titleValue: '', categoryId: null, tags: const []);
      _minimumRequiredTags = 0;
    }
    _typing.reset();
    _openedAt = _now();
    _fieldGeneration++;
    _notify();
  }

  void clearDocument() {
    if (_disposed) return;
    draftSettled();
    _state = ComposerState.editing;
    _error = null;
    _notice = null;
    _replaceDocument(TextEditingValue.empty);
    _clearUploads();
    _recomputeCanSubmit();
    _typing.reset();
    _openedAt = _now();
    _fieldGeneration++;
    _notify();
  }

  void replacePluginDocument({
    required String raw,
    required Iterable<ComposerUploadResult> uploads,
  }) {
    if (_disposed || _target.policy?.supportsEditing != true) return;
    draftSettled();
    _state = ComposerState.editing;
    _error = null;
    _notice = null;
    _clearUploads();
    for (final upload in uploads) {
      _uploads.add(
        ComposerUploadItem(
          id: _nextUploadId++,
          file: ComposerUploadFile(
            name: upload.originalFilename,
            length: () async => 0,
            openRead: () => const Stream<List<int>>.empty(),
          ),
          progress: 1,
          status: ComposerUploadStatus.completed,
          result: upload,
        ),
      );
    }
    _replaceDocument(
      TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      ),
    );
    _recomputeCanSubmit();
    _typing.reset();
    _openedAt = _now();
    _fieldGeneration++;
    _notify();
  }

  String _lastText = '';
  bool _replacingDocument = false;

  void _replaceDocument(TextEditingValue value) {
    _draftTimer?.cancel();
    autocomplete.close();
    _replacingDocument = true;
    try {
      text.value = value;
    } finally {
      _replacingDocument = false;
    }
  }

  void _replaceMetadata({
    required String titleValue,
    required int? categoryId,
    required Iterable<TopicTag> tags,
  }) {
    _replacingDocument = true;
    try {
      title.text = titleValue;
      _categoryId = categoryId;
      _tags = List.unmodifiable(tags);
    } finally {
      _replacingDocument = false;
    }
    _recomputeCanSubmit();
  }

  void _onTextChanged() {
    // TextEditingController also notifies for selection changes. Autocomplete
    // needs those caret updates; typing and draft clocks do not.
    if (!_replacingDocument) autocomplete.update(text.value);

    if (text.text == _lastText) return;
    _moveUploadAnchors(_lastText, text.text);
    _lastText = text.text;
    _draftRevision++;

    if (!_replacingDocument) {
      _typing.tick();
      _scheduleDraft();
    }

    // Only the send button depends on this, so notifying per keystroke would
    // rebuild the panel for nothing. Which means it has to be computed here
    // rather than read off the text: an edit typed back to what it said is a
    // change to the button with no change to whether the field is empty.
    _recomputeCanSubmit();
  }

  void _moveUploadAnchors(String before, String after) {
    if (_pendingUploads.isEmpty || before == after) return;
    var prefix = 0;
    final shared = before.length < after.length ? before.length : after.length;
    while (prefix < shared && before[prefix] == after[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before[before.length - suffix - 1] ==
            after[after.length - suffix - 1]) {
      suffix++;
    }
    final oldEnd = before.length - suffix;
    final newEnd = after.length - suffix;
    final delta = newEnd - oldEnd;
    for (final pending in _pendingUploads.values) {
      pending.anchor = switch (pending.anchor) {
        final anchor when anchor < prefix => anchor,
        final anchor when anchor > oldEnd => anchor + delta,
        _ => newEnd,
      };
    }
  }

  void _onMetadataChanged() {
    if (_disposed || _replacingDocument) return;
    _draftRevision++;
    _typing.tick();
    _scheduleDraft();
    final previousCanSubmit = _canSubmit;
    _recomputeCanSubmit();
    if (_canSubmit == previousCanSubmit) _notify();
  }

  void _recomputeCanSubmit() {
    final next = switch (_target.mode) {
      ComposerMode.reply => raw.isNotEmpty,
      ComposerMode.newTopic =>
        raw.isNotEmpty &&
            title.text.trim().isNotEmpty &&
            taxonomyValidationMessage == null,
      ComposerMode.privateMessage =>
        raw.isNotEmpty &&
            title.text.trim().isNotEmpty &&
            (_target.targetRecipients?.trim().isNotEmpty ?? false),
      ComposerMode.postEdit => raw.isNotEmpty && raw != _originalRaw,
      ComposerMode.topicEdit =>
        title.text.trim().isNotEmpty &&
            taxonomyValidationMessage == null &&
            (metadataChanged || (raw.isNotEmpty && raw != _originalRaw)),
      ComposerMode.categoryEdit =>
        taxonomyValidationMessage == null && metadataChanged,
      ComposerMode.tagsEdit =>
        taxonomyValidationMessage == null && !listEquals(_tags, _originalTags),
      ComposerMode.plugin => _target.policy!.validate(
        ComposerValidationContext(
          raw: raw,
          completedUploadCount: completedUploads.length,
        ),
      ),
    };
    if (next == _canSubmit) return;
    _canSubmit = next;
    _notify();
  }

  bool _disposed = false;

  void _clearUploads() {
    for (final pending in _pendingUploads.values) {
      if (!pending.abort.isCompleted) pending.abort.complete();
    }
    _pendingUploads.clear();
    _uploads.clear();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clearUploads();
    _wait?.cancel();
    _draftTimer?.cancel();
    text.removeListener(_onTextChanged);
    title.removeListener(_onMetadataChanged);
    text.dispose();
    title.dispose();
    autocomplete.dispose();
    focus.dispose();
    super.dispose();
  }
}

class _PendingComposerUpload {
  _PendingComposerUpload({
    required this.batch,
    required this.order,
    required this.anchor,
    required this.launchAnchor,
    required this.destination,
    required this.launchDestination,
    required this.galleryTarget,
  });

  final int batch;
  final int order;
  int anchor;
  final int launchAnchor;
  _ComposerUploadDestination destination;
  final _ComposerUploadDestination launchDestination;
  _PendingGalleryUploadTarget? galleryTarget;
  Completer<void> abort = Completer<void>();
  ComposerUploadResult? result;
  bool failed = false;
}

class _PendingGalleryUploadTarget {
  _PendingGalleryUploadTarget(this.gallery);

  ComposerImageGalleryBlock gallery;
  bool demoted = false;
}

enum _ComposerUploadDestination { standalone, newGallery, gallery }

class _ComposerTextReplacement {
  const _ComposerTextReplacement(this.start, this.end, this.replacement);

  final int start;
  final int end;
  final String replacement;
}
