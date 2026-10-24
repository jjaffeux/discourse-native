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
  Completer<UserCard>? cardGate;

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    if (cardGate case final gate?) {
      cardsRequested.add(username);
      return gate.future;
    }
    return super.userCard(
      siteUrl: siteUrl,
      username: username,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

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

Future<ShellController> _makeShell(_StatusApi api) async {
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
    final shell = await _makeShell(api);
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
      final shell = await _makeShell(api);
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
  for (final clear in [false, true]) {
    test(
      'old startup preserves a newer own live ${clear ? 'clear' : 'status'}',
      () async {
        final api = _StatusApi()..currentGate = Completer<DiscourseUser>();
        final shell = await _makeShell(api);
        addTearDown(shell.dispose);
        FakeSiteTracker.built.single.deliverPluginMessage('/user-status', {
          '7': clear ? null : {'description': 'Live now', 'emoji': 'house'},
        });
        api.currentGate!.complete(
          const DiscourseUser(
            id: 7,
            username: 'reader',
            status: UserStatus(description: 'Old', emoji: 'clock1'),
          ),
        );
        await pumpEventQueue();
        expect(
          shell.currentInstance!.user!.status?.description,
          clear ? null : 'Live now',
        );
        expect(
          shell.userStatuses
              .statusFor(site, 7, shell.currentInstance!.user!.status)
              ?.description,
          clear ? null : 'Live now',
        );
      },
    );
  }

  test('old startup preserves a confirmed own clear', () async {
    final api = _StatusApi()..currentGate = Completer<DiscourseUser>();
    final shell = await _makeShell(api);
    addTearDown(shell.dispose);
    expect(await shell.clearUserStatus(site), isNull);
    api.currentGate!.complete(
      const DiscourseUser(
        id: 7,
        username: 'reader',
        status: UserStatus(description: 'Old', emoji: 'clock1'),
      ),
    );
    await pumpEventQueue();
    expect(shell.currentInstance!.user!.status, isNull);
    expect(
      shell.userStatuses.statusFor(
        site,
        7,
        const UserStatus(description: 'Old', emoji: 'clock1'),
      ),
      isNull,
    );
  });

  test(
    'card dispatched before a live delivery keeps the live status',
    () async {
      final api = _StatusApi()..cardGate = Completer<UserCard>();
      final shell = await _makeShell(api);
      addTearDown(shell.dispose);
      final read = shell.loadUserCard('bob', siteUrl: site, force: true);
      await pumpEventQueue();
      shell.userStatuses.applyMessage(site, {
        '42': {'description': 'Live now', 'emoji': 'house'},
      });
      api.cardGate!.complete(
        const UserCard(
          id: 42,
          username: 'bob',
          name: 'Fresh name',
          status: UserStatus(description: 'Old', emoji: 'clock1'),
        ),
      );
      await read;
      final card = shell.userCard('bob', siteUrl: site)!;
      expect(card.name, 'Fresh name');
      expect(card.status?.description, 'Live now');
    },
  );

  for (final clear in [false, true]) {
    test(
      'fresh own card synchronizes canonical and badge ${clear ? 'clear' : 'status'}',
      () async {
        final api = _StatusApi()..currentGate = Completer<DiscourseUser>();
        final shell = await _makeShell(api);
        addTearDown(shell.dispose);
        await shell.setUserStatus(
          site,
          description: 'Previous',
          emoji: 'house',
        );
        api.cards['reader'] = UserCard(
          id: 7,
          username: 'reader',
          status: clear
              ? null
              : const UserStatus(description: 'Fresh', emoji: 'book'),
        );
        await shell.loadUserCard('reader', siteUrl: site, force: true);
        expect(
          shell.currentInstance!.user!.status?.description,
          clear ? null : 'Fresh',
        );
        expect(
          shell.userStatuses
              .statusFor(
                site,
                7,
                const UserStatus(description: 'Previous', emoji: 'house'),
              )
              ?.description,
          clear ? null : 'Fresh',
        );
        api.currentGate!.complete(
          const DiscourseUser(id: 7, username: 'reader'),
        );
        await pumpEventQueue();
        expect(
          shell.currentInstance!.user!.status?.description,
          clear ? null : 'Fresh',
        );
      },
    );
  }

  test('expired fresh card replaces a live status and stays hidden', () async {
    final api = _StatusApi();
    final shell = await _makeShell(api);
    addTearDown(shell.dispose);
    shell.userStatuses.record(
      site,
      42,
      const UserStatus(description: 'Previous', emoji: 'house'),
    );
    api.cards['bob'] = UserCard(
      id: 42,
      username: 'bob',
      status: UserStatus(
        description: 'Expired',
        emoji: 'book',
        endsAt: DateTime.utc(2000),
      ),
    );
    await shell.loadUserCard('bob', siteUrl: site, force: true);
    expect(
      shell.userStatuses.statusFor(
        site,
        42,
        const UserStatus(description: 'Previous', emoji: 'house'),
      ),
      isNull,
    );
  });

  test(
    'retirement during card status publication prevents card storage',
    () async {
      final api = _StatusApi();
      final shell = await _makeShell(api);
      addTearDown(shell.dispose);
      api.cards['bob'] = const UserCard(
        id: 42,
        username: 'bob',
        status: UserStatus(description: 'Fresh', emoji: 'book'),
      );
      shell.userStatuses.addListener(() => shell.lifecycle.invalidate(site));
      await shell.loadUserCard('bob', siteUrl: site, force: true);
      expect(shell.userCard('bob', siteUrl: site), isNull);
    },
  );
  test(
    'newer status during card notification is also stored on the card',
    () async {
      final api = _StatusApi();
      final shell = await _makeShell(api);
      addTearDown(shell.dispose);
      api.cards['bob'] = const UserCard(
        id: 42,
        username: 'bob',
        status: UserStatus(description: 'Snapshot', emoji: 'book'),
      );
      var delivered = false;
      shell.userStatuses.addListener(() {
        if (delivered) return;
        delivered = true;
        shell.userStatuses.record(
          site,
          42,
          const UserStatus(description: 'Newer live', emoji: 'house'),
        );
      });
      await shell.loadUserCard('bob', siteUrl: site, force: true);
      expect(
        shell.userCard('bob', siteUrl: site)!.status?.description,
        'Newer live',
      );
    },
  );
}
