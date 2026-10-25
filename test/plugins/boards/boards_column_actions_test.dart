import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';

void main() {
  test(
    'column edits preserve server replacement fields and use current rules',
    () async {
      final json = boardFixtureJson();
      final column = boardObject((json['columns'] as List).first);
      column.addAll({
        'icon': 'check',
        'color': '#123456',
        'tag_name': 'planned',
        'move_to_category_id': 5,
        'move_to_assigned': 'team',
        'move_to_status': 'closed',
      });
      json['columns'] = <Object?>[column, ...(json['columns'] as List).skip(1)];
      final fixture = BoardsFixture(json: json);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.columns.first['move_to_assigned'] = 'successor-team';
      await handle.refresh();
      final result = await handle.updateColumn(
        10,
        title: 'Ready',
        icon: 'rocket',
        order: BoardColumnOrder.recency,
      );
      expect(result.state, BoardWriteState.saved);
      final request = fixture.transport.writes.single;
      expect(request.method, 'PUT');
      expect(request.path, '/boards/api/boards/1/columns/10');
      expect(request.body, {
        'column': {
          'title': 'Ready',
          'icon': 'rocket',
          'color': '#123456',
          'default_sort': 'recency',
          'tag_name': 'planned',
          'move_to_category_id': 5,
          'move_to_assigned': 'successor-team',
          'move_to_status': 'closed',
        },
      });
      expect(handle.snapshot!.column(10)!.title, 'Ready');
    },
  );

  test('columns with an unsupported sort cannot be edited natively', () async {
    final json = boardFixtureJson();
    ((json['columns'] as List).first as Map)['default_sort'] = 'votes';
    final fixture = BoardsFixture(json: json);
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect(
      (await handle.updateColumn(
        10,
        title: 'Ready',
        icon: '',
        order: BoardColumnOrder.priority,
      )).state,
      BoardWriteState.refused,
    );
    expect(fixture.transport.writes, isEmpty);
  });

  test('column movement respects edges and management permission', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect((await handle.moveColumn(10, -1)).state, BoardWriteState.refused);
    expect((await handle.moveColumn(12, 1)).state, BoardWriteState.refused);
    expect(fixture.transport.writes, isEmpty);
    expect((await handle.moveColumn(10, 1)).state, BoardWriteState.saved);
    expect(fixture.transport.writes.single.body, {
      'column_id': 10,
      'direction': 1,
    });
    expect(handle.snapshot!.columns.map((column) => column.id), [11, 10, 12]);
    (fixture.data['board'] as Map)['can_manage'] = false;
    await handle.refresh();
    expect(handle.canWrite, isTrue);
    expect(handle.canManage, isFalse);
    expect((await handle.deleteColumn(10)).state, BoardWriteState.refused);
    expect((await handle.clearColumn(10)).state, BoardWriteState.refused);
    expect(fixture.transport.writes, hasLength(1));
  });

  test(
    'clearing refreshes every affected topic including old and duplicate cards',
    () async {
      final json = boardFixtureJson(sort: 'recency');
      final cards =
          ((json['columns'] as List).first as Map<String, dynamic>)['cards']
              as List;
      ((json['columns'] as List).first
          as Map<String, dynamic>)['cards'] = <Object?>[
        ...cards,
        {
          'id': 104,
          'column_id': 10,
          'card_type': 'topic',
          'topic_id': 501,
          'recency_at': '2020-01-01T00:00:00Z',
          'topic': {'id': 501, 'title': 'Old topic'},
        },
        {
          'id': 105,
          'column_id': 10,
          'card_type': 'topic',
          'topic_id': 500,
          'topic': {'id': 500, 'title': 'Duplicate topic card'},
        },
      ];
      final fixture = BoardsFixture(json: json);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      expect((await handle.clearColumn(10)).state, BoardWriteState.saved);
      expect(
        fixture.transport.writes.single.path,
        '/boards/api/boards/1/columns/10/cards',
      );
      expect(fixture.transport.writes.single.method, 'DELETE');
      expect(fixture.refreshedTopics, [500, 501]);
      expect(handle.snapshot!.column(10)!.cards, isEmpty);
      expect((await handle.clearColumn(10)).state, BoardWriteState.refused);
      expect(fixture.transport.writes, hasLength(1));
      expect((await handle.deleteColumn(10)).state, BoardWriteState.saved);
      expect(handle.snapshot!.column(10), isNull);
    },
  );

  test(
    'unknown clear results refresh affected topics without retrying the mutation',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture
              .transport
              .failures['DELETE /boards/api/boards/1/columns/10/cards'] =
          const WriteException(WriteFailure.unreachable);
      expect((await handle.clearColumn(10)).state, BoardWriteState.unknown);
      expect(fixture.refreshedTopics, [500]);
      expect(fixture.transport.writes, hasLength(1));
    },
  );

  for (final credentialAvailable in [true, false]) {
    test(
      'same-account refresh during credential admission restores the board with credentials $credentialAvailable',
      () async {
        final gate = _WriteGate();
        final fixture = BoardsFixture(requestHost: gate);
        addTearDown(fixture.dispose);
        final handle = fixture.controller.acquire(boardsSite, 1);
        addTearDown(handle.release);
        await handle.refresh();
        gate.block = true;
        final pending = handle.deleteColumn(10);
        await gate.entered.future;
        fixture.controller.pluginCurrentUserRefreshed(boardsSite);
        gate.pending.complete(
          credentialAvailable
              ? await gate.inner.writeCredentialFor(boardsSite)
              : (credentials: null, failure: null),
        );
        final result = await pending;
        expect(handle.snapshot, isNotNull);
        expect(handle.snapshot!.name, 'Product roadmap');
        expect(handle.reading, isFalse);
        expect(fixture.transport.writes, isEmpty);
        expect(
          result.state,
          credentialAvailable
              ? BoardWriteState.cancelled
              : BoardWriteState.refused,
        );
      },
    );
  }

  test(
    'same-account refresh during dispatched clear reconciles board and topic tags',
    () async {
      final json = boardFixtureJson(sort: 'recency');
      final column = boardObject((json['columns'] as List).first);
      column['cards'] = <Object?>[
        ...(column['cards'] as List),
        {
          'id': 104,
          'column_id': 10,
          'card_type': 'topic',
          'topic_id': 501,
          'recency_at': '2020-01-01T00:00:00Z',
          'topic': {'id': 501, 'title': 'Old affected topic'},
        },
      ];
      json['columns'] = <Object?>[column, ...(json['columns'] as List).skip(1)];
      final fixture = BoardsFixture(json: json);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      const route = 'DELETE /boards/api/boards/1/columns/10/cards';
      final clear = fixture.transport.responders[route]!;
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.transport.responders[route] = (request) async {
        entered.complete();
        await release.future;
        return clear(request);
      };
      final pending = handle.clearColumn(10);
      await entered.future;
      fixture.controller.pluginCurrentUserRefreshed(boardsSite);
      release.complete();
      final result = await pending;
      expect(handle.snapshot, isNotNull);
      expect(handle.snapshot!.column(10)!.cards, isEmpty);
      expect(result.state, BoardWriteState.saved);
      expect(fixture.refreshedTopics, [500, 501]);
      expect(fixture.transport.writes, hasLength(1));
    },
  );

  test(
    'retirement during column credential admission prevents transport',
    () async {
      final gate = _WriteGate();
      final fixture = BoardsFixture(requestHost: gate);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      gate.block = true;
      final pending = handle.deleteColumn(10);
      await Future<void>.delayed(Duration.zero);
      fixture.controller.forget(boardsSite);
      gate.pending.complete(await gate.inner.writeCredentialFor(boardsSite));
      expect((await pending).state, BoardWriteState.cancelled);
      expect(fixture.transport.writes, isEmpty);
    },
  );
}

class _WriteGate implements PluginRequestHost {
  final inner = PluginTestRequestHost(apiKeys: {boardsSite: 'key'});
  final pending = Completer<PluginWriteCredential>();
  final entered = Completer<void>();
  bool block = false;
  @override
  PluginSiteLease capture(String siteUrl) => inner.capture(siteUrl);
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) =>
      inner.credentialsFor(siteUrl);
  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) {
    if (!block) return inner.writeCredentialFor(siteUrl);
    entered.complete();
    return pending.future;
  }
}
