import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final clear in [false, true]) {
    final action = clear ? 'clear' : 'set';
    for (final outcome in ['success', 'write failure', 'unexpected failure']) {
      test('$action old $outcome leaves replacement busy', () async {
        final api = _GatedStatusApi();
        final shell = await _load(api);
        addTearDown(shell.dispose);
        final old = _write(shell, clear);
        await pumpEventQueue();
        expect(api.requests, hasLength(1));

        await shell.disconnectCurrentInstance();
        await shell.connectCurrentInstance();
        await pumpEventQueue();
        final replacement = _write(shell, clear);
        await pumpEventQueue();
        expect(api.requests, hasLength(2));

        switch (outcome) {
          case 'success':
            api.requests.first.complete();
          case 'write failure':
            api.requests.first.completeError(
              const WriteException(WriteFailure.forbidden),
            );
          case 'unexpected failure':
            api.requests.first.completeError(StateError('old account'));
        }
        expect(await old, isNull);
        expect(shell.userStatusWriteInFlight(_site), isTrue);
        expect(
          await _write(shell, !clear),
          'Another status change is still finishing.',
        );
        expect(api.requests, hasLength(2));
        expect(api.doNotDisturbResumes, isEmpty);
        expect(shell.currentInstance?.user?.status, isNull);

        api.requests.last.complete();
        await pumpEventQueue();
        expect(api.doNotDisturbResumes, [_site]);
        expect(shell.userStatusWriteInFlight(_site), isTrue);
        expect(
          await _write(shell, !clear),
          'Another status change is still finishing.',
        );
        api.resume.complete();
        expect(await replacement, isNull);
        expect(shell.userStatusWriteInFlight(_site), isFalse);
        expect(api.doNotDisturbResumes, [_site]);
        expect(
          shell.currentInstance?.user?.status?.description,
          clear ? isNull : 'Working',
        );
      });
    }

    test(
      '$action stops before credentials when a listener retires it',
      () async {
        final api = _GatedStatusApi();
        final auth = _CountingAuthenticator()..keys[_site] = 'key';
        final shell = await _load(api, auth: auth);
        addTearDown(shell.dispose);
        final reads = auth.reads;
        var invalidated = false;
        shell.addListener(() {
          if (!invalidated && shell.userStatusWriteInFlight(_site)) {
            invalidated = true;
            shell.lifecycle.invalidate(_site);
          }
        });

        expect(await _write(shell, clear), isNull);
        expect(auth.reads, reads);
        expect(api.requests, isEmpty);
        expect(shell.userStatusWriteInFlight(_site), isFalse);
      },
    );
  }
}

Future<String?> _write(ShellController shell, bool clear) => clear
    ? shell.clearUserStatus(_site)
    : shell.setUserStatus(
        _site,
        description: 'Working',
        emoji: 'house',
        pauseNotifications: false,
      );

Future<ShellController> _load(
  _GatedStatusApi api, {
  FakeAuthenticator? auth,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(
        user: DiscourseUser(
          id: 7,
          username: 'reader',
          doNotDisturbUntil: DateTime.utc(2030),
        ),
        config: const SiteConfig(userStatusEnabled: true),
      ),
    ]),
    api: api,
    authenticator: auth ?? (FakeAuthenticator()..keys[_site] = 'key'),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

class _GatedStatusApi extends FakeDiscourseApi {
  _GatedStatusApi()
    : super(
        user: DiscourseUser(
          id: 7,
          username: 'reader',
          doNotDisturbUntil: DateTime.utc(2030),
        ),
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
      );

  final requests = <Completer<void>>[];
  final resume = Completer<void>();

  @override
  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    doNotDisturbResumes.add(siteUrl);
    return resume.future;
  }

  Future<void> _request() {
    final request = Completer<void>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) => _request();

  @override
  Future<void> clearUserStatus({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) => _request();
}

class _CountingAuthenticator extends FakeAuthenticator {
  int reads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads++;
    return super.apiKeyFor(siteUrl);
  }
}
