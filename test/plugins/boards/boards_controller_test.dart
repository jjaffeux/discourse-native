import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';

void main() {
  test('same-account permission refresh retains an active composer', () async {
    late BoardsFixture fixture;
    OpenNewTopicComposerRequest? request;
    final composer = PluginComposerHost(
      buildComposer: (_) => null,
      openNewTopic: (value) async {
        request = value;
        return OpenComposerResult.opened;
      },
      isActive: (_) => true,
      siteConfigFor: (_) => fixture.config,
      siteConfigListenableFor: (_) => fixture.settings,
    );
    fixture = BoardsFixture(composer: composer);
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    await handle.createTopic('boards/1', 10, cardId: 102);
    fixture.controller.pluginCurrentUserRefreshed(boardsSite);
    await handle.refresh();
    expect(handle.composing(10, cardId: 102), isTrue);
    expect(request!.sourceStillCurrent!(), isTrue);
    expect(
      await handle.createTopic('boards/1', 10, cardId: 102),
      OpenComposerResult.unavailable,
    );
    request!.onCompleted!(
      const PluginTopicCreated(topicId: 777, slug: 'release', title: 'Release'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(handle.composing(10, cardId: 102), isFalse);
    expect(fixture.transport.writes, hasLength(1));
    expect(handle.snapshot!.card(102)!.topicId, 777);
  });
  test(
    'same-account user refresh preserves failed attachment recovery',
    () async {
      late BoardsFixture fixture;
      OpenNewTopicComposerRequest? request;
      var opens = 0;
      final composer = PluginComposerHost(
        buildComposer: (_) => null,
        openNewTopic: (value) async {
          opens++;
          request = value;
          return OpenComposerResult.opened;
        },
        isActive: (_) => true,
        siteConfigFor: (_) => fixture.config,
        siteConfigListenableFor: (_) => fixture.settings,
      );
      fixture = BoardsFixture(composer: composer);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.transport.failures['PUT /boards/api/boards/1/cards/102'] =
          const WriteException(WriteFailure.forbidden);
      await handle.createTopic('boards/1', 10, cardId: 102);
      request!.onCompleted!(
        const PluginTopicCreated(
          topicId: 777,
          slug: 'release',
          title: 'Release',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(handle.createdTopic(10, cardId: 102), 777);
      fixture.controller.pluginCurrentUserRefreshed(boardsSite);
      await handle.refresh();
      expect(handle.createdTopic(10, cardId: 102), 777);
      expect(
        await handle.createTopic('boards/1', 10, cardId: 102),
        OpenComposerResult.unavailable,
      );
      expect((await handle.attachCreatedTopic(10, cardId: 102)).saved, isTrue);
      expect(opens, 1);
    },
  );
  test(
    'applied topic move with a lost reply still repairs canonical topic data',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.transport.responders['PUT /boards/api/boards/1/cards/101'] = (_) {
        final source = fixture.columns.first['cards'] as List;
        final card = source.firstWhere((raw) => boardObject(raw)['id'] == 101);
        source.remove(card);
        (card as Map)['column_id'] = 11;
        (fixture.columns[1]['cards'] as List).add(card);
        throw const WriteException(WriteFailure.unreachable);
      };
      final result = await handle.move(
        101,
        11,
        const PlaceFirst(),
        review: (_, _, _) async => const BoardRepair(),
      );
      expect(result.state, BoardWriteState.unknown);
      expect(handle.snapshot!.card(101)!.columnId, 11);
      expect(fixture.refreshedTopics, [500]);
      expect(
        fixture.transport.writes.where(
          (request) => request.path.endsWith('/cards/101'),
        ),
        hasLength(1),
      );
    },
  );
  test(
    'late tracker attachment refreshes changes missed during bootstrap',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      (fixture.data['board'] as Map)['name'] = 'Roadmap after bootstrap';
      final channels = RecordingPluginLiveChannels();
      final reads = fixture.transport.reads.length;
      fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) {
        expect(channels.subscriberCount('/boards/1'), 1);
        return fixture.data;
      };
      fixture.controller.attachPluginTracker(boardsSite, channels);
      await Future<void>.delayed(Duration.zero);
      expect(handle.reading, isFalse);
      expect(fixture.transport.reads.length, reads + 1);
      expect(handle.snapshot!.name, 'Roadmap after bootstrap');
      expect(channels.subscriberCount('/boards/1'), 1);
      expect(fixture.live.channels, isEmpty);
    },
  );
  test(
    'promotion adopts a replacement card identity from authoritative refresh',
    () async {
      late BoardsFixture fixture;
      OpenNewTopicComposerRequest? request;
      final composer = PluginComposerHost(
        buildComposer: (_) => null,
        openNewTopic: (value) async {
          request = value;
          return OpenComposerResult.opened;
        },
        isActive: (_) => true,
        siteConfigFor: (_) => fixture.config,
        siteConfigListenableFor: (_) => fixture.settings,
      );
      fixture = BoardsFixture(composer: composer);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.transport.responders['PUT /boards/api/boards/1/cards/102'] = (_) {
        final cards = fixture.columns.first['cards'] as List;
        cards.removeWhere((raw) => boardObject(raw)['id'] == 102);
        final card = {
          'id': 999,
          'column_id': 10,
          'card_type': 'topic',
          'topic_id': 777,
          'topic': {'id': 777, 'title': 'Created release topic'},
        };
        cards.add(card);
        return {'card': card, 'adopted_floater_id': 102};
      };
      await handle.createTopic('boards/1', 10, cardId: 102);
      request!.onCompleted!(
        const PluginTopicCreated(
          topicId: 777,
          slug: 'release',
          title: 'Created release topic',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(handle.snapshot!.card(102), isNull);
      expect(handle.snapshot!.card(999)!.kind, BoardCardKind.topic);
      expect(handle.createdTopic(10, cardId: 102), isNull);
    },
  );
  test(
    'setting disabling immediately clears mounted snapshots and subscriptions',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.config = SiteConfig(
        plugins: PluginData.none.withValue(
          boardsSettingsKey,
          const BoardsSettings(),
        ),
      );
      expect(handle.snapshot, isNull);
      expect(fixture.live.channels, isEmpty);
      expect(
        (await handle.saveStandalone(10, 'Task', '')).state,
        BoardWriteState.refused,
      );
      final reads = fixture.transport.reads.length;
      await handle.refresh();
      expect(fixture.transport.reads.length, reads);
      fixture.config = SiteConfig(
        plugins: PluginData.none.withValue(
          boardsSettingsKey,
          const BoardsSettings(enabled: true),
        ),
      );
      await handle.refresh();
      expect(handle.snapshot, isNotNull);
    },
  );
  test(
    'setting disable cycle cancels an admitted write before transport',
    () async {
      final requests = _PausedWriteRequestHost();
      final fixture = BoardsFixture(requestHost: requests);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final lease = requests.capture(boardsSite);
      final write = handle.saveStandalone(10, 'Retired task', '');
      await requests.admitted.future;
      expect(handle.writing, isTrue);
      fixture.config = _boardsConfig(enabled: false);
      fixture.config = _boardsConfig(enabled: true);
      expect(lease.isCurrent, isTrue);
      requests.ready.complete();
      expect((await write).state, BoardWriteState.cancelled);
      expect(fixture.transport.writes, isEmpty);
      await handle.refresh();
      expect(handle.snapshot!.card(900), isNull);
      expect(handle.canWrite, isTrue);
      expect((await handle.saveStandalone(10, 'New task', '')).saved, isTrue);
      expect(fixture.transport.writes, hasLength(1));
      expect(handle.snapshot!.card(900)!.title, 'New task');
    },
  );
  test(
    'retired dispatched completion cannot release a successor write lane',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final oldReply = Completer<Map<String, dynamic>>();
      final oldSent = Completer<void>();
      fixture.transport.responders['POST /boards/api/boards/1/cards'] = (_) {
        oldSent.complete();
        return oldReply.future;
      };
      final oldWrite = handle.saveStandalone(10, 'Retired task', '');
      await oldSent.future;
      fixture.config = _boardsConfig(enabled: false);
      fixture.config = _boardsConfig(enabled: true);
      await handle.refresh();
      final newReply = Completer<Map<String, dynamic>>();
      final newSent = Completer<void>();
      fixture.transport.responders['POST /boards/api/boards/1/cards'] = (_) {
        newSent.complete();
        return newReply.future;
      };
      final newWrite = handle.saveStandalone(10, 'Current task', '');
      await newSent.future;
      final reads = fixture.transport.reads.length;
      oldReply.complete({
        'card': {'id': 901},
      });
      expect((await oldWrite).state, BoardWriteState.cancelled);
      expect(handle.writing, isTrue);
      expect(handle.snapshot!.card(901), isNull);
      expect(fixture.transport.reads.length, reads);
      expect(
        (await handle.saveStandalone(10, 'Overlapping task', '')).state,
        BoardWriteState.refused,
      );
      expect(fixture.transport.writes, hasLength(2));
      newReply.complete({
        'card': {'id': 902},
      });
      expect((await newWrite).saved, isTrue);
      expect(handle.canWrite, isTrue);
    },
  );
  test(
    'same-account permission refresh retains the admitted write lane',
    () async {
      final requests = _PausedWriteRequestHost();
      final fixture = BoardsFixture(requestHost: requests);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final write = handle.saveStandalone(10, 'Current task', '');
      await requests.admitted.future;
      fixture.controller.pluginCurrentUserRefreshed(boardsSite);
      expect(handle.writing, isTrue);
      expect(
        (await handle.saveStandalone(10, 'Overlapping task', '')).state,
        BoardWriteState.refused,
      );
      requests.ready.complete();
      expect((await write).saved, isTrue);
      expect(fixture.transport.writes, hasLength(1));
      expect(handle.snapshot!.card(900)!.title, 'Current task');
      expect(handle.canWrite, isTrue);
    },
  );
  for (final status in [403, 404]) {
    test(
      'manual recovery after $status restores live updates before reading',
      () async {
        final fixture = BoardsFixture();
        addTearDown(fixture.dispose);
        final handle = fixture.controller.acquire(boardsSite, 1);
        addTearDown(handle.release);
        await handle.refresh();
        expect(fixture.live.subscriberCount('/boards/1'), 1);
        fixture.transport.failures['GET /boards/api/boards/1.json'] =
            SiteLookupException(
              SiteLookupFailure.unreachable,
              boardsSite,
              statusCode: status,
            );
        await handle.refresh();
        expect(handle.snapshot, isNull);
        expect(fixture.live.channels, isEmpty);
        final reply = Completer<Map<String, dynamic>>();
        final sent = Completer<void>();
        var reads = 0;
        fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) {
          if (++reads == 1) {
            sent.complete();
            return reply.future;
          }
          return boardFixtureJson(canWrite: false);
        };
        final recovery = handle.refresh();
        expect(fixture.live.subscriberCount('/boards/1'), 1);
        await sent.future;
        fixture.live.deliver('/boards/1', {'type': 'board_updated'});
        reply.complete(boardFixtureJson());
        await recovery;
        expect(reads, 2);
        expect(handle.snapshot!.canWrite, isFalse);
        expect(handle.error, isNull);
        expect(fixture.live.subscriberCount('/boards/1'), 1);
      },
    );
  }
  test(
    'disposing the controller before releasing mounted handles is safe',
    () async {
      final fixture = BoardsFixture();
      final handle = fixture.controller.acquire(boardsSite, 1);
      await handle.refresh();
      fixture.dispose();
      handle.release();
      handle.release();
      expect(fixture.live.channels, isEmpty);
    },
  );
  test(
    'account reset during a write leaves successor handle writable',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final pending = Completer<Map<String, dynamic>>();
      fixture.transport.responders['POST /boards/api/boards/1/cards'] = (_) =>
          pending.future;
      final write = handle.saveStandalone(10, 'Old account task', '');
      await Future<void>.delayed(Duration.zero);
      fixture.requests.forget(boardsSite);
      fixture.controller.forget(boardsSite);
      await handle.refresh();
      pending.complete({
        'card': {'id': 900},
      });
      expect((await write).state, BoardWriteState.cancelled);
      expect(handle.canWrite, isTrue);
      expect(handle.snapshot!.card(900), isNull);
    },
  );
  test(
    'column recency, tag visibility and card detail settings are decoded',
    () {
      final json = boardFixtureJson();
      final raw = json['board'] as Map;
      raw['show_tags'] = false;
      raw['show_topic_thumbnail'] = true;
      raw['card_style'] = 'simple';
      final board = BoardSnapshot.decode(raw, columns: json['columns'])!;
      expect(board.showTags, isFalse);
      expect(board.showThumbnail, isTrue);
      expect(board.detailed, isFalse);
      expect(board.column(12)!.order, BoardColumnOrder.recency);
    },
  );
  test(
    'promotion binds exact composer result and seeds title, body, category and tags',
    () async {
      late BoardsFixture fixture;
      OpenNewTopicComposerRequest? request;
      final composer = PluginComposerHost(
        buildComposer: (_) => null,
        openNewTopic: (value) async {
          request = value;
          return OpenComposerResult.opened;
        },
        isActive: (_) => true,
        siteConfigFor: (_) => fixture.config,
        siteConfigListenableFor: (_) => fixture.settings,
      );
      fixture = BoardsFixture(composer: composer);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      expect(
        await handle.createTopic('boards/1', 10, cardId: 102),
        OpenComposerResult.opened,
      );
      expect(request!.initialTitle, 'Write release notes');
      expect(request!.seed.raw, 'Review the release with the team.');
      expect(request!.initialTags, ['docs']);
      expect(handle.composing(10, cardId: 102), isTrue);
      request!.onCompleted!(
        const PluginTopicCreated(
          topicId: 777,
          slug: 'release',
          title: 'Write release notes',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transport.writes.single.body['card'], {'topic_id': 777});
      expect(handle.composing(10, cardId: 102), isFalse);
      request!.onCompleted!(
        const PluginTopicCreated(topicId: 778, slug: 'other', title: 'Other'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transport.writes, hasLength(1));
    },
  );
  test('queued or cancelled composer does not attach a floater', () async {
    late BoardsFixture fixture;
    OpenNewTopicComposerRequest? request;
    final composer = PluginComposerHost(
      buildComposer: (_) => null,
      openNewTopic: (value) async {
        request = value;
        return OpenComposerResult.opened;
      },
      isActive: (_) => true,
      siteConfigFor: (_) => fixture.config,
      siteConfigListenableFor: (_) => fixture.settings,
    );
    fixture = BoardsFixture(composer: composer);
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    await handle.createTopic('boards/1', 10, cardId: 102);
    request!.onCompleted!(const PluginTopicCreationQueued());
    await Future<void>.delayed(Duration.zero);
    expect(fixture.transport.writes, isEmpty);
    expect(handle.composing(10, cardId: 102), isFalse);
    await handle.createTopic('boards/1', 10, cardId: 102);
    request!.onCompleted!(const PluginTopicCreationCancelled());
    await Future<void>.delayed(Duration.zero);
    expect(fixture.transport.writes, isEmpty);
  });
  test(
    'failed promotion attachment retains topic ID for retry without another creation',
    () async {
      late BoardsFixture fixture;
      OpenNewTopicComposerRequest? request;
      var opens = 0;
      final composer = PluginComposerHost(
        buildComposer: (_) => null,
        openNewTopic: (value) async {
          opens++;
          request = value;
          return OpenComposerResult.opened;
        },
        isActive: (_) => true,
        siteConfigFor: (_) => fixture.config,
        siteConfigListenableFor: (_) => fixture.settings,
      );
      fixture = BoardsFixture(composer: composer);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.transport.failures['PUT /boards/api/boards/1/cards/102'] =
          const WriteException(WriteFailure.forbidden);
      await handle.createTopic('boards/1', 10, cardId: 102);
      request!.onCompleted!(
        const PluginTopicCreated(
          topicId: 777,
          slug: 'release',
          title: 'Release',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(handle.createdTopic(10, cardId: 102), 777);
      expect((await handle.attachCreatedTopic(10, cardId: 102)).saved, isTrue);
      expect(opens, 1);
      expect(handle.createdTopic(10, cardId: 102), isNull);
    },
  );
  test(
    'late composer completion after account retirement cannot attach',
    () async {
      late BoardsFixture fixture;
      OpenNewTopicComposerRequest? request;
      final composer = PluginComposerHost(
        buildComposer: (_) => null,
        openNewTopic: (value) async {
          request = value;
          return OpenComposerResult.opened;
        },
        isActive: (_) => true,
        siteConfigFor: (_) => fixture.config,
        siteConfigListenableFor: (_) => fixture.settings,
      );
      fixture = BoardsFixture(composer: composer);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      await handle.createTopic('boards/1', 10, cardId: 102);
      fixture.requests.forget(boardsSite);
      fixture.controller.forget(boardsSite);
      request!.onCompleted!(
        const PluginTopicCreated(
          topicId: 777,
          slug: 'release',
          title: 'Release',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transport.writes, isEmpty);
      expect(handle.createdTopic(10, cardId: 102), isNull);
    },
  );
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
    'a released board keeps its snapshot and refreshes when shown again',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      int boardReads() => fixture.transport.reads
          .where((request) => request.path == '/boards/api/boards/1.json')
          .length;
      final first = fixture.controller.acquire(boardsSite, 1);
      await pumpEventQueue();
      first.release();
      expect(fixture.live.channels, isEmpty);
      (fixture.data['board'] as Map)['name'] = 'Renamed while away';
      final reads = boardReads();
      final second = fixture.controller.acquire(boardsSite, 1);
      addTearDown(second.release);
      expect(second, same(first));
      expect(second.snapshot?.name, 'Product roadmap');
      await pumpEventQueue();
      expect(second.snapshot?.name, 'Renamed while away');
      expect(boardReads(), reads + 1);
      expect(fixture.live.subscriberCount('/boards/1'), 1);
    },
  );
  test('released boards stay idle and an account refresh drops them', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final first = fixture.controller.acquire(boardsSite, 1);
    await pumpEventQueue();
    first.release();
    final reads = fixture.transport.reads.length;
    final channels = RecordingPluginLiveChannels();
    fixture.controller
      ..setForeground(false)
      ..setForeground(true)
      ..attachPluginTracker(boardsSite, channels);
    await fixture.controller.hydratePluginRoute(boardsSite, 'boards/1');
    await pumpEventQueue();
    expect(fixture.transport.reads, hasLength(reads));
    expect(fixture.live.channels, isEmpty);
    expect(channels.channels, isEmpty);
    fixture.controller.pluginCurrentUserRefreshed(boardsSite);
    await pumpEventQueue();
    expect(fixture.transport.reads, hasLength(reads));
    final second = fixture.controller.acquire(boardsSite, 1);
    addTearDown(second.release);
    expect(second.snapshot, isNull);
  });
  test('only the eight most recently released boards are kept', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    for (var id = 2; id <= 9; id++) {
      fixture.transport.responders['GET /boards/api/boards/$id.json'] = (_) => {
        ...fixture.data,
        'board': {...boardObject(fixture.data['board']), 'id': id},
      };
    }
    for (var id = 1; id <= 9; id++) {
      final handle = fixture.controller.acquire(boardsSite, id);
      await pumpEventQueue();
      expect(handle.snapshot?.id, id);
      handle.release();
    }
    final oldest = fixture.controller.acquire(boardsSite, 1);
    addTearDown(oldest.release);
    expect(oldest.snapshot, isNull);
    final kept = fixture.controller.acquire(boardsSite, 2);
    addTearDown(kept.release);
    expect(kept.snapshot?.id, 2);
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
    'invalidation during read discards the superseded answer and rereads',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      final pending = Completer<Map<String, dynamic>>();
      var count = 0;
      String? heldDuringReread;
      fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) {
        if (++count == 1) return pending.future;
        heldDuringReread = handle.snapshot?.name;
        return boardFixtureJson(canWrite: false);
      };
      final reading = handle.refresh();
      await Future<void>.delayed(Duration.zero);
      fixture.live.deliver('/boards/1', {
        'type': 'board_updated',
        'client_id': 'test-client',
      });
      final superseded = boardFixtureJson();
      (superseded['board'] as Map)['name'] = 'Superseded';
      pending.complete(superseded);
      await reading;
      expect(count, 2);
      expect(heldDuringReread, 'Product roadmap');
      expect(handle.snapshot!.canWrite, isFalse);
    },
  );
  test(
    'same-account refresh fences a directory read and shares its successor',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final replies = <Completer<Map<String, dynamic>>>[];
      fixture.transport.responders['GET /boards/api/boards.json'] = (_) {
        replies.add(Completer());
        return replies.last.future;
      };
      Map<String, dynamic> named(String name) => {
        'boards': [
          {...boardObject(fixture.data['board']), 'name': name},
        ],
      };
      final stale = fixture.controller.loadDirectory(boardsSite);
      await Future<void>.delayed(Duration.zero);
      expect(replies, hasLength(1));
      fixture.controller.pluginCurrentUserRefreshed(boardsSite);
      final current = fixture.controller.loadDirectory(boardsSite);
      await Future<void>.delayed(Duration.zero);
      expect(replies, hasLength(2));
      replies.first.complete(named('Before refresh'));
      expect(await stale, isEmpty);
      expect(fixture.controller.directory(boardsSite), isNull);
      final joined = fixture.controller.loadDirectory(boardsSite);
      await Future<void>.delayed(Duration.zero);
      expect(replies, hasLength(2));
      replies[1].complete(named('After refresh'));
      expect((await current).single.name, 'After refresh');
      expect((await joined).single.name, 'After refresh');
      expect(
        fixture.controller.directory(boardsSite)!.single.name,
        'After refresh',
      );
    },
  );
  test(
    'board reads keep the held directory current without reading it',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      expect(fixture.controller.directory(boardsSite), isNull);
      final held = await fixture.controller.loadDirectory(boardsSite);
      expect(held.single.column(10)!.title, 'Backlog');
      final result = await handle.updateColumn(
        10,
        title: 'Ideas',
        icon: '',
        order: BoardColumnOrder.priority,
      );
      expect(result.saved, isTrue);
      final directory = fixture.controller.directory(boardsSite)!;
      expect(directory.single.column(10)!.title, 'Ideas');
      expect(
        await fixture.controller.loadDirectory(boardsSite),
        same(directory),
      );
      expect(
        fixture.transport.reads.where(
          (request) => request.path == '/boards/api/boards.json',
        ),
        hasLength(1),
      );
    },
  );
  test(
    'a board revoked before the directory is read leaves it unread',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      fixture.transport.failures['GET /boards/api/boards/1.json'] =
          const WriteException(WriteFailure.forbidden);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      expect(handle.snapshot, isNull);
      expect(fixture.controller.directory(boardsSite), isNull);
      expect(
        (await fixture.controller.loadDirectory(boardsSite)).single.name,
        'Product roadmap',
      );
    },
  );
  test('topic-scoped board choices never replace the directory', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.transport.responders['GET /boards/api/boards/available.json'
        '?allowed_permissions=edit,manage&topic_id=500'] = (_) => {
      'boards': [
        {...boardObject(fixture.data['board']), 'id': 2, 'name': 'Support'},
      ],
    };
    await fixture.controller.loadDirectory(boardsSite);
    final choices = await fixture.controller.loadDirectory(
      boardsSite,
      topicId: 500,
    );
    expect(choices.single.name, 'Support');
    expect(
      fixture.controller.directory(boardsSite)!.single.name,
      'Product roadmap',
    );
  });
  test('malformed board replies surface as read errors', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.transport.responders['GET /boards/api/boards.json'] = (_) => {
      'boards': 'none',
    };
    await expectLater(
      fixture.controller.loadDirectory(boardsSite),
      throwsFormatException,
    );
    final replies = [
      {
        ...fixture.data,
        'board': boardObject(fixture.data['board'])..['id'] = 2,
      },
      {'board': fixture.data['board']},
    ];
    var reply = replies.first;
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        reply;
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    for (final next in replies) {
      reply = next;
      await handle.refresh();
      expect(handle.snapshot, isNull);
      expect(handle.error, contains('Invalid board response'));
    }
  });
  test(
    'setting disable cycle retires composer slots and attachment receipts',
    () async {
      late BoardsFixture fixture;
      OpenNewTopicComposerRequest? request;
      final composer = PluginComposerHost(
        buildComposer: (_) => null,
        openNewTopic: (value) async {
          request = value;
          return OpenComposerResult.opened;
        },
        isActive: (_) => true,
        siteConfigFor: (_) => fixture.config,
        siteConfigListenableFor: (_) => fixture.settings,
      );
      fixture = BoardsFixture(composer: composer);
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.transport.failures['PUT /boards/api/boards/1/cards/102'] =
          const WriteException(WriteFailure.forbidden);
      await handle.createTopic('boards/1', 10, cardId: 102);
      request!.onCompleted!(
        const PluginTopicCreated(
          topicId: 777,
          slug: 'release',
          title: 'Release',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(handle.createdTopic(10, cardId: 102), 777);
      await handle.refresh();
      await handle.createTopic('boards/1', 10);
      final retired = request!;
      expect(handle.composing(10), isTrue);
      fixture.config = _boardsConfig(enabled: false);
      fixture.config = _boardsConfig(enabled: true);
      await handle.refresh();
      expect(handle.createdTopic(10, cardId: 102), isNull);
      expect(handle.composing(10), isFalse);
      expect(
        await handle.createTopic('boards/1', 10),
        OpenComposerResult.opened,
      );
      retired.onCompleted!(const PluginTopicCreationCancelled());
      await Future<void>.delayed(Duration.zero);
      expect(handle.composing(10), isTrue);
    },
  );
  test('only standalone cards that still exist can be promoted', () async {
    late BoardsFixture fixture;
    OpenNewTopicComposerRequest? request;
    final composer = PluginComposerHost(
      buildComposer: (_) => null,
      openNewTopic: (value) async {
        request = value;
        return OpenComposerResult.opened;
      },
      isActive: (_) => true,
      siteConfigFor: (_) => fixture.config,
      siteConfigListenableFor: (_) => fixture.settings,
    );
    fixture = BoardsFixture(composer: composer);
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect(
      await handle.createTopic('boards/1', 10, cardId: 101),
      OpenComposerResult.unavailable,
    );
    expect(request, isNull);
    await handle.createTopic('boards/1', 10, cardId: 102);
    expect(request!.sourceStillCurrent!(), isTrue);
    (fixture.columns.first['cards'] as List).removeWhere(
      (raw) => boardObject(raw)['id'] == 102,
    );
    await handle.refresh();
    expect(request!.sourceStillCurrent!(), isFalse);
  });
  test('receipt retry waits for an in-flight board read', () async {
    late BoardsFixture fixture;
    OpenNewTopicComposerRequest? request;
    final composer = PluginComposerHost(
      buildComposer: (_) => null,
      openNewTopic: (value) async {
        request = value;
        return OpenComposerResult.opened;
      },
      isActive: (_) => true,
      siteConfigFor: (_) => fixture.config,
      siteConfigListenableFor: (_) => fixture.settings,
    );
    fixture = BoardsFixture(composer: composer);
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    fixture.transport.failures['POST /boards/api/boards/1/cards'] =
        const WriteException(WriteFailure.forbidden);
    await handle.createTopic('boards/1', 10);
    request!.onCompleted!(
      const PluginTopicCreated(topicId: 777, slug: 'release', title: 'Release'),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(handle.createdTopic(10), 777);
    await handle.refresh();
    final reply = Completer<Map<String, dynamic>>();
    var held = true;
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) {
      if (!held) return fixture.data;
      held = false;
      return reply.future;
    };
    final read = handle.refresh();
    expect(handle.reading, isTrue);
    final retry = handle.attachCreatedTopic(10);
    reply.complete(fixture.data);
    await read;
    expect((await retry).saved, isTrue);
    expect(handle.snapshot!.card(900)!.topicId, 777);
  });
  test(
    'board read failure withdraws a revoked board and retains it otherwise',
    () async {
      for (final (failure, revoked) in <(Object, bool)>[
        (
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            boardsSite,
            statusCode: 404,
          ),
          true,
        ),
        (const WriteException(WriteFailure.forbidden), true),
        (
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            boardsSite,
            statusCode: 500,
          ),
          false,
        ),
      ]) {
        final fixture = BoardsFixture();
        addTearDown(fixture.dispose);
        await fixture.controller.loadDirectory(boardsSite);
        final handle = fixture.controller.acquire(boardsSite, 1);
        addTearDown(handle.release);
        await handle.refresh();
        fixture.transport.failures['GET /boards/api/boards/1.json'] = failure;
        await handle.refresh();
        expect(handle.error, isNotNull);
        expect(handle.snapshot == null, revoked);
        expect(fixture.live.subscriberCount('/boards/1'), revoked ? 0 : 1);
        expect(
          fixture.controller.directory(boardsSite)!.map((board) => board.id),
          revoked ? isEmpty : [1],
        );
      }
    },
  );
  test(
    'background suspends live updates and foreground reconciles the board',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      fixture.controller.setForeground(false);
      expect(fixture.live.channels, isEmpty);
      await handle.refresh();
      expect(fixture.live.channels, isEmpty);
      (fixture.data['board'] as Map)['name'] = 'Changed while away';
      fixture.controller.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(handle.snapshot!.name, 'Changed while away');
      expect(fixture.live.subscriberCount('/boards/1'), 1);
    },
  );
  test('unrelated site setting changes keep the mounted board', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    final snapshot = handle.snapshot;
    final reads = fixture.transport.reads.length;
    fixture.config = SiteConfig(
      emojiEnabled: false,
      plugins: fixture.config.plugins,
    );
    await Future<void>.delayed(Duration.zero);
    expect(handle.snapshot, same(snapshot));
    expect(fixture.transport.reads, hasLength(reads));
  });
  test('unsent create failure is refused rather than uncertain', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.transport.failures['POST /boards/api/boards/1/cards'] =
        const WriteException(WriteFailure.unreachable, notSent: true);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect(
      (await handle.saveStandalone(10, 'Task', '')).state,
      BoardWriteState.refused,
    );
    expect(
      (await handle.saveStandalone(10, '  ', '')).state,
      BoardWriteState.refused,
    );
    expect(fixture.transport.writes, hasLength(1));
  });
  test('failed topic repair after a saved move asks for refresh', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    fixture.topicReloadFailure = StateError('topic offline');
    final result = await handle.move(
      101,
      11,
      const PlaceFirst(),
      review: (_, _, _) async => const BoardRepair(),
    );
    expect(result.state, BoardWriteState.refreshNeeded);
    expect(result.saved, isTrue);
    expect(handle.snapshot!.card(101)!.columnId, 11);
  });
  test('removing a topic card repairs its canonical topic', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.transport.responders['DELETE /boards/api/boards/1/cards/101'] =
        (_) {
          (fixture.columns.first['cards'] as List).removeWhere(
            (raw) => boardObject(raw)['id'] == 101,
          );
          return <String, dynamic>{};
        };
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect((await handle.removeCard(101)).saved, isTrue);
    expect(handle.snapshot!.card(101), isNull);
    expect(fixture.refreshedTopics, [500]);
  });
  test('placement anchors must be another card in the target column', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    for (final (column, anchor) in [(10, 101), (11, 102)]) {
      expect(
        (await handle.move(
          101,
          column,
          PlaceAfter(anchor),
          review: (_, _, _) async => const BoardRepair(),
        )).state,
        BoardWriteState.refused,
      );
    }
    expect(fixture.transport.writes, isEmpty);
  });
  test(
    'same-column reorder skips constraint checks and confirmation',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      (fixture.data['board'] as Map)['require_confirmation'] = true;
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      var reviews = 0;
      final result = await handle.move(
        101,
        10,
        const PlaceFirst(),
        review: (_, _, _) async {
          reviews++;
          return null;
        },
      );
      expect(result.saved, isTrue);
      expect(reviews, 0);
      expect(
        fixture.transport.writes.single.path,
        '/boards/api/boards/1/cards/101',
      );
    },
  );
  test(
    'cross-column moves send the reviewed repair and server-side placement',
    () async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      fixture
              .transport
              .responders['PUT /boards/api/boards/1/check-constraint-mismatches'] =
          (_) => {
            'categories_needed': <int>[],
            'tags_needed': ['doing'],
          };
      final handle = fixture.controller.acquire(boardsSite, 1);
      addTearDown(handle.release);
      await handle.refresh();
      await handle.move(
        101,
        11,
        const PlaceLast(),
        review: (_, _, check) async {
          expect(check.tagNames, ['doing']);
          return const BoardRepair(tagNames: ['doing']);
        },
      );
      expect(fixture.transport.writes.first.body, {
        'topic_id': 500,
        'target_column_id': 11,
      });
      expect(fixture.transport.writes.last.body, {
        'card': {'column_id': 11},
        'constraint_fix': {
          'tag_names': ['doing'],
        },
      });
      fixture
              .transport
              .responders['PUT /boards/api/boards/1/check-constraint-mismatches'] =
          (_) => {'categories_needed': <int>[], 'tags_needed': <String>[]};
      await handle.move(
        101,
        12,
        const PlaceFirst(),
        review: (_, _, _) async => const BoardRepair(),
      );
      expect(fixture.transport.writes.last.body, {
        'card': {'column_id': 12},
      });
    },
  );
  test('confirmation boards review every topic addition', () async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    (fixture.data['board'] as Map)['require_confirmation'] = true;
    final handle = fixture.controller.acquire(boardsSite, 1);
    addTearDown(handle.release);
    await handle.refresh();
    expect(
      (await handle.addTopic(700, 11, review: (_, _, _) async => null)).state,
      BoardWriteState.cancelled,
    );
    expect(fixture.transport.writes.map((request) => request.path), [
      '/boards/api/boards/1/check-constraint-mismatches',
    ]);
  });
}

SiteConfig _boardsConfig({required bool enabled}) => SiteConfig(
  plugins: PluginData.none.withValue(
    boardsSettingsKey,
    BoardsSettings(enabled: enabled),
  ),
);

final class _PausedWriteRequestHost implements PluginRequestHost {
  final delegate = PluginTestRequestHost(apiKeys: {boardsSite: 'key'});
  final admitted = Completer<void>();
  final ready = Completer<void>();

  @override
  PluginSiteLease capture(String siteUrl) => delegate.capture(siteUrl);

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) =>
      delegate.credentialsFor(siteUrl);

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    if (!admitted.isCompleted) admitted.complete();
    await ready.future;
    return delegate.writeCredentialFor(siteUrl);
  }
}
