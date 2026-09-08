import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
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

  for (final mine in [false, true]) {
    for (final search in [null, 'planning & review']) {
      test(
        '${mine ? 'my' : 'upcoming'} events ${search == null ? 'without search' : 'with search'} request an ISO date bound before the result limit',
        () async {
          final path = Uri(
            path: '/discourse-post-event/events.json',
            queryParameters: {
              'include_details': 'true',
              'include_ongoing': 'true',
              'order': 'asc',
              'limit': '200',
              if (mine) 'attending_user': 'lee',
              if (mine) 'include_interested': 'true',
              'search': ?search,
              'after': '2026-09-08T08:00:00.000Z',
            },
          ).toString();
          ports.transport.responses['GET $path'] = {
            'events': [current],
          };

          final rows = await ports.controller.list(
            eventSite,
            mine: mine,
            search: search,
          );

          expect(rows.map((event) => event.id), [42]);
          expect(ports.transport.requests.map((r) => (r.method, r.path)), [
            ('GET', path),
          ]);
          final request = ports.transport.requests.single;
          expect(request.siteUrl, eventSite);
          expect(request.apiKey, 'key');
          expect(request.clientId, 'test-client');
        },
      );
    }
  }

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

  for (final command in [
    'refresh',
    'updateSource',
    'respond',
    'withdraw',
    'invite',
    'participants',
  ]) {
    test('$command rejects a released handle with a live peer', () async {
      current = eventJson(
        overrides: {
          'is_public': true,
          'is_private': false,
          'watching_invitee': watching(),
        },
      );
      final seed = PostEvent.decode(current)!;
      final released = ports.controller.acquire(eventSite, seed);
      addTearDown(released.dispose);
      final peer = ports.controller.acquire(eventSite, seed);
      addTearDown(peer.dispose);
      await peer.refresh();
      ports.transport.responses.addAll({
        'PUT /discourse-post-event/events/42/invitees/83.json': {},
        'DELETE /discourse-post-event/events/42/invitees/83.json': {},
        'POST /discourse-post-event/events/42/invite': {},
        'GET /discourse-post-event/events/42/invitees.json?': {
          'invitees': [watching()],
        },
      });
      final source = PostEvent.decode(
        eventJson(overrides: {'name': 'Updated source'}),
      )!;
      Future<void> run(EventHandle handle) async {
        switch (command) {
          case 'refresh':
            await handle.refresh();
          case 'updateSource':
            handle.updateSource(source);
          case 'respond':
            await handle.respond('interested');
          case 'withdraw':
            await handle.withdraw();
          case 'invite':
            expect(await handle.invite(['sam']), handle.isCurrent);
          case 'participants':
            final rows = ports.controller.participants(handle);
            if (handle.isCurrent) {
              expect((await rows).map((row) => row.id), [83]);
            } else {
              await expectLater(rows, throwsA(isA<WriteException>()));
            }
        }
      }

      released.dispose();
      final requests = ports.transport.requests.length;
      await run(released);
      expect(ports.transport.requests, hasLength(requests));
      expect(ports.posts.lanes, isEmpty);
      expect(released.isCurrent, isFalse);
      expect(peer.authoritative, isTrue);

      await run(peer);
      expect(ports.transport.requests.length, greaterThan(requests));
      current = eventJson(overrides: {'name': 'Still subscribed'});
      ports.channels.deliver('/discourse-post-event/700', {'id': 42});
      await peer.refresh();
      expect(peer.event!.title, 'Still subscribed');
      expect(ports.channels.subscriberCount('/discourse-post-event/700'), 1);
      peer.dispose();
      expect(ports.channels.channels, isEmpty);
    });
  }

  test(
    'releasing an initiating handle after write admission preserves the write and its live peer',
    () async {
      final seed = PostEvent.decode(current)!;
      final handle = ports.controller.acquire(eventSite, seed);
      addTearDown(handle.dispose);
      final peer = ports.controller.acquire(eventSite, seed);
      addTearDown(peer.dispose);
      await peer.refresh();
      ports.posts.onBeginWrite = handle.dispose;
      ports.transport.responders[create] = (_) {
        expect(handle.isCurrent, isFalse);
        expect(peer.pending, isTrue);
        current = eventJson(
          overrides: {'watching_invitee': watching(recurring: true)},
        );
        return {'invitee': watching(recurring: true)};
      };

      await handle.respond('going', recurring: true);

      final request = ports.transport.writes.single;
      expect(
        (request.method, request.path),
        ('POST', '/discourse-post-event/events/42/invitees.json'),
      );
      expect(request.body, {
        'invitee': {'status': 'going', 'recurring': true},
      });
      expect(peer.event!.watching!.recurring, isTrue);
      expect(peer.authoritative, isTrue);
      expect(peer.pending, isFalse);
      expect(ports.posts.lanes, isEmpty);
      expect(ports.refreshedTopics, [(eventSite, 700)]);
      expect(ports.channels.subscriberCount('/discourse-post-event/700'), 1);
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
    'account replacement during write admission preserves the new post lane',
    () async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      addTearDown(handle.dispose);
      await handle.refresh();
      ports.posts.onBeginWrite = () {
        ports.posts.onBeginWrite = null;
        ports.requests.forget(eventSite);
        ports.controller.forget(eventSite);
        ports.posts.lanes.clear();
        ports.posts.beginWrite(eventSite, 42);
      };

      await handle.respond('going');

      expect(ports.transport.writes, isEmpty);
      expect(ports.posts.lanes, {(eventSite, 42)});
      expect(ports.refreshedTopics, isEmpty);
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
    'forgotten handles and a pending old read cannot change a replacement entry',
    () async {
      final seed = PostEvent.decode(current)!;
      final old = ports.controller.acquire(eventSite, seed);
      addTearDown(old.dispose);
      await old.refresh();
      final entered = Completer<void>();
      final pending = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) {
        entered.complete();
        return pending.future;
      };
      final oldRead = old.refresh();
      await entered.future;
      ports.requests.forget(eventSite);
      ports.requests.apiKeys[eventSite] = 'replacement-key';
      ports.controller.forget(eventSite);

      current = eventJson(
        overrides: {'name': 'Replacement account', 'watching_invitee': null},
      );
      ports.transport.responders[read] = (_) => {'event': current};
      final next = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      final peer = ports.controller.acquire(eventSite, seed);
      addTearDown(next.dispose);
      addTearDown(peer.dispose);
      await next.refresh();
      expect(next.event, same(peer.event));
      final reads = ports.transport.reads.length;

      old.updateSource(
        PostEvent.decode(eventJson(overrides: {'name': 'Obsolete source'}))!,
      );
      await old.refresh();
      await old.respond('going');
      expect(await old.invite(['sam']), isFalse);
      await expectLater(
        ports.controller.participants(old),
        throwsA(isA<WriteException>()),
      );
      expect(ports.transport.reads, hasLength(reads));
      expect(ports.transport.writes, isEmpty);

      pending.complete({
        'event': eventJson(
          overrides: {
            'name': 'Previous account',
            'watching_invitee': watching(),
          },
        ),
      });
      await oldRead;
      expect(old.event, isNull);
      expect(old.authoritative, isFalse);
      expect(next.event!.title, 'Replacement account');
      expect(next.event!.watching, isNull);
      expect(next.authoritative, isTrue);

      old.dispose();
      old.dispose();
      next.dispose();
      expect(ports.channels.subscriberCount('/discourse-post-event/700'), 1);
      current = eventJson(overrides: {'name': 'Still subscribed'});
      ports.channels.deliver('/discourse-post-event/700', {'id': 42});
      await peer.refresh();
      expect(peer.event!.title, 'Still subscribed');
      peer.dispose();
      expect(ports.channels.channels, isEmpty);
    },
  );

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
