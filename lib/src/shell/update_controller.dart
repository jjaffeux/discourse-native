import 'dart:async';

import '../data/app_release.dart';
import '../data/update_store.dart';
import '../data/updater.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';

enum UpdateStatus {
  /// Nothing has been asked for yet, or the last thing asked for is finished
  /// and left nothing behind.
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  installing,
  failed,
}

/// Everything the update UI reads.
///
/// A separate [ChangeNotifier] owned by [ShellController] as a field, not
/// fields on [ShellController] itself and not a second [InheritedNotifier].
/// This is the [ComposerController] pattern, and it is here for the same
/// reasons, heaviest first:
///
///  - A shell notification makes every selector re-evaluate and wakes any
///    deliberately broad scope subscriber. A download progress tick has no
///    business touching site navigation or content state at all.
///  - None of this is shell state. Everything on [ShellController] is per-site
///    or per-navigation; this is the first thing that is fully meaningful with
///    zero sites connected, which is exactly the case the rail has to handle.
///  - A staged download has to survive `selectInstance` and `removeInstance`,
///    neither of which should be able to see it, let alone reset it.
///
/// Widgets subscribe with a `ListenableBuilder` at the one place that needs it,
/// the way [ComposerPanel] does.
class UpdateController extends FrameSafeNotifier {
  UpdateController({required this.updater, required this.store});

  final Updater updater;
  final UpdateStore store;

  void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    DiagnosticSeverity severity = DiagnosticSeverity.error,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'updater',
      severity: severity,
      handled: true,
      degraded: true,
    );
  }

  /// How stale a check has to be before launch quietly repeats it.
  static const Duration _recheckAfter = Duration(hours: 24);

  bool get isSupported => updater.isSupported;

  /// What is running now, for the sheet to show. Empty in a build the release
  /// pipeline did not produce.
  String get runningVersion => AppRelease.version;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  UpdateChannel _channel = AppRelease.defaultChannel;
  UpdateChannel get channel => _channel;

  UpdateRelease? _available;
  UpdateRelease? get available => _available;

  /// 0..1, only meaningful while [status] is [UpdateStatus.downloading].
  double _progress = 0;
  double get progress => _progress;

  String? _error;
  String? get error => _error;

  DateTime? _lastChecked;
  DateTime? get lastChecked => _lastChecked;

  int _revision = 0;
  UpdateChannel? _queuedChannel;
  Future<void>? _channelChangeTask;

  /// Reads the stored channel and, if nobody has looked in a while, looks.
  Future<void> load() async {
    if (isDisposed || !isSupported) return;

    var revision = _revision;
    final UpdateChannel? storedChannel;
    final DateTime? storedLastChecked;
    try {
      storedChannel = await store.readChannel();
      storedLastChecked = await store.readLastChecked();
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        'updater.loadPreferences',
        severity: DiagnosticSeverity.warning,
      );
      // Update preferences are optional. A later launch or explicit action can
      // retry them without making the shell's startup Future fail.
      return;
    }
    if (!_isCurrent(revision)) return;

    var mustCheckHydratedChannel = false;
    final channel = storedChannel ?? AppRelease.defaultChannel;
    if (channel != _channel) {
      // Preference hydration normally wins before anybody can interact with
      // the updater. If startup I/O is unusually slow, however, a user may
      // already have staged (or started staging) a release on the built-in
      // channel. Invalidate its callbacks first, then make the adapter remove
      // that old-channel artifact before checking the stored channel.
      if (_status == UpdateStatus.installing) return;
      mustCheckHydratedChannel = _status != UpdateStatus.idle;
      _resetForChannel(channel);
      revision = _revision;
      await _discardForChannelChange('updater.discardHydratedChannel');
      if (!_isCurrent(revision)) return;
    }
    _lastChecked = storedLastChecked;
    notifySafely();
    if (!_isCurrent(revision)) return;

    final last = _lastChecked;
    if (mustCheckHydratedChannel ||
        last == null ||
        DateTime.now().difference(last) >= _recheckAfter) {
      await check(silent: true);
    }
  }

  /// Asks the channel what it has.
  ///
  /// A [silent] check is the one nobody asked for — the one on launch. It
  /// leaves no error behind when it fails, because there is no one to tell and
  /// nothing they could do; the rail simply stays quiet. Only a check the user
  /// started gets to put a message on screen.
  Future<void> check({bool silent = false}) async {
    if (isDisposed || !isSupported) return;
    // A second check while one is running would race the first's result into
    // the same fields. Same guard as connectCurrentInstance.
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing) {
      return;
    }

    final previous = _status;
    final revision = _revision;
    final channel = _channel;
    bool checkIsCurrent() => _isCurrent(revision) && channel == _channel;
    _status = UpdateStatus.checking;
    if (!silent) _error = null;
    notifySafely();
    if (!checkIsCurrent()) return;

    try {
      final release = await updater.check(channel: channel);
      if (!checkIsCurrent()) return;

      _lastChecked = DateTime.now();
      store.writeLastChecked(_lastChecked!).ignore();

      _available = release;
      _status = release == null
          ? UpdateStatus.upToDate
          : UpdateStatus.available;
    } on UpdateException catch (e, stackTrace) {
      if (!checkIsCurrent()) return;
      _report(e, stackTrace, 'updater.check');
      if (silent) {
        // Put back whatever was on screen before, so a failed background check
        // cannot clear a release the user has already been offered.
        _status = previous;
      } else {
        _error = e.message;
        _status = UpdateStatus.failed;
      }
    } finally {
      if (checkIsCurrent()) notifySafely();
    }
  }

  /// Fetches and verifies the release already found, leaving it staged.
  Future<void> download() async {
    if (isDisposed) return;
    final release = _available;
    if (release == null || _status == UpdateStatus.downloading) return;

    _status = UpdateStatus.downloading;
    _progress = 0;
    _error = null;
    notifySafely();
    final revision = _revision;
    if (!_isCurrent(revision)) return;

    try {
      await updater.download(
        release,
        onProgress: (fraction) {
          if (_isCurrent(revision)) _onProgress(fraction);
        },
      );
      if (!_isCurrent(revision)) return;
      _status = UpdateStatus.readyToInstall;
      _progress = 1;
    } on UpdateException catch (e, stackTrace) {
      if (!_isCurrent(revision)) return;
      _report(e, stackTrace, 'updater.download');
      _error = e.message;
      // Back to `available`, not `failed`: the release is still on offer and
      // the button to try again is the same button.
      _status = UpdateStatus.available;
      _progress = 0;
    } finally {
      if (_isCurrent(revision)) notifySafely();
    }
  }

  /// Hands the app over to the updater. On success this never returns.
  Future<void> installAndRestart() async {
    if (isDisposed || _status != UpdateStatus.readyToInstall) return;

    _status = UpdateStatus.installing;
    _error = null;
    notifySafely();
    final revision = _revision;
    if (!_isCurrent(revision)) return;

    try {
      await updater.installAndRestart();
    } on UpdateException catch (e, stackTrace) {
      if (!_isCurrent(revision)) return;
      _report(e, stackTrace, 'updater.install');
      _error = e.message;
      // The download is still staged and still good, so offer the restart
      // again rather than making the user fetch it a second time.
      _status = UpdateStatus.readyToInstall;
      notifySafely();
    }
  }

  /// Moves to another channel and immediately asks what is on it.
  ///
  /// Discarding first is the point: a canary build downloaded a minute ago must
  /// not stay installable for someone who has since asked for stable.
  Future<void> setChannel(UpdateChannel channel) {
    if (isDisposed) return Future<void>.value();
    if (channel == _channel) {
      return _channelChangeTask ?? Future<void>.value();
    }
    if (_status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing) {
      return Future<void>.value();
    }

    _queuedChannel = channel;
    _resetForChannel(channel);
    notifySafely();

    return _channelChangeTask ??= _drainChannelChanges();
  }

  Future<void> _drainChannelChanges() async {
    try {
      while (true) {
        final channel = _queuedChannel;
        if (channel == null) break;
        _queuedChannel = null;
        final revision = _revision;

        try {
          await store.writeChannel(channel);
        } catch (error, stackTrace) {
          _report(
            error,
            stackTrace,
            'updater.persistChannel',
            severity: DiagnosticSeverity.warning,
          );
          // Keep the session's selection useful even when preferences are
          // temporarily unavailable. A later channel change can persist it.
        }
        if (!_isCurrent(revision) || _queuedChannel != null) continue;

        await _discardForChannelChange('updater.discard');
        if (!_isCurrent(revision) || _queuedChannel != null) continue;

        await check();
      }
    } finally {
      _channelChangeTask = null;
    }
  }

  Future<void> _discardForChannelChange(String operation) async {
    try {
      await updater.discard();
    } on UpdateException catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        operation,
        severity: DiagnosticSeverity.warning,
      );
      // Nothing staged, or it could not be removed. Neither is worth telling
      // the user about; the check which follows is the useful outcome.
    }
  }

  void _resetForChannel(UpdateChannel channel) {
    _revision++;
    _channel = channel;
    _available = null;
    _progress = 0;
    _error = null;
    _status = UpdateStatus.idle;
  }

  /// Whole percent only. A download reports far more often than that, and a
  /// rebuild per byte is not worth the fidelity nobody can see.
  void _onProgress(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    if ((clamped * 100).round() == (_progress * 100).round()) return;
    _progress = clamped;
    notifySafely();
  }

  bool _isCurrent(int revision) => !isDisposed && revision == _revision;

  @override
  void dispose() {
    _revision++;
    // An updater session may still have a check or download in flight. Discard
    // is its cancellation/close boundary; the controller's revision suppresses
    // the resulting late completion.
    try {
      unawaited(
        updater.discard().onError((Object error, StackTrace stackTrace) {
          _report(
            error,
            stackTrace,
            'updater.dispose',
            severity: DiagnosticSeverity.warning,
          );
        }),
      );
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        'updater.dispose',
        severity: DiagnosticSeverity.warning,
      );
      // Disposal must still finish if an adapter fails before returning its
      // Future. There is no live controller left to surface the failure on.
    }
    super.dispose();
  }
}
