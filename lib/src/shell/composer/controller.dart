// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/discourse_api.dart';
import '../../data/draft_store.dart';
import '../../data/site_pdf_thumbnail_repository.dart';

import '../../foundation/count_label.dart';
import '../../models/composer_draft.dart';
import '../../models/composer_upload.dart';
import '../../models/site_config.dart';
import '../../models/topic_tag.dart';
import '../../plugin_api/composer_syntax.dart';
import '../../plugin_api/hashtag_kind.dart';
import '../../plugin_api/plugin_data.dart';
import 'autocomplete.dart';
import 'block_controller.dart';
import 'components/core.dart';
import 'components/gallery_source.dart';
import 'components/image_source.dart';
import 'components/list_source.dart';
import 'components/quote.dart';
import 'components/upload.dart';
import 'edit_history.dart';
import 'markdown_editing_controller.dart';
import 'markdown_highlight.dart';
import 'marks.dart';
import 'pills.dart';
import 'target.dart';
import 'triggers.dart';

export 'target.dart';

part 'upload_transactions.dart';

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

enum ComposerDiscardPreview { changes, all }

enum DraftStatus { clean, saving, saved, failing }

/// Immutable sent facts retained for the submission owner's read-only recheck.
abstract interface class ComposerSubmission {
  Object get attempt;
}

sealed class _ComposerSubmissionState {
  const _ComposerSubmissionState();
}

final class _ComposerEditing extends _ComposerSubmissionState {
  const _ComposerEditing();
}

sealed class _ComposerAttemptState extends _ComposerSubmissionState {
  const _ComposerAttemptState();

  Object get attempt;
}

final class _ComposerPreparing extends _ComposerAttemptState {
  const _ComposerPreparing(this.attempt);

  @override
  final Object attempt;
}

sealed class _ComposerSentState extends _ComposerAttemptState {
  const _ComposerSentState(this.sent);

  final ComposerSubmission sent;

  @override
  Object get attempt => sent.attempt;
}

final class _ComposerSent extends _ComposerSentState {
  const _ComposerSent(super.sent);
}

final class _ComposerChecking extends _ComposerSentState {
  const _ComposerChecking(super.sent);
}

final class _ComposerUnresolved extends _ComposerSentState {
  const _ComposerUnresolved(super.sent);
}

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
    this.prepareUpload,
    ComposerUploadUrlResolver? resolveUploadUrls,
    this.canUploadImage,
    this.canUploadFile,
    this.simultaneousUploads = 15,
    bool enableAutoGridImages = true,
    bool enableMarkdownLinkify = true,
    List<String> markdownLinkifyTlds = SiteConfig.defaultMarkdownLinkifyTlds,
    int maxImageWidth = 690,
    int maxImageHeight = 500,
    int minimumRequiredTags = 0,
    ComposerEditHistory? sharedHistory,
    DateTime Function()? now,
  }) : _ownsHistory = sharedHistory == null,
       _enableAutoGridImages = enableAutoGridImages,
       text = MarkdownEditingController(
         protectComponentSource: true,
         imageSiteUrl: _target.siteUrl,
         resolveEmoji: resolveEmoji,
         pills: pills,
         pluginHashtagPresentation: pluginHashtagPresentation,
         formatQuoteContents: formatQuoteContents,
         syntaxPolicies: [...syntaxPolicies],
         resolveUploadUrls: resolveUploadUrls,
         enableMarkdownLinkify: enableMarkdownLinkify,
         markdownLinkifyTlds: markdownLinkifyTlds,
         maxImageWidth: maxImageWidth,
         maxImageHeight: maxImageHeight,
         enableImageGalleries: !_target.isPlugin,
         enableTodos: !_target.isPlugin,
         enableBlockSeparators: !_target.isPlugin,
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
       _originalRecipients = _target.targetRecipients ?? '',
       _originalCategoryId = _target.initialCategoryId,
       _originalTags = List.unmodifiable(_target.initialTags),
       _whisper = _target.replyingToWhisper,
       _minimumRequiredTags = minimumRequiredTags {
    text.syntaxPolicies.addAll(coreComposerSyntaxPolicies(this));
    history =
        sharedHistory ??
        ComposerEditHistory(
          text,
          beforeRestore: text.clearKeyboardPillSelection,
          deferUntilSession: true,
        );
    text.onRemoveQuote = removeQuote;
    text.onTodoChanged = (value) {
      if (isEditing) history.transact(() => text.value = value);
    };
    blocks = ComposerBlockController(
      text: text,
      history: history,
      canEdit: () =>
          isEditing && !loadingBody && !activeEditor.history.composing,
      notice: showNotice,
    );
    text.addListener(_onTextChanged);
    focus.addListener(_activateMainEditor);
    title.addListener(_onMetadataChanged);
    _recomputeCanSubmit();
  }

  static const Duration draftDebounce = Duration(seconds: 2);

  static const Duration draftMaxWait = Duration(seconds: 15);

  static const int maxDraftFailures = 5;

  final void Function(String code)? onEmojiAccepted;

  final Future<int?> Function(ComposerDraftSave save)? onSaveDraft;
  final Future<void> Function(ComposerDraftSave save)? onStageDraft;

  final ComposerImageUploader? imageUploader;
  final ComposerUploadPreparer? prepareUpload;
  final bool Function(String filename)? canUploadImage;
  final bool Function(String filename)? canUploadFile;
  final int simultaneousUploads;
  bool _enableAutoGridImages;
  bool get enableAutoGridImages => _enableAutoGridImages;

  void updateEnableAutoGridImages(bool value) {
    _enableAutoGridImages = value;
    if (value) return;
    _uploadTransactions.disableAutomaticGalleries();
  }

  void updateMarkdownLinkify({
    required bool enabled,
    required List<String> tlds,
  }) => text.updateMarkdownLinkify(enabled: enabled, tlds: tlds);

  final ComposerPluginStateReader? pluginStateReader;
  final bool Function()? isCurrentComposer;

  final MarkdownEditingController text;
  late final ComposerEditHistory history;
  final bool _ownsHistory;

  /// Embedded list bodies share document history and adapt native proposals
  /// before they become edits to the canonical Markdown.
  List<TextInputFormatter> get inputFormatters => const [];
  bool get singleNewlineParagraphs => false;
  late final ComposerBlockController blocks;
  final TextEditingController title;

  ComposerController? _activeEmbeddedEditor;

  /// Routes the enclosing toolbar to the rich text editor last focused.
  ComposerController get activeEditor {
    final embedded = _activeEmbeddedEditor;
    return embedded != null && embedded.isCurrent
        ? embedded.activeEditor
        : this;
  }

  void activateEmbeddedEditor(ComposerController? editor) {
    if (_disposed) return;
    _activeEmbeddedEditor = editor;
    // A nested region can change while its enclosing editor stays the same.
    // Rebuild the shared toolbar for the deepest newly focused editor.
    _notify();
  }

  void deactivateEmbeddedEditor(ComposerController editor) {
    if (!identical(_activeEmbeddedEditor, editor)) return;
    _activeEmbeddedEditor = null;
    // Embedded fields may unmount while the enclosing editor is rebuilding.
    scheduleMicrotask(_notify);
  }

  void _activateMainEditor() {
    // Initial focus already belongs to the main editor. Only switching back
    // from an embedded field needs to rebuild the shared toolbar and panel.
    if (focus.hasPrimaryFocus && _activeEmbeddedEditor != null) {
      activateEmbeddedEditor(null);
    }
  }

  int? _categoryId;
  int? get categoryId => _categoryId;

  List<TopicTag> _tags;
  List<TopicTag> get tags => _tags;

  bool _whisper;
  bool get whisper => _whisper;

  void setWhisper(bool value) {
    if (!isEditing ||
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
  final String _originalRecipients;
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
  /// whether Discard needs confirmation. An applied category template is the
  /// body's baseline, as core makes it the composer's original text.
  bool get hasChanges =>
      text.text.trim() !=
          (_originalRaw ?? _appliedTopicTemplate ?? '').trim() ||
      (_target.isPrivateMessage &&
          _target.targetRecipients != _originalRecipients) ||
      ((_target.createsTopic || _target.editsTopicMetadata) &&
          title.text.trim() != _originalTitle.trim());

  bool get canSaveDraft => onSaveDraft != null;

  int get draftRevision => _draftRevision;

  // The draft as opened, independent of continuously advancing autosaves.
  ComposerDraft? _savedDraft;
  ComposerTarget? _savedDraftTarget;
  ComposerDraft? get savedDraft => _savedDraft;

  bool get hasSavedDraftChanges {
    final saved = _savedDraft;
    if (saved == null) return false;
    final current = draft;
    return current.reply.trimRight() != saved.reply.trimRight() ||
        current.title?.trimRight() != saved.title?.trimRight() ||
        current.categoryId != saved.categoryId ||
        !listEquals(current.tags, saved.tags) ||
        current.recipients != saved.recipients ||
        current.replyToPostNumber != saved.replyToPostNumber ||
        current.replyToUsername != saved.replyToUsername ||
        current.whisper != saved.whisper;
  }

  void captureDraftSavepoint() {
    if (_disposed || !_restoredDraft) return;
    _savedDraft = draft;
    _savedDraftTarget = _target;
  }

  ComposerDiscardPreview? _discardPreview;
  int? _discardPreviewRevision;
  ComposerDraft? _rollbackPreviewFrom;
  Animation<double>? _rollbackAnimation;

  ComposerDraft? get discardPreviewTarget =>
      _discardPreviewRevision != _draftRevision
      ? null
      : switch (_discardPreview) {
          ComposerDiscardPreview.changes => _savedDraft,
          ComposerDiscardPreview.all => const ComposerDraft(
            reply: '',
            title: '',
          ),
          null => null,
        };
  ComposerDraft get discardPreviewFrom => _rollbackPreviewFrom ?? draft;
  Animation<double>? get rollbackAnimation => _rollbackAnimation;

  ComposerDiscardPreview? get discardPreviewKind =>
      discardPreviewTarget == null ? null : _discardPreview;

  void previewDiscard(ComposerDiscardPreview? preview, int revision) {
    if (_disposed || _discarding || revision != _draftRevision) return;
    if (_discardPreview == preview && _discardPreviewRevision == revision) {
      return;
    }
    _discardPreview = preview;
    _discardPreviewRevision = revision;
    _notify();
  }

  void clearDiscardPreview() {
    _discardPreview = null;
    _discardPreviewRevision = null;
    _rollbackPreviewFrom = null;
    _rollbackAnimation = null;
    _notify();
  }

  bool showDraftRollback(
    ComposerDraft from,
    Animation<double> animation,
    int revision,
  ) {
    if (_disposed || revision != _draftRevision || beginDiscard() == null) {
      return false;
    }
    _rollbackPreviewFrom = from;
    _rollbackAnimation = animation;
    _discardPreview = ComposerDiscardPreview.changes;
    _discardPreviewRevision = revision;
    _notify();
    return true;
  }

  int? applySavedDraftRollback(int revision) {
    final saved = _savedDraft;
    final target = _savedDraftTarget;
    if (!_discarding ||
        !discardRevisionIsCurrent(revision) ||
        saved == null ||
        target == null ||
        target.siteUrl != _target.siteUrl ||
        target.draftKey != _target.draftKey) {
      return null;
    }
    autocomplete.close();
    _target = target;
    _whisper = saved.whisper;
    _replacingDocument = true;
    try {
      history.transact(
        () => text.value = TextEditingValue(
          text: saved.reply,
          selection: TextSelection.collapsed(offset: saved.reply.length),
        ),
      );
      if (_target.createsTopic) {
        title.text = saved.title ?? '';
        _categoryId = saved.categoryId;
        _tags = List.unmodifiable(saved.tags);
      }
    } finally {
      _replacingDocument = false;
    }
    blocks.reset();
    _resumeDraftAfterDiscardPrompt = false;
    final conflict = _draftConflict;
    draftSettled();
    _draftConflict = conflict;
    if (conflict) _draftStatus = DraftStatus.failing;
    _recomputeCanSubmit();
    _notify();
    return _draftRevision;
  }

  void draftRollbackWriteFailed({required bool localFailed}) {
    if (_disposed) return;
    _localDraftFailed = localFailed;
    _draftStatus = DraftStatus.failing;
    _notify();
  }

  bool _hasUnappliedDraft = false;
  bool get hasUnappliedDraft => _hasUnappliedDraft;
  bool _restoredDraft = false;
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
              (_target.targetRecipients?.isEmpty == true ||
                  draft.recipients?.trim() ==
                      _target.targetRecipients?.trim())));

  bool _discarding = false;
  bool get discarding => _discarding;

  bool _closing = false;
  bool get closing => _closing;

  bool beginClose() {
    if (_disposed || _discarding || _closing) return false;
    _closing = true;
    _notify();
    return true;
  }

  void cancelClose() {
    if (_disposed || !_closing) return;
    _closing = false;
    _notify();
  }

  bool _discardPromptOpen = false;
  bool _resumeDraftAfterDiscardPrompt = false;

  bool beginDiscardPrompt() {
    if (_disposed || _discarding || _discardPromptOpen) return false;
    _discardPromptOpen = true;
    _resumeDraftAfterDiscardPrompt = draftPending;
    _draftTimer?.cancel();
    _queuedDraft = null;
    return true;
  }

  void finishDiscardPrompt() {
    clearDiscardPreview();
    _discardPromptOpen = false;
    if (_resumeDraftAfterDiscardPrompt) {
      _resumeDraftAfterDiscardPrompt = false;
      _scheduleDraft();
    }
  }

  int? beginDiscard() {
    if (_disposed ||
        _discarding ||
        (state != ComposerState.editing && state != ComposerState.unresolved)) {
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
      ? appL10n.chooseAtLeastForThisCategory(
          (countLabel(_minimumRequiredTags, CountNoun.tag)).toString(),
        )
      : null;

  void setCategory(int? value, {int minimumRequiredTags = 0}) {
    if (_disposed ||
        (value == _categoryId && minimumRequiredTags == _minimumRequiredTags)) {
      return;
    }
    _clearTagRemovalNotice();
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

  /// Nothing has been typed, chosen or restored into this composer yet.
  bool get _untouched =>
      _draftRevision == 0 && !_restoredDraft && !_hasUnappliedDraft;

  void applyInitialTagsIfUntouched(Iterable<TopicTag> value) {
    if (_disposed || !_untouched) return;
    final next = List<TopicTag>.unmodifiable(value);
    if (listEquals(next, _tags)) return;
    _tags = next;
    _originalTags = next;
    _recomputeCanSubmit();
    _notify();
  }

  /// The category template this composer last put in its body. It stays the
  /// baseline of [hasChanges] until the document is replaced.
  String? _appliedTopicTemplate;

  /// Mirrors core's `applyTopicTemplate` for a new topic whose category has
  /// changed: a body that is empty, or still exactly [replacing] (the previous
  /// category's template), becomes [template], or empty when the category has
  /// none. Anything else was written by the author and stays.
  ///
  /// The template belongs to the category choice, which undo does not revisit,
  /// so it replaces the document rather than becoming a step undo could take
  /// back. It is not a draft of its own: only a save the author's changes
  /// already scheduled goes on to carry it.
  void applyTopicTemplate(String? template, {String? replacing}) {
    if (_disposed || !_target.isNewTopic || !isEditing) return;
    final body = text.text;
    if (body.isNotEmpty && body != replacing) return;
    final next = template ?? '';
    if (next == body) return;
    final draftWasPending = _draftTimer?.isActive ?? false;
    _replaceDocument(
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      ),
    );
    _appliedTopicTemplate = template;
    if (draftWasPending) _scheduleDraft();
    _notify();
  }

  /// The template of the category a new topic opens in. A composer the author
  /// has already typed, chosen or restored into keeps what it holds.
  void applyInitialTopicTemplateIfUntouched(String? template) {
    if (_disposed || !_untouched) return;
    applyTopicTemplate(template);
  }

  /// Takes what the site stored as the baseline of the next metadata write.
  /// The site's [title] and [tags], when its answer carried them, replace the
  /// typed values too: a baseline left at the typed title fails the next
  /// write's `original_title` check, and fields left at it read as a change.
  void metadataSettled({
    required int? categoryId,
    String? title,
    List<TopicTag>? tags,
  }) {
    if (_disposed) return;
    _categoryId = categoryId;
    if (title != null && title != this.title.text.trim()) {
      _replaceMetadata(
        titleValue: title,
        categoryId: categoryId,
        tags: tags ?? _tags,
      );
    } else if (tags != null) {
      _tags = List.unmodifiable(tags);
    }
    _originalTitle = this.title.text.trim();
    _originalCategoryId = _categoryId;
    _originalTags = _tags;
    _recomputeCanSubmit();
    _notify();
  }

  final FocusNode focus = FocusNode();
  final FocusNode titleFocus = FocusNode(debugLabel: 'Composer title');

  int get fieldGeneration => _fieldGeneration;
  int _fieldGeneration = 0;

  final ComposerAutocomplete autocomplete;

  final TypingClock _typing;
  final DateTime Function() _now;
  DateTime _openedAt;

  ComposerTarget _target;
  ComposerTarget get target => _target;
  PluginComposerTarget? get _pluginTarget => switch (_target) {
    final PluginComposerTarget target => target,
    _ => null,
  };

  void setRecipients(Iterable<String> values) {
    final target = _target;
    if (_disposed || target is! PrivateMessageComposerTarget || !isEditing) {
      return;
    }
    final recipients = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(',');
    if (recipients == _target.targetRecipients) return;
    _target = target.withRecipients(recipients);
    _onMetadataChanged();
  }

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
  bool get isNewTopic => _target.isNewTopic;

  @override
  bool get isReply => _target.mode == ComposerMode.reply;

  @override
  bool get isPrivateMessage =>
      _target.isPrivateMessage || _target.privateMessageTopic;

  @override
  bool get isEditing =>
      isCurrent &&
      !_discarding &&
      !_closing &&
      !_loadingBody &&
      (state == ComposerState.editing || state == ComposerState.unresolved);

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

  _ComposerSubmissionState _submissionState = const _ComposerEditing();

  ComposerState get state => switch (_submissionState) {
    _ComposerEditing() => ComposerState.editing,
    _ComposerPreparing() || _ComposerSent() => ComposerState.submitting,
    _ComposerChecking() => ComposerState.checking,
    _ComposerUnresolved() => ComposerState.unresolved,
  };

  bool get submitting => state == ComposerState.submitting;

  bool get canRecheck => _submissionState is _ComposerUnresolved;

  WriteException? _error;

  WriteException? get error => _error;

  String? _notice;

  String? get notice => _notice;

  void showNotice(String? message) {
    if (_disposed) return;
    _notice = message;
    _notify();
  }

  String? _tagRemovalNotice;
  Timer? _tagRemovalNoticeTimer;

  String? get tagRemovalNotice => _tagRemovalNotice;

  void showTagRemovalNotice({String? categoryName}) {
    if (_disposed) return;
    _clearTagRemovalNotice();
    _tagRemovalNotice = categoryName == null || categoryName.isEmpty
        ? appL10n.theyArenTAvailableInThisCategory
        : appL10n.theyArenTAvailableIn((categoryName).toString());
    _tagRemovalNoticeTimer = Timer(
      const Duration(seconds: 7),
      dismissTagRemovalNotice,
    );
    _notify();
  }

  void dismissTagRemovalNotice() {
    if (_disposed || _tagRemovalNotice == null) return;
    _clearTagRemovalNotice();
    _notify();
  }

  void _clearTagRemovalNotice() {
    _tagRemovalNoticeTimer?.cancel();
    _tagRemovalNoticeTimer = null;
    _tagRemovalNotice = null;
  }

  late final _uploadTransactions = _ComposerUploadTransactions(
    editor: _ComposerUploadEditor(this),
    uploader: imageUploader,
    prepare: prepareUpload,
    acceptsImage: canUploadImage,
    acceptsFile: canUploadFile,
    simultaneousLimit: simultaneousUploads,
  );

  ComposerUploadPlaceholders get uploadPlaceholders =>
      _uploadTransactions.uploadPlaceholders;

  List<ComposerUploadItem> get uploads => _uploadTransactions.uploads;
  List<ComposerUploadResult> get completedUploads =>
      _uploadTransactions.completedUploads;
  bool get hasActiveUploads => _uploadTransactions.hasActiveUploads;
  bool get canUpload => _uploadTransactions.canUpload;

  void addFiles(
    Iterable<ComposerUploadFile> files,
    int offset, {
    ComposerImageGalleryBlock? gallery,
  }) => _uploadTransactions.addFiles(files, offset, gallery: gallery);

  void addImages(Iterable<ComposerUploadFile> files, int offset) =>
      _uploadTransactions.addImages(files, offset);

  void addImagesToGallery(
    Iterable<ComposerUploadFile> files,
    ComposerImageGalleryBlock gallery,
  ) => _uploadTransactions.addImagesToGallery(files, gallery);

  void retryUpload(int id) => _uploadTransactions.retryUpload(id);
  void cancelUpload(int id) => _uploadTransactions.cancelUpload(id);
  void removeUpload(int id) => cancelUpload(id);

  Timer? _wait;
  bool _rateLimited = false;

  bool get rateLimited => _rateLimited;

  void toggleMark(ComposerMark mark) {
    if (!isEditing ||
        selectionTouchesComposerQuote(text.quoteBlocks, text.selection)) {
      return;
    }
    text.value = toggleMarkdownMark(text.value, mark.marker);
  }

  void toggleSelectedInlineCode() {
    if (!isEditing) return;
    final selection = text.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    toggleMark(ComposerMark.inlineCode);
  }

  void formatSelection(TextEditingValue Function(TextEditingValue) format) {
    if (!isEditing ||
        !text.selection.isValid ||
        text.selection.isCollapsed ||
        selectionTouchesComposerQuote(text.quoteBlocks, text.selection)) {
      return;
    }
    history.transact(() => text.value = format(text.value));
  }

  /// Applies an ATX heading to the caret's line, preserving its text.
  void setHeading(int level) {
    if (!isEditing || level < 1 || level > 4) return;
    final old = text.value;
    final caret = old.selection.isValid
        ? old.selection.extentOffset
        : old.text.length;
    final start = caret == 0 ? 0 : old.text.lastIndexOf('\n', caret - 1) + 1;
    final prefix = RegExp(
      r'^ {0,3}#{1,6}(?:[ \t]+|$)',
    ).firstMatch(old.text.substring(start));
    final end = start + (prefix?.end ?? 0);
    final marker = '${'#' * level} ';
    text.value = old.copyWith(
      text: old.text.replaceRange(start, end, marker),
      selection: TextSelection.collapsed(
        offset: (caret < end ? start : caret - (end - start)) + marker.length,
      ),
      composing: TextRange.empty,
    );
  }

  void insertText(String insertion) {
    if (!isEditing || insertion.isEmpty) return;
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

  void insertMention() {
    if (!isEditing) return;
    final old = text.value;
    // Reopen a dismissed mention without adding a second @ to its query.
    if (composerTriggerAt(old)?.kind == ComposerTriggerKind.mention) {
      autocomplete.close();
      autocomplete.update(old);
      return;
    }
    final selection = old.selection.isValid
        ? old.selection
        : TextSelection.collapsed(offset: old.text.length);
    final start = selection.start;
    final prefix = _emojiSigilOpensWord(old.text, start) ? '' : ' ';
    final suffix =
        selection.end < old.text.length &&
            !RegExp(r'\s').hasMatch(old.text[selection.end])
        ? ' '
        : '';
    text.value = old.copyWith(
      text: old.text.replaceRange(start, selection.end, '$prefix@$suffix'),
      selection: TextSelection.collapsed(offset: start + prefix.length + 1),
      composing: TextRange.empty,
    );
  }

  void insertEmoji(String bareCode) {
    if (!isEditing) return;
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
    if (!isEditing || text.value != expectedValue || markdown.trim().isEmpty) {
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
    final lineEnding = old.text.contains('\r\n') ? '\r\n' : '\n';
    final block = markdown.trim();
    final separator = _separatorBefore(after, lineEnding);
    final insertion = '${_separatorAfter(before, lineEnding)}$block$separator';
    final caret = after.isEmpty
        ? insertion.length
        : insertion.length -
              separator.length +
              _followingGapLength('$separator$after');

    text.value = old.copyWith(
      text: old.text.replaceRange(selection.start, selection.end, insertion),
      selection: TextSelection.collapsed(offset: selection.start + caret),
      composing: TextRange.empty,
    );
  }

  void prependBlock(String markdown) {
    if (!isEditing || markdown.trim().isEmpty) return;
    text.selection = const TextSelection.collapsed(offset: 0);
    _insertBlock(markdown);
  }

  static String _separatorAfter(String before, [String lineEnding = '\n']) {
    if (before.isEmpty || _endsWithLineBreaks(before, 2)) return '';
    return _endsWithLineBreaks(before, 1)
        ? lineEnding
        : '$lineEnding$lineEnding';
  }

  static String _separatorBefore(String after, [String lineEnding = '\n']) {
    if (after.isEmpty) return '$lineEnding$lineEnding';
    if (_startsWithLineBreaks(after, 2)) return '';
    return _startsWithLineBreaks(after, 1)
        ? lineEnding
        : '$lineEnding$lineEnding';
  }

  /// The blank line between a block and the next one is structural spacing
  /// that cannot hold a caret, and the editor only snaps a caret out of it
  /// when the text is unchanged. The caret after an inserted block therefore
  /// passes the block's own line break and at most one blank line, landing
  /// where the next block starts; further empty lines are the author's own.
  static int _followingGapLength(String source) {
    var cursor = 0;
    for (var lineBreaks = 0; lineBreaks < 2; lineBreaks++) {
      final length = _lineBreakLengthAt(source, cursor);
      if (length == 0) break;
      cursor += length;
    }
    return cursor;
  }

  static int _lineBreakLengthAt(String source, int offset) {
    if (offset >= source.length) return 0;
    if (source.codeUnitAt(offset) == 0x0A) return 1;
    return offset + 1 < source.length &&
            source.codeUnitAt(offset) == 0x0D &&
            source.codeUnitAt(offset + 1) == 0x0A
        ? 2
        : 0;
  }

  static bool _endsWithLineBreaks(String source, int count) {
    var cursor = source.length;
    for (var found = 0; found < count; found++) {
      if (cursor == 0 || source.codeUnitAt(cursor - 1) != 0x0A) return false;
      cursor--;
      if (cursor > 0 && source.codeUnitAt(cursor - 1) == 0x0D) cursor--;
    }
    return true;
  }

  static bool _startsWithLineBreaks(String source, int count) {
    var cursor = 0;
    for (var found = 0; found < count; found++) {
      if (cursor < source.length && source.codeUnitAt(cursor) == 0x0D) {
        cursor++;
      }
      if (cursor >= source.length || source.codeUnitAt(cursor) != 0x0A) {
        return false;
      }
      cursor++;
    }
    return true;
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

  void moveImageToOffset(ComposerImageBlock image, int offset) {
    if (!isEditing || !_stillContainsImage(image)) return;
    final gallery = galleryForImage(image);
    if (gallery != null) {
      moveImageOutOfGallery(gallery, image, offset: offset);
      return;
    }
    final old = text.value;
    if (offset < 0 ||
        offset > old.text.length ||
        (offset >= image.start && offset <= image.end) ||
        text.galleryBlocks.any(
          (block) => offset > block.start && offset < block.end,
        )) {
      return;
    }
    final withoutImage = old.text.replaceRange(image.start, image.end, '');
    final destination = offset > image.end
        ? offset - (image.end - image.start)
        : offset;
    final before = withoutImage.substring(0, destination);
    final after = withoutImage.substring(destination);
    final insertion =
        '${_separatorAfter(before)}${image.source}${_separatorBefore(after)}';
    text.value = old.copyWith(
      text: withoutImage.replaceRange(destination, destination, insertion),
      selection: TextSelection.collapsed(
        offset: destination + insertion.length,
      ),
      composing: TextRange.empty,
    );
  }

  void moveImageOutOfGallery(
    ComposerImageGalleryBlock gallery,
    ComposerImageBlock image, {
    int? offset,
  }) {
    if (!isEditing) return;
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
    if (offset != null) {
      final old = text.value;
      if (offset < 0 ||
          offset > old.text.length ||
          text.galleryBlocks.any(
            (block) => offset > block.start && offset < block.end,
          )) {
        return;
      }
      final uploadEdit = _uploadTransactions.captureGalleryEdit(current);
      final replacement = remaining.isEmpty
          ? ''
          : _galleryMarkdown(current.mode, remaining);
      final withoutImage = old.text.replaceRange(
        current.start,
        current.end,
        replacement,
      );
      final destination = offset >= current.end
          ? offset + replacement.length - (current.end - current.start)
          : offset;
      final before = withoutImage.substring(0, destination);
      final after = withoutImage.substring(destination);
      final insertion =
          '${_separatorAfter(before)}${member.source}${_separatorBefore(after)}';
      final galleryStart = destination <= current.start
          ? current.start + insertion.length
          : current.start;
      text.value = old.copyWith(
        text: withoutImage.replaceRange(destination, destination, insertion),
        selection: TextSelection.collapsed(
          offset: destination + insertion.length,
        ),
        composing: TextRange.empty,
      );
      final updated = remaining.isEmpty
          ? null
          : text.galleryBlocks
                .where((block) => block.start == galleryStart)
                .firstOrNull;
      uploadEdit.complete(
        updated,
        fallbackAnchor: destination + insertion.length,
      );
      return;
    }
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
    Iterable<ComposerImageBlock> images, {
    int? insertionIndex,
  }) {
    if (!isEditing) return;
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

    final uploadEdit = _uploadTransactions.captureGalleryEdit(current);
    final members = current.images.toList();
    members.insertAll(
      (insertionIndex ?? members.length).clamp(0, members.length),
      selected,
    );
    final replacement = _galleryMarkdown(current.mode, members);
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
    uploadEdit.complete(updated, fallbackAnchor: galleryEnd);
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
    if (!isEditing ||
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
    if (!isEditing ||
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

  ComposerImageGalleryBlock? _resolveGalleryIdentity(
    ComposerImageGalleryBlock captured, {
    int? anchor,
  }) {
    if (_disposed || _target.isPlugin) return null;
    final galleries = parseComposerImageGalleries(text.text);
    final exact = galleries
        .where((candidate) => _sameComposerGallery(candidate, captured))
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

  void _replaceGallery(
    ComposerImageGalleryBlock gallery,
    String replacement, {
    bool preservePendingTarget = true,
  }) {
    if (!isEditing) return;
    final current = _currentGallery(gallery);
    if (current == null) return;
    final uploadEdit = _uploadTransactions.captureGalleryEdit(current);
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
    uploadEdit.complete(
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
    if (!isEditing || suggestion.action != null) return;
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

  /// The loaded body exactly as the site holds it: an edit sends it as
  /// `original_text`, which the site compares byte-for-byte with the post's
  /// raw and refuses as a conflict on any difference.
  String? _originalRaw;

  @override
  String? get originalRaw => _originalRaw;

  bool _missingEditBody = false;

  bool get canSubmit =>
      _canSubmit &&
      state == ComposerState.editing &&
      !_rateLimited &&
      !_loadingBody &&
      !_missingEditBody &&
      !hasActiveUploads;

  void beginLoadingBody() {
    if (_disposed) return;
    _loadingBody = true;
    _notify();
  }

  void loadedBody(String raw, {int? caretOffset}) {
    if (_disposed) return;
    _loadingBody = false;
    _missingEditBody = false;
    _originalRaw = raw;
    final offset = (caretOffset ?? raw.length).clamp(0, raw.length);
    _replaceDocument(
      TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: offset),
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

  /// New posts keep leading Markdown indentation, as PostCreator does.
  String get raw =>
      _uploadTransactions.uploadPlaceholders.strip(text.text).trimRight();

  /// The body an edit sends. The site stores a revision right-stripped but
  /// keeps its start, so trimming it would unindent a leading code block.
  String get editRaw =>
      _uploadTransactions.uploadPlaceholders.strip(text.text).trimRight();

  /// Whether saving the edit would change the body the site stores.
  bool get _bodyEdited => editRaw != _originalRaw?.trimRight();

  int draftSequence = 0;

  ComposerSubmission? get submission => switch (_submissionState) {
    _ComposerSentState(:final sent) => sent,
    _ComposerEditing() || _ComposerPreparing() => null,
  };

  bool ownsSubmission(Object attempt) {
    final current = _submissionState;
    return !_disposed &&
        current is _ComposerAttemptState &&
        identical(current.attempt, attempt);
  }

  void retainSubmission(ComposerSubmission submission) {
    if (_disposed) return;
    if (_submissionState case _ComposerPreparing(
      :final attempt,
    ) when identical(attempt, submission.attempt)) {
      _submissionState = _ComposerSent(submission);
    }
  }

  void _retireSubmission() {
    _submissionState = const _ComposerEditing();
  }

  Timer? _draftTimer;
  DateTime? _lastDraftSaveAt;
  int _draftFailures = 0;
  bool _draftsGaveUp = false;
  bool _draftConflict = false;
  int _draftSettlement = 0;
  bool _localDraftFailed = false;
  int _draftRevision = 0;
  _PendingDraft? _queuedDraft;
  Future<void>? _draftSaveTask;

  DraftStatus _draftStatus = DraftStatus.clean;
  DraftStatus get draftStatus => _draftStatus;

  bool get draftsGaveUp => _draftsGaveUp || _draftConflict;

  bool get draftConflict => _draftConflict;

  void draftSaveConflicted() {
    if (_disposed) return;
    _draftConflict = true;
    _draftStatus = DraftStatus.failing;
    _notify();
  }

  bool get localDraftFailed => _localDraftFailed;

  bool get draftPending =>
      (_draftTimer?.isActive ?? false) || _queuedDraft != null;

  bool get draftPersistencePending => draftPending || _draftSaveTask != null;

  ComposerDraft get draft => ComposerDraft(
    reply: _uploadTransactions.uploadPlaceholders.strip(text.text),
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
    _restoredDraft = true;
    final target = _target;
    final recipients = draft.recipients;
    if (target is PrivateMessageComposerTarget &&
        target.targetRecipients.isEmpty &&
        recipients != null) {
      _target = target.withRecipients(recipients);
    }
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
    captureDraftSavepoint();
    _notify();
    return true;
  }

  void draftSettled() {
    _draftSettlement++;
    _draftConflict = false;
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

  Future<void> flushDraftOnBackground() {
    if (!(_draftTimer?.isActive ?? false) ||
        _discarding ||
        (state != ComposerState.editing && state != ComposerState.unresolved)) {
      return Future.value();
    }
    // Queued revisions are already staged locally. Enqueuing them again
    // could reclaim a shared draft key from another retained composer.
    return flushDraft();
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
        (state != ComposerState.editing && state != ComposerState.unresolved)) {
      return;
    }
    _draftTimer?.cancel();

    if (_discardPromptOpen) {
      _resumeDraftAfterDiscardPrompt = true;
      return;
    }

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
    final settlement = _draftSettlement;

    if (request.localOnly) {
      // The site is not being asked again, but the local copy is still
      // written — the shell sees [draftsGaveUp] and stops after it. The
      // status is left as it was: the site still does not have the text.
      try {
        await save(request);
        if (!_disposed && request.isCurrent()) _localDraftFailed = false;
      } catch (error) {
        if (!_disposed && request.isCurrent()) {
          // DraftStore reports the original storage exception before wrapping
          // it. Reporting that wrapper here would both duplicate the failure
          // and risk retaining a nested cause supplied by another backend.

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
        _draftStatus = _draftConflict ? DraftStatus.failing : DraftStatus.saved;
      }
    } catch (error) {
      if (!_disposed &&
          settlement == _draftSettlement &&
          error is WriteException &&
          error.failure == WriteFailure.conflict) {
        draftSaveConflicted();
      }
      _draftFailures++;
      // No immediate retry: the next keystroke reschedules, which throttles
      // this to the speed someone types rather than the speed of a loop.
      if (_draftFailures >= maxDraftFailures) _draftsGaveUp = true;
      if (!_disposed && request.isCurrent()) {
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
        localOnly: draftsGaveUp,
        isCurrent: () => pending.revision == _draftRevision,
      );

  /// Points the reply at another post. The draft records the reply target,
  /// so once the composer holds a draft the change advances the draft
  /// revision and schedules a save like any other draft field; a draft being
  /// restored passes [recordDraft] false, since the target is the draft's own.
  void retarget({
    int? replyToPostNumber,
    String? replyToUsername,
    bool replyingToWhisper = false,
    bool recordDraft = true,
  }) {
    // A submit already out was built from the target as it stood; the reply
    // it will create must not change underneath it.
    if (_disposed || _discarding || state == ComposerState.submitting) return;
    final target = _target;
    if (target is! ReplyComposerTarget) return;
    final next = target.replyingTo(
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
    // Before anything is typed or restored there is no draft to record the
    // target in: the first save carries it. Saving the empty composer instead
    // would put an empty reply over the copy a restore is still reading, and
    // a restore takes any revision change for an edit that outranks it.
    if (recordDraft && !_untouched) {
      _draftRevision++;
      _scheduleDraft();
    }
    _notify();
  }

  void beginSubmit({Object? attempt}) {
    if (_disposed) return;
    _submissionState = _ComposerPreparing(attempt ?? Object());
    _clearTagRemovalNotice();
    _error = null;
    _notice = null;
    _notify();
  }

  void failed(WriteException error) {
    if (_disposed) return;
    _retireSubmission();
    _error = error;
    if (error.failure == WriteFailure.rateLimited) _holdFor(error.retryAfter);
    _notify();
  }

  void checking() {
    if (_disposed) return;
    final current = _submissionState;
    if (current is! _ComposerSentState) return;
    _submissionState = _ComposerChecking(current.sent);
    _error = null;
    _notice = appL10n.checkingWhetherThatPosted;
    _notify();
  }

  void checkedNotPosted(WriteException error) {
    if (_disposed) return;
    _retireSubmission();
    _notice = null;
    _error = error;
    _notify();
  }

  void unresolved() {
    if (_disposed) return;
    final current = _submissionState;
    if (current is! _ComposerSentState) return;
    _submissionState = _ComposerUnresolved(current.sent);
    _error = null;
    _notice = appL10n.thatMayHavePostedTheSiteCouldNotBeReachedTo;
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
    _retireSubmission();
    _clearTagRemovalNotice();
    draftSettled();
    _error = null;
    _notice = message ?? appL10n.yourReplyWasSentForReviewSoItIsNotPosted;
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

  /// Empties the document in place for the next message.
  ///
  /// Unlike a document replacement, this keeps [fieldGeneration]: the mounted
  /// field and its native input session survive, so a focused composer keeps
  /// its keyboard. A remount would close the session and iOS would start
  /// dismissing the keyboard before focus could reopen it. Undo already lives
  /// in [history], which the replacement resets.
  void clearDocument() {
    if (_disposed) return;
    _retireSubmission();
    _clearTagRemovalNotice();
    draftSettled();
    _error = null;
    _notice = null;
    // A valid caret, as TextEditingController.clear leaves it: the live input
    // session keeps typing into this value without a focus change to place it.
    _replaceDocument(
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    _uploadTransactions.clear();
    _recomputeCanSubmit();
    _typing.reset();
    _openedAt = _now();
    _notify();
  }

  void replacePluginDocument({
    required String raw,
    required Iterable<ComposerUploadResult> uploads,
  }) {
    if (_disposed || _pluginTarget?.policy.supportsEditing != true) return;
    _clearTagRemovalNotice();
    draftSettled();
    _retireSubmission();
    _error = null;
    _notice = null;
    _uploadTransactions.replaceCompleted(uploads);
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
    _appliedTopicTemplate = null;
    autocomplete.close();
    _replacingDocument = true;
    try {
      text.value = value;
    } finally {
      _replacingDocument = false;
    }
    if (_ownsHistory) history.reset();
    blocks.reset();
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
    final wasDraftPending = draftPending;
    final couldSubmit = _canSubmit;
    final before = _lastText;
    _lastText = text.text;
    _uploadTransactions.documentChanged(before, text.text);
    _draftRevision++;
    if (_discardPreview != null && !_replacingDocument) clearDiscardPreview();

    if (!_replacingDocument) {
      _typing.tick();
      _scheduleDraft();
    }

    // Update the send button and save status when they change, without
    // rebuilding the panel for every keystroke during the debounce window.
    _recomputeCanSubmit();
    if (_canSubmit == couldSubmit && draftPending != wasDraftPending) {
      _notify();
    }
  }

  /// Moves [offset], measured against [measuredAgainst], to the same place in
  /// the current text, as a pending upload's anchor would have moved.
  ///
  /// An insertion point captured before an asynchronous platform read must be
  /// rebased before use: an earlier upload finishing meanwhile rewrites its
  /// placeholder, and the raw offset would then split that upload's Markdown.
  int rebaseOffset(String measuredAgainst, int offset) =>
      _TextEdit.between(measuredAgainst, text.text).move(offset);

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
    final next = switch (_target) {
      ReplyComposerTarget() => raw.isNotEmpty,
      NewTopicComposerTarget() =>
        raw.isNotEmpty &&
            title.text.trim().isNotEmpty &&
            taxonomyValidationMessage == null,
      PrivateMessageComposerTarget(:final targetRecipients) =>
        raw.isNotEmpty &&
            title.text.trim().isNotEmpty &&
            targetRecipients.trim().isNotEmpty,
      PostEditComposerTarget() => raw.isNotEmpty && _bodyEdited,
      TopicEditComposerTarget() =>
        title.text.trim().isNotEmpty &&
            taxonomyValidationMessage == null &&
            (metadataChanged || (raw.isNotEmpty && _bodyEdited)),
      CategoryEditComposerTarget() =>
        taxonomyValidationMessage == null && metadataChanged,
      TagsEditComposerTarget() =>
        taxonomyValidationMessage == null && !listEquals(_tags, _originalTags),
      PluginComposerTarget(:final policy) => policy.validate(
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

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _retireSubmission();
    _disposed = true;
    _clearTagRemovalNotice();
    _uploadTransactions.dispose();
    _wait?.cancel();
    _draftTimer?.cancel();
    text.removeListener(_onTextChanged);
    title.removeListener(_onMetadataChanged);
    blocks.dispose();
    if (_ownsHistory) history.dispose();
    text.dispose();
    title.dispose();
    autocomplete.dispose();
    focus.removeListener(_activateMainEditor);
    focus.dispose();
    titleFocus.dispose();
    super.dispose();
  }
}

final class _ComposerUploadEditor {
  _ComposerUploadEditor(this._composer);

  final ComposerController _composer;

  MarkdownEditingController get text => _composer.text;
  bool get isEditing => _composer.isEditing;
  bool get isDisposed => _composer._disposed;
  bool get usesInlineSlots => !_composer.isPluginTarget;
  bool get autoGridEnabled => _composer.enableAutoGridImages;
  ComposerUploadDisposition get disposition =>
      _composer._pluginTarget?.policy.uploadDisposition ??
      ComposerUploadDisposition.insertMarkdown;

  ComposerImageGalleryBlock? galleryAt(int offset) =>
      _composer._galleryAtContentOffset(offset);

  ComposerImageGalleryBlock? resolveGallery(
    ComposerImageGalleryBlock captured, {
    int? anchor,
  }) => _composer._resolveGalleryIdentity(captured, anchor: anchor);

  void amendHistory(VoidCallback change) => _composer.history.amend(change);
  void showNotice(String message) => _composer.showNotice(message);

  void changed({bool affectsSubmission = false}) {
    if (affectsSubmission) _composer._recomputeCanSubmit();
    _composer._notify();
  }
}

bool _sameComposerGallery(
  ComposerImageGalleryBlock left,
  ComposerImageGalleryBlock right,
) =>
    left.start == right.start &&
    left.end == right.end &&
    left.source == right.source;

/// The one span two texts differ in, bounded by their common prefix and
/// suffix. An offset before the span stays, one after it shifts by the length
/// change, and one inside it moves to the end of the replacement, so a moved
/// offset never lands inside text the edit introduced.
class _TextEdit {
  factory _TextEdit.between(String before, String after) {
    var prefix = 0;
    final shared = before.length < after.length ? before.length : after.length;
    while (prefix < shared &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before.codeUnitAt(before.length - suffix - 1) ==
            after.codeUnitAt(after.length - suffix - 1)) {
      suffix++;
    }
    return _TextEdit._(prefix, before.length - suffix, after.length - suffix);
  }

  const _TextEdit._(this.start, this.oldEnd, this.newEnd);

  final int start;
  final int oldEnd;
  final int newEnd;

  int move(int offset) => offset < start
      ? offset
      : offset > oldEnd
      ? offset + newEnd - oldEnd
      : newEnd;
}

class _ComposerTextReplacement {
  const _ComposerTextReplacement(this.start, this.end, this.replacement);

  final int start;
  final int end;
  final String replacement;
}
