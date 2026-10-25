import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';

void main() {
  test(
    'missing setting disables directory, board reads, links and writes',
    () async {
      final fixture = BoardsFixture(enabled: false);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      expect(await fixture.controller.loadDirectory(boardsSite), isEmpty);
      expect(
        await fixture.navigation.openPluginUrl('$boardsSite/boards/roadmap/1'),
        isFalse,
      );
      expect(
        (await handle.saveStandalone(10, 'Task', '')).state,
        BoardWriteState.refused,
      );
      expect(fixture.transport.requests, isEmpty);
      expect(fixture.live.channels, isEmpty);
    },
  );
  test(
    'board snapshots use hydrated columns and preserve duplicate topic cards',
    () {
      final json = boardFixtureJson();
      ((json['columns'] as List)[1] as Map)['cards'] = [
        {
          'id': 103,
          'column_id': 11,
          'card_type': 'topic',
          'topic_id': 500,
          'topic': {'id': 500, 'title': 'Improve search'},
        },
      ];
      final board = BoardSnapshot.decode(
        json['board'],
        columns: json['columns'],
      )!;
      expect(board.columns, hasLength(3));
      expect(board.card(101)!.topicId, board.card(103)!.topicId);
      expect(board.card(101)!.id, isNot(board.card(103)!.id));
      expect(
        BoardCard.decode({
          'id': 9,
          'column_id': 10,
          'card_type': 'topic',
          'topic_id': 999,
        }),
        isNull,
      );
    },
  );
  test('membership decoding retains every column placement', () {
    final memberships = BoardMemberships.decode([
      {
        'board_id': 1,
        'board_name': 'Roadmap',
        'cards': [
          {'card_id': 10, 'column_title': 'Todo'},
          {'card_id': 11, 'column_title': 'Done'},
        ],
      },
    ]);
    expect(memberships.values.map((value) => value.cardId), [10, 11]);
  });
  test('record permissions fail closed and archives are read-only', () {
    expect(BoardSnapshot.decode({'id': 1})!.canWrite, isFalse);
    final json = boardFixtureJson(archived: true);
    expect(BoardSnapshot.decode(json['board'])!.canWrite, isFalse);
  });
  test(
    'subfolder board and card links use numeric identity; configure stays web',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      expect(
        await fixture.navigation.openPluginUrl(
          '$boardsSite/boards/old-slug/1/cards/102',
        ),
        isTrue,
      );
      expect(fixture.host.currentContent!.id, 'boards/1/cards/102');
      expect(
        await fixture.navigation.openPluginUrl(
          '$boardsSite/boards/old/1?card=101',
        ),
        isTrue,
      );
      expect(fixture.host.currentContent!.id, 'boards/1/cards/101');
      expect(
        await fixture.navigation.openPluginUrl(
          '$boardsSite/boards/old/1/configure',
        ),
        isFalse,
      );
      expect(
        await fixture.navigation.openPluginUrl(
          'https://elsewhere.example/boards/a/1',
        ),
        isFalse,
      );
      expect(BoardsRoute.parse('boards/0'), isNull);
    },
  );
  test('one account board shares one handle and live subscription', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final first = fixture.controller.acquire(boardsSite, 1);
    final second = fixture.controller.acquire(boardsSite, 1);
    expect(first, same(second));
    await first.refresh();
    expect(fixture.live.subscriberCount('/boards/1'), 1);
    first.release();
    expect(fixture.live.subscriberCount('/boards/1'), 1);
    second.release();
    expect(fixture.live.channels, isEmpty);
  });
  test(
    'priority move uses server command and refetches both board and topic',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final result = await handle.move(
        101,
        11,
        const PlaceFirst(),
        review: (_, _, _) async => const BoardRepair(),
      );
      expect(result.saved, isTrue);
      final write = fixture.transport.writes.last;
      expect(write.method, 'PUT');
      expect(write.body['card'], {'column_id': 11, 'after_card_id': null});
      expect(handle.snapshot!.card(101)!.columnId, 11);
      expect(fixture.refreshedTopics, [500]);
    },
  );
  test(
    'same-column last anchors to the last other card and recency refuses reorder',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      await handle.move(
        101,
        10,
        const PlaceLast(),
        review: (_, _, _) async => const BoardRepair(),
      );
      expect(
        (fixture.transport.writes.last.body['card'] as Map)['after_card_id'],
        102,
      );
      ((fixture.data['columns'] as List)[0] as Map)['default_sort'] = 'recency';
      await handle.refresh();
      final before = fixture.transport.writes.length;
      expect(
        (await handle.move(
          101,
          10,
          const PlaceFirst(),
          review: (_, _, _) async => const BoardRepair(),
        )).state,
        BoardWriteState.refused,
      );
      expect(fixture.transport.writes.length, before);
    },
  );
  test(
    'constraint repair is top-level and topic addition uses cards endpoint',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      fixture
              .transport
              .responders['PUT /boards/api/boards/1/check-constraint-mismatches'] =
          (_) => {
            'constraints_need_fixing': true,
            'categories_needed': [5],
            'tags_needed': ['planned'],
          };
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final result = await handle.addTopic(
        700,
        11,
        review: (_, _, check) async {
          expect(check.categoryIds, [5]);
          return const BoardRepair(categoryId: 5, tagNames: ['planned']);
        },
      );
      expect(result.saved, isTrue);
      expect(fixture.transport.writes.last.path, '/boards/api/boards/1/cards');
      expect(fixture.transport.writes.last.body['constraint_fix'], {
        'category_id': 5,
        'tag_names': ['planned'],
      });
    },
  );
  test('cancelled constraint review sends no mutation', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    (fixture.data['board'] as Map)['require_confirmation'] = true;
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect(
      (await handle.move(
        102,
        11,
        const PlaceFirst(),
        review: (_, _, _) async => null,
      )).state,
      BoardWriteState.cancelled,
    );
    expect(fixture.transport.writes, isEmpty);
  });
  test('unknown create outcome is reconciled without replay', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.transport.responders['POST /boards/api/boards/1/cards'] = (_) =>
        throw const WriteException(WriteFailure.unreachable);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect(
      (await handle.saveStandalone(10, 'Task', '')).state,
      BoardWriteState.unknown,
    );
    expect(fixture.transport.writes, hasLength(1));
    expect(handle.writing, isFalse);
  });
  test('known save with failed refresh reports saved refresh-needed', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        throw StateError('offline');
    expect(
      (await handle.saveStandalone(10, 'Task', '')).state,
      BoardWriteState.refreshNeeded,
    );
  });
  test(
    'account reset during a read discards old answer and remains usable',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final oldRead = Completer<Map<String, dynamic>>();
      fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
          oldRead.future;
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await Future<void>.delayed(Duration.zero);
      fixture.requests.forget(boardsSite);
      fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
          boardFixtureJson(canWrite: false);
      fixture.controller.forget(boardsSite);
      await handle.refresh();
      oldRead.complete(boardFixtureJson());
      await Future<void>.delayed(Duration.zero);
      expect(handle.snapshot!.canWrite, isFalse);
      expect(handle.reading, isFalse);
      expect(handle.writing, isFalse);
    },
  );
  test(
    'invalidation during read schedules a trailing authoritative read',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final pending = Completer<Map<String, dynamic>>();
      var count = 0;
      fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
          ++count == 1 ? pending.future : boardFixtureJson(canWrite: false);
      final reading = handle.refresh();
      await Future<void>.delayed(Duration.zero);
      fixture.live.deliver('/boards/1', {
        'type': 'board_updated',
        'client_id': 'test-client',
      });
      pending.complete(boardFixtureJson());
      await reading;
      expect(count, 2);
      expect(handle.snapshot!.canWrite, isFalse);
    },
  );
}
