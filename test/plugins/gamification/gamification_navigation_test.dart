import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native route round-trips board and period without inventing catalogue',
    () {
      for (final p in GamificationPeriod.values) {
        final route = GamificationRoute(boardId: 7, period: p);
        final parsed = GamificationRoute.parse(route.id)!;
        expect(parsed.boardId, 7);
        expect(parsed.period, p);
      }
      expect(GamificationRoute.parse('gamification/0'), isNull);
      expect(GamificationRoute.parse('gamification/archive'), isNull);
      expect(GamificationRoute.parse('gamification?period=future'), isNull);
    },
  );
  test('source web routes and legacy admin alias resolve precisely', () {
    expect(
      GamificationRoute.web('/leaderboard/42', {'period': 'all'})!.period,
      GamificationPeriod.allTime,
    );
    expect(GamificationRoute.web('/leaderboard', {})!.boardId, isNull);
    expect(
      GamificationRoute.web(
        '/admin/plugins/discourse-gamification/leaderboards/42',
        {},
      )!.admin,
      isTrue,
    );
    expect(
      GamificationRoute.web('/admin/plugins/gamification.json', {})!.admin,
      isTrue,
    );
    expect(GamificationRoute.web('/leaderboard/0', {}), isNull);
    expect(GamificationRoute.web('/leaderboard/42/other', {}), isNull);
  });
}
