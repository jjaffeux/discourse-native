import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
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
  Future<void> pull(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final (size, dark) in [
    (const Size(1360, 900), false),
    (const Size(390, 844), false),
    (const Size(390, 844), true),
  ]) {
    testWidgets(
      'production leaderboard ranks, personal context and identity at ${size.width}, dark: $dark',
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
            theme: dark ? AppTheme.dark : AppTheme.light,
            platform: size.width < 600
                ? TargetPlatform.iOS
                : TargetPlatform.macOS,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your position'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(find.text('-2'), findsOneWidget);
        final personal = find.ancestor(
          of: find.text('Your position'),
          matching: find.byType(DCard),
        );
        expect(
          find.descendant(of: personal, matching: find.text('Rank')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: personal, matching: find.text('Cheers')),
          findsOneWidget,
        );
        expect(find.text('Refresh'), findsNothing);
        expect(find.text('About Cheers'), findsOneWidget);
        expect(find.text('1,234'), findsNWidgets(2));
        expect(find.byType(DAvatar), findsNWidgets(4));
        expect(tester.takeException(), isNull);
        await captureNativeUi(
          tester,
          'gamification-member-${size.width.toInt()}${dark ? '-dark' : ''}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'pull refresh retains period and results until server data arrives',
    (tester) async {
      gameSize(tester, const Size(1200, 1000));
      final f = GamificationFixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(gameApp(page(f)));
      await tester.pumpAndSettle();
      await gameTap(tester, find.text('All time'));
      await gameTap(tester, find.text('Last week'));
      expect(
        f.transport.reads.map((read) => read.path),
        containsAllInOrder([
          '/leaderboard/?format=json&page=0&period=weekly',
          '/leaderboard/?format=json&page=1&period=weekly',
        ]),
      );
      expect(find.text('Load more'), findsNothing);
      tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            ),
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final readback = Completer<Map<String, dynamic>>();
      f
              .transport
              .responders['GET /leaderboard/?format=json&page=0&period=weekly'] =
          (_) => readback.future;
      final before = f.transport.reads.length;
      await pull(tester);
      expect(f.transport.reads.length, before + 1);
      expect(
        f.transport.reads.last.path,
        '/leaderboard/?format=json&page=0&period=weekly',
      );
      expect(find.text('Last week'), findsOneWidget);
      expect(find.text('Member 1'), findsWidgets);
      expect(find.byType(DSpinner), findsOneWidget);
      await pull(tester);
      expect(f.transport.reads.length, before + 1);
      readback.complete(gameResponse(users: [gameUser(id: 9, score: 4321)]));
      await tester.pumpAndSettle();
      expect(find.text('Member 9'), findsWidgets);
      expect(find.text('4,321'), findsOneWidget);
      expect(find.text('Member 1'), findsNothing);
      expect(find.text('Last week'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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
    await pull(tester);
    await tester.pumpAndSettle();
    expect(find.text('Preparing positions'), findsOneWidget);
    expect(find.text('No ranked members for this period.'), findsNothing);
    f.publicResponse = gameResponse(users: [gameUser(id: 9)]);
    await pull(tester);
    await tester.pumpAndSettle();
    expect(find.text('Member 9'), findsWidgets);
    expect(find.text('Preparing positions'), findsNothing);
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
  testWidgets('pull retries a restricted short page after access changes', (
    tester,
  ) async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    const path = 'GET /leaderboard/?format=json&page=0';
    f.transport.failures[path] = const SiteLookupException(
      SiteLookupFailure.unreachable,
      '',
      statusCode: 403,
    );
    await tester.pumpWidget(gameApp(page(f)));
    await tester.pumpAndSettle();
    expect(
      find.text('This leaderboard is restricted or no longer available.'),
      findsOneWidget,
    );
    final before = f.transport.reads
        .where((read) => read.path == '/leaderboard/?format=json&page=0')
        .length;
    f.transport.failures.remove(path);
    f.publicResponse = gameResponse(users: [gameUser(id: 9)]);
    await pull(tester);
    await tester.pumpAndSettle();
    expect(
      f.transport.reads.where(
        (read) => read.path == '/leaderboard/?format=json&page=0',
      ),
      hasLength(before + 1),
    );
    expect(find.text('Member 9'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('pull cannot duplicate the initial leaderboard read', (
    tester,
  ) async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    final initial = Completer<Map<String, dynamic>>();
    f.transport.responders['GET /leaderboard/?format=json&page=0'] = (_) =>
        initial.future;
    await tester.pumpWidget(gameApp(page(f)));
    await tester.pumpAndSettle();
    expect(f.transport.reads, hasLength(1));
    await pull(tester);
    expect(f.transport.reads, hasLength(1));
    initial.complete(gameResponse());
    await tester.pumpAndSettle();
    expect(find.text('Your position'), findsOneWidget);
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
