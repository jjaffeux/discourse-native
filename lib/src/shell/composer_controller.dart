import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/composer_draft.dart';
import 'composer_autocomplete.dart';
import 'composer_marks.dart';
import 'composer_pills.dart';
import 'composer_triggers.dart';
import 'markdown_editing_controller.dart';

/// What a composer is writing to.
///
/// Carries its own [siteUrl] rather than reading the current instance when it
/// comes time to submit. Switching sites while a reply is half written must not
/// send it to the site the user switched to, and every other cache in the shell
/// is site-keyed for the same reason.
@immutable
class ComposerTarget {
  const ComposerTarget({
    required this.siteUrl,
    required this.topicId,
    required this.slug,
    required this.topicTitle,
    this.replyToPostNumber,
    this.replyToUsername,
    this.editingPostId,
    this.editingPostNumber,
  });

  final String siteUrl;
  final int topicId;
  final String slug;
  final String topicTitle;

  /// The post being answered, or null when the reply is to the topic itself.
  final int? replyToPostNumber;

  final String? replyToUsername;

  /// The post being rewritten, when this composer is editing rather than
  /// replying. Null for a reply.
  final int? editingPostId;

  /// Its number in the topic, for saying which post is being edited.
  final int? editingPostNumber;

  bool get isEdit => editingPostId != null;

  /// What Discourse files a draft for this topic under.
  String get draftKey => 'topic_$topicId';

  ComposerTarget replyingTo(int? postNumber, String? username) =>
      ComposerTarget(
        siteUrl: siteUrl,
        topicId: topicId,
        slug: slug,
        topicTitle: topicTitle,
        replyToPostNumber: postNumber,
        replyToUsername: username,
      );
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
class ComposerController extends ChangeNotifier {
  ComposerController(
    this._target, {
    this.onSaveDraft,
    ComposerSearch? search,
    String Function(String name)? resolveEmoji,
    ComposerPills? pills,
    DateTime Function()? now,
  }) : text = MarkdownEditingController(
         resolveEmoji: resolveEmoji,
         pills: pills,
       ),
       autocomplete = ComposerAutocomplete(search: search),
       _typing = TypingClock(now: now),
       _now = now ?? DateTime.now,
       _openedAt = (now ?? DateTime.now)() {
    text.addListener(_onTextChanged);
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

  /// What will be posted, and what is typed into.
  ///
  /// A [MarkdownEditingController] only to change how it is *drawn* — the
  /// string is untouched, and every other caller here treats it as the plain
  /// controller it still is.
  final MarkdownEditingController text;

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

  Timer? _wait;
  bool _rateLimited = false;

  /// True while a rate limit is still in force, so sending is held back rather
  /// than earning a second refusal.
  bool get rateLimited => _rateLimited;

  /// Turns [mark] on or off around the selection.
  void toggleMark(ComposerMark mark) {
    if (_disposed) return;
    text.value = toggleMarkdownMark(text.value, mark.marker);
  }

  /// Writes [suggestion] over the trigger that is open.
  ///
  /// Through `text.value` rather than poked into `text.text`, so
  /// [_onTextChanged] fires: the draft timer, the typing clock and `canSubmit`
  /// all hang off that one notification, and a mention inserted around it
  /// would be text the site never hears about. It also keeps the insertion on
  /// the undo stack, which an assignment with no valid selection would not.
  void acceptSuggestion(ComposerSuggestion suggestion) {
    if (_disposed) return;
    final open = autocomplete.trigger;
    if (open == null) return;

    text.value = applyComposerCompletion(text.value, open, suggestion.value);
    autocomplete.close();
  }

  bool _canSubmit = false;

  bool _loadingBody = false;

  /// True while the post being edited is still being fetched.
  ///
  /// The stream carries cooked HTML only, so an edit composer opens empty and
  /// fills in once the markdown arrives.
  bool get loadingBody => _loadingBody;

  String? _originalRaw;

  /// Whether there is anything worth sending. Blank is not a post, and neither
  /// is an edit nobody has changed — the site refuses that anyway.
  ///
  /// An edit has one more way of being not worth sending: the body may not
  /// have arrived yet, and saving then would replace the post with nothing.
  bool get canSubmit =>
      _canSubmit &&
      _state == ComposerState.editing &&
      !_rateLimited &&
      !_loadingBody;

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
  /// disabled: an empty field here would blank the post rather than leave it.
  void bodyLoadFailed() {
    if (_disposed) return;
    _loadingBody = false;
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

  /// This composer's contents, in the shape Discourse stores drafts in.
  ComposerDraft get draft => ComposerDraft(
    reply: text.text,
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
    if (_disposed || text.text.isNotEmpty) return;
    _replaceDocument(
      TextEditingValue(
        text: draft.reply,
        selection: TextSelection.collapsed(offset: draft.reply.length),
      ),
    );
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
    final next = raw.isNotEmpty && raw != _originalRaw;
    if (next == _canSubmit) return;
    _canSubmit = next;
    _notify();
  }

  bool _disposed = false;

  /// A submit outlives the panel — closing the composer while one is in flight
  /// is normal — and ChangeNotifier throws once disposed.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _wait?.cancel();
    _draftTimer?.cancel();
    text.removeListener(_onTextChanged);
    text.dispose();
    autocomplete.dispose();
    focus.dispose();
    super.dispose();
  }
}
