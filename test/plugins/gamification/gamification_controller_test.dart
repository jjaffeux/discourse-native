import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_controller.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gamification_fixture.dart';

void main() {
  test(
    'independent handles keep their own period and reject old selection response',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final old = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /leaderboard.json?page=0'] = (_) =>
          old.future;
      final a = f.controller.acquire(gameSite, const GamificationQuery());
      final b = f.controller.acquire(
        gameSite,
        const GamificationQuery(period: GamificationPeriod.daily),
      );
      addTearDown(a.release);
      addTearDown(b.release);
      await gameFlush();
      f.publicResponse = gameResponse(board: gameBoard(name: 'Weekly'));
      await a.selectPeriod(GamificationPeriod.weekly);
      old.complete(gameResponse(board: gameBoard(name: 'Obsolete')));
      await gameFlush();
      expect((a.state as GamificationReady).snapshot.board.name, 'Weekly');
      expect(a.query.period, GamificationPeriod.weekly);
      expect(b.query.period, GamificationPeriod.daily);
      expect(
        (b.state as GamificationReady).snapshot.board.name,
        'Community champions',
      );
    },
  );
  test(
    'append deduplicates in-flight page and an empty page exhausts it',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(h.release);
      await h.refresh();
      final pending = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /leaderboard.json?page=1'] = (_) =>
          pending.future;
      final first = h.loadNextPage();
      await h.loadNextPage();
      await gameFlush();
      expect(
        f.transport.reads.where((r) => r.path.endsWith('page=1')),
        hasLength(1),
      );
      pending.complete(gameResponse(users: []));
      await first;
      expect(
        (h.state as GamificationReady).append,
        GamificationAppend.exhausted,
      );
      expect((h.state as GamificationReady).snapshot.users, hasLength(3));
    },
  );
  test(
    'refresh retires appending pages; duplicate users force first page refresh',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(h.release);
      await h.refresh();
      final old = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /leaderboard.json?page=1'] = (_) =>
          old.future;
      final append = h.loadNextPage();
      await gameFlush();
      await h.refresh();
      old.complete(gameResponse(users: [gameUser(id: 10, rank: 99)]));
      await append;
      expect((h.state as GamificationReady).snapshot.users.map((u) => u.id), [
        1,
        2,
        3,
      ]);
      f.transport.responders['GET /leaderboard.json?page=1'] = (_) =>
          gameResponse(users: [gameUser()]);
      final before = f.transport.reads.length;
      await h.loadNextPage();
      expect(f.transport.reads.length - before, 2);
      expect((h.state as GamificationReady).snapshot.page, 0);
    },
  );
  test(
    'account transition rejects old response and permission denial clears rows',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final old = Completer<Map<String, dynamic>>();
      f.transport.responders['GET /leaderboard.json?page=0'] = (_) =>
          old.future;
      final h = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(h.release);
      await gameFlush();
      f.requests.forget(gameSite);
      f.requests.apiKeys[gameSite] = 'account-b';
      f.user = const DiscourseUser(username: 'b', id: 90);
      f.transport.responders['GET /leaderboard.json?page=0'] = (_) =>
          gameResponse(users: [gameUser(id: 90)]);
      f.controller.pluginCurrentUserRefreshed(gameSite);
      await gameFlush();
      old.complete(gameResponse(users: [gameUser(id: 88)]));
      await gameFlush();
      expect((h.state as GamificationReady).snapshot.users.single.id, 90);
      f.transport.failures['GET /leaderboard.json?page=0'] =
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            '',
            statusCode: 403,
          );
      await h.refresh();
      expect(h.state, isA<GamificationRestricted>());
    },
  );
  test(
    'same-account refresh failure preserves visible retry state; disable clears it',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(h.release);
      await h.refresh();
      f.transport.failures['GET /leaderboard.json?page=0'] = Exception(
        'offline',
      );
      await h.refresh();
      expect((h.state as GamificationReady).error, isNotNull);
      f.disable();
      expect(h.state, isA<GamificationUnavailable>());
      expect(f.controller.enabled(gameSite), isFalse);
    },
  );
  test(
    'released snapshots cache for the account and forget retires them',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final a = f.controller.acquire(gameSite, const GamificationQuery());
      await a.refresh();
      a.release();
      final reads = f.transport.reads.length;
      final b = f.controller.acquire(gameSite, const GamificationQuery());
      addTearDown(b.release);
      expect(b.state, isA<GamificationReady>());
      expect(f.transport.reads.length, reads);
      f.controller.forget(gameSite);
      expect(b.state, isA<GamificationUnavailable>());
      expect(f.controller.installed(gameSite), isFalse);
    },
  );
  test(
    'late admin reads and mutations cannot cross account retirement',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final a = f.controller.acquireAdmin(gameSite);
      addTearDown(a.release);
      await a.refresh();
      final pending = Completer<Map<String, dynamic>>();
      f
              .transport
              .responders['POST /admin/plugins/gamification/leaderboard.json'] =
          (_) => pending.future;
      final saving = a.createAndConfigure(
        GamificationBoardDraft(name: 'Private contest'),
      );
      await gameFlush();
      f.requests.forget(gameSite);
      f.user = const DiscourseUser(username: 'member', id: 91);
      f.controller.pluginCurrentUserRefreshed(gameSite);
      pending.complete(gameBoard(id: 2));
      await saving;
      expect(a.index, isNull);
      expect(a.createdBoardId, isNull);
      expect(f.transport.writes, hasLength(1));
    },
  );
  test(
    'create/configure failure retains real ID and retry never POSTs twice',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final a = f.controller.acquireAdmin(gameSite);
      addTearDown(a.release);
      await a.refresh();
      f
              .transport
              .failures['PUT /admin/plugins/gamification/leaderboard/2.json'] =
          const WriteException(WriteFailure.validation, errors: ['Bad dates']);
      final draft = GamificationBoardDraft(
        name: 'Contest',
        scoreOverrides: {GamificationRule.likeGiven: 0},
      );
      expect(
        (await a.createAndConfigure(draft)).status,
        GamificationMutationStatus.failed,
      );
      expect(a.createdBoardId, 2);
      expect(a.pendingCreatedDraft!.name, 'Contest');
      expect(
        (await a.createAndConfigure(draft)).status,
        GamificationMutationStatus.saved,
      );
      expect(f.transport.writes.where((r) => r.method == 'POST'), hasLength(1));
      expect(a.createdBoardId, isNull);
      expect(a.index!.boards, hasLength(2));
    },
  );
  test(
    'ambiguous create is locked until readback identifies the created board',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final a = f.controller.acquireAdmin(gameSite);
      addTearDown(a.release);
      await a.refresh();
      f
              .transport
              .responders['POST /admin/plugins/gamification/leaderboard.json'] =
          (_) {
            f.boards.add({
              ...gameBoard(id: 2, name: 'Contest'),
              'created_by_id': 88,
            });
            throw const WriteException(WriteFailure.unreachable);
          };
      final draft = GamificationBoardDraft(name: 'Contest');
      expect(
        (await a.createAndConfigure(draft)).status,
        GamificationMutationStatus.unknown,
      );
      await a.createAndConfigure(draft);
      expect(f.transport.writes, hasLength(1));
      await a.reviewUncertainWrite();
      expect(a.createdBoardId, 2);
      await a.createAndConfigure(draft);
      expect(f.transport.writes.where((r) => r.method == 'POST'), hasLength(1));
    },
  );
  test(
    'disabled administrators can enable via settings while moderators cannot',
    () async {
      final f = GamificationFixture(enabled: false);
      addTearDown(f.dispose);
      final a = f.controller.acquireAdmin(gameSite);
      addTearDown(a.release);
      await a.refresh();
      expect(a.settings!.enabled, isFalse);
      expect(a.index, isNull);
      final settings = a.settings!;
      expect(
        (await a.saveSettings(
          GamificationGlobalSettings(
            enabled: true,
            categoryIds: {},
            weights: settings.weights,
            ranking: settings.ranking,
          ),
        )).status,
        GamificationMutationStatus.saved,
      );
      expect(f.controller.enabled(gameSite), isTrue);
      expect(a.index, isNotNull);
      f.user = const DiscourseUser(username: 'moderator', staff: true, id: 88);
      f.controller.pluginCurrentUserRefreshed(gameSite);
      await gameFlush();
      expect(a.canManage, isFalse);
      expect(a.settings, isNull);
    },
  );
  test('future recalc is rejected locally before spending allowance', () async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    final a = f.controller.acquireAdmin(gameSite);
    addTearDown(a.release);
    await a.refresh();
    await expectLater(
      a.recalculate(DCalendarDate(2026, 11, 2)),
      throwsArgumentError,
    );
    expect(f.transport.writes, isEmpty);
    expect(f.remaining, 5);
  });
}
