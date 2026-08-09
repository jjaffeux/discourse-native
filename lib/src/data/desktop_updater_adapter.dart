import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_updater/desktop_updater.dart' as du;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/diagnostics_redactor.dart';
import '../foundation/private_file_permissions.dart';
import 'app_release.dart';
import 'updater.dart';

typedef DesktopUpdateSessionFactory =
    Future<DesktopUpdateSession> Function(UpdateChannel channel);

/// The part of `DesktopUpdaterController` this adapter depends on.
abstract interface class DesktopUpdateSession {
  du.UpdateState get state;

  Future<du.ManualUpdateCheckResult> checkForUpdates();

  Future<void> downloadUpdate();

  Future<void> restartApp();

  void addListener(VoidCallback listener);

  void removeListener(VoidCallback listener);

  void dispose();
}

/// [Updater] backed by `package:desktop_updater`.
///
/// The only file in this repository that may import it. Everything the library
/// exposes — a channel fixed at construction, progress as a state subtype
/// rather than a callback, failures as states rather than throws, and two
/// persistence interfaces of its own — stops here and is translated into the
/// vocabulary in [updater.dart].
///
/// This is also the only file in `lib/` that touches `dart:io`, which is
/// otherwise deliberately absent. The library's recovery store has to be
/// durable across a process replacement, so it cannot live anywhere else.
class DesktopUpdaterAdapter implements Updater {
  DesktopUpdaterAdapter({DesktopUpdateSessionFactory? createSession})
    : _createSession = createSession ?? _createDefaultSession;

  final DesktopUpdateSessionFactory _createSession;

  /// Which platforms this can install on, independent of whether *this* build
  /// is one it should.
  ///
  /// Separated so it can be tested for every platform without a
  /// release-stamped binary to run it in.
  ///
  /// Linux only. iOS is out by App Store rule and Android has no bundle to
  /// swap. Windows is untried. macOS would replace a signed bundle with an
  /// unsigned copy, changing the code signature that the keychain ACL is bound
  /// to — see [SecureStore] for what a keychain that stops answering looks
  /// like — so it waits for a real Developer ID certificate.
  static bool supportsPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.linux;

  @override
  bool get isSupported =>
      !kIsWeb &&
      supportsPlatform(defaultTargetPlatform) &&
      AppRelease.isReleaseBuild &&
      AppRelease.canVerifyReleases;

  _ManagedSession? _inner;
  _PendingSession? _pending;

  Future<_ManagedSession> _controllerFor(UpdateChannel channel) {
    final existing = _inner;
    if (existing != null && existing.channel == channel) {
      return Future.value(existing);
    }

    final pending = _pending;
    if (pending != null && pending.channel == channel) return pending.result;

    pending?.cancel();
    _pending = null;
    _cancelInner();

    final replacement = _PendingSession(channel);
    _pending = replacement;
    replacement.result = _openSession(replacement);
    return replacement.result;
  }

  Future<_ManagedSession> _openSession(_PendingSession pending) async {
    try {
      final creation = _createSession(
        pending.channel,
      ).then((controller) => _ManagedSession(pending.channel, controller));
      unawaited(
        creation
            .then<void>((session) {
              if (pending.isCancelled) session.cancel();
            })
            .catchError((_) {}),
      );

      final session = await Future.any([
        creation,
        pending.cancelled.then<_ManagedSession>(
          (_) => throw _discardedException,
        ),
      ]);
      if (pending.isCancelled) {
        session.cancel();
        throw _discardedException;
      }

      _inner = session;
      return session;
    } on UpdateException {
      rethrow;
    } catch (error, stackTrace) {
      throw _translate(error, stackTrace: stackTrace);
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  static Future<DesktopUpdateSession> _createDefaultSession(
    UpdateChannel channel,
  ) async {
    final support = await getApplicationSupportDirectory();
    return _PluginSession(
      du.DesktopUpdaterController(
        appArchiveUrl: Uri.parse(AppRelease.archiveUrlFor(channel)),
        expectedPackageId: _packageId,
        channel: channel.name,
        trustedReleasePublicKeys: AppRelease.trustedReleaseKeys,
        recoveryStore: FileUpdateRecoveryStore(
          File('${support.path}/pending-update.json'),
        ),
        skipInitialVersionCheck: true,
      ),
    );
  }

  /// Must match APPLICATION_ID in linux/CMakeLists.txt: the library refuses a
  /// descriptor published under a different package id, which is what stops a
  /// feed for some other app from installing over this one.
  static const String _packageId = 'org.discourse.native';

  @override
  Future<UpdateRelease?> check({required UpdateChannel channel}) async {
    final session = await _controllerFor(channel);

    final du.ManualUpdateCheckResult result;
    try {
      result = await _untilCancelled(
        session,
        session.controller.checkForUpdates(),
      );
    } on UpdateException {
      rethrow;
    } catch (e, stackTrace) {
      throw _translate(e, stackTrace: stackTrace);
    }

    return switch (result) {
      du.ManualUpdateCheckUpToDate() => null,
      du.ManualUpdateCheckAvailable(:final descriptor) => _release(
        descriptor,
        channel,
      ),
      // Both mean "there is something newer, but this install cannot take it
      // in place" — a fresh download, or a version too old for the policy. The
      // sheet's failure state sends the user to the releases page, which is
      // the only thing that actually helps here.
      du.ManualUpdateCheckFreshInstallRequired() => throw const UpdateException(
        UpdateFailure.install,
        'ManualUpdateCheckFreshInstallRequired',
      ),
      du.ManualUpdateCheckBlockedBySupportPolicy() =>
        throw const UpdateException(
          UpdateFailure.install,
          'ManualUpdateCheckBlockedBySupportPolicy',
        ),
      du.ManualUpdateCheckFailed(:final error, :final stackTrace) =>
        throw _translate(error, stackTrace: stackTrace),
    };
  }

  @override
  Future<void> download(
    UpdateRelease release, {
    void Function(double fraction)? onProgress,
  }) async {
    final session = await _controllerFor(release.channel);
    final controller = session.controller;
    final done = Completer<void>();
    UpdateException? terminalError;

    /// Completes [done] when the state is terminal, reports progress while it
    /// is not. Run on every notification and once by hand after the download
    /// is handed off: a controller already in a terminal state — a release
    /// staged by an earlier, interrupted run — may never notify again, and
    /// waiting on a notification that will not come would wait forever.
    void observe() {
      switch (controller.state) {
        case du.UpdateDownloading(:final receivedBytes, :final totalBytes):
          if (totalBytes > 0) {
            onProgress?.call((receivedBytes / totalBytes).clamp(0.0, 1.0));
          }
        case du.UpdateReadyToInstall():
          if (!done.isCompleted) done.complete();
        case du.UpdateFailed(:final error):
          if (!done.isCompleted) {
            terminalError = _translate(error, stackTrace: StackTrace.current);
            done.complete();
          }
        default:
          break;
      }
    }

    controller.addListener(observe);
    try {
      await _untilCancelled(session, controller.downloadUpdate());
      // downloadUpdate returns when it has handed off, not necessarily when
      // the artifact is staged, so the terminal state is what we wait on —
      // reading it once first in case it is terminal already.
      observe();
      await _untilCancelled(session, done.future);
      if (terminalError case final error?) throw error;
    } on UpdateException {
      rethrow;
    } catch (e, stackTrace) {
      throw _translate(e, stackTrace: stackTrace);
    } finally {
      controller.removeListener(observe);
    }
  }

  @override
  Future<void> installAndRestart() async {
    final session = _inner;
    if (session == null) {
      throw const UpdateException(UpdateFailure.install, 'nothing staged');
    }

    try {
      await _untilCancelled(session, session.controller.restartApp());
    } on UpdateException {
      rethrow;
    } catch (e, stackTrace) {
      throw _translate(e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> discard() async {
    // The library has no "throw away what was staged": there is
    // makeSkipUpdate, which marks a version skipped rather than removing it,
    // and an internal cleanup pass. Dropping the controller is what we can do
    // — the next check builds a fresh one bound to the new channel, and the
    // library's own cleanup reclaims the stale staging directory.
    _pending?.cancel();
    _pending = null;
    _cancelInner();
  }

  void _cancelInner() {
    final inner = _inner;
    _inner = null;
    try {
      inner?.cancel();
    } on UpdateException {
      rethrow;
    } catch (error, stackTrace) {
      throw _translate(error, stackTrace: stackTrace);
    }
  }

  static Future<T> _untilCancelled<T>(
    _ManagedSession session,
    Future<T> operation,
  ) async {
    final result = await Future.any([
      operation,
      session.cancelled.then<T>((_) => throw _discardedException),
    ]);
    if (session.isCancelled) throw _discardedException;
    return result;
  }

  static const _discardedException = UpdateException(
    UpdateFailure.install,
    'update session discarded',
  );

  UpdateRelease _release(
    du.ReleaseDescriptor descriptor,
    UpdateChannel channel,
  ) {
    return UpdateRelease(
      version: descriptor.version,
      channel: channel,
      publishedAt: descriptor.generatedAt,
      sizeBytes: descriptor.artifact.length,
      // The library only offers a descriptor when it considers it an upgrade,
      // so anything reached here is newer. Moving to an older stable arrives
      // as a fresh check on the new channel, and the comparison it did to get
      // here is the one that decides.
      isDowngrade: false,
    );
  }

  /// The library reports failures as an opaque `Object`, so the distinction
  /// between "could not reach it" and "it did not verify" has to be recovered
  /// from the text. Crude, and the reason it is worth doing anyway is that
  /// telling a user to retry a signature failure is the one piece of advice
  /// that must never be given.
  static UpdateException _translate(Object error, {StackTrace? stackTrace}) {
    final detail = _safeTranslationDetail(error);
    final text = detail.toLowerCase();

    if (text.contains('signature') ||
        text.contains('sha256') ||
        text.contains('checksum') ||
        text.contains('digest') ||
        text.contains('untrusted') ||
        text.contains('verif')) {
      return UpdateException.caused(
        UpdateFailure.untrusted,
        detail,
        error,
        stackTrace,
      );
    }
    if (error is FormatException ||
        text.contains('format') ||
        text.contains('schema') ||
        text.contains('parse') ||
        text.contains('malformed')) {
      return UpdateException.caused(
        UpdateFailure.malformed,
        detail,
        error,
        stackTrace,
      );
    }
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        text.contains('socket') ||
        text.contains('http')) {
      return UpdateException.caused(
        UpdateFailure.unreachable,
        detail,
        error,
        stackTrace,
      );
    }
    return UpdateException.caused(
      UpdateFailure.install,
      detail,
      error,
      stackTrace,
    );
  }

  static String _safeTranslationDetail(Object error) {
    final detail = switch (error) {
      FormatException(:final message, :final offset) =>
        '$message${offset == null ? '' : ' at $offset'}',
      _ => DiagnosticsRedactor.safeString(error),
    };
    return DiagnosticsRedactor.scrub(detail);
  }
}

final class _PluginSession implements DesktopUpdateSession {
  _PluginSession(this._controller);

  final du.DesktopUpdaterController _controller;

  @override
  du.UpdateState get state => _controller.state;

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  Future<du.ManualUpdateCheckResult> checkForUpdates() =>
      _controller.checkForUpdates();

  @override
  Future<void> downloadUpdate() => _controller.downloadUpdate();

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  Future<void> restartApp() => _controller.restartApp();

  @override
  void dispose() => _controller.dispose();
}

final class _ManagedSession {
  _ManagedSession(this.channel, this.controller);

  final UpdateChannel channel;
  final DesktopUpdateSession controller;
  final Completer<void> _cancelled = Completer<void>();

  Future<void> get cancelled => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (_cancelled.isCompleted) return;
    _cancelled.complete();
    controller.dispose();
  }
}

final class _PendingSession {
  _PendingSession(this.channel);

  final UpdateChannel channel;
  final Completer<void> _cancelled = Completer<void>();
  late Future<_ManagedSession> result;

  Future<void> get cancelled => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// The pending-install marker, as a JSON file replaced atomically.
///
/// Modelled on the reference implementation in the package's own example. The
/// library requires that a write only completes once a later read can return
/// the same bytes, which is why this goes through a temporary file and a
/// rename rather than writing in place: a process replaced halfway through
/// writing its own recovery marker is exactly the case the marker exists for.
///
/// Not shared_preferences, despite that being the house answer for small
/// persistent state, because the marker has to survive the binary being
/// swapped underneath it and preferences give no ordering guarantee at all.
final class FileUpdateRecoveryStore implements du.UpdateRecoveryStore {
  FileUpdateRecoveryStore(this.file);

  final File file;

  @override
  Future<du.UpdateInstallRecoveryMarker?> readPendingInstall({
    required String channel,
  }) async {
    final String encoded;
    try {
      if (!await file.exists()) return null;
      await ensurePrivateDirectory(file.parent);
      restrictPrivateFile(file);
      encoded = await file.readAsString();
    } catch (error, stackTrace) {
      _reportUpdaterRecoveryError(error, stackTrace, 'updater.recovery.read');
      return null;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final marker = _fromJson(decoded);
      // A marker left by another channel is not ours to recover.
      return marker.channel == channel ? marker : null;
    } catch (_) {
      // An unreadable marker must not stop the app launching. The cost is one
      // unrecovered install, which the next check finds again anyway.
      return null;
    }
  }

  @override
  Future<void> writePendingInstall(
    du.UpdateInstallRecoveryMarker marker,
  ) async {
    await ensurePrivateDirectory(file.parent);
    final pending = _pendingFile;
    try {
      await ensurePrivateFile(pending);
      await pending.writeAsString(jsonEncode(_toJson(marker)), flush: true);
      await pending.rename(file.path);
      restrictPrivateFile(file);
    } finally {
      await _deleteIfPresent(pending);
    }
  }

  @override
  Future<void> clearPendingInstall({required String channel}) async {
    await _clearMarker(file, channel);
    await _clearMarker(_pendingFile, channel);
  }

  File get _pendingFile => File('${file.path}.pending');

  static Future<void> _clearMarker(File markerFile, String channel) async {
    if (!await markerFile.exists()) return;

    try {
      await ensurePrivateDirectory(markerFile.parent);
      restrictPrivateFile(markerFile);
      final decoded = jsonDecode(await markerFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        final marker = _fromJson(decoded);
        if (marker.channel != channel) return;
      }
    } catch (_) {
      // A corrupt marker has no channel owner and cannot be recovered.
    }
    await _deleteIfPresent(markerFile);
  }

  static Future<void> _deleteIfPresent(File target) async {
    try {
      if (await target.exists()) await target.delete();
    } on FileSystemException {
      if (await target.exists()) rethrow;
    }
  }

  static Map<String, Object?> _toJson(du.UpdateInstallRecoveryMarker m) => {
    'createdAt': m.createdAt.toUtc().toIso8601String(),
    'packageVersion': m.packageVersion,
    'platform': m.platform,
    'channel': m.channel,
    'appVersion': m.appVersion,
    'updateVersion': m.updateVersion,
    'updateBuildNumber': m.updateBuildNumber,
    'expectedPackageId': m.expectedPackageId,
    'stagingPath': m.stagingPath,
    'stageProvenanceSha256': m.stageProvenanceSha256,
    'diagnosticsText': m.diagnosticsText,
    'transactionId': m.transactionId,
  };

  static du.UpdateInstallRecoveryMarker _fromJson(Map<String, dynamic> json) =>
      du.UpdateInstallRecoveryMarker(
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        packageVersion: json['packageVersion'] as String,
        platform: json['platform'] as String,
        channel: json['channel'] as String,
        appVersion: json['appVersion'] as String?,
        updateVersion: json['updateVersion'] as String?,
        updateBuildNumber: json['updateBuildNumber'] as int?,
        expectedPackageId: json['expectedPackageId'] as String?,
        stagingPath: json['stagingPath'] as String?,
        stageProvenanceSha256: json['stageProvenanceSha256'] as String?,
        diagnosticsText: json['diagnosticsText'] as String?,
        transactionId: json['transactionId'] as String?,
      );
}

void _reportUpdaterRecoveryError(
  Object error,
  StackTrace stackTrace,
  String operation,
) {
  DiagnosticsSink.current.reportError(
    error,
    stackTrace,
    operation: operation,
    source: 'updater',
    severity: DiagnosticSeverity.warning,
    handled: true,
    degraded: true,
  );
}
