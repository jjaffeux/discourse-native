import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/invite.dart';
import 'package:discourse_native/src/shell/invites_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/invite_fixtures.dart';

void main() {
  late InviteTransport transport;
  late SiteLifecycle lifecycle;
  late InviteCredentials credentials;
  late InvitesController controller;
  final draft = InviteDraft(maxRedemptions: 10, expiresAt: DateTime.utc(2027));

  setUp(() {
    transport = InviteTransport();
    lifecycle = SiteLifecycle();
    credentials = InviteCredentials();
    controller = InvitesController(
      api: InvitesApi(transport),
      credentials: credentials,
      instance: inviteSite,
      lifecycle: lifecycle,
    );
    addTearDown(controller.dispose);
  });

  test(
    'retains a failed next page and retries at its original offset',
    () async {
      transport.onGet = (_) => invitePage([inviteRow(1)], pending: 2);
      await controller.load();
      transport.onGet = (_) => throw StateError('offline');
      await controller.load(more: true);
      expect(controller.invites.map((invite) => invite.id), [1]);
      expect(controller.error, isNotNull);
      expect(controller.loaded, isTrue);
      transport.onGet = (_) => invitePage([inviteRow(2)], pending: 2);
      await controller.load(more: true);
      expect(controller.invites.map((invite) => invite.id), [1, 2]);
      expect(controller.hasMore, isFalse);
      expect(controller.error, isNull);
      expect(
        transport.requests.map(
          (request) => Uri.parse(request.path).queryParameters['offset'],
        ),
        ['0', '1', '1'],
      );
    },
  );

  test('a delayed filter response cannot replace a newer search', () async {
    final old = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    transport.onGet = (_) {
      started.complete();
      return old.future;
    };
    final first = controller.load();
    await started.future;
    transport.onGet = (_) => invitePage([inviteRow(2)], expired: 1);
    await controller.load(filter: InviteFilter.expired, search: 'sam');
    old.complete(invitePage([inviteRow(1)]));
    await first;
    expect(controller.filter, InviteFilter.expired);
    expect(controller.search, 'sam');
    expect(controller.invites.map((invite) => invite.id), [2]);
    expect(controller.loading, isFalse);
  });

  test(
    'falls back to redeemed users when invite details are withheld',
    () async {
      transport.onGet = (request) =>
          Uri.parse(request.path).queryParameters['filter'] == 'pending'
          ? invitePage([], canSeeDetails: false, redeemed: 1)
          : invitePage(
              [
                {
                  'id': 1,
                  'user': {'id': 2, 'username': 'sam'},
                },
              ],
              canSeeDetails: false,
              redeemed: 1,
            );
      await controller.load();
      expect(controller.filter, InviteFilter.redeemed);
      expect(controller.invites.single.username, 'sam');
      expect(controller.canSeeDetails, isFalse);
    },
  );

  test('removal refreshes the list and its server counts', () async {
    transport.onGet = (_) => invitePage([inviteRow(1)]);
    await controller.load();
    final invite = controller.invites.single;
    transport.onGet = (_) => invitePage([]);
    expect(await controller.remove(invite), isTrue);
    expect(controller.invites, isEmpty);
    expect(controller.counts[InviteFilter.pending], 0);
    expect(controller.message, 'Invite removed.');
  });

  test(
    'a write refresh supersedes reads started before the invite was created',
    () async {
      final old = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      transport.onGet = (_) {
        started.complete();
        return old.future;
      };
      final loading = controller.load();
      await started.future;
      transport.onGet = (_) => invitePage([inviteRow(99)]);
      expect((await controller.create(draft))?.id, 99);
      old.complete(invitePage([]));
      await loading;
      expect(controller.invites.map((invite) => invite.id), [99]);
      expect(controller.counts[InviteFilter.pending], 1);
    },
  );

  test(
    'does not publish a list returned after the account session is retired',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      transport.onGet = (_) {
        started.complete();
        return gate.future;
      };
      final loading = controller.load();
      await started.future;
      lifecycle.invalidate(inviteSite.url);
      gate.complete(invitePage([inviteRow(1)]));
      await loading;
      expect(controller.invites, isEmpty);
      expect(controller.loaded, isFalse);
    },
  );

  test(
    'preserves a server error instead of reporting an empty invite list',
    () async {
      transport.onGet = (_) => {
        'invites': <Object?>[],
        'can_see_invite_details': false,
        'error': 'Invites are disabled on this site.',
      };
      await controller.load();
      expect(controller.error, 'Invites are disabled on this site.');
      expect(controller.loaded, isFalse);
      expect(controller.filter, InviteFilter.pending);
      expect(transport.requests.length, 1);
    },
  );

  test('serializes writes and presents server validation errors', () async {
    final write = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    transport.onWrite = (_) {
      started.complete();
      return write.future;
    };
    final first = controller.create(draft);
    await started.future;
    expect(await controller.create(draft), isNull);
    write.completeError(
      const WriteException(
        WriteFailure.validation,
        errors: ['This email already belongs to a user.'],
      ),
    );
    expect(await first, isNull);
    expect(controller.actionError, 'This email already belongs to a user.');
    expect(controller.writing, isFalse);
    expect(transport.requests.length, 1);
  });

  for (final credential in ['key', 'client ID']) {
    test(
      'account replacement while reading $credential prevents dispatch',
      () async {
        final gate = Completer<String>();
        final started = Completer<void>();
        Future<String> read() {
          started.complete();
          return gate.future;
        }

        if (credential == 'key') {
          credentials.readKey = read;
        } else {
          credentials.readClientId = read;
        }
        final create = controller.create(draft);
        await started.future;
        lifecycle.invalidate(inviteSite.url);
        gate.complete('replacement');
        expect(await create, isNull);
        expect(transport.requests, isEmpty);
      },
    );
  }

  test(
    'a completed write cannot refresh or report success for a retired account',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      transport.onWrite = (_) {
        started.complete();
        return gate.future;
      };
      final create = controller.create(draft);
      await started.future;
      lifecycle.invalidate(inviteSite.url);
      gate.complete(inviteRow(1));
      expect(await create, isNull);
      expect(controller.message, isNull);
      expect(transport.requests.map((request) => request.method), ['POST']);
    },
  );

  test(
    'does not remove an invite without the server deletion permission',
    () async {
      transport.onGet = (_) => invitePage([inviteRow(1, canDelete: false)]);
      await controller.load();
      expect(await controller.remove(controller.invites.single), isFalse);
      expect(transport.requests.map((request) => request.method), ['GET']);
    },
  );
}
