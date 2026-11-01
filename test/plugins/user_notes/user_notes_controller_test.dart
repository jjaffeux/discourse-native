import 'dart:async';
import 'dart:convert';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/discourse_api.dart' show DiscourseApi;
import 'package:discourse_native/src/plugins/user_notes/user_notes_api.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'user_notes_fixture.dart';

void main() {
  test('member and disabled sessions admit no requests', () async {
    for (final f in [
      NotesFixture(staff: false),
      NotesFixture(enabled: false),
    ]) {
      addTearDown(f.dispose);
      expect(
        () => f.controller.open(siteUrl: notesSite, userId: 7),
        throwsA(isA<WriteException>()),
      );
      expect(f.transport.requests, isEmpty);
    }
  });
  test(
    'overlapping reads coalesce and account retirement clears data before a late response',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      final pending = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /user_notes?user_id=7'] = (_) =>
          pending.future;
      final session = f.controller.open(siteUrl: notesSite, userId: 7);
      await Future<void>.delayed(Duration.zero);
      final a = session.refresh(), b = session.refresh();
      expect(f.transport.reads, hasLength(1));
      f.requests.forget(notesSite);
      expect(session.status, UserNotesReadStatus.closed);
      expect(session.notes, isEmpty);
      pending.complete(notesPage([noteWire()]));
      await Future.wait([a, b]);
      expect(session.notes, isEmpty);
      expect(f.controller.count(notesSite, 7), isNull);
    },
  );
  test(
    'same subject opened from a new post retires the old immutable association',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      final old = f.controller.open(siteUrl: notesSite, userId: 7, postId: 11);
      await old.refresh();
      final current = f.controller.open(
        siteUrl: notesSite,
        userId: 7,
        postId: 22,
      );
      await current.refresh();
      expect(old.status, UserNotesReadStatus.closed);
      expect(await old.add('Stale note'), isFalse);
      expect(await current.add('New context'), isTrue);
      expect(
        (f.transport.writes.single.body['user_note']! as Map)['post_id'],
        22,
      );
    },
  );
  test(
    'writes serialize, preserve server note order and update only the account/site count',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      final session = f.controller.open(siteUrl: notesSite, userId: 7);
      await session.refresh();
      final pending = Completer<Map<String, dynamic>>();
      f.transport.responders['POST /user_notes'] = (_) => pending.future;
      final add = session.add('New note');
      expect(await session.add('Double tap'), isFalse);
      pending.complete({'user_note': noteWire(id: 'new', raw: 'New note')});
      expect(await add, isTrue);
      expect(session.notes.map((n) => n.id), ['new', 'note-1']);
      expect(f.controller.count(notesSite, 7), 2);
      expect(f.controller.count(notesOtherSite, 7), isNull);
      expect(await session.remove('note-1'), isTrue);
      expect(session.notes.single.id, 'new');
    },
  );
  test(
    'uncertain create never retries itself and refresh is required before deliberate resubmission',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      final session = f.controller.open(siteUrl: notesSite, userId: 7);
      await session.refresh();
      f.transport.responders.remove('POST /user_notes');
      f.transport.failures['POST /user_notes'] = const WriteException(
        WriteFailure.unreachable,
      );
      expect(await session.add('Keep this draft'), isFalse);
      expect(session.failure, UserNotesFailure.uncertain);
      expect(session.uncertain, isTrue);
      expect(await session.add('Keep this draft'), isFalse);
      expect(f.transport.writes, hasLength(1));
      await session.refresh();
      expect(session.uncertain, isFalse);
      expect(f.transport.writes, hasLength(1));
    },
  );
  test(
    'disablement and staff loss clear body/count state and abort pending cooking',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      var session = f.controller.open(siteUrl: notesSite, userId: 7);
      await session.refresh();
      var aborted = false;
      unawaited(session.aborted.then((_) => aborted = true));
      f.settings(enabled: false);
      expect(session.notes, isEmpty);
      expect(session.isCurrent, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(aborted, isTrue);
      expect(f.controller.count(notesSite, 7), isNull);
      f.settings(enabled: true);
      session = f.controller.open(siteUrl: notesSite, userId: 7);
      await session.refresh();
      f.fresh.staff = false;
      f.controller.pluginCurrentUserRefreshed(notesSite);
      expect(session.status, UserNotesReadStatus.closed);
      expect(session.notes, isEmpty);
    },
  );
  test(
    'Unicode scalar max length and trimmed blank validation make no writes',
    () async {
      final f = NotesFixture(maximumLength: 2);
      addTearDown(f.dispose);
      final session = f.controller.open(siteUrl: notesSite, userId: 7);
      await session.refresh();
      expect(await session.add(' \n '), isFalse);
      expect(session.failure, UserNotesFailure.blank);
      expect(await session.add('😀😀😀'), isFalse);
      expect(session.failure, UserNotesFailure.tooLong);
      expect(f.transport.writes, isEmpty);
      expect(await session.add('😀😀'), isTrue);
    },
  );
  test('server delete permission is authoritative', () async {
    final f = NotesFixture();
    addTearDown(f.dispose);
    f.transport.responders['GET /user_notes?user_id=7'] = (_) =>
        notesPage([noteWire(canDelete: false)]);
    final session = f.controller.open(siteUrl: notesSite, userId: 7);
    await session.refresh();
    expect(await session.remove('note-1'), isFalse);
    expect(f.transport.writes, isEmpty);
  });
  for (final status in [401, 403, 404]) {
    test(
      'real GET $status retires all private site readers and pending work',
      () async {
        final f = NotesFixture();
        addTearDown(f.dispose);
        var denied = false;
        final pending = Completer<http.Response>();
        addTearDown(() {
          if (!pending.isCompleted) pending.complete(http.Response('{}', 200));
        });
        final pendingStarted = Completer<void>();
        final transport = DiscourseApi(
          client: MockClient((request) async {
            if (request.url.queryParameters['user_id'] == '8') {
              pendingStarted.complete();
              return pending.future;
            }
            return http.Response(
              jsonEncode(
                denied
                    ? {
                        'errors': ['Access refused'],
                      }
                    : notesPage([noteWire()]),
              ),
              denied ? status : 200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(transport.close);
        final controller = UserNotesController(
          api: UserNotesApiClient(transport),
          requests: f.requests,
          account: f.fresh,
          site: f.controller.site,
          cooking: f.cookingHost,
        );
        addTearDown(controller.dispose);
        final session = controller.open(siteUrl: notesSite, userId: 7);
        await session.refresh();
        expect(session.notes.single.raw, 'Private **staff** context.');
        expect(session.username, 'mira');
        expect(controller.count(notesSite, 7), 1);
        final other = controller.open(
          siteUrl: notesSite,
          userId: 8,
          username: 'private pending subject',
        );
        final otherRead = other.refresh();
        await pendingStarted.future;
        var aborted = false;
        unawaited(session.aborted.then((_) => aborted = true));
        denied = true;
        await session.refresh();
        expect(session.status, UserNotesReadStatus.closed);
        expect(session.isCurrent, isFalse);
        expect(session.notes, isEmpty);
        expect(session.username, isNull);
        expect(controller.count(notesSite, 7), isNull);
        expect(controller.canOpen(notesSite), isFalse);
        expect(other.status, UserNotesReadStatus.closed);
        expect(other.username, isNull);
        await session.aborted;
        expect(aborted, isTrue);
        pending.complete(
          http.Response(
            jsonEncode(
              notesPage([noteWire(userId: 8, raw: 'Late private response')]),
            ),
            200,
          ),
        );
        await otherRead;
        expect(other.notes, isEmpty);
        expect(await session.add('Cannot submit after denial'), isFalse);
      },
    );
  }

  test(
    'real GET network failure remains retryable without revoking access',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      var unavailable = false;
      final transport = DiscourseApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              unavailable
                  ? {
                      'errors': ['Unavailable'],
                    }
                  : notesPage([noteWire()]),
            ),
            unavailable ? 500 : 200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(transport.close);
      final controller = UserNotesController(
        api: UserNotesApiClient(transport),
        requests: f.requests,
        account: f.fresh,
        site: f.controller.site,
        cooking: f.cookingHost,
      );
      addTearDown(controller.dispose);
      final session = controller.open(siteUrl: notesSite, userId: 7);
      await session.refresh();
      unavailable = true;
      await session.refresh();
      expect(session.status, UserNotesReadStatus.failed);
      expect(session.failure, UserNotesFailure.network);
      expect(session.isCurrent, isTrue);
      expect(controller.canOpen(notesSite), isTrue);
      unavailable = false;
      await session.refresh();
      expect(session.status, UserNotesReadStatus.ready);
      expect(session.notes.single.raw, 'Private **staff** context.');
    },
  );

  test(
    'real POST unauthorized response retires the reader rather than allowing retry',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      var writes = 0;
      final transport = DiscourseApi(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            return http.Response(
              '{"errors":["Unauthorized"]}',
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(notesPage([noteWire()])),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(transport.close);
      final controller = UserNotesController(
        api: UserNotesApiClient(transport),
        requests: f.requests,
        account: f.fresh,
        site: f.controller.site,
        cooking: f.cookingHost,
      );
      addTearDown(controller.dispose);
      final session = controller.open(siteUrl: notesSite, userId: 7);
      await session.refresh();
      expect(await session.add('Private unsent retry'), isFalse);
      expect(session.status, UserNotesReadStatus.closed);
      expect(session.notes, isEmpty);
      expect(controller.canOpen(notesSite), isFalse);
      expect(await session.add('Private unsent retry'), isFalse);
      expect(writes, 1);
    },
  );

  test(
    'identical subjects on distinct sites use separate credentials and private lists',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      f.transport.responders['GET /user_notes?user_id=7'] = (request) =>
          notesPage([
            noteWire(
              raw: request.siteUrl == notesSite
                  ? 'Only site one'
                  : 'Only site two',
            ),
          ]);
      final first = f.controller.open(siteUrl: notesSite, userId: 7),
          second = f.controller.open(siteUrl: notesOtherSite, userId: 7);
      await Future.wait([first.refresh(), second.refresh()]);
      expect(first.notes.single.raw, 'Only site one');
      expect(second.notes.single.raw, 'Only site two');
      expect(f.transport.reads.map((r) => r.apiKey).toSet(), {
        'first-key',
        'second-key',
      });
      f.controller.forget(notesSite);
      expect(first.notes, isEmpty);
      expect(second.notes.single.raw, 'Only site two');
    },
  );
  test(
    'late create under a retired account cannot populate its successor',
    () async {
      final f = NotesFixture();
      addTearDown(f.dispose);
      final old = f.controller.open(siteUrl: notesSite, userId: 7);
      await old.refresh();
      final pending = Completer<Map<String, dynamic>>();
      f.transport.responders['POST /user_notes'] = (_) => pending.future;
      final write = old.add('Old account secret');
      await Future<void>.delayed(Duration.zero);
      f.requests.forget(notesSite);
      f.requests.apiKeys[notesSite] = 'successor-key';
      f.transport.responders['GET /user_notes?user_id=7'] = (_) =>
          notesPage([noteWire(raw: 'Successor view')]);
      final current = f.controller.open(siteUrl: notesSite, userId: 7);
      await current.refresh();
      pending.complete({
        'user_note': noteWire(id: 'old-write', raw: 'Old account secret'),
      });
      expect(await write, isFalse);
      expect(old.notes, isEmpty);
      expect(current.notes.single.raw, 'Successor view');
      expect(f.controller.count(notesSite, 7), 1);
    },
  );
}
