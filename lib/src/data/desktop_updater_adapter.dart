import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_updater/desktop_updater.dart' as du;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_release.dart';
import 'updater.dart';

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
  DesktopUpdaterAdapter();

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

  /// The library binds a channel at construction, so there is one of these per
  /// channel and switching disposes the last.
  du.DesktopUpdaterController? _inner;
  UpdateChannel? _innerChannel;

  Future<du.DesktopUpdaterController> _controllerFor(
    UpdateChannel channel,
  ) async {
    final existing = _inner;
    if (existing != null && _innerChannel == channel) return existing;

    existing?.dispose();

    final support = await getApplicationSupportDirectory();
    final controller = du.DesktopUpdaterController(
      appArchiveUrl: Uri.parse(AppRelease.archiveUrlFor(channel)),
      expectedPackageId: _packageId,
      channel: channel.name,
      trustedReleasePublicKeys: AppRelease.trustedReleaseKeys,
      recoveryStore: _MarkerFile(
        File('${support.path}/pending-update.json'),
      ),
      // We decide when to look. Left on, the constructor starts a check of its
      // own and the first result the UI sees is one nobody asked for.
      skipInitialVersionCheck: true,
    );

    _inner = controller;
    _innerChannel = channel;
    return controller;
  }

  /// Must match APPLICATION_ID in linux/CMakeLists.txt: the library refuses a
  /// descriptor published under a different package id, which is what stops a
  /// feed for some other app from installing over this one.
  static const String _packageId = 'org.discourse.native';

  @override
  Future<UpdateRelease?> check({required UpdateChannel channel}) async {
    final controller = await _controllerFor(channel);

    final du.ManualUpdateCheckResult result;
    try {
      result = await controller.checkForUpdates();
    } catch (e) {
      throw UpdateException(UpdateFailure.unreachable, '$e');
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
      du.ManualUpdateCheckFailed(:final error) => throw _translate(error),
    };
  }

  @override
  Future<void> download(
    UpdateRelease release, {
    void Function(double fraction)? onProgress,
  }) async {
    final controller = await _controllerFor(release.channel);
    final done = Completer<void>();

    void onState() {
      switch (controller.state) {
        case du.UpdateDownloading(:final receivedBytes, :final totalBytes):
          if (totalBytes > 0) onProgress?.call(receivedBytes / totalBytes);
        case du.UpdateReadyToInstall():
          if (!done.isCompleted) done.complete();
        case du.UpdateFailed(:final error):
          if (!done.isCompleted) done.completeError(_translate(error));
        default:
          break;
      }
    }

    controller.addListener(onState);
    try {
      await controller.downloadUpdate();
      // downloadUpdate returns when it has handed off, not necessarily when
      // the artifact is staged, so the terminal state is what we wait on.
      await done.future;
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw _translate(e);
    } finally {
      controller.removeListener(onState);
    }
  }

  @override
  Future<void> installAndRestart() async {
    final controller = _inner;
    if (controller == null) {
      throw const UpdateException(UpdateFailure.install, 'nothing staged');
    }

    try {
      await controller.restartApp();
    } catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> discard() async {
    // The library has no "throw away what was staged": there is
    // makeSkipUpdate, which marks a version skipped rather than removing it,
    // and an internal cleanup pass. Dropping the controller is what we can do
    // — the next check builds a fresh one bound to the new channel, and the
    // library's own cleanup reclaims the stale staging directory.
    _inner?.dispose();
    _inner = null;
    _innerChannel = null;
  }

  UpdateRelease _release(du.ReleaseDescriptor descriptor, UpdateChannel channel) {
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
  static UpdateException _translate(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('signature') ||
        text.contains('sha256') ||
        text.contains('checksum') ||
        text.contains('digest') ||
        text.contains('untrusted') ||
        text.contains('verif')) {
      return UpdateException(UpdateFailure.untrusted, '$error');
    }
    if (text.contains('format') ||
        text.contains('schema') ||
        text.contains('parse') ||
        text.contains('malformed')) {
      return UpdateException(UpdateFailure.malformed, '$error');
    }
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        text.contains('socket') ||
        text.contains('http')) {
      return UpdateException(UpdateFailure.unreachable, '$error');
    }
    return UpdateException(UpdateFailure.install, '$error');
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
final class _MarkerFile implements du.UpdateRecoveryStore {
  _MarkerFile(this.file);

  final File file;

  @override
  Future<du.UpdateInstallRecoveryMarker?> readPendingInstall({
    required String channel,
  }) async {
    if (!await file.exists()) return null;

    try {
      final decoded = jsonDecode(await file.readAsString());
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
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(_toJson(marker)), flush: true);
    await pending.rename(file.path);
  }

  @override
  Future<void> clearPendingInstall({required String channel}) async {
    if (await file.exists()) await file.delete();
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
