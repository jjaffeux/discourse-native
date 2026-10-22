import 'dart:async';

import '../data/app_release.dart';
import '../data/update_store.dart';
import '../data/updater.dart';

import '../foundation/frame_safe_notifier.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  installing,
  failed,
}

class UpdateController extends FrameSafeNotifier {
  UpdateController({required this.updater, required this.store});

  final Updater updater;
  final UpdateStore store;

  static const Duration _recheckAfter = Duration(hours: 24);

  bool get isSupported => updater.isSupported;

  String get runningVersion => AppRelease.version;

  _UpdateState _state = const _UpdateIdle();
  UpdateStatus get status => _state.status;

  UpdateChannel _channel = AppRelease.defaultChannel;
  UpdateChannel get channel => _channel;

  UpdateRelease? get available => _state.release;
  double get progress => _state.progress;
  String? get error => _state.error;

  DateTime? _lastChecked;
  DateTime? get lastChecked => _lastChecked;

  int _revision = 0;
  UpdateChannel? _queuedChannel;
  Future<void>? _channelChangeTask;

  Future<void> load() async {
    if (isDisposed || !isSupported) return;

    var revision = _revision;
    final UpdateChannel? storedChannel;
    final DateTime? storedLastChecked;
    try {
      storedChannel = await store.readChannel();
      storedLastChecked = await store.readLastChecked();
    } catch (error) {
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
      if (status == UpdateStatus.installing) return;
      mustCheckHydratedChannel = status != UpdateStatus.idle;
      _resetForChannel(channel);
      revision = _revision;
      await _discardForChannelChange();
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

  Future<void> check({bool silent = false}) async {
    if (isDisposed || !isSupported) return;
    // A second check while one is running would race the first's result into
    // the same fields. Same guard as connectCurrentInstance.
    if (status == UpdateStatus.checking ||
        status == UpdateStatus.downloading ||
        status == UpdateStatus.installing) {
      return;
    }

    final operation = _UpdateCheck(_revision, _state, silent: silent);
    final channel = _channel;
    _state = _UpdateChecking(operation);
    notifySafely();
    if (!_owns(operation)) return;

    try {
      final release = await updater.check(channel: channel);
      if (!_owns(operation)) return;

      _lastChecked = DateTime.now();
      store.writeLastChecked(_lastChecked!).ignore();

      _settle(operation, _UpdateChecked(operation, release));
    } catch (error, stackTrace) {
      if (!_owns(operation)) return;
      final e = _asUpdateException(
        error,
        stackTrace,
        UpdateFailure.unreachable,
      );
      _settle(
        operation,
        silent ? operation.previous : _UpdateCheckFailed(operation, e.message),
      );
    }
  }

  Future<void> download() async {
    if (isDisposed) return;
    final release = available;
    if (release == null || status == UpdateStatus.downloading) return;

    final operation = _UpdateTransfer(_revision, release);
    _state = _UpdateDownloading(operation);
    notifySafely();
    if (!_owns(operation)) return;

    try {
      await updater.download(
        release,
        onProgress: (fraction) {
          if (_owns(operation)) {
            _onProgress(operation, fraction);
          }
        },
      );
      _settle(operation, _UpdateStaged(operation.release));
    } catch (error, stackTrace) {
      if (!_owns(operation)) return;
      final e = _asUpdateException(
        error,
        stackTrace,
        UpdateFailure.unreachable,
      );
      _settle(operation, _UpdateOffered(operation.release, e.message));
    }
  }

  Future<void> installAndRestart() async {
    if (isDisposed) return;
    final staged = _state;
    if (staged is! _UpdateStaged) return;

    final operation = _UpdateTransfer(_revision, staged.release);
    _state = _UpdateInstalling(operation);
    notifySafely();
    if (!_owns(operation)) return;

    try {
      await updater.installAndRestart();
    } catch (error, stackTrace) {
      if (!_owns(operation)) return;
      final e = _asUpdateException(error, stackTrace, UpdateFailure.install);
      _settle(operation, _UpdateStaged(operation.release, error: e.message));
    }
  }

  Future<void> setChannel(UpdateChannel channel) {
    if (isDisposed) return Future<void>.value();
    if (channel == _channel) {
      return _channelChangeTask ?? Future<void>.value();
    }
    if (status == UpdateStatus.downloading ||
        status == UpdateStatus.installing) {
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
        } catch (_) {
          // Keep the session's selection useful even when preferences are
          // temporarily unavailable. A later channel change can persist it.
        }
        if (!_isCurrent(revision) || _queuedChannel != null) continue;

        await _discardForChannelChange();
        if (!_isCurrent(revision) || _queuedChannel != null) continue;

        await check();
      }
    } finally {
      _channelChangeTask = null;
    }
  }

  Future<void> _discardForChannelChange() async {
    try {
      await updater.discard();
    } catch (_) {
      // Nothing staged, or it could not be removed. Neither is worth telling
      // the user about; the check which follows is the useful outcome.
    }
  }

  /// The adapter's contract is `UpdateException`, but a platform can still
  /// throw anything out of socket, file or process I/O. Whatever it throws
  /// must not strand the status the caller just set: `checking`,
  /// `downloading` and `installing` gate every later update action.
  static UpdateException _asUpdateException(
    Object error,
    StackTrace stackTrace,
    UpdateFailure fallback,
  ) => error is UpdateException
      ? error
      : UpdateException.caused(fallback, null, error, stackTrace);

  void _resetForChannel(UpdateChannel channel) {
    _revision++;
    _channel = channel;
    _state = const _UpdateIdle();
  }

  void _onProgress(_UpdateTransfer operation, double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    if ((clamped * 100).round() == (progress * 100).round()) return;
    _state = _UpdateDownloading(operation, progress: clamped);
    notifySafely();
  }

  void _settle(_UpdateOperation operation, _UpdateState next) {
    if (!_owns(operation)) return;
    _state = next;
    notifySafely();
  }

  bool _owns(_UpdateOperation operation) =>
      _isCurrent(operation.revision) && identical(_state.operation, operation);

  bool _isCurrent(int revision) => !isDisposed && revision == _revision;

  @override
  void dispose() {
    _revision++;
    // An updater session may still have a check or download in flight. Discard
    // is its cancellation/close boundary; the controller's revision suppresses
    // the resulting late completion.
    try {
      unawaited(
        updater.discard().onError((Object error, StackTrace stackTrace) {}),
      );
    } catch (_) {
      // Disposal must still finish if an adapter fails before returning its
      // Future. There is no live controller left to surface the failure on.
    }
    super.dispose();
  }
}

sealed class _UpdateOperation {
  const _UpdateOperation(this.revision);

  final int revision;
}

final class _UpdateCheck extends _UpdateOperation {
  const _UpdateCheck(super.revision, this.previous, {required this.silent});

  final _UpdateState previous;
  final bool silent;
}

final class _UpdateTransfer extends _UpdateOperation {
  const _UpdateTransfer(super.revision, this.release);

  final UpdateRelease release;
}

sealed class _UpdateState {
  const _UpdateState();

  UpdateStatus get status;
  _UpdateOperation? get operation => null;
  UpdateRelease? get release => null;
  double get progress => 0;
  String? get error => null;
}

final class _UpdateIdle extends _UpdateState {
  const _UpdateIdle();

  @override
  UpdateStatus get status => UpdateStatus.idle;
}

final class _UpdateChecking extends _UpdateState {
  const _UpdateChecking(this.operation);

  @override
  final _UpdateCheck operation;
  @override
  UpdateStatus get status => UpdateStatus.checking;
  @override
  UpdateRelease? get release => operation.previous.release;
  @override
  double get progress => operation.previous.progress;
  @override
  String? get error => operation.silent ? operation.previous.error : null;
}

final class _UpdateChecked extends _UpdateState {
  _UpdateChecked(_UpdateCheck operation, this.release)
    : progress = operation.previous.progress,
      error = operation.silent ? operation.previous.error : null;

  @override
  final UpdateRelease? release;
  @override
  final double progress;
  @override
  final String? error;
  @override
  UpdateStatus get status =>
      release == null ? UpdateStatus.upToDate : UpdateStatus.available;
}

final class _UpdateCheckFailed extends _UpdateState {
  _UpdateCheckFailed(_UpdateCheck operation, this.error)
    : release = operation.previous.release,
      progress = operation.previous.progress;

  @override
  final UpdateRelease? release;
  @override
  final double progress;
  @override
  final String error;
  @override
  UpdateStatus get status => UpdateStatus.failed;
}

sealed class _UpdateTransferState extends _UpdateState {
  const _UpdateTransferState(this.operation);

  @override
  final _UpdateTransfer operation;
  @override
  UpdateRelease get release => operation.release;
}

final class _UpdateDownloading extends _UpdateTransferState {
  const _UpdateDownloading(super.operation, {this.progress = 0});

  @override
  final double progress;
  @override
  UpdateStatus get status => UpdateStatus.downloading;
}

final class _UpdateOffered extends _UpdateState {
  const _UpdateOffered(this.release, this.error);

  @override
  final UpdateRelease release;

  @override
  final String error;
  @override
  UpdateStatus get status => UpdateStatus.available;
}

final class _UpdateStaged extends _UpdateState {
  const _UpdateStaged(this.release, {this.error});

  @override
  final UpdateRelease release;

  @override
  final String? error;
  @override
  double get progress => 1;
  @override
  UpdateStatus get status => UpdateStatus.readyToInstall;
}

final class _UpdateInstalling extends _UpdateTransferState {
  const _UpdateInstalling(super.operation);

  @override
  double get progress => 1;
  @override
  UpdateStatus get status => UpdateStatus.installing;
}
