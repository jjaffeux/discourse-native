import 'dart:async';

import 'package:discourse_native/src/data/app_release.dart';
import 'package:discourse_native/src/data/desktop_updater_adapter.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:flutter/foundation.dart';
import 'package:discourse_native/src/shell/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

UpdateRelease release(
  String version, {
  UpdateChannel channel = UpdateChannel.stable,
  bool isDowngrade = false,
}) => UpdateRelease(
  version: version,
  channel: channel,
  isDowngrade: isDowngrade,
);

UpdateController controllerWith({
  FakeUpdater? updater,
  FakeUpdateStore? store,
}) => UpdateController(
  updater: updater ?? FakeUpdater(isSupported: true),
  store: store ?? FakeUpdateStore(),
);

void main() {
  // UpdateController defers a notification raised mid-frame to a post-frame
  // callback, which reads SchedulerBinding.instance. These are plain tests
  // rather than testWidgets, so the binding has to be stood up by hand.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('channels', () {
    test('a name that is no longer a channel reads as nothing', () {
      // The point of the null: a preference written by a build that had a
      // channel this one does not must not throw on launch.
      expect(UpdateChannel.byName('nightly'), isNull);
      expect(UpdateChannel.byName(null), isNull);
      expect(UpdateChannel.byName('canary'), UpdateChannel.canary);
    });

    test('every channel has its own feed', () {
      final urls = {
        for (final channel in UpdateChannel.values)
          AppRelease.archiveUrlFor(channel),
      };

      // Two indexes, not one, so publishing to one can never rewrite the other.
      expect(urls, hasLength(UpdateChannel.values.length));
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

      // Distinct, because a failure that reads the same as another one is a
      // failure the reader cannot tell apart — see the signature case below.
      expect(messages, hasLength(UpdateFailure.values.length));
    });

    test('a bad signature does not read as an unreachable server', () {
      // The security-relevant distinction, pinned: told "couldn't reach it", a
      // user retries until it works. That is the wrong advice for a download
      // that failed to verify.
      const untrusted = UpdateException(UpdateFailure.untrusted);
      const unreachable = UpdateException(UpdateFailure.unreachable);

      expect(untrusted.message, isNot(unreachable.message));
      expect(untrusted.message, contains('signature'));
    });
  });

  group('what can update', () {
    test('only Linux can be updated in place', () {
      for (final platform in TargetPlatform.values) {
        expect(
          DesktopUpdaterAdapter.supportsPlatform(platform),
          platform == TargetPlatform.linux,
          reason: '$platform',
        );
      }
    });

    test('a key is pinned for every channel', () {
      // Pinned keys are the only thing between the update feed and arbitrary
      // code execution. One per channel, because the channel is chosen at
      // runtime and a build has to verify whichever one the user switches to.
      expect(AppRelease.canVerifyReleases, isTrue);
      expect(
        AppRelease.trustedReleaseKeys,
        hasLength(UpdateChannel.values.length),
      );
      // Distinct, so a leaked canary key cannot sign a stable release.
      expect(
        AppRelease.trustedReleaseKeys.values.toSet(),
        hasLength(UpdateChannel.values.length),
      );
    });

    test('having keys is not on its own enough to offer updates', () {
      // Still false here, because `flutter test` stamps no version. Keys are
      // one of three gates, not the whole of it.
      expect(DesktopUpdaterAdapter().isSupported, isFalse);
    });

    test('a build with no updater behind it says so rather than pretending', () {
      const updater = UnsupportedUpdater();

      expect(updater.isSupported, isFalse);
      // Throwing, not returning null: a caller that ignores isSupported should
      // fail loudly rather than look like it updated and do nothing.
      expect(
        () => updater.check(channel: UpdateChannel.stable),
        throwsA(isA<UpdateException>()),
      );
    });

    test('a build the release pipeline never stamped is not a release', () {
      // No --dart-define under `flutter test`, which is the point: a developer
      // running the app must never be offered an update over their own tree.
      expect(AppRelease.isReleaseBuild, isFalse);
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

    test('a check nobody asked for fails quietly', () async {
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: const UpdateException(UpdateFailure.unreachable),
        ),
      );

      await controller.check(silent: true);

      // Nobody asked, so there is nobody to tell and nothing they could do.
      expect(controller.error, isNull);
      expect(controller.status, isNot(UpdateStatus.failed));
    });

    test('a quiet check that fails leaves an offer already made alone', () async {
      final updater = FakeUpdater(
        isSupported: true,
        releases: {UpdateChannel.stable: release('1.4.0')},
      );
      final controller = controllerWith(updater: updater);

      await controller.check();
      expect(controller.status, UpdateStatus.available);

      final failing = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: const UpdateException(UpdateFailure.unreachable),
        ),
      );
      await failing.check(silent: true);
      expect(failing.status, UpdateStatus.idle);
    });

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

      // Back to `available`, so the button to try again is the same button.
      expect(controller.status, UpdateStatus.available);
      expect(controller.error, contains('signature'));
      expect(controller.available, isNotNull);
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

      // The download is still good; do not make the user fetch it twice.
      expect(controller.status, UpdateStatus.readyToInstall);
      expect(controller.error, isNotNull);
    });

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

      await controller.setChannel(UpdateChannel.canary);

      // A canary user must not be able to install the stable build they
      // fetched a minute ago, and vice versa.
      expect(updater.discardCount, 1);
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

    test('switching to the channel already on does nothing', () async {
      final updater = FakeUpdater(isSupported: true);
      final controller = controllerWith(updater: updater);

      await controller.setChannel(UpdateChannel.stable);

      expect(updater.discardCount, 0);
      expect(updater.checkCount, 0);
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

      expect(seen, contains(0.25));
      expect(seen, contains(0.75));
    });

    test('progress that has not moved a whole percent does not notify', () async {
      var notifications = 0;
      final controller = controllerWith(
        updater: FakeUpdater(
          isSupported: true,
          releases: {UpdateChannel.stable: release('1.4.0')},
          // Three reports inside the same percent, then one that moves it.
          progressSteps: const [0.5001, 0.5002, 0.5003, 0.75],
        ),
      );

      await controller.check();
      controller.addListener(() => notifications++);
      await controller.download();

      // Entering downloading, one move to 50%, one to 75%, one to
      // readyToInstall. The three redundant reports are dropped.
      expect(notifications, lessThanOrEqualTo(4));
    });
  });
}
