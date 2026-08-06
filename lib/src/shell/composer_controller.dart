import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/discourse_api.dart';
import '../models/composer_draft.dart';

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
  });

  final String siteUrl;
  final int topicId;
  final String slug;
  final String topicTitle;

  /// The post being answered, or null when the reply is to the topic itself.
  final int? replyToPostNumber;

  final String? replyToUsername;

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
  ComposerController(this._target, {this.onSaveDraft, DateTime Function()? now})
    : _typing = TypingClock(now: now),
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

  /// Persists the draft. Supplied by the shell, which owns the site and the
  /// key; the composer only decides *when*.
  final Future<void> Function(ComposerController composer)? onSaveDraft;

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();

  final TypingClock _typing;
  final DateTime Function() _now;
  final DateTime _openedAt;

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

  bool _canSubmit = false;

  /// Whether there is anything worth sending. Blank is not a post.
  bool get canSubmit =>
      _canSubmit && _state == ComposerState.editing && !_rateLimited;

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

  DraftStatus _draftStatus = DraftStatus.clean;
  DraftStatus get draftStatus => _draftStatus;

  /// True once the sync has stopped trying, so the panel can say the site does
  /// not have this yet.
  bool get draftsGaveUp => _draftsGaveUp;

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
    text.value = TextEditingValue(
      text: draft.reply,
      selection: TextSelection.collapsed(offset: draft.reply.length),
    );
    // Restoring is not typing, so it must not schedule a save of text the site
    // already has.
    _draftTimer?.cancel();
    _draftStatus = DraftStatus.clean;
    _notify();
  }

  /// Marks the draft as no longer this composer's problem — the post landed,
  /// and Discourse deletes the draft itself when it accepts one.
  void draftSettled() {
    _draftTimer?.cancel();
    _draftStatus = DraftStatus.clean;
  }

  void _scheduleDraft() {
    if (onSaveDraft == null || _draftsGaveUp || _disposed) return;
    _draftTimer?.cancel();

    final last = _lastDraftSaveAt;
    if (last != null && _now().difference(last) >= draftMaxWait) {
      unawaited(_saveDraft());
      return;
    }
    _draftTimer = Timer(draftDebounce, () => unawaited(_saveDraft()));
  }

  Future<void> _saveDraft() async {
    final save = onSaveDraft;
    if (_disposed || save == null || _draftsGaveUp) return;

    _draftTimer?.cancel();
    _lastDraftSaveAt = _now();
    _draftStatus = DraftStatus.saving;
    _notify();

    try {
      await save(this);
      if (_disposed) return;
      _draftFailures = 0;
      _draftStatus = DraftStatus.saved;
    } catch (_) {
      if (_disposed) return;
      _draftFailures++;
      // No immediate retry: the next keystroke reschedules, which throttles
      // this to the speed someone types rather than the speed of a loop.
      if (_draftFailures >= maxDraftFailures) _draftsGaveUp = true;
      _draftStatus = DraftStatus.failing;
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
  void enqueued(String? message) {
    if (_disposed) return;
    draftSettled();
    _state = ComposerState.editing;
    _error = null;
    _notice =
        message ?? 'Your reply was sent for review, so it is not posted yet.';
    text.clear();
    _notify();
  }

  void _onTextChanged() {
    _typing.tick();
    _scheduleDraft();

    // Only the send button depends on this, so notifying per keystroke would
    // rebuild the panel for nothing.
    final next = text.text.trim().isNotEmpty;
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
    focus.dispose();
    super.dispose();
  }
}
