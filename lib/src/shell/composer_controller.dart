import 'dart:async';

import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/topic_tag.dart';
import '../plugin_api/composer_syntax.dart';
import '../plugin_api/emoji_usage.dart';
import '../plugin_api/plugin_data.dart';
import 'composer_autocomplete.dart';
import 'composer_images.dart';
import 'composer_marks.dart';
import 'composer_pills.dart';
import 'composer_quotes.dart';
import 'composer_triggers.dart';
import 'markdown_editing_controller.dart';

/// What a composer is writing to.
///
/// Carries its own [siteUrl] rather than reading the current instance when it
/// comes time to submit. Switching sites while a reply is half written must not
/// send it to the site the user switched to, and every other cache in the shell
/// is site-keyed for the same reason.
enum ComposerMode { reply, newTopic, postEdit, topicEdit, tagsEdit, plugin }

/// Stable identity for a plugin-owned writing surface.
///
/// The pair is deliberately namespaced: two independently installed plugins
/// may both call a target `message` without either one stealing the other's
/// drafts or policy.
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

/// The mutable facts a target strategy may use to decide whether Send is live.
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

/// One resolved strategy for one plugin composer instance.
///
/// Resolution happens at the registry boundary. The controller retains this
/// immutable answer, which means uninstalling or reordering plugins cannot
/// silently change the policy of an already-open document.
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

/// Input handed to the exact strategy registered for [kind].
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
    this.editingPostId,
    this.editingPostNumber,
    ComposerMode? mode,
    this.originFeedId,
    this.originTopicId,
    this.initialCategoryId,
    this.initialTags = const [],
  }) : policy = null,
       data = const {},
       mode =
           mode ??
           (editingPostId == null ? ComposerMode.reply : ComposerMode.postEdit),
       assert(mode != ComposerMode.plugin);

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
       replyToPostNumber = null,
       replyToUsername = null,
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

  /// The post being answered, or null when the reply is to the topic itself.
  final int? replyToPostNumber;

  final String? replyToUsername;

  /// The post being rewritten, when this composer is editing rather than
  /// replying. Null for a reply.
  final int? editingPostId;

  /// Its number in the topic, for saying which post is being edited.
  final int? editingPostNumber;

  bool get isEdit => switch (mode) {
    ComposerMode.postEdit ||
    ComposerMode.topicEdit ||
    ComposerMode.tagsEdit => true,
    _ => false,
  };
  bool get isNewTopic => mode == ComposerMode.newTopic;
  bool get editsTopicMetadata => mode == ComposerMode.topicEdit;
  bool get isTagsEdit => mode == ComposerMode.tagsEdit;
  bool get isPlugin => mode == ComposerMode.plugin;

  /// What Discourse files a draft for this topic under.
  String get draftKey => switch (mode) {
    ComposerMode.newTopic => ComposerDraft.newTopicDraftKey,
    ComposerMode.plugin => policy!.draftKey,
    _ => 'topic_$topicId',
  };

  ComposerTarget replyingTo(int? postNumber, String? username) {
    if (isPlugin) return this;
    return ComposerTarget(
      siteUrl: siteUrl,
      tabId: tabId,
      topicId: topicId,
      slug: slug,
      topicTitle: topicTitle,
      replyToPostNumber: postNumber,
      replyToUsername: username,
      mode: mode,
      originFeedId: originFeedId,
      originTopicId: originTopicId,
      initialCategoryId: initialCategoryId,
      initialTags: initialTags,
    );
  }
}

/// One immutable draft revision handed to the persistence boundary.
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

/// Time spent actually typing.
///
/// Discourse's fast-typer check reads `typing_duration_msecs`, and it means
/// this rather than wall clock since the composer opened — a reply written over
/// a lunch break is not a bot. Gaps longer than [_pause] are someone reading or
/// thinking, so they do not count.
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

/// Where an open composer is in the business of sending.
enum ComposerState {
  editing,

  /// A create is in flight.
  submitting,

  /// A create failed in a way that might have posted anyway, and the topic is
  /// being re-read to find out.
  checking,

  /// The check could not be completed, so whether it posted is still unknown.
  /// Sending is held back — a second attempt would be a second post.
  unresolved,
}

/// How the draft of an open composer is getting on.
enum DraftStatus {
  /// Nothing written since the last save, or nothing written at all.
  clean,

  /// Being sent.
  saving,

  /// The site has this text.
  saved,

  /// The site does not have it. The local copy still does.
  failing,
}

/// One open composer.
///
/// Its own notifier rather than state on `ShellController`: a keystroke changes
/// nothing outside this panel, and the shell's notifier rebuilds the rail, the
/// sidebar and the whole post list along with it.
class ComposerController extends ChangeNotifier implements ComposerEditorHost {
  ComposerController(
    this._target, {
    this.onSaveDraft,
    ComposerSearch? search,
    this.onEmojiAccepted,
    String Function(String name)? resolveEmoji,
    ComposerPills? pills,
    ComposerQuoteContentsFormatter? formatQuoteContents,
    List<ComposerSyntaxPolicy> syntaxPolicies = const [],
    this.pluginStateReader,
    this.isCurrentComposer,
    this.imageUploader,
    ComposerUploadUrlResolver? resolveUploadUrls,
    this.canUploadImage,
    this.simultaneousUploads = 15,
    int maxImageWidth = 690,
    int maxImageHeight = 500,
    int minimumRequiredTags = 0,
    DateTime Function()? now,
  }) : text = MarkdownEditingController(
         imageSiteUrl: _target.siteUrl,
         resolveEmoji: resolveEmoji,
         pills: pills,
         formatQuoteContents: formatQuoteContents,
         syntaxPolicies: syntaxPolicies,
         resolveUploadUrls: resolveUploadUrls,
         maxImageWidth: maxImageWidth,
         maxImageHeight: maxImageHeight,
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
       // Named publicly for callers; the backing field stays encapsulated.
       // ignore: prefer_initializing_formals
       _minimumRequiredTags = minimumRequiredTags {
    text.addListener(_onTextChanged);
    title.addListener(_onMetadataChanged);
    _recomputeCanSubmit();
  }

  /// Waits this long after the last keystroke before saving, so a save is not
  /// sent per character.
  static const Duration draftDebounce = Duration(seconds: 2);

  /// Saves anyway once this much time has passed since the last one. Without
  /// it, someone typing without pause keeps pushing the debounce out and
  /// nothing is ever saved.
  static const Duration draftMaxWait = Duration(seconds: 15);

  /// After this many consecutive failures the sync gives up rather than
  /// keep asking a site that is not answering. The local copy is still being
  /// written, so nothing is lost by stopping.
  static const int maxDraftFailures = 5;

  /// Records an emoji accepted from autocomplete. Picker selections record
  /// themselves in the picker context before returning to the composer.
  final void Function(String code)? onEmojiAccepted;

  /// Write validation text originates in a response body. Keep the useful
  /// classification and status in diagnostics without retaining that text.
  static Object _safeDiagnosticError(Object error) => switch (error) {
    WriteException() => WriteException(
      error.failure,
      statusCode: error.statusCode,
      retryAfter: error.retryAfter,
    ),
    DraftWriteException() => const DraftWriteException(),
    _ => error,
  };

  /// Persists the draft. Supplied by the shell, which owns the site and the
  /// key; the composer only decides *when*.
  final Future<int?> Function(ComposerDraftSave save)? onSaveDraft;

  final ComposerImageUploader? imageUploader;
  final bool Function(String filename)? canUploadImage;
  final int simultaneousUploads;
  final ComposerPluginStateReader? pluginStateReader;
  final bool Function()? isCurrentComposer;

  /// What will be posted, and what is typed into.
  ///
  /// A [MarkdownEditingController] only to change how it is *drawn* — the
  /// string is untouched, and every other caller here treats it as the plain
  /// controller it still is.
  final MarkdownEditingController text;
  final TextEditingController title;

  int? _categoryId;
  int? get categoryId => _categoryId;

  List<TopicTag> _tags;
  List<TopicTag> get tags => _tags;

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

  /// Bumped every time the field starts a fresh document, for the panel to key
  /// the editable on.
  ///
  /// Rebuilding under a new key is the only way to drop the undo stack: it
  /// lives in the state of `EditableText`'s `UndoHistory`, nothing exposes it —
  /// `UndoHistoryController` offers `undo` and `redo` and no way to forget —
  /// and emptying the text does not touch it. Without this, undo walks straight
  /// back over the clear in [enqueued]; see there for what that costs.
  int get fieldGeneration => _fieldGeneration;
  int _fieldGeneration = 0;

  /// The mention and emoji popup over this composer.
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
  void requestFocus() => focus.requestFocus();

  ComposerState _state = ComposerState.editing;
  ComposerState get state => _state;

  bool get submitting => _state == ComposerState.submitting;

  /// Whether the check can be run again, after one could not be completed.
  bool get canRecheck => _state == ComposerState.unresolved;

  WriteException? _error;

  /// Why the last attempt was refused, if it was.
  WriteException? get error => _error;

  String? _notice;

  /// Something the site wants read — that the post was queued for review,
  /// usually.
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

  /// Starts valid images at the text position underneath the drop pointer.
  void addDroppedImages(Iterable<ComposerUploadFile> files, int offset) {
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
      showNotice('Drop at most $simultaneousUploads images at a time.');
      return;
    }

    final batch = _nextUploadBatch++;
    final anchor = offset.clamp(0, text.text.length);
    for (var order = 0; order < valid.length; order++) {
      final id = _nextUploadId++;
      final file = valid[order];
      _pendingUploads[id] = _PendingComposerUpload(
        batch: batch,
        order: order,
        anchor: anchor,
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
      final insertionOffset = first.value.anchor;

      final insertion = _imageBlockInsertion(
        text.text,
        insertionOffset,
        uploadImageMarkdown(result),
      );
      _pendingUploads.remove(first.key);
      _uploads.removeWhere((upload) => upload.id == first.key);
      _insertAt(insertionOffset, insertion);
      // A failed earlier item still owns the slot before what just landed. Its
      // anchor moved with the text insertion like every other pending upload;
      // put it back at the boundary so a later retry restores drop order.
      for (final pending in earlierFailed) {
        pending.anchor = insertionOffset;
      }
    }
    _recomputeCanSubmit();
    _notify();
  }

  int _uploadIndex(int id) => _uploads.indexWhere((upload) => upload.id == id);

  void _insertAt(int offset, String insertion) {
    final old = text.value;
    final at = offset.clamp(0, old.text.length);
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

  Timer? _wait;
  bool _rateLimited = false;

  /// True while a rate limit is still in force, so sending is held back rather
  /// than earning a second refusal.
  bool get rateLimited => _rateLimited;

  /// Turns [mark] on or off around the selection.
  void toggleMark(ComposerMark mark) {
    if (_disposed ||
        selectionTouchesComposerQuote(text.quoteBlocks, text.selection)) {
      return;
    }
    text.value = toggleMarkdownMark(text.value, mark.marker);
  }

  /// Inserts [insertion] over the current selection and leaves the caret after
  /// it.
  ///
  /// Compact plugin add-actions use this for mention and emoji triggers. It is
  /// kept here rather than manipulating the field from the widget so the same
  /// notification path drives autocomplete, uploads, and undo history.
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

  /// Inserts one canonical emoji shortcode at the current selection.
  ///
  /// A picker opened from `:part` completes that run, just as the web editor
  /// does. Otherwise the selection is replaced and prose immediately before
  /// it is separated from the shortcode by one space. No trailing space is
  /// forced: adjacent emoji and punctuation remain possible.
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

  /// Inserts a markdown block over the current selection, separated from the
  /// prose on either side by a blank line.
  ///
  /// Post quotes arrive through this path. Keeping block spacing here makes a
  /// quote safe at the beginning, middle, or end of an existing draft instead
  /// of making the selection toolbar reason about composer text.
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

  /// Prepends a block without discarding a restored new-topic draft.
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

  void removeImage(ComposerImageBlock image) => _replaceImage(image, '');

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

  /// Writes [suggestion] over the trigger that is open.
  ///
  /// Through `text.value` rather than poked into `text.text`, so
  /// [_onTextChanged] fires: the draft timer, the typing clock and `canSubmit`
  /// all hang off that one notification, and a mention inserted around it
  /// would be text the site never hears about. It also keeps the insertion on
  /// the undo stack, which an assignment with no valid selection would not.
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

  /// Removes an emoji completion that became disallowed while metadata was
  /// loading, without disturbing mention or hashtag completion.
  void closeEmojiAutocomplete() {
    if (_disposed || autocomplete.trigger?.kind != ComposerTriggerKind.emoji) {
      return;
    }
    autocomplete.close();
  }

  bool _canSubmit = false;

  bool _loadingBody = false;

  /// True while the post being edited is still being fetched.
  ///
  /// The stream carries cooked HTML only, so an edit composer opens empty and
  /// fills in once the markdown arrives.
  @override
  bool get loadingBody => _loadingBody;

  String? _originalRaw;

  /// The body an edit opened with: the baseline changes are measured against,
  /// and what the site checks for edit conflicts as `original_text`. Null
  /// until [loadedBody] supplies it — including after a failed fetch.
  @override
  String? get originalRaw => _originalRaw;

  /// Latched by [bodyLoadFailed], cleared only when [loadedBody] supplies the
  /// baseline. While set, the field holds typed-over emptiness rather than
  /// the post, so a submit would replace the whole post with it — and with no
  /// [originalRaw] to send, without the site's edit-conflict check either.
  bool _missingEditBody = false;

  /// Whether there is anything worth sending. Blank is not a post, and neither
  /// is an edit nobody has changed — the site refuses that anyway.
  ///
  /// An edit has one more way of being not worth sending: the body may not
  /// have arrived yet — or may have failed to arrive at all — and saving then
  /// would replace the post with whatever little the field holds.
  bool get canSubmit =>
      _canSubmit &&
      _state == ComposerState.editing &&
      !_rateLimited &&
      !_loadingBody &&
      !_missingEditBody &&
      !hasActiveUploads;

  /// Marks an edit composer as waiting for the post it is going to rewrite.
  void beginLoadingBody() {
    if (_disposed) return;
    _loadingBody = true;
    _notify();
  }

  /// Puts the post's own markdown in front of the user to edit.
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

  /// The post could not be fetched, so there is nothing to edit. Sending stays
  /// disabled until [loadedBody] supplies the body: an empty field here would
  /// blank the post rather than leave it, and text typed over the emptiness
  /// would replace the post rather than amend it. Metadata-only topic edits
  /// are held back with it, because the submit path follows a metadata save
  /// with a body update whenever the field differs from the baseline — and
  /// with no baseline, "unchanged" cannot be told from "missing".
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

  /// What the next draft save must be sequenced against. Seeded from the topic
  /// and advanced by every save and by a successful post.
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

  /// True once the sync has stopped trying, so the panel can say the site does
  /// not have this yet.
  bool get draftsGaveUp => _draftsGaveUp;

  /// Whether the latest unsynced revision could not be retained on-device.
  bool get localDraftFailed => _localDraftFailed;

  /// Whether a save is waiting out the debounce, so text neither the site nor
  /// this device has yet can be flushed before this composer is thrown away.
  bool get draftPending =>
      (_draftTimer?.isActive ?? false) || _queuedDraft != null;

  /// Whether local persistence is still waiting or running for this draft.
  ///
  /// Shell teardown needs the running case too: an operation may be waiting on
  /// platform storage without still being present in the debounce queue.
  bool get draftPersistencePending => draftPending || _draftSaveTask != null;

  /// This composer's contents, in the shape Discourse stores drafts in.
  ComposerDraft get draft => ComposerDraft(
    reply: text.text,
    action: _target.isNewTopic
        ? ComposerDraft.createTopicAction
        : ComposerDraft.replyAction,
    title: _target.isNewTopic ? title.text : null,
    categoryId: _target.isNewTopic ? _categoryId : null,
    tags: _target.isNewTopic ? _tags : const [],
    replyToPostNumber: _target.replyToPostNumber,
    replyToUsername: _target.replyToUsername,
    typingTime: typingDuration,
    composerTime: openDuration,
  );

  /// Puts an unfinished reply back in front of the user.
  ///
  /// Only when nothing has been typed yet: a restore that lands after someone
  /// has started writing must not overwrite them.
  void restore(ComposerDraft draft) {
    if (_disposed || text.text.isNotEmpty || title.text.isNotEmpty) return;
    _replaceDocument(
      TextEditingValue(
        text: draft.reply,
        selection: TextSelection.collapsed(offset: draft.reply.length),
      ),
    );
    if (_target.isNewTopic) {
      _replaceMetadata(
        titleValue: draft.title ?? '',
        categoryId: draft.categoryId,
        tags: draft.tags,
      );
    }
    _draftStatus = DraftStatus.clean;
    _localDraftFailed = false;
    _notify();
  }

  /// Marks the draft as no longer this composer's problem — the post landed,
  /// and Discourse deletes the draft itself when it accepts one.
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

  void _scheduleDraft() {
    // Scheduled even once the remote sync has given up: the save then writes
    // the local copy only — see `_saveDraft` — which is what the panel's
    // "kept on this device only" promises.
    if (onSaveDraft == null || _disposed || _state != ComposerState.editing) {
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
    if (running != null) return running;

    return _draftSaveTask = _drainDrafts(save);
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
    final request = ComposerDraftSave(
      target: pending.target,
      draft: pending.draft,
      sequence: draftSequence,
      localOnly: _draftsGaveUp,
      isCurrent: () => pending.revision == _draftRevision,
    );

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

  /// Points an already-open composer at a different post in the same topic,
  /// instead of throwing away what has been written.
  void retarget({int? replyToPostNumber, String? replyToUsername}) {
    _target = _target.replyingTo(replyToPostNumber, replyToUsername);
    _notify();
  }

  void beginSubmit() {
    if (_disposed) return;
    _state = ComposerState.submitting;
    _error = null;
    _notice = null;
    _notify();
  }

  /// Refused for a reason that is certain — the site said no, and said why.
  void failed(WriteException error) {
    if (_disposed) return;
    _state = ComposerState.editing;
    _error = error;
    if (error.failure == WriteFailure.rateLimited) _holdFor(error.retryAfter);
    _notify();
  }

  /// Looking for the post, after a failure that might have posted anyway.
  void checking() {
    if (_disposed) return;
    _state = ComposerState.checking;
    _error = null;
    _notice = 'Checking whether that posted…';
    _notify();
  }

  /// Checked, and it did not post. Safe to send again.
  void checkedNotPosted(WriteException error) {
    if (_disposed) return;
    _state = ComposerState.editing;
    _notice = null;
    _error = error;
    _notify();
  }

  /// The check itself failed, so whether it posted is unknown. Sending stays
  /// held back: guessing wrong here means posting twice with no way to undo it.
  void unresolved() {
    if (_disposed) return;
    _state = ComposerState.unresolved;
    _error = null;
    _notice =
        'That may have posted — the site could not be reached to check. '
        'Check again before sending it a second time.';
    _notify();
  }

  /// Discourse hands back how long to wait; sending is disabled until then
  /// rather than letting the user earn another refusal.
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

  /// Held for review: there is no post to show, so the composer stays open and
  /// says so rather than silently appearing to have done nothing.
  ///
  /// The text goes, because the reply *was* accepted — leaving it would put a
  /// working send button under writing that has already been submitted, and
  /// pressing it queues a second copy.
  ///
  /// Emptying the field is not enough on its own: the undo stack outlives it,
  /// so one Ctrl+Z would step back over the clear and hand the submitted text
  /// back, under a send button this composer has just made live again. The
  /// reply that was accepted is a finished document, so the field starts a new
  /// one — see [fieldGeneration].
  void enqueued(String? message) {
    if (_disposed) return;
    draftSettled();
    _state = ComposerState.editing;
    _error = null;
    _notice =
        message ?? 'Your reply was sent for review, so it is not posted yet.';
    _replaceDocument(TextEditingValue.empty);
    if (_target.isNewTopic) {
      _replaceMetadata(titleValue: '', categoryId: null, tags: const []);
      _minimumRequiredTags = 0;
    }
    _typing.reset();
    _openedAt = _now();
    _fieldGeneration++;
    _notify();
  }

  /// Starts a fresh document after a successful non-topic send.
  ///
  /// Replacing the keyed editable is intentional: clearing only the controller
  /// leaves the submitted message in Flutter's undo stack, where one Ctrl+Z
  /// would put already-sent text back under an enabled send button.
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

  /// Replaces a plugin composer with a record being edited.
  ///
  /// Retained attachments do not live in the Markdown body, so entering edit mode
  /// has to replace both parts of the document. Retained uploads are completed
  /// queue rows: they can be removed or sent with the edit, but never retried
  /// because there is no local file behind them.
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
    // A `TextEditingController` notifies on selection as well as on text, so
    // this runs on every click, every arrow key and every frame of a selection
    // drag. None of what follows is about the caret: ticking the clock here
    // counts reading time as typing time against Discourse's fast-typer check,
    // and scheduling a draft here spends a request re-sending text the site
    // already has.
    // Ahead of the guard below, because the popup is the one thing here that
    // *is* about the caret: clicking away from a half-typed name closes it.
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
    _recomputeCanSubmit();
  }

  void _recomputeCanSubmit() {
    final next = switch (_target.mode) {
      ComposerMode.reply => raw.isNotEmpty,
      ComposerMode.newTopic =>
        raw.isNotEmpty &&
            title.text.trim().isNotEmpty &&
            taxonomyValidationMessage == null,
      ComposerMode.postEdit => raw.isNotEmpty && raw != _originalRaw,
      ComposerMode.topicEdit =>
        title.text.trim().isNotEmpty &&
            taxonomyValidationMessage == null &&
            (metadataChanged || (raw.isNotEmpty && raw != _originalRaw)),
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

  /// A submit outlives the panel — closing the composer while one is in flight
  /// is normal — and ChangeNotifier throws once disposed.
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
  });

  final int batch;
  final int order;
  int anchor;
  Completer<void> abort = Completer<void>();
  ComposerUploadResult? result;
  bool failed = false;
}
