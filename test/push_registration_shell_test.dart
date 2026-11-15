import 'package:discourse_native/src/data/push_registration.dart';
import 'package:discourse_native/src/data/push_registration_ledger.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'Reader');

PushRegistration _registration(String token) =>
    PushRegistration(clientId: token, pushUrl: 'https://push.example/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sign-in records what it registered, a rotation prompts, and only the '
      'user starts the new authorization', () async {
    SharedPreferences.setMockInitialValues({});
    final authenticator = FakeAuthenticator(
      credentials: const UserApiCredentials(
        key: 'api-key',
        apiVersion: 4,
        push: true,
      ),
    )..currentPush = _registration('token-a');
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
      api: FakeDiscourseApi(user: _user, feeds: const {'/latest.json': []}),
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();

    await shell.connectCurrentInstance();
    await pumpEventQueue();
    final recorded = await const PushRegistrationLedger().read(_site, 'reader');
    expect(recorded?.fingerprint, pushTokenFingerprint('token-a'));
    expect(recorded?.accepted, isTrue);
    await shell.pushRegistrations.check();
    expect(shell.pushRegistrations.prompts, isEmpty);

    authenticator.currentPush = _registration('token-b');
    await shell.pushRegistrations.check();
    expect(shell.pushRegistrations.prompts.single.siteUrl, _site);
    expect(authenticator.connected, [_site]);

    await shell.reauthorizeNotifications(_site);
    await pumpEventQueue();
    expect(authenticator.connected, [_site, _site]);
    expect(shell.pushRegistrations.prompts, isEmpty);
    await shell.pushRegistrations.check();
    expect(shell.pushRegistrations.prompts, isEmpty);
  });
}
