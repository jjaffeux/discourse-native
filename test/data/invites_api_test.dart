import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/models/invite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/invite_fixtures.dart';

void main() {
  test(
    'uses authenticated core routes, filters and offsets under subfolder sites',
    () async {
      final requests = <http.Request>[];
      final transport = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(invitePage([inviteRow(1)])), 200);
        }),
      );
      addTearDown(transport.close);
      final page = await InvitesApi(transport).list(
        siteUrl: inviteSite.url,
        username: 'Alice+Ops',
        apiKey: 'key',
        clientId: 'client',
        filter: InviteFilter.expired,
        search: ' Sam+test@example.com ',
        offset: 50,
      );
      expect(page.invites.single.id, 1);
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.pathSegments, [
        'community',
        'u',
        'alice+ops',
        'invited.json',
      ]);
      expect(request.url.queryParameters, {
        'filter': 'expired',
        'offset': '50',
        'search': 'Sam+test@example.com',
      });
      expect(request.headers['user-api-key'], 'key');
      expect(request.headers['user-api-client-id'], 'client');
    },
  );

  test(
    'creates links without email and sends email only when requested',
    () async {
      final transport = InviteTransport();
      final api = InvitesApi(transport);
      final expires = DateTime.utc(2026, 12, 1);
      await api.create(
        siteUrl: inviteSite.url,
        apiKey: 'key',
        draft: InviteDraft(
          description: ' Meetup ',
          maxRedemptions: 10,
          expiresAt: expires,
        ),
      );
      await api.create(
        siteUrl: inviteSite.url,
        apiKey: 'key',
        draft: InviteDraft(
          email: ' sam@example.com ',
          customMessage: ' Join us ',
          maxRedemptions: 10,
          expiresAt: expires,
          sendEmail: true,
        ),
      );
      await api.create(
        siteUrl: inviteSite.url,
        apiKey: 'key',
        draft: InviteDraft(
          email: 'sam@example.com',
          maxRedemptions: 1,
          expiresAt: expires,
        ),
      );
      expect(
        transport.requests.map((request) => (request.method, request.path)),
        [
          ('POST', '/invites.json'),
          ('POST', '/invites.json'),
          ('POST', '/invites.json'),
        ],
      );
      expect(transport.requests.map((request) => request.body), [
        {
          'description': 'Meetup',
          'max_redemptions_allowed': 10,
          'expires_at': '2026-12-01T00:00:00.000Z',
          'skip_email': true,
        },
        {
          'email': 'sam@example.com',
          'description': '',
          'custom_message': 'Join us',
          'max_redemptions_allowed': 1,
          'expires_at': '2026-12-01T00:00:00.000Z',
          'send_email': true,
        },
        {
          'email': 'sam@example.com',
          'description': '',
          'custom_message': '',
          'max_redemptions_allowed': 1,
          'expires_at': '2026-12-01T00:00:00.000Z',
          'skip_email': true,
        },
      ]);
    },
  );

  test('resends by email and deletes by invitation ID', () async {
    final transport = InviteTransport();
    final api = InvitesApi(transport);
    await api.resend(
      siteUrl: inviteSite.url,
      apiKey: 'key',
      email: 'sam@example.com',
    );
    await api.remove(siteUrl: inviteSite.url, apiKey: 'key', inviteId: 42);
    expect(
      transport.requests.map((request) => (request.method, request.path)),
      [('POST', '/invites/reinvite.json'), ('DELETE', '/invites.json')],
    );
    expect(transport.requests.map((request) => request.body), [
      {'email': 'sam@example.com'},
      {'id': 42},
    ]);
  });
}
