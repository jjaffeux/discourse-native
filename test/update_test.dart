import 'dart:async';

import 'package:discourse_native/src/data/app_release.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/shell/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

UpdateRelease release(
  String version, {
  UpdateChannel channel = UpdateChannel.stable,
  bool isDowngrade = false,
}) =>
    UpdateRelease(version: version, channel: channel, isDowngrade: isDowngrade);

UpdateController controllerWith({
  FakeUpdater? updater,
  FakeUpdateStore? store,
}) => UpdateController(
  updater: updater ?? FakeUpdater(isSupported: true),
  store: store ?? FakeUpdateStore(),
);

final class _FailingUpdateStore extends FakeUpdateStore {
  @override
  Future<UpdateChannel?> readChannel() async => throw StateError('read failed');

  @override
  Future<void> writeChannel(UpdateChannel channel) async =>
      throw StateError('write failed');

  @override
  Future<void> writeLastChecked(DateTime at) async =>
      throw StateError('write failed');
}

final class _CountingUpdateStore extends FakeUpdateStore {
  int channelReads = 0;

  @override
  Future<UpdateChannel?> readChannel() async {
    channelReads++;
    return super.readChannel();
  }
}

final class _GatedUpdateStore extends FakeUpdateStore {
  _GatedUpdateStore({required this.readGate, super.rawChannel});

  final Completer<void> readGate;

  @override
  Future<UpdateChannel?> readChannel() async {
    await readGate.future;
    return super.readChannel();
  }
}

final class _OfferThenFailUpdater extends FakeUpdater {
  _OfferThenFailUpdater() : super(isSupported: true);

  @override
  Future<UpdateRelease?> check({required UpdateChannel channel}) async {
    checkCount++;
    lastCheckedChannel = channel;
    if (checkCount == 1) return release('1.4.0');
    throw const UpdateException(UpdateFailure.unreachable);
  }
}

void main() {
  // UpdateController defers a notification raised mid-frame to a post-frame
  // callback, which reads SchedulerBinding.instance. These are plain tests
  // rather than testWidgets, so the binding has to be stood up by hand.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('channels', () {
    test('a name that is no longer a channel reads as nothing', () {
      expect(UpdateChannel.byName('nightly'), isNull);
      expect(UpdateChannel.byName(null), isNull);
      expect(UpdateChannel.byName('canary'), UpdateChannel.canary);
    });
  });

  group('failures', () {
    test('every failure says something a reader can act on', () {
      final messages = <String>{};

      for (final failure in UpdateFailure.values) {
        final message = UpdateException(failure).message;
        expect(message, isNotEmpty);
        expect(
          message.endsWith('.'),
          isTrue,
          reason: '$failure reads as a fragment, not a sentence',
        );
        messages.add(message);
      }

      expect(messages, hasLength(UpdateFailure.values.length));
    });

    test('a bad signature does not read as an unreachable server', () {
      const untrusted = UpdateException(UpdateFailure.untrusted);
      const unreachable = UpdateException(UpdateFailure.unreachable);

      expect(untrusted.message, isNot(unreachable.message));
      expect(untrusted.message, contains('signature'));
    });
  });

  group('what can update', () {
    test(
      'a build with no updater behind it says so rather than pretending',
      () {
        const updater = UnsupportedUpdater();

        expect(updater.isSupported, isFalse);
        expect(
          () => updater.check(channel: UpdateChannel.stable),
          throwsA(isA<UpdateException>()),
        );
      },
    );

    test('a build the release pipeline never stamped is not a release', () {
      // No --dart-define under `flutter test`, so a local build never presents
      // the pubspec version as if CI had published it.
      expect(AppRelease.version, isEmpty);
    });
  });

  group('the update controller', () {
    test('does nothing at all where updates are not supported', () async {
      final updater = FakeUpdater(isSupported: false);
      final controller = controllerWith(updater: updater);

      await controller.load();
      await controller.check();

      expect(updater.checkCount, 0);
      expect(controller.status, UpdateStatus.idle);
    });

    test('preference failures leave update actions usable', () async {
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(
        updater: updater,
        store: _FailingUpdateStore(),
      );

      await controller.load();
      expect(controller.status, UpdateStatus.idle);
      expect(updater.checkCount, 0);

      await controller.setChannel(UpdateChannel.canary);
      expect(controller.channel, UpdateChannel.canary);
      expect(controller.status, UpdateStatus.upToDate);
      expect(updater.checkCount, 1);
    });

    test('a check that finds nothing reports up to date', () async {
      final controller = controllerWith(
        updater: FakeUpdater(isSupported: true, releases: const {}),
      );

      await controller.check();

      expect(controller.status, UpdateStatus.upToDate);
      expect(controller.available, isNull);
    });

    test('a check that finds a release offers it', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          releases: {UpdateChannel.stable: release('1.4.0')},
        ),
      );

      await controller.check();

      expect(controller.status, UpdateStatus.available);
      expect(controller.available?.version, '1.4.0');
    });

    test('a check the user started reports what went wrong', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: const UpdateException(UpdateFailure.unreachable),
        ),
      );

      await controller.check();

      expect(controller.status, UpdateStatus.failed);
      expect(controller.error, contains("Couldn't reach"));
    });

    test('a check that dies of something else can be tried again', () async {
      final updater = FakeUpdater(
        isSupported: true,
        checkFailure: const FormatException('not a manifest'),
      );
      final controller = controllerWith(updater: updater);

      await controller.check();
      expect(controller.status, UpdateStatus.failed);
      expect(controller.error, contains("Couldn't reach"));

      // `checking` gates every later check; it must not survive the failure.
      await controller.check();
      expect(updater.checkCount, 2);
      expect(controller.status, UpdateStatus.failed);
    });

    test('a quiet check that dies of something else leaves no trace', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: StateError('adapter bug'),
        ),
      );

      await controller.check(silent: true);

      expect(controller.error, isNull);
      expect(controller.status, UpdateStatus.idle);
    });

    test('a check nobody asked for fails quietly', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: const UpdateException(UpdateFailure.unreachable),
        ),
      );

      await controller.check(silent: true);

      expect(controller.error, isNull);
      expect(controller.status, UpdateStatus.idle);
    });

    test(
      'a quiet check that fails leaves an offer already made alone',
      () async {
        final controller = controllerWith(updater: _OfferThenFailUpdater());

        await controller.check();
        expect(controller.status, UpdateStatus.available);
        expect(controller.available?.version, '1.4.0');

        await controller.check(silent: true);

        expect(controller.status, UpdateStatus.available);
        expect(controller.available?.version, '1.4.0');
        expect(controller.error, isNull);
      },
    );

    test('a check while one is running is ignored', () async {
      final gate = Completer<void>();
      final updater = FakeUpdater(isSupported: true, gate: gate);
      final controller = controllerWith(updater: updater);

      final first = controller.check();
      expect(controller.status, UpdateStatus.checking);

      await controller.check();
      expect(updater.checkCount, 1);

      gate.complete();
      await first;
    });

    test('load prefers a stored channel over the one built in', () async {
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(
        updater: updater,
        store: FakeUpdateStore(rawChannel: 'canary'),
      );

      await controller.load();

      expect(controller.channel, UpdateChannel.canary);
      expect(updater.lastCheckedChannel, UpdateChannel.canary);
    });

    test(
      'a stored channel invalidates a check started while preferences load',
      () async {
        final preferencesGate = Completer<void>();
        final stableGate = Completer<void>();
        final updater = FakeUpdater(
          isSupported: true,
          releases: {
            UpdateChannel.stable: release('1.4.0'),
            UpdateChannel.canary: release(
              '1.5.0-canary.2',
              channel: UpdateChannel.canary,
            ),
          },
          checkGates: {UpdateChannel.stable: stableGate},
        );
        final controller = controllerWith(
          updater: updater,
          store: _GatedUpdateStore(
            readGate: preferencesGate,
            rawChannel: UpdateChannel.canary.name,
          ),
        );

        final loading = controller.load();
        final oldCheck = controller.check();
        expect(updater.lastCheckedChannel, UpdateChannel.stable);

        preferencesGate.complete();
        await loading;
        expect(controller.channel, UpdateChannel.canary);
        expect(controller.available?.version, '1.5.0-canary.2');

        stableGate.complete();
        await oldCheck;

        expect(controller.channel, UpdateChannel.canary);
        expect(controller.available?.channel, UpdateChannel.canary);
        expect(controller.available?.version, '1.5.0-canary.2');
        expect(controller.status, UpdateStatus.available);
      },
    );

    test('late channel hydration discards an old-channel download', () async {
      final preferencesGate = Completer<void>();
      final downloadGate = Completer<void>();
      final updater = FakeUpdater(
        isSupported: true,
        releases: {
          UpdateChannel.stable: release('1.4.0'),
          UpdateChannel.canary: release(
            '1.5.0-canary.2',
            channel: UpdateChannel.canary,
          ),
        },
        downloadGate: downloadGate,
      );
      final controller = controllerWith(
        updater: updater,
        store: _GatedUpdateStore(
          readGate: preferencesGate,
          rawChannel: UpdateChannel.canary.name,
        ),
      );

      final loading = controller.load();
      await controller.check();
      final oldDownload = controller.download();
      expect(controller.status, UpdateStatus.downloading);

      preferencesGate.complete();
      await loading;

      expect(updater.discardCount, 1);
      expect(updater.stagedRelease, isNull);
      expect(controller.channel, UpdateChannel.canary);
      expect(controller.available?.version, '1.5.0-canary.2');

      downloadGate.complete();
      await oldDownload;

      expect(controller.channel, UpdateChannel.canary);
      expect(controller.available?.version, '1.5.0-canary.2');
      expect(controller.status, UpdateStatus.available);
      expect(
        updater.stagedRelease,
        isNull,
        reason: 'discard is a barrier against late old-channel staging',
      );
    });

    test('load falls back to stable for a channel this build lost', () async {
      final controller = controllerWith(
        store: FakeUpdateStore(rawChannel: 'nightly'),
      );

      await controller.load();

      expect(controller.channel, UpdateChannel.stable);
    });

    test('load does not re-check if it looked recently', () async {
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(
        updater: updater,
        store: FakeUpdateStore(lastChecked: DateTime.now()),
      );

      await controller.load();

      expect(updater.checkCount, 0);
    });

    test('load checks again once the last look is stale', () async {
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(
        updater: updater,
        store: FakeUpdateStore(
          lastChecked: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );

      await controller.load();

      expect(updater.checkCount, 1);
    });

    test('a finished download offers to restart', () async {
      final updater = FakeUpdater(
        isSupported: true,
        releases: {UpdateChannel.stable: release('1.4.0')},
      );
      final controller = controllerWith(updater: updater);

      await controller.check();
      await controller.download();

      expect(controller.status, UpdateStatus.readyToInstall);
      expect(controller.progress, 1);
      expect(updater.lastDownloaded?.version, '1.4.0');
    });

    test('a download that fails leaves the release still on offer', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          releases: {UpdateChannel.stable: release('1.4.0')},
          downloadFailure: const UpdateException(UpdateFailure.untrusted),
        ),
      );

      await controller.check();
      await controller.download();

      expect(controller.status, UpdateStatus.available);
      expect(controller.error, contains('signature'));
      expect(controller.available, isNotNull);
    });

    test('a download that dies of something else keeps the offer', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          releases: {UpdateChannel.stable: release('1.4.0')},
          downloadFailure: StateError('disk full'),
        ),
      );

      await controller.check();
      await controller.download();

      expect(controller.status, UpdateStatus.available);
      expect(controller.progress, 0);
      expect(controller.error, contains("Couldn't reach"));
      expect(controller.available?.version, '1.4.0');
    });

    test('restarting hands the app over to the updater', () async {
      final updater = FakeUpdater(
        isSupported: true,
        releases: {UpdateChannel.stable: release('1.4.0')},
      );
      final controller = controllerWith(updater: updater);

      await controller.check();
      await controller.download();
      await controller.installAndRestart();

      expect(updater.installCount, 1);
    });

    test('an install that fails still offers the staged build', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          releases: {UpdateChannel.stable: release('1.4.0')},
          installFailure: const UpdateException(UpdateFailure.install),
        ),
      );

      await controller.check();
      await controller.download();
      await controller.installAndRestart();

      expect(controller.status, UpdateStatus.readyToInstall);
      expect(controller.error, isNotNull);
    });

    test(
      'an install that dies of something else still offers the staged build',
      () async {
        final controller = controllerWith(
          updater: FakeUpdater(
            isSupported: true,
            releases: {UpdateChannel.stable: release('1.4.0')},
            installFailure: StateError('helper missing'),
          ),
        );

        await controller.check();
        await controller.download();
        await controller.installAndRestart();

        expect(controller.status, UpdateStatus.readyToInstall);
        expect(controller.error, contains('could not be installed'));
      },
    );

    test(
      'a discard that dies of something else still asks the new channel',
      () async {
        final updater = _ThrowingDiscardUpdater(
          releases: {UpdateChannel.canary: release('1.5.0-canary.2')},
        );
        final controller = controllerWith(updater: updater);

        await controller.setChannel(UpdateChannel.canary);

        expect(updater.lastCheckedChannel, UpdateChannel.canary);
        expect(controller.status, UpdateStatus.available);
        expect(controller.available?.version, '1.5.0-canary.2');
      },
    );

    test('switching channels persists the choice', () async {
      final store = FakeUpdateStore();
      final controller = controllerWith(store: store);

      await controller.setChannel(UpdateChannel.canary);

      expect(controller.channel, UpdateChannel.canary);
      expect(store.rawChannel, 'canary');
      expect(store.writeCount, 1);
    });

    test('switching channels throws away anything downloaded', () async {
      final updater = FakeUpdater(
        isSupported: true,
        releases: {UpdateChannel.stable: release('1.4.0')},
      );
      final controller = controllerWith(updater: updater);

      await controller.check();
      await controller.download();
      expect(controller.status, UpdateStatus.readyToInstall);
      expect(updater.stagedRelease?.version, '1.4.0');

      await controller.setChannel(UpdateChannel.canary);

      expect(updater.discardCount, 1);
      expect(updater.stagedRelease, isNull);
      expect(controller.status, UpdateStatus.upToDate);
      expect(controller.available, isNull);
    });

    test('switching channels asks the new one straight away', () async {
      final updater = FakeUpdater(
        isSupported: true,
        releases: {UpdateChannel.canary: release('1.5.0-canary.2')},
      );
      final controller = controllerWith(updater: updater);

      await controller.setChannel(UpdateChannel.canary);

      expect(updater.lastCheckedChannel, UpdateChannel.canary);
      expect(controller.available?.version, '1.5.0-canary.2');
    });

    test('a late check cannot replace the new channel result', () async {
      final stableGate = Completer<void>();
      final updater = FakeUpdater(
        isSupported: true,
        releases: {
          UpdateChannel.stable: release('1.4.0'),
          UpdateChannel.canary: release(
            '1.5.0-canary.2',
            channel: UpdateChannel.canary,
          ),
        },
        checkGates: {UpdateChannel.stable: stableGate},
      );
      final controller = controllerWith(updater: updater);

      final oldCheck = controller.check();
      await controller.setChannel(UpdateChannel.canary);

      expect(controller.available?.version, '1.5.0-canary.2');
      stableGate.complete();
      await oldCheck;

      expect(controller.channel, UpdateChannel.canary);
      expect(controller.available?.version, '1.5.0-canary.2');
      expect(controller.status, UpdateStatus.available);
    });

    test('rapid channel changes persist the final selection last', () async {
      final canaryWrite = Completer<void>();
      final store = FakeUpdateStore(
        channelWriteGates: {UpdateChannel.canary: canaryWrite},
      );
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(updater: updater, store: store);

      final selectingCanary = controller.setChannel(UpdateChannel.canary);
      final selectingStable = controller.setChannel(UpdateChannel.stable);
      canaryWrite.complete();
      await Future.wait([selectingCanary, selectingStable]);

      expect(controller.channel, UpdateChannel.stable);
      expect(store.rawChannel, UpdateChannel.stable.name);
      expect(store.writeCount, 2);
      expect(updater.discardCount, 1);
      expect(updater.lastCheckedChannel, UpdateChannel.stable);
    });

    test('switching to the channel already on does nothing', () async {
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(updater: updater);

      await controller.setChannel(UpdateChannel.stable);

      expect(updater.discardCount, 0);
      expect(updater.checkCount, 0);
    });

    test('disposing releases the updater session', () async {
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(updater: updater);

      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(updater.discardCount, 1);
    });

    test('a disposed controller cannot persist a channel change', () async {
      final updater = FakeUpdater(isSupported: true);
      final store = FakeUpdateStore();
      final controller = controllerWith(updater: updater, store: store);

      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      await controller.setChannel(UpdateChannel.canary);

      expect(controller.channel, UpdateChannel.stable);
      expect(store.rawChannel, isNull);
      expect(store.writeCount, 0);
      expect(updater.checkCount, 0);
      expect(updater.discardCount, 1);
    });

    test(
      'disposed controllers reject every public update entry point',
      () async {
        final updater = FakeUpdater(
          isSupported: true,
          releases: {UpdateChannel.stable: release('1.4.0')},
        );
        final store = _CountingUpdateStore();
        final controller = controllerWith(updater: updater, store: store);
        controller.dispose();

        await controller.load();
        await controller.check();
        await controller.download();
        await controller.installAndRestart();

        expect(store.channelReads, 0);
        expect(updater.checkCount, 0);
        expect(updater.downloadCount, 0);
        expect(updater.installCount, 0);
      },
    );

    test('an updater cleanup failure cannot break controller disposal', () {
      final controller = controllerWith(updater: _ThrowingDiscardUpdater());

      expect(controller.dispose, returnsNormally);
    });

    test('progress is reported as it arrives', () async {
      final seen = <double>[];
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          releases: {UpdateChannel.stable: release('1.4.0')},
          progressSteps: const [0.25, 0.5, 0.75],
        ),
      );
      controller.addListener(() {
        if (controller.status == UpdateStatus.downloading) {
          seen.add(controller.progress);
        }
      });

      await controller.check();
      await controller.download();

      expect(seen, [0, 0.25, 0.5, 0.75]);
    });

    test(
      'progress that has not moved a whole percent does not notify',
      () async {
        var notifications = 0;
        final controller = controllerWith(
          updater: FakeUpdater(
            isSupported: true,
            releases: {UpdateChannel.stable: release('1.4.0')},
            progressSteps: const [0.5001, 0.5002, 0.5003, 0.75],
          ),
        );

        await controller.check();
        controller.addListener(() => notifications++);
        await controller.download();

        expect(notifications, 4);
      },
    );
  });
}

final class _ThrowingDiscardUpdater extends FakeUpdater {
  _ThrowingDiscardUpdater({super.releases}) : super(isSupported: true);

  @override
  Future<void> discard() => throw StateError('cleanup failed');
}
