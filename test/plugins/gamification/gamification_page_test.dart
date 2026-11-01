import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_navigation.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_page.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_user_score.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/native_ui_evidence.dart';
import 'gamification_fixture.dart';
import 'gamification_widget_support.dart';

void main() {
  Widget page(GamificationFixture f) => GamificationPage(
    site: gameSite,
    controller: f.controller,
    navigation: GamificationNavigation(
      host: GamificationTestNavigationHost(),
      controller: f.controller,
    ),
  );
  for (final size in [const Size(1360, 900), const Size(390, 844)]) {
    testWidgets(
      'production leaderboard ranks, personal context and identity at ${size.width}',
      (tester) async {
        gameSize(tester, size);
        await prepareNativeUiEvidence(tester);
        final f = GamificationFixture();
        addTearDown(f.dispose);
        f.publicResponse = gameResponse(
          users: [gameUser(score: 1234), gameUser(id: 2, rank: 1, score: 1234)],
        );
        await tester.pumpWidget(
          gameApp(
            page(f),
            platform: size.width < 600
                ? TargetPlatform.iOS
                : TargetPlatform.macOS,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your position'), findsOneWidget);
        expect(find.text('Rank 12 · -2 Cheers'), findsOneWidget);
        expect(find.text('1,234'), findsNWidgets(2));
        expect(find.byType(DAvatar), findsNWidgets(4));
        expect(tester.takeException(), isNull);
        await captureNativeUi(
          tester,
          'gamification-member-${size.width.toInt()}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('period, refresh and append actions request server data', (
    tester,
  ) async {
    gameSize(tester, const Size(1200, 1000));
    final f = GamificationFixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(gameApp(page(f)));
    await tester.pumpAndSettle();
    await gameTap(tester, find.text('All time'));
    await gameTap(tester, find.text('Last week'));
    expect(
      f.transport.reads.last.path,
      '/leaderboard/?format=json&page=0&period=weekly',
    );
    await gameTap(tester, find.text('Load more'));
    expect(
      f.transport.reads.last.path,
      '/leaderboard/?format=json&page=1&period=weekly',
    );
    expect(find.text('Load more'), findsNothing);
    await gameTap(tester, find.text('Refresh'));
    expect(
      f.transport.reads.last.path,
      '/leaderboard/?format=json&page=0&period=weekly',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('empty unranked, anonymous and preparing states stay distinct', (
    tester,
  ) async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    f.publicResponse = gameResponse(users: [], personal: false);
    await tester.pumpWidget(gameApp(page(f)));
    await tester.pumpAndSettle();
    expect(find.text('You are not ranked for this period.'), findsOneWidget);
    expect(find.text('No ranked members for this period.'), findsOneWidget);
    f.publicResponse = {
      'leaderboard': gameBoard(),
      'users': <Object?>[],
      'reason': 'Preparing positions',
    };
    await gameTap(tester, find.text('Refresh'));
    expect(find.text('Preparing positions'), findsOneWidget);
    expect(find.text('No ranked members for this period.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    final anon = GamificationFixture(connected: false);
    addTearDown(anon.dispose);
    anon.publicResponse = gameResponse(personal: false);
    await tester.pumpWidget(gameApp(page(anon)));
    await tester.pumpAndSettle();
    expect(find.text('Your position'), findsNothing);
    expect(find.text('You are not ranked for this period.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'disabled period selector, row highlight, RTL and large text use kit behavior',
    (tester) async {
      gameSize(tester, const Size(390, 844));
      await prepareNativeUiEvidence(tester);
      final f = GamificationFixture();
      addTearDown(f.dispose);
      f.publicResponse = gameResponse(
        board: gameBoard(disabled: true),
        users: [gameUser(id: 88, score: -2, rank: 12)],
      );
      await tester.pumpWidget(
        gameApp(page(f), scale: 2, rtl: true, platform: TargetPlatform.iOS),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DSelect<GamificationPeriod>>(
              find.byType(DSelect<GamificationPeriod>),
            )
            .enabled,
        isFalse,
      );
      final table = tester.widget<DTable>(find.byType(DTable));
      expect(table.body.rows.single.selected, isTrue);
      expect(tester.takeException(), isNull);
      await captureNativeUi(tester, 'gamification-member-rtl-large');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'cached Cheers metadata links to default all-time and hides on disable',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final host = GamificationTestNavigationHost();
      var closed = false;
      await tester.pumpWidget(
        gameApp(
          Center(
            child: GamificationUserScoreMetadata(
              controller: f.controller,
              site: gameSite,
              score: const GamificationUserScore(-1234),
              navigation: GamificationNavigation(
                host: host,
                controller: f.controller,
              ),
              close: () => closed = true,
            ),
          ),
        ),
      );
      await gameTap(tester, find.text('-1,234 Cheers'));
      expect(closed, isTrue);
      expect(host.currentContent!.id, 'gamification?period=all_time');
      f.disable();
      await tester.pumpAndSettle();
      expect(find.text('-1,234 Cheers'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'score metadata for another registered forum navigates to its own site',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final host = GamificationTestNavigationHost();
      await tester.pumpWidget(
        gameApp(
          Center(
            child: GamificationUserScoreMetadata(
              controller: f.controller,
              site: 'https://second.example/forum',
              score: const GamificationUserScore(50),
              navigation: GamificationNavigation(
                host: host,
                controller: f.controller,
              ),
            ),
          ),
        ),
      );
      await gameTap(tester, find.text('50 Cheers'));
      expect(host.selected, 1);
      expect(host.currentSite.url, 'https://second.example/forum');
      expect(host.currentContent!.id, 'gamification?period=all_time');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
