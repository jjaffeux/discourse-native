import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _initialStatus = UserStatus(description: 'Before', emoji: 'house');
final _start = DateTime.utc(2030, 1, 1, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('status notification pause', () {
    for (final (name, remaining, responseDelay, minutes) in [
      ('sub-minute expiry', const Duration(seconds: 10), Duration.zero, 1),
      (
        'one-hour expiry after a delayed response',
        const Duration(hours: 1),
        const Duration(seconds: 3),
        60,
      ),
      (
        'response arriving in the final minute',
        const Duration(minutes: 2),
        const Duration(minutes: 1, seconds: 58),
        1,
      ),
    ]) {
      test('saves status and covers its $name', () async {
        var now = _start;
        final endsAt = now.add(remaining);
        final serverUntil = DateTime.utc(2030, 1, 1, 14);
        final api = _StatusApi(pauseUntil: serverUntil);
        final shell = await _load(api, clock: () => now);

        final write = _setStatus(shell, endsAt: endsAt);
        await api.statusStarted.future;
        expect(api.calls, ['status']);
        expect(shell.currentInstance?.user?.status, _initialStatus);
        now = now.add(responseDelay);
        api.statusReply.complete();

        expect(await write, isNull);
        expect(api.calls, ['status', 'pause']);
        expect(api.userStatusesSet, [
          (description: 'Working', emoji: 'house', endsAt: endsAt),
        ]);
        expect(
          api.doNotDisturbDurations.map((duration) => duration.wireValue),
          [minutes],
        );
        final expected = UserStatus(
          description: 'Working',
          emoji: 'house',
          endsAt: endsAt,
        );
        expect(shell.currentInstance?.user?.status, expected);
        expect(shell.currentInstance?.user?.doNotDisturbUntil, serverUntil);
        expect(shell.doNotDisturb.stateFor(_site).until, serverUntil);
        expect(shell.userStatusWriteInFlight(_site), isFalse);
        final saved = (await shell.instanceStore.load()).single.user;
        expect(saved?.status, expected);
        expect(saved?.doNotDisturbUntil, serverUntil);
      });
    }

    for (final remaining in [
      Duration.zero,
      const Duration(microseconds: -1),
      const Duration(minutes: -1),
    ]) {
      test('rejects an expiry at $remaining before writing status', () async {
        final previousPause = _start.add(const Duration(hours: 2));
        final api = _StatusApi(initialPause: previousPause)
          ..statusReply.complete();
        final shell = await _load(api, clock: () => _start);

        expect(
          await _setStatus(shell, endsAt: _start.add(remaining)),
          'Choose a time in the future.',
        );
        expect(api.calls, isEmpty);
        expect(shell.currentInstance?.user?.status, _initialStatus);
        expect(shell.doNotDisturb.stateFor(_site).until, previousPause);
        expect(shell.userStatusWriteInFlight(_site), isFalse);
      });
    }

    for (final afterExpiry in [
      Duration.zero,
      const Duration(microseconds: 1),
    ]) {
      test(
        'keeps status success when the response arrives $afterExpiry after expiry',
        () async {
          var now = _start;
          final endsAt = now.add(const Duration(seconds: 10));
          final previousPause = now.add(const Duration(hours: 2));
          final api = _StatusApi(initialPause: previousPause);
          final shell = await _load(api, clock: () => now);

          final write = _setStatus(shell, endsAt: endsAt);
          await api.statusStarted.future;
          now = endsAt.add(afterExpiry);
          api.statusReply.complete();

          expect(await write, isNull);
          expect(api.calls, ['status']);
          final expected = UserStatus(
            description: 'Working',
            emoji: 'house',
            endsAt: endsAt,
          );
          expect(shell.currentInstance?.user?.status, expected);
          expect(shell.doNotDisturb.stateFor(_site).until, previousPause);
          expect(shell.userStatusWriteInFlight(_site), isFalse);
          final saved = (await shell.instanceStore.load()).single.user;
          expect(saved?.status, expected);
          expect(saved?.doNotDisturbUntil, previousPause);
        },
      );
    }

    test('keeps an indefinite status paused until the eternal day', () async {
      var now = _start;
      final api = _StatusApi(pauseUntil: eternalDoNotDisturbUntil);
      final shell = await _load(api, clock: () => now);

      final write = _setStatus(shell);
      await api.statusStarted.future;
      now = now.add(const Duration(seconds: 3));
      api.statusReply.complete();

      expect(await write, isNull);
      expect(api.calls, ['status', 'pause']);
      expect(
        api.doNotDisturbDurations.single.minutes,
        eternalDoNotDisturbUntil.difference(_start).inMinutes,
      );
      expect(shell.doNotDisturb.stateFor(_site).isEternal, isTrue);
      expect(
        shell.currentInstance?.user?.status,
        const UserStatus(description: 'Working', emoji: 'house'),
      );
    });

    test(
      'does not pause a replacement account after a stale response',
      () async {
        final api = _StatusApi();
        final shell = await _load(api, clock: () => _start);

        final write = _setStatus(
          shell,
          endsAt: _start.add(const Duration(seconds: 10)),
        );
        await api.statusStarted.future;
        await shell.disconnectCurrentInstance();
        await shell.connectCurrentInstance();
        await pumpEventQueue();
        api.statusReply.complete();

        expect(await write, isNull);
        expect(api.calls, ['status']);
        expect(shell.currentInstance?.user?.status, _initialStatus);
        expect(shell.doNotDisturb.stateFor(_site).until, isNull);
        expect(shell.userStatusWriteInFlight(_site), isFalse);
      },
    );
  });
}

Future<String?> _setStatus(ShellController shell, {DateTime? endsAt}) =>
    shell.setUserStatus(
      _site,
      description: 'Working',
      emoji: 'house',
      endsAt: endsAt,
      pauseNotifications: true,
    );

Future<ShellController> _load(
  _StatusApi api, {
  required DateTime Function() clock,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(
        user: api.user,
        config: const SiteConfig(userStatusEnabled: true),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    clock: clock,
  );
  addTearDown(shell.dispose);
  addTearDown(() {
    if (!api.statusReply.isCompleted) api.statusReply.complete();
  });
  await shell.load();
  await pumpEventQueue();
  return shell;
}

class _StatusApi extends FakeDiscourseApi {
  _StatusApi({DateTime? initialPause, DateTime? pauseUntil})
    : super(
        user: DiscourseUser(
          id: 7,
          username: 'reader',
          status: _initialStatus,
          doNotDisturbUntil: initialPause,
        ),
        doNotDisturbUntil: pauseUntil,
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
      );

  final calls = <String>[];
  final statusStarted = Completer<void>();
  final statusReply = Completer<void>();

  @override
  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) async {
    calls.add('status');
    await super.setUserStatus(
      siteUrl: siteUrl,
      apiKey: apiKey,
      description: description,
      emoji: emoji,
      endsAt: endsAt,
      clientId: clientId,
    );
    statusStarted.complete();
    await statusReply.future;
  }

  @override
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  }) {
    calls.add('pause');
    return super.enterDoNotDisturb(
      siteUrl: siteUrl,
      apiKey: apiKey,
      duration: duration,
      clientId: clientId,
    );
  }

  @override
  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    calls.add('resume');
    return super.leaveDoNotDisturb(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
