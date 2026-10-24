import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const site = 'https://meta.discourse.org';

class _StatusApi extends FakeDiscourseApi {
  _StatusApi()
    : super(
        cards: {},
        user: const DiscourseUser(id: 7, username: 'reader'),
        feeds: const {'/latest.json': []},
        siteConfigs: const {site: SiteConfig(userStatusEnabled: true)},
      );
  Completer<DiscourseUser>? currentGate;
  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    currentUserRequests.add(siteUrl);
    return currentGate == null
        ? const DiscourseUser(id: 7, username: 'reader')
        : currentGate!.future;
  }
}

Future<ShellController> makeShell(_StatusApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(
        user: const DiscourseUser(id: 7, username: 'reader'),
        config: const SiteConfig(userStatusEnabled: true),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fresh profile status replaces an earlier live clear', () async {
    final api = _StatusApi();
    final shell = await makeShell(api);
    addTearDown(shell.dispose);
    shell.userStatuses.applyMessage(site, {'42': null});
    api.cards['bob'] = const UserCard(
      id: 42,
      username: 'bob',
      status: UserStatus(
        description: 'Available now',
        emoji: 'house',
        messageBusLastId: 100,
      ),
    );
    await shell.loadUserCard('bob', siteUrl: site, force: true);
    final fresh = shell.userCard('bob', siteUrl: site)!;
    expect(api.cardsRequested, ['bob']);
    expect(fresh.status!.description, 'Available now');
    final shown = shell.userStatuses.statusFor(site, fresh.id, fresh.status);
    expect(shown?.description, 'Available now');
  });
  test(
    'startup current-user snapshot preserves an accepted new status',
    () async {
      final api = _StatusApi()..currentGate = Completer<DiscourseUser>();
      final shell = await makeShell(api);
      addTearDown(shell.dispose);
      expect(api.currentUserRequests, isNotEmpty);
      expect(
        await shell.setUserStatus(
          site,
          description: 'Working now',
          emoji: 'house',
        ),
        isNull,
      );
      expect(shell.currentInstance!.user!.status!.description, 'Working now');
      api.currentGate!.complete(const DiscourseUser(id: 7, username: 'reader'));
      await pumpEventQueue();
      final user = shell.currentInstance!.user!;
      expect(user.status?.description, 'Working now');
      expect(
        shell.userStatuses.statusFor(site, 7, user.status)!.description,
        'Working now',
      );
    },
  );
}
