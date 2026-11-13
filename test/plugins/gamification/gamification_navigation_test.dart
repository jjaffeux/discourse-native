import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_navigation.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gamification_fixture.dart';

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
  test('unrepresentable leaderboard IDs never open the default board', () {
    const oversized = '9223372036854775808';
    expect(GamificationRoute.parse('gamification/$oversized'), isNull);
    expect(GamificationRoute.parse('gamification/admin/$oversized'), isNull);
    expect(GamificationRoute.web('/leaderboard/$oversized', {}), isNull);
    expect(
      GamificationRoute.web(
        '/admin/plugins/discourse-gamification/leaderboards/$oversized/edit',
        {},
      ),
      isNull,
    );
  });

  test('native routes decline malformed query bytes', () {
    for (final value in ['%FF', '%C3', '%ED%A0%80', '%F4%90%80%80']) {
      expect(GamificationRoute.parse('gamification/7?period=$value'), isNull);
    }
  });
  test('malformed web queries decline without navigating', () async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    final host = GamificationTestNavigationHost();
    final navigation = GamificationNavigation(
      host: host,
      controller: f.controller,
    );
    var navigated = false;

    for (final path in ['/leaderboard/7', '/unrelated']) {
      for (final value in ['%FF', '%C3', '%ED%A0%80', '%F4%90%80%80']) {
        expect(
          await navigation.openPluginUrl(
            'https://second.example/forum$path?period=$value',
            onNavigated: () => navigated = true,
          ),
          isFalse,
        );
      }
    }
    expect(host.selected, 0);
    expect(host.currentContent, isNull);
    expect(navigated, isFalse);
  });
  test(
    'subfolder links select the serving forum and admin links retain new/edit identity',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final host = GamificationTestNavigationHost();
      final navigation = GamificationNavigation(
        host: host,
        controller: f.controller,
      );
      expect(
        await navigation.openPluginUrl('https://forum.example/leaderboard/7'),
        isFalse,
      );
      expect(
        await navigation.openPluginUrl(
          'https://forum.example/community/leaderboard/7?period=weekly',
        ),
        isTrue,
      );
      expect(host.currentContent!.id, 'gamification/7?period=weekly');
      expect(
        await navigation.openPluginUrl(
          'https://second.example/forum/admin/plugins/discourse-gamification/leaderboards/new',
        ),
        isTrue,
      );
      expect(host.selected, 1);
      expect(host.currentContent!.id, 'gamification/admin/new');
      expect(
        await navigation.openPluginUrl(
          'https://second.example/forum/admin/plugins/discourse-gamification/leaderboards/7/edit',
        ),
        isTrue,
      );
      expect(host.currentContent!.id, 'gamification/admin/7');
    },
  );
}
