import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_directory_session.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  late _Transport transport;
  setUp(() {
    transport = _Transport();
    ports = EventTestPorts(transport: transport);
  });
  tearDown(() => ports.close());

  EventDirectorySession open({
    EventCalendarView view = EventCalendarView.schedule,
    int month = 9,
    String site = eventSite,
    bool mine = false,
  }) {
    final session = EventDirectorySession(
      controller: ports.controller,
      site: site,
      mine: mine,
      page: EventCalendarPage(view, DateTime.utc(2026, month, 8)),
    );
    addTearDown(session.dispose);
    return session;
  }

  test(
    'quarter queries preserve DST boundaries and deduplicate overlaps',
    () async {
      final session = open(view: EventCalendarView.year);
      await transport.waitFor(1);
      for (var i = 0; i < 4; i++) {
        transport.pending[i].complete({
          'events': [eventJson()],
        });
        await flush();
      }
      expect(
        transport.queries.map(
          (q) => (q.queryParameters['after'], q.queryParameters['before']),
        ),
        [
          ('2025-12-31T23:00:00.000Z', '2026-03-31T22:00:00.000Z'),
          ('2026-03-31T22:00:00.000Z', '2026-06-30T22:00:00.000Z'),
          ('2026-06-30T22:00:00.000Z', '2026-09-30T22:00:00.000Z'),
          ('2026-09-30T22:00:00.000Z', '2026-12-31T23:00:00.000Z'),
        ],
      );
      expect(session.loading, isFalse);
      expect(session.failed, isFalse);
      expect(session.occurrences.single.id, 42);
    },
  );

  for (final fails in [false, true]) {
    test(
      'superseded ${fails ? 'error' : 'success'} cannot end replacement loading',
      () async {
        final session = open(view: EventCalendarView.year);
        await transport.waitFor(1);
        session.show(
          EventCalendarPage(EventCalendarView.schedule, DateTime.utc(2026, 10)),
        );
        await transport.waitFor(2);
        if (fails) {
          transport.pending[0].completeError(StateError('old request'));
        } else {
          transport.pending[0].complete({
            'events': [eventJson()],
          });
        }
        await flush();
        expect(transport.queries, hasLength(2));
        expect(session.loading, isTrue);
        expect(session.failed, isFalse);
        expect(session.occurrences, isEmpty);
        transport.pending[1].complete({
          'events': [_event(99)],
        });
        await flush();
        expect(session.occurrences.single.id, 99);
        expect(session.loading, isFalse);
      },
    );
  }

  for (final change in ['account', 'foreground', 'timezone']) {
    test(
      '$change invalidation clears data and cancels remaining quarters',
      () async {
        ports.user = null;
        final session = open();
        await transport.waitFor(1);
        transport.pending[0].complete({
          'events': [eventJson()],
        });
        await flush();
        session.show(
          EventCalendarPage(EventCalendarView.year, DateTime.utc(2026)),
        );
        await transport.waitFor(2);
        expect(session.occurrences, isNotEmpty);
        switch (change) {
          case 'account':
            ports.controller.pluginCurrentUserRefreshed(eventSite);
          case 'foreground':
            ports.controller.setForeground(false);
            expect(transport.queries, hasLength(2));
            ports.controller.setForeground(true);
          case 'timezone':
            ports.environment.setDeviceTimezone('Europe/Paris');
        }
        await transport.waitFor(3);
        expect(session.occurrences, isEmpty);
        expect(session.loading, isTrue);
        transport.pending[1].complete({
          'events': [_event(88)],
        });
        await flush();
        expect(transport.queries, hasLength(3));
        expect(session.occurrences, isEmpty);
        for (var i = 2; i < 6; i++) {
          transport.pending[i].complete({
            'events': [_event(99)],
          });
          await flush();
        }
        expect(transport.queries, hasLength(6));
        expect(session.occurrences.single.id, 99);
        if (change == 'timezone') {
          expect(
            transport.queries[1].queryParameters['after'],
            '2026-01-01T00:00:00.000Z',
          );
          expect(
            transport.queries[2].queryParameters['after'],
            '2025-12-31T23:00:00.000Z',
          );
        }
      },
    );
  }

  test(
    'same range and settings changes do not reload; refresh can retry',
    () async {
      final session = open();
      await transport.waitFor(1);
      transport.pending[0].complete({
        'events': [eventJson()],
      });
      await flush();
      var notifications = 0;
      session.addListener(() => notifications++);
      session.show(
        EventCalendarPage(
          EventCalendarView.schedule,
          DateTime.utc(2026, 9, 25),
        ),
      );
      ports.settings = const EventSettings(
        enabled: true,
        calendarView: EventCalendarView.year,
      );
      ports.controller.setForeground(false);
      await flush();
      expect(transport.queries, hasLength(1));
      expect(notifications, 1);
      final retry = session.refresh();
      await transport.waitFor(2);
      expect(session.occurrences, isNotEmpty);
      transport.pending[1].completeError(StateError('offline'));
      await retry;
      expect(session.failed, isTrue);
      expect(session.loading, isFalse);
      expect(session.occurrences, isEmpty);
      final recovered = session.refresh();
      await transport.waitFor(3);
      expect(session.failed, isFalse);
      transport.pending[2].complete({
        'events': [eventJson()],
      });
      await recovered;
      expect(session.occurrences.single.id, 42);
    },
  );

  test('withdrawal removes an event from the loaded My Events directory', () async {
    var current = eventJson(overrides: {
      'is_public': true,
      'is_private': false,
      'watching_invitee': watching(),
    });
    transport.responders['GET /discourse-post-event/events/42.json'] =
        (_) => {'event': current};
    transport.responses['DELETE /discourse-post-event/events/42/invitees/83.json'] = {};
    final handle = ports.controller.acquire(eventSite, PostEvent.decode(current)!);
    addTearDown(handle.dispose);
    await handle.refresh();
    final session = open(mine: true);
    await transport.waitFor(1);
    transport.pending[0].complete({'events': [current]});
    await flush();
    expect(session.occurrences.single.watching?.status, 'going');
    current = {...current, 'watching_invitee': null};
    await handle.withdraw();
    expect(handle.event!.watching, isNull);
    expect(handle.error, isNull);
    await transport.waitFor(2);
    transport.pending[1].complete({'events': <Object?>[]});
    await flush();
    expect(session.occurrences, isEmpty);
    expect(session.loading, isFalse);
    await flush();
    expect(transport.queries, hasLength(2));
  });

  test('authoritative event date changes replace the loaded calendar dates', () async {
    var current = eventJson();
    transport.responders['GET /discourse-post-event/events/42.json'] =
        (_) => {'event': current};
    final handle = ports.controller.acquire(eventSite, PostEvent.decode(current)!);
    addTearDown(handle.dispose);
    await handle.refresh();
    final session = open();
    await transport.waitFor(1);
    transport.pending[0].complete({'events': [current]});
    await flush();
    expect(session.occurrences.single.fields['starts_at'], current['starts_at']);
    current = {...current, 'starts_at': '2026-09-15T23:00:00+02:00'};
    await handle.refresh();
    expect(handle.event!.fields['starts_at'], current['starts_at']);
    await transport.waitFor(2);
    transport.pending[1].complete({'events': [current]});
    await flush();
    expect(session.occurrences.single.fields['starts_at'], current['starts_at']);
    await handle.refresh();
    await flush();
    expect(transport.queries, hasLength(2));
  });

  test('first weekday changes replace the visible month query', () async {
    var firstDay = 1;
    final controller = EventController(
      api: ports.controller.api,
      requests: ports.requests,
      posts: ports.posts,
      siteState: PluginSiteStateHost(
        currentUserFor: (_) => ports.user,
        siteConfigFor: (_) => SiteConfig(
          plugins: PluginData.none.withValue(
            topicCalendarSettingsKey,
            TopicCalendarSettings(firstDay: firstDay),
          ),
        ),
      ),
      accounts: ports.controller.accounts,
      topics: ports.controller.topics,
      trackers: ports.controller.trackers,
      zones: ports.zones,
    );
    addTearDown(controller.dispose);
    final page = EventCalendarPage(
      EventCalendarView.month,
      DateTime.utc(2026, 9),
    );
    final session = EventDirectorySession(
      controller: controller,
      site: eventSite,
      mine: false,
      page: page,
    );
    addTearDown(session.dispose);
    await transport.waitFor(1);
    firstDay = 0;
    session.show(page);
    await transport.waitFor(2);
    expect(session.firstDay, 0);
    expect(
      transport.queries[0].queryParameters['after'],
      '2026-08-30T22:00:00.000Z',
    );
    expect(
      transport.queries[1].queryParameters['after'],
      '2026-08-29T22:00:00.000Z',
    );
    transport.pending[1].complete({
      'events': [_event(99)],
    });
    await flush();
    transport.pending[0].completeError(StateError('old first day'));
    await flush();
    expect(session.occurrences.single.id, 99);
    expect(session.failed, isFalse);
  });

  test(
    'distinct directories retain independent identity and lifetimes',
    () async {
      final first = open();
      final second = open(site: 'https://other.example', mine: true, month: 10);
      await transport.waitFor(2);
      expect(transport.sites, [eventSite, 'https://other.example']);
      expect(transport.queries[0].queryParameters['attending_user'], isNull);
      expect(transport.queries[1].queryParameters['attending_user'], 'lee');
      transport.pending[1].complete({
        'events': [_event(99)],
      });
      await flush();
      expect(first.loading, isTrue);
      expect(second.occurrences.single.id, 99);
      transport.pending[0].complete({
        'events': [eventJson()],
      });
      await flush();
      expect(first.occurrences.single.id, 42);
      expect(second.occurrences.single.id, 99);
    },
  );

  test(
    'disposal drops responses and prevents further quarter requests',
    () async {
      final session = EventDirectorySession(
        controller: ports.controller,
        site: eventSite,
        mine: false,
        page: EventCalendarPage(EventCalendarView.year, DateTime.utc(2026)),
      );
      await transport.waitFor(1);
      var notifications = 0;
      session.addListener(() => notifications++);
      session.dispose();
      transport.pending[0].complete({
        'events': [eventJson()],
      });
      ports.controller.pluginCurrentUserRefreshed(eventSite);
      await flush();
      expect(transport.queries, hasLength(1));
      expect(notifications, 0);
      expect(session.occurrences, isEmpty);
    },
  );
}

Map<String, dynamic> _event(int id) => eventJson(
  overrides: {
    'id': id,
    'post': {'id': id},
  },
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

final class _Transport extends RecordingPluginTransport {
  final queries = <Uri>[];
  final sites = <String>[];
  final pending = <Completer<Map<String, dynamic>>>[];

  Future<void> waitFor(int count) async {
    await flush();
    expect(queries, hasLength(count));
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    if (Uri.parse(path).path != '/discourse-post-event/events.json') {
      return super.pluginGetJson(siteUrl: siteUrl, path: path, apiKey: apiKey, clientId: clientId);
    }
    sites.add(siteUrl);
    queries.add(Uri.parse(path));
    final response = Completer<Map<String, dynamic>>();
    pending.add(response);
    return response.future;
  }
}
