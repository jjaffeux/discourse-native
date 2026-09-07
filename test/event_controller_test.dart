import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  const read = 'GET /discourse-post-event/events/42.json';
  const create = 'POST /discourse-post-event/events/42/invitees.json';
  late EventTestPorts ports;
  late Map<String, dynamic> current;
  setUp(() {
    current = eventJson();
    ports = EventTestPorts();
    ports.transport.responders[read] = (_) => {'event': current};
  });
  tearDown(() => ports.close());

  test(
    'two cards share hydration and a reference-counted subscription',
    () async {
      final a = ports.controller.acquire(eventSite, PostEvent.decode(current)!);
      final b = ports.controller.acquire(eventSite, PostEvent.decode(current)!);
      expect(a.authoritative, isFalse);
      await a.refresh();
      expect(a.authoritative, isTrue);
      expect(a.event, same(b.event));
      expect(ports.channels.subscriberCount('/discourse-post-event/700'), 1);
      a.dispose();
      expect(ports.channels.subscriberCount('/discourse-post-event/700'), 1);
      b.dispose();
      expect(ports.channels.channels, isEmpty);
    },
  );

  test(
    'same numeric event on different sites never shares personalized state',
    () async {
      ports.transport.responders[read] = (r) => {
        'event': eventJson(overrides: {'name': r.siteUrl}),
      };
      final a = ports.controller.acquire(eventSite, PostEvent.decode(current)!);
      final b = ports.controller.acquire(
        'https://other.example',
        PostEvent.decode(current)!,
      );
      await Future.wait([a.refresh(), b.refresh()]);
      expect(a.event!.title, eventSite);
      expect(b.event!.title, 'https://other.example');
      a.dispose();
      b.dispose();
    },
  );

  test(
    'RSVP reconciles recurring response and topic tracking; duplicate taps issue one write',
    () async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await handle.refresh();
      final entered = Completer<void>();
      final completion = Completer<Map<String, dynamic>>();
      ports.transport.responders[create] = (_) {
        entered.complete();
        return completion.future;
      };
      final write = handle.respond('going', recurring: true);
      await entered.future;
      await handle.respond('interested');
      expect(ports.transport.writes, hasLength(1));
      current = eventJson(
        overrides: {'watching_invitee': watching(recurring: true)},
      );
      completion.complete({'invitee': watching(recurring: true)});
      await write;
      expect(handle.event!.watching!.recurring, isTrue);
      expect(handle.pending, isFalse);
      expect(ports.posts.lanes, isEmpty);
      expect(ports.refreshedTopics, [(eventSite, 700)]);
      handle.dispose();
    },
  );

  test(
    'pre-write read, live echo and stale post source cannot roll an RSVP back',
    () async {
      final seed = PostEvent.decode(current)!;
      final handle = ports.controller.acquire(eventSite, seed);
      await handle.refresh();
      final oldGet = Completer<Map<String, dynamic>>();
      final getEntered = Completer<void>();
      ports.transport.responders[read] = (_) {
        getEntered.complete();
        return oldGet.future;
      };
      final refresh = handle.refresh();
      await getEntered.future;
      final writeEntered = Completer<void>();
      final writeDone = Completer<Map<String, dynamic>>();
      ports.transport.responders[create] = (_) {
        writeEntered.complete();
        return writeDone.future;
      };
      final write = handle.respond('going', recurring: true);
      await writeEntered.future;
      ports.channels.deliver('/discourse-post-event/700', {'id': 42});
      oldGet.complete({'event': current});
      await refresh;
      current = eventJson(
        overrides: {'watching_invitee': watching(recurring: true)},
      );
      ports.transport.responders[read] = (_) => {'event': current};
      writeDone.complete({'invitee': watching(recurring: true)});
      await write;
      handle.updateSource(
        PostEvent.decode(
          eventJson(overrides: {'name': 'An older topic response'}),
        )!,
      );
      await handle.refresh();
      expect(handle.event!.watching!.status, 'going');
      expect(handle.event!.watching!.recurring, isTrue);
      handle.dispose();
    },
  );

  test(
    'ambiguous write refreshes before retry and uses the newly discovered invitee ID',
    () async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await handle.refresh();
      ports.transport.responders[create] = (_) {
        current = eventJson(overrides: {'watching_invitee': watching()});
        throw const WriteException(WriteFailure.unreachable);
      };
      await handle.respond('going');
      expect(handle.event!.watching!.id, 83);
      expect(handle.error, isNotNull);
      ports
          .transport
          .responses['PUT /discourse-post-event/events/42/invitees/83.json'] = {
        'invitee': watching(status: 'interested'),
      };
      await handle.respond('interested');
      expect(ports.transport.writes.last.method, 'PUT');
      expect(ports.transport.writes.last.body, {
        'invitee': {'status': 'interested', 'recurring': false},
      });
      handle.dispose();
    },
  );

  test(
    'capacity and permission failures re-read, retain server errors, and release the lane',
    () async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await handle.refresh();
      ports.transport.responders[create] = (_) {
        current = eventJson(overrides: {'at_capacity': true});
        throw const WriteException(
          WriteFailure.validation,
          statusCode: 422,
          errors: ['The event is full.'],
        );
      };
      await handle.respond('going');
      expect(handle.event!.canChoose('going'), isFalse);
      expect(handle.error, 'The event is full.');
      expect(ports.posts.lanes, isEmpty);
      await handle.respond('going');
      expect(ports.transport.writes, hasLength(1));
      ports.transport.responders[read] = (_) => throw const SiteLookupException(
        SiteLookupFailure.unreachable,
        eventSite,
        statusCode: 403,
      );
      await handle.refresh();
      expect(handle.event, isNull);
      expect(handle.authoritative, isFalse);
      handle.dispose();
    },
  );

  test(
    'private response cannot be cleared and archived topics reject writes',
    () async {
      current = eventJson(overrides: {'watching_invitee': watching()});
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await handle.refresh();
      await handle.withdraw();
      ports.posts.archived = true;
      await handle.respond('interested');
      expect(ports.transport.writes, isEmpty);
      handle.dispose();
    },
  );

  test(
    'disconnect during a pending response never commits stale data or releases a new lane',
    () async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await handle.refresh();
      final entered = Completer<void>();
      final done = Completer<Map<String, dynamic>>();
      ports.transport.responders[create] = (_) {
        entered.complete();
        return done.future;
      };
      final write = handle.respond('going');
      await entered.future;
      ports.requests.forget(eventSite);
      ports.controller.forget(eventSite);
      ports.posts.lanes.clear();
      ports.posts.beginWrite(eventSite, 42);
      done.complete({'invitee': watching()});
      await write;
      expect(handle.event, isNull);
      expect(handle.authoritative, isFalse);
      expect(ports.refreshedTopics, isEmpty);
      expect(ports.posts.lanes, contains((eventSite, 42)));
      expect(ports.channels.channels, isEmpty);
      handle.dispose();
    },
  );

  test(
    'tracker replacement and backgrounding cancel subscriptions and refresh on return',
    () async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await handle.refresh();
      final replacement = RecordingPluginLiveChannels();
      ports.controller.attachPluginTracker(eventSite, replacement);
      await handle.refresh();
      expect(ports.channels.channels, isEmpty);
      expect(replacement.channels, ['/discourse-post-event/700']);
      ports.controller.setForeground(false);
      expect(replacement.channels, isEmpty);
      current = eventJson(overrides: {'is_closed': true});
      ports.controller.setForeground(true);
      await handle.refresh();
      expect(handle.event!.canRespond, isFalse);
      expect(replacement.subscriberCount('/discourse-post-event/700'), 1);
      handle.dispose();
      expect(replacement.channels, isEmpty);
    },
  );

  test('an event moved to another topic replaces its live channel', () async {
    final handle = ports.controller.acquire(
      eventSite,
      PostEvent.decode(current)!,
    );
    await handle.refresh();
    current = eventJson(
      overrides: {
        'post': {
          'id': 42,
          'topic': {'id': 701, 'title': 'Moved event'},
        },
      },
    );
    await handle.refresh();
    expect(handle.event!.topicId, 701);
    expect(ports.channels.subscriberCount('/discourse-post-event/700'), 0);
    expect(ports.channels.subscriberCount('/discourse-post-event/701'), 1);
    handle.dispose();
  });

  test(
    'disposing an old account card cannot evict a new account record with the same ID',
    () async {
      final old = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await old.refresh();
      ports.requests.forget(eventSite);
      ports.controller.forget(eventSite);
      final next = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      await next.refresh();
      old.dispose();
      expect(next.authoritative, isTrue);
      expect(ports.channels.subscriberCount('/discourse-post-event/700'), 1);
      next.dispose();
    },
  );
}
