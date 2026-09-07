import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  const credentials = PluginRequestCredentials(
    apiKey: 'key',
    clientId: 'client',
  );
  test(
    'event reads and self RSVP use the event post ID and exact nested payload',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /discourse-post-event/events/42.json': {'event': eventJson()},
          'POST /discourse-post-event/events/42/invitees.json': {
            'invitee': watching(recurring: true),
          },
          'PUT /discourse-post-event/events/42/invitees/83.json': {
            'invitee': watching(status: 'interested'),
          },
          'DELETE /discourse-post-event/events/42/invitees/83.json': {
            'success': 'OK',
          },
          'POST /discourse-post-event/events/42/invite': {'success': 'OK'},
        },
      );
      final api = EventApi(transport);
      expect((await api.get(eventSite, 42, credentials)).topicId, 700);
      await api.respond(
        eventSite,
        42,
        apiKey: 'key',
        clientId: 'client',
        status: 'going',
        recurring: true,
      );
      await api.respond(
        eventSite,
        42,
        apiKey: 'key',
        clientId: 'client',
        status: 'interested',
        recurring: false,
        inviteeId: 83,
      );
      await api.withdraw(eventSite, 42, 83, apiKey: 'key', clientId: 'client');
      await api.invite(
        eventSite,
        42,
        ['lee', 'sam'],
        apiKey: 'key',
        clientId: 'client',
      );
      expect(transport.writes.map((r) => r.body), [
        {
          'invitee': {'status': 'going', 'recurring': true},
        },
        {
          'invitee': {'status': 'interested', 'recurring': false},
        },
        <String, Object?>{},
        {
          'invites': ['lee', 'sam'],
        },
      ]);
      expect(
        transport.requests.every(
          (r) => r.apiKey == 'key' && r.clientId == 'client',
        ),
        isTrue,
      );
      expect(transport.requests.any((r) => r.path.contains('700')), isFalse);
    },
  );

  test('null-clearing and bad IDs are not emitted to the server', () async {
    final transport = RecordingPluginTransport();
    final api = EventApi(transport);
    await expectLater(
      api.respond(
        eventSite,
        42,
        apiKey: 'key',
        clientId: 'client',
        status: 'null',
        recurring: false,
      ),
      throwsA(isA<WriteException>()),
    );
    await expectLater(
      api.withdraw(eventSite, 42, 0, apiKey: 'key', clientId: 'client'),
      throwsArgumentError,
    );
    expect(transport.writes, isEmpty);
  });

  test(
    'show rejects a mismatched event and lists request full server-filtered details',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /discourse-post-event/events/42.json': {
            'event': eventJson(overrides: {'id': 43}),
          },
        },
      );
      final api = EventApi(transport);
      await expectLater(
        api.get(eventSite, 42, credentials),
        throwsFormatException,
      );
      const path =
          '/discourse-post-event/events.json?include_details=true&include_ongoing=true&order=asc&limit=200&attending_user=lee&include_interested=true&search=planning';
      transport.responses['GET $path'] = {
        'events': [eventJson()],
      };
      final result = await api.list(
        eventSite,
        credentials,
        attendingUser: 'lee',
        search: 'planning',
      );
      expect(result.single.id, 42);
      expect(transport.reads.last.path, path);
    },
  );

  group('event list date bounds', () {
    for (final (name, upcoming, after, before, dates) in [
      (
        'unbounded requests retain historical events',
        false,
        null,
        null,
        <String, String>{},
      ),
      (
        'upcoming requests use server now and retain an upper bound',
        true,
        null,
        DateTime.parse('2100-02-01T12:00:00+02:00'),
        {'after': 'now', 'before': '2100-02-01T10:00:00.000Z'},
      ),
      (
        'historical ranges retain both UTC bounds',
        false,
        DateTime.parse('2000-01-01T12:00:00+02:00'),
        DateTime.parse('2000-02-01T12:00:00+02:00'),
        {
          'after': '2000-01-01T10:00:00.000Z',
          'before': '2000-02-01T10:00:00.000Z',
        },
      ),
      (
        'an explicit lower bound takes precedence over upcoming',
        true,
        DateTime.parse('2000-01-01T12:00:00+02:00'),
        null,
        {'after': '2000-01-01T10:00:00.000Z'},
      ),
      (
        'an upper bound does not introduce an upcoming lower bound',
        false,
        null,
        DateTime.parse('2000-02-01T12:00:00+02:00'),
        {'before': '2000-02-01T10:00:00.000Z'},
      ),
    ]) {
      test(name, () async {
        final path = Uri(
          path: '/discourse-post-event/events.json',
          queryParameters: {
            'include_details': 'true',
            'include_ongoing': 'true',
            'order': 'asc',
            'limit': '200',
            ...dates,
          },
        ).toString();
        final transport = RecordingPluginTransport(
          responses: {
            'GET $path': {
              'events': [
                eventJson(
                  overrides: {
                    'recurrence': null,
                    'starts_at': '2000-01-02T10:00:00Z',
                    'ends_at': '2000-01-02T11:00:00Z',
                  },
                ),
              ],
            },
          },
        );

        final result = await EventApi(transport).list(
          eventSite,
          credentials,
          upcoming: upcoming,
          after: after,
          before: before,
        );

        expect(result.map((event) => event.id), [42]);
        expect(transport.requests.map((r) => (r.method, r.path)), [
          ('GET', path),
        ]);
      });
    }
  });
}
