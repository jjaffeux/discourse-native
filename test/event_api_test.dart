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
}
