import 'dart:async';
import 'dart:io';

import 'package:desktop_updater/desktop_updater.dart' as du;
import 'package:discourse_native/src/data/desktop_updater_adapter.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopUpdaterAdapter', () {
    test('maps an available release into the app model', () async {
      final descriptor = releaseDescriptor(
        version: '2.4.1',
        generatedAt: DateTime.utc(2026, 8, 8),
        length: 8192,
      );
      final session = FakeDesktopUpdateSession(
        onCheck: () async => du.ManualUpdateCheckAvailable(
          descriptor: descriptor,
          mandatory: false,
        ),
      );
      final channels = <UpdateChannel>[];
      final updater = DesktopUpdaterAdapter(
        createSession: (channel) async {
          channels.add(channel);
          return session;
        },
      );

      final release = await updater.check(channel: UpdateChannel.canary);

      expect(channels, [UpdateChannel.canary]);
      expect(release?.version, '2.4.1');
      expect(release?.channel, UpdateChannel.canary);
      expect(release?.publishedAt, DateTime.utc(2026, 8, 8));
      expect(release?.sizeBytes, 8192);
      expect(release?.isDowngrade, isFalse);
    });

    test('maps an up-to-date result to no release', () async {
      final updater = updaterWith(FakeDesktopUpdateSession());

      expect(await updater.check(channel: UpdateChannel.stable), isNull);
    });

    test('reports progress and always removes its listener', () async {
      late FakeDesktopUpdateSession session;
      session = FakeDesktopUpdateSession(
        onDownload: () async {
          session
            ..emit(
              const du.UpdateDownloading(receivedBytes: 50, totalBytes: 100),
            )
            ..emit(
              const du.UpdateDownloading(receivedBytes: 150, totalBytes: 100),
            )
            ..emit(const du.UpdateReadyToInstall(stagingPath: '/stage'));
        },
      );
      final progress = <double>[];

      await updaterWith(
        session,
      ).download(appRelease(), onProgress: progress.add);

      expect(progress, [0.5, 1.0]);
      expect(session.addCount, 1);
      expect(session.removeCount, 1);
      expect(session.listenerCount, 0);
    });

    test('waits for a terminal state after download handoff', () async {
      final session = FakeDesktopUpdateSession(
        currentState: const du.UpdateDownloading(
          receivedBytes: 10,
          totalBytes: 100,
        ),
      );
      final download = updaterWith(session).download(appRelease());
      await flushEvents();

      expect(session.listenerCount, 1);
      var completed = false;
      unawaited(download.then((_) => completed = true));
      await flushEvents();
      expect(completed, isFalse);

      session.emit(const du.UpdateReadyToInstall(stagingPath: '/stage'));
      await download;

      expect(session.listenerCount, 0);
    });

    test('translates a terminal verification failure and cleans up', () async {
      late FakeDesktopUpdateSession session;
      session = FakeDesktopUpdateSession(
        onDownload: () async {
          session.emit(du.UpdateFailed(StateError('signature mismatch')));
        },
      );

      await expectLater(
        updaterWith(session).download(appRelease()),
        throwsUpdateFailure(UpdateFailure.untrusted),
      );
      expect(session.removeCount, 1);
      expect(session.listenerCount, 0);
    });

    test('translates thrown transport and format failures', () async {
      final unreachable = updaterWith(
        FakeDesktopUpdateSession(
          onCheck: () async => throw const SocketException('offline'),
        ),
      );
      final malformed = updaterWith(
        FakeDesktopUpdateSession(
          onCheck: () async => du.ManualUpdateCheckFailed(
            const FormatException('malformed schema'),
            StackTrace.current,
          ),
        ),
      );

      await expectLater(
        unreachable.check(channel: UpdateChannel.stable),
        throwsUpdateFailure(UpdateFailure.unreachable),
      );
      await expectLater(
        malformed.check(channel: UpdateChannel.stable),
        throwsUpdateFailure(UpdateFailure.malformed),
      );
    });

    test('never retains a parser source while translating failures', () async {
      const secretBody = '{"token":"updater-response-body-secret"}';
      const parseFailure = FormatException(
        'malformed update schema',
        secretBody,
        9,
      );
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'updater-parser-privacy',
      );
      final binding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        binding.close();
        await diagnostics.close();
      });
      final updater = updaterWith(
        FakeDesktopUpdateSession(
          onCheck: () async => du.ManualUpdateCheckFailed(
            parseFailure,
            StackTrace.fromString('original updater parser stack'),
          ),
        ),
      );

      UpdateException? translated;
      try {
        await updater.check(channel: UpdateChannel.stable);
        fail('The malformed updater response should fail.');
      } on UpdateException catch (error) {
        translated = error;
      }

      expect(translated.failure, UpdateFailure.malformed);
      expect(translated.detail, 'malformed update schema at 9');
      expect(translated.toString(), isNot(contains(secretBody)));
      DiagnosticsSink.current.reportError(
        translated,
        StackTrace.current,
        operation: 'updater.check',
        source: 'updater',
      );
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single.message,
        'malformed update schema (offset 9)',
      );
      expect(
        diagnostics.buildJsonReport(diagnostics.events),
        isNot(contains('updater-response-body-secret')),
      );
    });

    test('preserves opaque state failures for terminal reporting', () async {
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'updater-state-failures',
      );
      final binding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        binding.close();
        await diagnostics.close();
      });

      final checkFailure = StateError('opaque check failure');
      final checkStack = StackTrace.fromString('original check stack');
      final downloadFailure = StateError('opaque download failure');
      late FakeDesktopUpdateSession session;
      session = FakeDesktopUpdateSession(
        onCheck: () async =>
            du.ManualUpdateCheckFailed(checkFailure, checkStack),
        onDownload: () async {
          session.emit(du.UpdateFailed(downloadFailure));
        },
      );
      final updater = updaterWith(session);

      Future<void> reportTerminal(
        String operation,
        Future<void> Function() invoke,
      ) async {
        try {
          await invoke();
          fail('The updater operation should fail.');
        } on UpdateException catch (error, stackTrace) {
          DiagnosticsSink.current.reportError(
            error,
            stackTrace,
            operation: operation,
            source: 'updater',
          );
        }
      }

      await reportTerminal(
        'updater.check',
        () async => updater.check(channel: UpdateChannel.stable),
      );
      await reportTerminal(
        'updater.download',
        () => updater.download(appRelease()),
      );

      final checkEvent = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .singleWhere((event) => event.operation == 'updater.check');
      expect(checkEvent.message, contains('opaque check failure'));
      expect(checkEvent.stackTrace, contains('original check stack'));

      final downloadEvent = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .singleWhere((event) => event.operation == 'updater.download');
      expect(downloadEvent.message, contains('opaque download failure'));
      expect(downloadEvent.stackTrace, isNotEmpty);
    });

    test(
      'translates session creation failures into the updater contract',
      () async {
        final updater = DesktopUpdaterAdapter(
          createSession: (_) => throw const SocketException('offline'),
        );

        await expectLater(
          updater.check(channel: UpdateChannel.stable),
          throwsUpdateFailure(UpdateFailure.unreachable),
        );
      },
    );

    test('discard cancels a download and removes its listener', () async {
      final gate = Completer<void>();
      final session = FakeDesktopUpdateSession(onDownload: () => gate.future);
      final updater = updaterWith(session);
      final download = updater.download(appRelease());
      final expectation = expectLater(
        download,
        throwsUpdateFailure(UpdateFailure.install),
      );
      await flushEvents();

      await updater.discard();
      await expectation;

      expect(session.disposeCount, 1);
      expect(session.removeCount, 1);
      expect(session.listenerCount, 0);
      gate.complete();
      await flushEvents();
    });

    test('discard prevents a pending session from becoming active', () async {
      final created = Completer<DesktopUpdateSession>();
      final session = FakeDesktopUpdateSession();
      final updater = DesktopUpdaterAdapter(
        createSession: (_) => created.future,
      );
      final check = updater.check(channel: UpdateChannel.stable);
      final expectation = expectLater(
        check,
        throwsUpdateFailure(UpdateFailure.install),
      );
      await flushEvents();

      await updater.discard();
      await expectation;
      created.complete(session);
      await flushEvents();

      expect(session.disposeCount, 1);
      await expectLater(
        updater.installAndRestart(),
        throwsUpdateFailure(UpdateFailure.install),
      );
    });

    test(
      'discard clears the current session even when disposal fails',
      () async {
        final session = FakeDesktopUpdateSession(
          disposeError: StateError('cleanup failed'),
        );
        final updater = updaterWith(session);
        await updater.check(channel: UpdateChannel.stable);

        await expectLater(
          updater.discard(),
          throwsUpdateFailure(UpdateFailure.install),
        );
        await expectLater(
          updater.installAndRestart(),
          throwsUpdateFailure(UpdateFailure.install),
        );

        expect(session.disposeCount, 1);
        expect(session.restartCount, 0);
      },
    );

    test(
      'switching channels cancels work and disposes the old session',
      () async {
        final stableCheck = Completer<du.ManualUpdateCheckResult>();
        final stable = FakeDesktopUpdateSession(
          onCheck: () => stableCheck.future,
        );
        final canary = FakeDesktopUpdateSession();
        final updater = DesktopUpdaterAdapter(
          createSession: (channel) async => switch (channel) {
            UpdateChannel.stable => stable,
            UpdateChannel.canary => canary,
          },
        );
        final firstCheck = updater.check(channel: UpdateChannel.stable);
        final firstExpectation = expectLater(
          firstCheck,
          throwsUpdateFailure(UpdateFailure.install),
        );
        await flushEvents();

        expect(await updater.check(channel: UpdateChannel.canary), isNull);
        await firstExpectation;

        expect(stable.disposeCount, 1);
        expect(canary.disposeCount, 0);
        stableCheck.complete(const du.ManualUpdateCheckUpToDate());
        await flushEvents();
      },
    );

    test('coalesces concurrent creation for the same channel', () async {
      final created = Completer<DesktopUpdateSession>();
      var createCount = 0;
      final updater = DesktopUpdaterAdapter(
        createSession: (_) {
          createCount += 1;
          return created.future;
        },
      );

      final first = updater.check(channel: UpdateChannel.stable);
      final second = updater.check(channel: UpdateChannel.stable);
      created.complete(FakeDesktopUpdateSession());

      expect(await first, isNull);
      expect(await second, isNull);
      expect(createCount, 1);
    });

    test('requires a staged session before restart', () async {
      final updater = updaterWith(FakeDesktopUpdateSession());

      await expectLater(
        updater.installAndRestart(),
        throwsUpdateFailure(UpdateFailure.install),
      );
    });

    test(
      'restarts through the current session and translates failures',
      () async {
        final working = FakeDesktopUpdateSession();
        final broken = FakeDesktopUpdateSession(
          onRestart: () async => throw StateError('install handoff failed'),
        );
        final workingUpdater = updaterWith(working);
        final brokenUpdater = updaterWith(broken);
        await workingUpdater.check(channel: UpdateChannel.stable);
        await brokenUpdater.check(channel: UpdateChannel.stable);

        await workingUpdater.installAndRestart();
        await expectLater(
          brokenUpdater.installAndRestart(),
          throwsUpdateFailure(UpdateFailure.install),
        );

        expect(working.restartCount, 1);
        expect(broken.restartCount, 1);
      },
    );
  });

  group('FileUpdateRecoveryStore', () {
    late Directory directory;
    late File file;
    late FileUpdateRecoveryStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('update-recovery-');
      file = File('${directory.path}/pending-update.json');
      store = FileUpdateRecoveryStore(file);
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('round-trips every recovery field through an atomic write', () async {
      final marker = recoveryMarker(channel: 'stable');

      await store.writePendingInstall(marker);
      final restored = await store.readPendingInstall(channel: 'stable');

      expect(restored?.createdAt, marker.createdAt);
      expect(restored?.packageVersion, marker.packageVersion);
      expect(restored?.platform, marker.platform);
      expect(restored?.channel, marker.channel);
      expect(restored?.appVersion, marker.appVersion);
      expect(restored?.updateVersion, marker.updateVersion);
      expect(restored?.updateBuildNumber, marker.updateBuildNumber);
      expect(restored?.expectedPackageId, marker.expectedPackageId);
      expect(restored?.stagingPath, marker.stagingPath);
      expect(restored?.stageProvenanceSha256, marker.stageProvenanceSha256);
      expect(restored?.diagnosticsText, marker.diagnosticsText);
      expect(restored?.transactionId, marker.transactionId);
      expect(await File('${file.path}.pending').exists(), isFalse);
    });

    test('does not read or clear a marker owned by another channel', () async {
      await store.writePendingInstall(recoveryMarker(channel: 'canary'));

      expect(await store.readPendingInstall(channel: 'stable'), isNull);
      await store.clearPendingInstall(channel: 'stable');

      expect(await file.exists(), isTrue);
      expect(
        (await store.readPendingInstall(channel: 'canary'))?.channel,
        'canary',
      );
      await store.clearPendingInstall(channel: 'canary');
      expect(await file.exists(), isFalse);
    });

    test('ignores a corrupt marker and allows it to be cleared', () async {
      await file.writeAsString('{not json');

      expect(await store.readPendingInstall(channel: 'stable'), isNull);
      await store.clearPendingInstall(channel: 'stable');

      expect(await file.exists(), isFalse);
    });

    test('cleans the pending file when atomic replacement fails', () async {
      await Directory(file.path).create();
      final pending = File('${file.path}.pending');

      await expectLater(
        store.writePendingInstall(recoveryMarker(channel: 'stable')),
        throwsA(isA<FileSystemException>()),
      );

      expect(await pending.exists(), isFalse);
    });

    test('clears an interrupted pending marker only for its channel', () async {
      final pending = File('${file.path}.pending');
      await store.writePendingInstall(recoveryMarker(channel: 'canary'));
      await file.rename(pending.path);

      await store.clearPendingInstall(channel: 'stable');
      expect(await pending.exists(), isTrue);

      await store.clearPendingInstall(channel: 'canary');
      expect(await pending.exists(), isFalse);
    });
  });
}

DesktopUpdaterAdapter updaterWith(FakeDesktopUpdateSession session) =>
    DesktopUpdaterAdapter(createSession: (_) async => session);

UpdateRelease appRelease({UpdateChannel channel = UpdateChannel.stable}) =>
    UpdateRelease(version: '2.4.1', channel: channel);

Matcher throwsUpdateFailure(UpdateFailure failure) => throwsA(
  isA<UpdateException>().having((error) => error.failure, 'failure', failure),
);

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

du.ReleaseDescriptor releaseDescriptor({
  required String version,
  required DateTime generatedAt,
  required int length,
}) => du.ReleaseDescriptor(
  schemaVersion: 3,
  packageId: 'org.discourse.native',
  appName: 'Discourse',
  version: version,
  buildNumber: 1,
  platform: 'linux',
  channel: 'stable',
  artifact: du.ReleaseArtifact(
    kind: 'zip',
    url: Uri.parse('https://updates.example/app.zip'),
    sha256: 'a' * 64,
    length: length,
  ),
  install: const du.ReleaseInstall(strategy: 'wholeBundleReplace'),
  minimumUpdaterVersion: '3.1.1',
  generatedAt: generatedAt,
);

du.UpdateInstallRecoveryMarker recoveryMarker({required String channel}) =>
    du.UpdateInstallRecoveryMarker(
      createdAt: DateTime.utc(2026, 8, 8, 12),
      packageVersion: '3.1.1',
      platform: 'linux',
      channel: channel,
      appVersion: '2.3.0',
      updateVersion: '2.4.1',
      updateBuildNumber: 241,
      expectedPackageId: 'org.discourse.native',
      stagingPath: '/tmp/discourse-stage',
      stageProvenanceSha256: 'b' * 64,
      diagnosticsText: 'ready',
      transactionId: '123e4567-e89b-42d3-a456-426614174000',
    );

final class FakeDesktopUpdateSession implements DesktopUpdateSession {
  FakeDesktopUpdateSession({
    this.currentState = const du.UpdateIdle(),
    this.onCheck,
    this.onDownload,
    this.onRestart,
    this.disposeError,
  });

  du.UpdateState currentState;
  final Future<du.ManualUpdateCheckResult> Function()? onCheck;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onRestart;
  final Object? disposeError;
  final Set<VoidCallback> _listeners = {};

  int addCount = 0;
  int removeCount = 0;
  int disposeCount = 0;
  int restartCount = 0;

  int get listenerCount => _listeners.length;

  void emit(du.UpdateState state) {
    currentState = state;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  du.UpdateState get state => currentState;

  @override
  void addListener(VoidCallback listener) {
    addCount += 1;
    _listeners.add(listener);
  }

  @override
  Future<du.ManualUpdateCheckResult> checkForUpdates() =>
      onCheck?.call() ?? Future.value(const du.ManualUpdateCheckUpToDate());

  @override
  Future<void> downloadUpdate() => onDownload?.call() ?? Future.value();

  @override
  void removeListener(VoidCallback listener) {
    removeCount += 1;
    _listeners.remove(listener);
  }

  @override
  Future<void> restartApp() {
    restartCount += 1;
    return onRestart?.call() ?? Future.value();
  }

  @override
  void dispose() {
    disposeCount += 1;
    if (disposeError case final error?) throw error;
  }
}
