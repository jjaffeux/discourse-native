import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_api.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'gamification_fixture.dart';

void main() {
  late GamificationFixture f;
  setUp(() => f = GamificationFixture());
  tearDown(() => f.dispose());
  test(
    'default leaderboard negotiates JSON at the mounted subfolder root',
    () async {
      final requests = <http.Request>[];
      final transport = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/community/leaderboard/') {
            if (request.url.queryParameters['format'] == 'json') {
              return http.Response(jsonEncode(gameResponse()), 200);
            }
            return http.Response('<html>Leaderboard</html>', 200);
          }
          return http.Response('Not Found', 404);
        }),
      );
      addTearDown(transport.close);

      final read =
          await GamificationApi(transport).readLeaderboard(
                gameSite,
                gameAuth,
                const GamificationQuery(period: GamificationPeriod.weekly),
                previewUserLimit: 10,
              )
              as LeaderboardReady;

      expect(read.board.id, 1);
      expect(read.users.map((user) => user.position), [1, 1, 3]);
      expect(requests.single.url.path, '/community/leaderboard/');
      expect(requests.single.url.queryParameters, {
        'format': 'json',
        'page': '0',
        'period': 'weekly',
        'user_limit': '10',
      });
    },
  );
  test(
    'default/detail paths, all period wires and authoritative ties',
    () async {
      for (final p in GamificationPeriod.values) {
        final read =
            await f.controller.api.readLeaderboard(
                  gameSite,
                  gameAuth,
                  GamificationQuery(period: p),
                )
                as LeaderboardReady;
        expect(read.users.map((u) => u.position), [1, 1, 3]);
        expect(read.users.last.totalScore, 0);
        expect((read.personal as RankedMember).user.position, 12);
      }
      await f.controller.api.readLeaderboard(
        gameSite,
        gameAuth,
        const GamificationQuery(target: LeaderboardById(1)),
      );
      expect(f.transport.reads.last.path, '/leaderboard/1.json?page=0');
      await f.controller.api.readLeaderboard(
        gameSite,
        gameAuth,
        const GamificationQuery(),
        page: 1,
      );
      expect(f.transport.reads.last.path, '/leaderboard/?format=json&page=1');
      expect(GamificationPeriod.decode('all'), GamificationPeriod.allTime);
    },
  );
  test(
    'pending serializer root is handled before ranked response decoding',
    () async {
      f.publicResponse = {
        'leaderboard': gameBoard(),
        'users': <Object?>[],
        'reason': 'Positions are being prepared',
      };
      final read =
          await f.controller.api.readLeaderboard(
                gameSite,
                gameAuth,
                const GamificationQuery(),
              )
              as LeaderboardPreparing;
      expect(read.board!.createdById, -1);
      expect(read.reason, 'Positions are being prepared');
      f.publicResponse = {'users': <Object?>[], 'reason': 'Preparing'};
      expect(
        (await f.controller.api.readLeaderboard(
                  gameSite,
                  gameAuth,
                  const GamificationQuery(),
                )
                as LeaderboardPreparing)
            .board,
        isNull,
      );
    },
  );
  test('anonymous and unranked personal results stay distinct', () async {
    f.publicResponse = gameResponse(personal: false);
    final anon =
        await f.controller.api.readLeaderboard(
              gameSite,
              const PluginRequestCredentials(apiKey: null, clientId: ''),
              const GamificationQuery(),
            )
            as LeaderboardReady;
    expect(anon.personal, isA<AnonymousRank>());
    final member =
        await f.controller.api.readLeaderboard(
              gameSite,
              gameAuth,
              const GamificationQuery(),
            )
            as LeaderboardReady;
    expect(member.personal, isA<UnrankedMember>());
  });
  test('create payload is minimal and PUT is a full configuration', () async {
    final api = GamificationApi(f.transport);
    final created = await api.createBoard(
      gameSite,
      gameAuth,
      name: 'Contest',
      creatorId: -1,
    );
    expect(f.transport.writes.single.body, {
      'name': 'Contest',
      'created_by_id': -1,
    });
    await api.updateBoard(
      gameSite,
      gameAuth,
      created.board.id,
      GamificationBoardDraft(
        name: 'Contest',
        excludedGroupIds: {10},
        categoryIds: {4},
        scoreOverrides: {GamificationRule.chatMessageCreated: 0},
      ),
    );
    final write = f.transport.writes.last;
    expect(write.path, '/admin/plugins/gamification/leaderboard/2.json');
    expect(write.method, 'PUT');
    expect(
      write.body.keys,
      unorderedEquals([
        'name',
        'from_date',
        'to_date',
        'default_period',
        'period_filter_disabled',
        'visible_to_groups_ids',
        'included_groups_ids',
        'excluded_groups_ids',
        'scorable_category_ids',
        'score_overrides',
      ]),
    );
    expect(write.body['score_overrides'], {'chat_message_created': 0});
  });
  test(
    'global settings whitelist18 values, signed weights and category-list wire',
    () async {
      f.global['like_given_score_value'] = '-5';
      final api = GamificationApi(f.transport),
          settings = await f.controller.api.readGlobalSettings(
            gameSite,
            gameAuth,
          );
      expect(settings.weights[GamificationRule.likeGiven], -5);
      await api.saveGlobalSettings(
        gameSite,
        gameAuth,
        GamificationGlobalSettings(
          enabled: false,
          categoryIds: {4, 5},
          weights: settings.weights,
          ranking: GamificationRankingStrategy.rank,
        ),
      );
      final body = f.transport.writes.single.body['settings'] as Map;
      expect(body, hasLength(18));
      expect(body['scorable_categories'], {'value': '4|5'});
      expect(body['score_ranking_strategy'], {'value': 'rank'});
      expect((await api.readGlobalSettings(gameSite, gameAuth)).categoryIds, {
        4,
        5,
      });
    },
  );
  test(
    'event edits clear category and description explicitly; user/date omitted',
    () async {
      await f.controller.api.editScoreEvent(
        gameSite,
        gameAuth,
        const EditScoreEvent(
          id: 1,
          points: -9,
          description: null,
          categoryId: null,
        ),
      );
      expect(f.transport.writes.single.body, {
        'id': 1,
        'points': -9,
        'description': '',
        'category_id': '',
      });
      final events = await f.controller.api.readScoreEvents(
        gameSite,
        gameAuth,
        const ScoreEventQuery(),
      );
      expect(events.single.categoryId, isNull);
      expect(events.single.points, -9);
      await f.controller.api.enqueueRecalculation(
        gameSite,
        gameAuth,
        fromDate: DCalendarDate(2014, 8, 26),
      );
      expect(f.transport.writes.last.body, {'from_date': '2014-08-26'});
    },
  );
  test(
    'malformed ranks and event overflow fail rather than inventing values',
    () async {
      f.publicResponse = gameResponse(
        users: [
          {...gameUser(), 'position': null},
        ],
      );
      await expectLater(
        f.controller.api.readLeaderboard(
          gameSite,
          gameAuth,
          const GamificationQuery(),
        ),
        throwsFormatException,
      );
      f.events.addAll(List.generate(100, (_) => gameEvent()));
      await expectLater(
        f.controller.api.readScoreEvents(
          gameSite,
          gameAuth,
          const ScoreEventQuery(),
        ),
        throwsFormatException,
      );
    },
  );
}
