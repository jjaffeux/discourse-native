import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_controller.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gamification_fixture.dart';

void main() {
  test(
    'retired host leases prohibit cached reuse and stale refresh fallback before observer runs',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final a = f.controller.acquire(gameSite, const GamificationQuery());
      await a.refresh();
      a.release();
      f.requests.forget(gameSite);
      f.transport.failures['GET /leaderboard/?format=json&page=0'] = Exception(
        'offline under account B',
      );
      final b = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(b.release);
      expect(b.state, isNot(isA<GamificationReady>()));
      await b.refresh();
      expect(b.state, isA<GamificationFailed>());
      await b.refresh();
      expect(b.state, isA<GamificationReady>());
      f.requests.forget(gameSite);
      expect(b.state, isA<GamificationUnavailable>());
      f.transport.failures['GET /leaderboard/?format=json&page=0'] = Exception(
        'offline under account C',
      );
      await b.refresh();
      expect(b.state, isA<GamificationFailed>());
    },
  );
  test(
    'forget clears data but reacquisition can use a new same-site account lease',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final a = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(a.release);
      await a.refresh();
      f.requests.forget(gameSite);
      f.controller.forget(gameSite);
      expect(a.state, isA<GamificationUnavailable>());
      f.controller.activatePluginSite(gameSite, connected: true);
      final b = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(b.release);
      await b.refresh();
      expect(b.state, isA<GamificationReady>());
    },
  );
  test(
    'foreground and admin refresh during save do not strand the mutation',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      final pending = Completer<Map<String, dynamic>>();
      f
              .transport
              .responders['PUT /admin/plugins/gamification/leaderboard/1.json'] =
          (_) => pending.future;
      final saved = h.saveBoard(1, GamificationBoardDraft(name: 'Updated'));
      await gameFlush();
      expect(h.busy, isTrue);
      f.controller.setForeground(false);
      f.controller.setForeground(true);
      await h.refresh();
      pending.complete({'success': true});
      expect((await saved).status, GamificationMutationStatus.saved);
      expect(h.busy, isFalse);
      expect(f.transport.writes, hasLength(1));
    },
  );
  test(
    'confirmed event POST remains saved when the follow-up list fails',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      f
              .transport
              .failures['GET /admin/plugins/gamification/score_events.json'] =
          Exception('readback failed');
      final result = await h.createEvent(
        CreateScoreEvent(
          userId: 88,
          date: DCalendarDate(2026, 10, 30),
          points: -25,
        ),
      );
      expect(result.status, GamificationMutationStatus.saved);
      expect(h.lastCreatedEvent!.id, 2);
      expect(h.lastCreatedEvent!.points, -25);
      expect(h.error, isNotNull);
      expect(f.events, hasLength(2));
      expect(f.transport.writes, hasLength(1));
      await h.queryEvents(const ScoreEventQuery());
      expect(f.transport.writes, hasLength(1));
    },
  );
  test(
    'admin records and writes are gated by their acquisition lease before observers run',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      await h.queryEvents(const ScoreEventQuery());
      expect(h.index, isNotNull);
      expect(h.settings, isNotNull);
      expect(h.events, isNotNull);
      f.requests.forget(gameSite);
      expect(h.canManage, isFalse);
      expect(h.index, isNull);
      expect(h.settings, isNull);
      expect(h.events, isNull);
      await h.saveBoard(1, GamificationBoardDraft(name: 'Old draft'));
      expect(f.transport.writes, isEmpty);
    },
  );
  test(
    'confirmed administrator settings disable active reads even before public settings refresh',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final member = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(member.release);
      await member.refresh();
      final admin = f.controller.acquireAdmin(gameSite);
      addTearDown(admin.release);
      await admin.refresh();
      f.global['discourse_gamification_enabled'] = 'false';
      await admin.refresh();
      expect(f.controller.enabled(gameSite), isFalse);
      expect(member.state, isA<GamificationUnavailable>());
      expect(admin.settings!.enabled, isFalse);
      expect(admin.index, isNull);
    },
  );
  testWidgets(
    'preparing reads retry four times, then wait for explicit refresh',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      f.publicResponse = {'users': <Object?>[], 'reason': 'Preparing'};
      final h = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(h.release);
      await tester.pump();
      expect(h.state, isA<GamificationPreparing>());
      for (final delay in [2, 5, 10, 20]) {
        await tester.pump(Duration(seconds: delay));
      }
      expect(f.transport.reads, hasLength(5));
      await tester.pump(const Duration(minutes: 1));
      expect(f.transport.reads, hasLength(5));
      h.release();
    },
  );
  test(
    'released snapshots expire after a minute and retention is bounded to eight boards',
    () async {
      var now = DateTime.utc(2026, 11, 1);
      final f = GamificationFixture(clock: () => now);
      addTearDown(f.dispose);
      final first = f.controller.acquire(gameSite, const GamificationQuery());
      await first.refresh();
      first.release();
      now = now.add(const Duration(seconds: 61));
      final readback = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /leaderboard/?format=json&page=0'] = (_) =>
          readback.future;
      final expired = f.controller.acquire(gameSite, const GamificationQuery());
      expect(expired.state, isA<GamificationReady>());
      expect((expired.state as GamificationReady).refreshing, isTrue);
      expect((expired.state as GamificationReady).snapshot.users, hasLength(3));
      await gameFlush();
      expect((expired.state as GamificationReady).snapshot.users, hasLength(3));
      readback.complete(gameResponse(board: gameBoard(name: 'Refreshed')));
      await gameFlush();
      expect(
        (expired.state as GamificationReady).snapshot.board.name,
        'Refreshed',
      );
      expect((expired.state as GamificationReady).refreshing, isFalse);
      expired.release();
      for (var id = 1; id <= 9; id++) {
        f.transport.responders['GET /leaderboard/$id.json?page=0'] = (_) =>
            gameResponse(board: gameBoard(id: id));
        final h = f.controller.acquire(
          gameSite,
          GamificationQuery(target: LeaderboardById(id)),
        );
        await h.refresh();
        h.release();
      }
      final evicted = f.controller.acquire(
        gameSite,
        const GamificationQuery(target: LeaderboardById(1)),
      );
      addTearDown(evicted.release);
      expect(evicted.state, isA<GamificationLoading>());
      await evicted.refresh();
    },
  );
  test(
    'confirmed denial evicts released snapshots before reacquisition',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final seed = f.controller.acquire(gameSite, const GamificationQuery());
      await seed.refresh();
      seed.release();
      final cached = f.controller.acquire(gameSite, const GamificationQuery());
      expect(cached.state, isA<GamificationReady>());
      f.transport.failures['GET /leaderboard/?format=json&page=0'] =
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            '',
            statusCode: 403,
          );
      await cached.refresh();
      expect(cached.state, isA<GamificationRestricted>());
      cached.release();
      final again = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(again.release);
      expect(again.state, isNot(isA<GamificationReady>()));
      await again.refresh();
    },
  );
  test(
    'a denied explicit board clears its default alias without clearing other boards',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final alias = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(alias.release);
      await alias.refresh();
      f.transport.responders['GET /leaderboard/2.json?page=0'] = (_) =>
          gameResponse(board: gameBoard(id: 2));
      final other = f.controller.acquire(
        gameSite,
        const GamificationQuery(target: LeaderboardById(2)),
      );
      addTearDown(other.release);
      await other.refresh();
      final weekly = f.controller.acquire(
        gameSite,
        const GamificationQuery(
          target: LeaderboardById(1),
          period: GamificationPeriod.weekly,
        ),
      );
      addTearDown(weekly.release);
      await weekly.refresh();
      f
              .transport
              .responders['GET /leaderboard/?format=json&page=0&period=weekly&user_limit=10'] =
          (_) => gameResponse();
      final preview = f.controller.acquire(
        gameSite,
        const GamificationQuery(period: GamificationPeriod.weekly),
        previewUserLimit: 10,
      );
      addTearDown(preview.release);
      await preview.refresh();
      final otherRead = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /leaderboard/3.json?page=0'] = (_) =>
          otherRead.future;
      final pendingOther = f.controller.acquire(
        gameSite,
        const GamificationQuery(target: LeaderboardById(3)),
      );
      addTearDown(pendingOther.release);
      await gameFlush();
      f.transport.failures['GET /leaderboard/1.json?page=0'] =
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            '',
            statusCode: 404,
          );
      final denied = f.controller.acquire(
        gameSite,
        const GamificationQuery(target: LeaderboardById(1)),
      );
      addTearDown(denied.release);
      await denied.refresh();
      otherRead.complete(gameResponse(board: gameBoard(id: 3)));
      await gameFlush();
      expect(alias.state, isA<GamificationRestricted>());
      expect(weekly.state, isA<GamificationRestricted>());
      expect(preview.state, isA<GamificationRestricted>());
      expect(other.state, isA<GamificationReady>());
      expect(pendingOther.state, isA<GamificationReady>());
    },
  );
  test(
    'an older default read cannot publish a board denied by a later direct read',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final pending = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /leaderboard/?format=json&page=0'] = (_) =>
          pending.future;
      final late = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(late.release);
      await gameFlush();
      f.transport.failures['GET /leaderboard/1.json?page=0'] =
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            '',
            statusCode: 403,
          );
      final denied = f.controller.acquire(
        gameSite,
        const GamificationQuery(target: LeaderboardById(1)),
      );
      addTearDown(denied.release);
      await denied.refresh();
      pending.complete(gameResponse());
      await gameFlush();
      expect(late.state, isA<GamificationRestricted>());
    },
  );
  test(
    'an index read begun before a write cannot replace its confirmed result',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      final oldIndex = {
        ...f.adminIndex,
        'gamification_leaderboards': [
          Map<String, dynamic>.from(f.boards.single),
        ],
      };
      final delayed = Completer<Map<String, dynamic>>();
      var reads = 0;
      f
              .transport
              .responders['GET /admin/plugins/discourse-gamification/leaderboards.json'] =
          (_) => ++reads == 1 ? delayed.future : f.adminIndex;
      final refresh = h.refresh();
      await gameFlush();
      await h.saveBoard(
        1,
        GamificationBoardDraft(name: 'Confirmed new configuration'),
      );
      expect(h.index!.boards.single.board.name, 'Confirmed new configuration');
      delayed.complete(oldIndex);
      await refresh;
      expect(h.index!.boards.single.board.name, 'Confirmed new configuration');
    },
  );
  test(
    'a global settings read begun before a write cannot replace confirmed weights',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      Map<String, dynamic> globals() => {
        'site_settings': [
          for (final e in f.global.entries)
            {'setting': e.key, 'value': e.value, 'type': 'string'},
        ],
      };
      final oldSettings = globals(),
          delayed = Completer<Map<String, dynamic>>();
      var reads = 0;
      f
              .transport
              .responders['GET /admin/site_settings.json?plugin=discourse-gamification'] =
          (_) => ++reads == 1 ? delayed.future : globals();
      final refresh = h.refresh();
      await gameFlush();
      final settings = h.settings!;
      await h.saveSettings(
        GamificationGlobalSettings(
          enabled: true,
          categoryIds: {},
          weights: {...settings.weights, GamificationRule.likeGiven: 9},
          ranking: settings.ranking,
        ),
      );
      expect(h.settings!.weights[GamificationRule.likeGiven], 9);
      delayed.complete(oldSettings);
      await refresh;
      expect(h.settings!.weights[GamificationRule.likeGiven], 9);
    },
  );
}
