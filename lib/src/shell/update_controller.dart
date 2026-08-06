import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../data/app_release.dart';
import '../data/update_store.dart';
import '../data/updater.dart';

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
///  - `ShellController._notify()` rebuilds every one of its scope's dependents:
///    the rail, the sidebar, the main content, the topic list. A download
///    progress tick has no business rebuilding any of them.
///  - None of this is shell state. Everything on [ShellController] is per-site
///    or per-navigation; this is the first thing that is fully meaningful with
///    zero sites connected, which is exactly the case the rail has to handle.
///  - A staged download has to survive `selectInstance` and `removeInstance`,
///    neither of which should be able to see it, let alone reset it.
///
/// Widgets subscribe with a `ListenableBuilder` at the one place that needs it,
/// the way [ComposerPanel] does.
class UpdateController extends ChangeNotifier {
  UpdateController({required this.updater, required this.store});

  final Updater updater;
  final UpdateStore store;

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

  bool _disposed = false;
  bool _notifyScheduled = false;

  /// Reads the stored channel and, if nobody has looked in a while, looks.
  Future<void> load() async {
    if (!isSupported) return;

    _channel = await store.readChannel() ?? AppRelease.defaultChannel;
    _lastChecked = await store.readLastChecked();
    _notify();

    final last = _lastChecked;
    if (last == null || DateTime.now().difference(last) >= _recheckAfter) {
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
    if (!isSupported) return;
    // A second check while one is running would race the first's result into
    // the same fields. Same guard as connectCurrentInstance.
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing) {
      return;
    }

    final previous = _status;
    _status = UpdateStatus.checking;
    if (!silent) _error = null;
    _notify();

    try {
      final release = await updater.check(channel: _channel);

      _lastChecked = DateTime.now();
      unawaited(store.writeLastChecked(_lastChecked!));

      _available = release;
      _status = release == null ? UpdateStatus.upToDate : UpdateStatus.available;
    } on UpdateException catch (e) {
      if (silent) {
        // Put back whatever was on screen before, so a failed background check
        // cannot clear a release the user has already been offered.
        _status = previous;
      } else {
        _error = e.message;
        _status = UpdateStatus.failed;
      }
    } finally {
      _notify();
    }
  }

  /// Fetches and verifies the release already found, leaving it staged.
  Future<void> download() async {
    final release = _available;
    if (release == null || _status == UpdateStatus.downloading) return;

    _status = UpdateStatus.downloading;
    _progress = 0;
    _error = null;
    _notify();

    try {
      await updater.download(release, onProgress: _onProgress);
      _status = UpdateStatus.readyToInstall;
      _progress = 1;
    } on UpdateException catch (e) {
      _error = e.message;
      // Back to `available`, not `failed`: the release is still on offer and
      // the button to try again is the same button.
      _status = UpdateStatus.available;
      _progress = 0;
    } finally {
      _notify();
    }
  }

  /// Hands the app over to the updater. On success this never returns.
  Future<void> installAndRestart() async {
    if (_status != UpdateStatus.readyToInstall) return;

    _status = UpdateStatus.installing;
    _error = null;
    _notify();

    try {
      await updater.installAndRestart();
    } on UpdateException catch (e) {
      _error = e.message;
      // The download is still staged and still good, so offer the restart
      // again rather than making the user fetch it a second time.
      _status = UpdateStatus.readyToInstall;
      _notify();
    }
  }

  /// Moves to another channel and immediately asks what is on it.
  ///
  /// Discarding first is the point: a canary build downloaded a minute ago must
  /// not stay installable for someone who has since asked for stable.
  Future<void> setChannel(UpdateChannel channel) async {
    if (channel == _channel) return;
    if (_status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing) {
      return;
    }

    _channel = channel;
    _available = null;
    _progress = 0;
    _error = null;
    _status = UpdateStatus.idle;
    _notify();

    await store.writeChannel(channel);
    try {
      await updater.discard();
    } on UpdateException {
      // Nothing staged, or it could not be removed. Neither is worth telling
      // the user about, and the check below is what they are waiting on.
    }

    await check();
  }

  /// Whole percent only. A download reports far more often than that, and a
  /// rebuild per byte is not worth the fidelity nobody can see.
  void _onProgress(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    if ((clamped * 100).round() == (_progress * 100).round()) return;
    _progress = clamped;
    _notify();
  }

  /// The deferral is copied from [ShellController._notify], for the reason
  /// given at length there: a notification raised inside the build phase has to
  /// wait for the end of the frame. Copied rather than lifted into a shared
  /// base class, because that is a change to a two-thousand-line file for the
  /// benefit of two call sites.
  void _notify() {
    if (_disposed) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
      return;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
