import 'package:discourse_native/src/models/badge.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/shell/badges_controller.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';
import 'support/shell_test_harness.dart' show renderedText;

const _site = 'https://example.com';

void main() {
  for (final (width, scale, platform) in [
    (825.0, 1.0, TargetPlatform.macOS),
    (825.0, 2.0, TargetPlatform.macOS),
    (1100.0, 1.0, TargetPlatform.android),
    (390.0, 1.0, TargetPlatform.iOS),
    (390.0, 2.0, TargetPlatform.iOS),
  ]) {
    testWidgets(
      'scrolls through every badge group at $width and scale $scale',
      (tester) async {
        final catalog = BadgeCatalog.fromJson({
          'badge_groupings': [
            for (var group = 1; group <= 5; group++)
              {'id': group, 'name': 'Group $group', 'position': group},
          ],
          'badges': [
            for (var id = 1; id <= 75; id++)
              {
                ...badgeWire,
                'id': id,
                'name': 'Badge ${id.toString().padLeft(2, '0')}',
                'badge_grouping_id': (id - 1) ~/ 15 + 1,
                'description':
                    'Contributions remarquables durant le premier mois. ' *
                    (id % 3 + 1),
              },
          ],
        }, _site);
        await _pump(
          tester,
          BadgesState(catalog: catalog, loaded: true),
          size: Size(width, 844),
          scale: scale,
        );
        final scrollable = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        final pointerPosition = tester.getCenter(find.byType(CustomScrollView));
        for (var group = 1; group <= 5; group++) {
          final lastCard = find.byKey(ValueKey('badge-card-${group * 15}'));
          for (
            var step = 0;
            step < 150 && lastCard.hitTestable().evaluate().isEmpty;
            step++
          ) {
            final before = position.pixels;
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: pointerPosition,
                scrollDelta: const Offset(0, 400),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              position.pixels,
              greaterThan(before),
              reason: 'Scroll stopped before group $group',
            );
          }
          expect(lastCard.hitTestable(), findsOneWidget);
        }
        for (var step = 0; step < 150 && position.pixels > 0; step++) {
          final before = position.pixels;
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, 500),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            position.pixels,
            lessThan(before),
            reason: 'Scroll stopped returning to the first group',
          );
        }
        expect(position.pixels, 0);
        expect(
          find.byKey(const ValueKey('badge-card-1')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final (width, columns, scale, platform) in [
    (390.0, 1, 1.0, TargetPlatform.macOS),
    (760.0, 2, 1.0, TargetPlatform.macOS),
    (1100.0, 2, 1.0, TargetPlatform.macOS),
    (1100.0, 3, 1.0, TargetPlatform.android),
    (390.0, 1, 2.0, TargetPlatform.android),
  ]) {
    testWidgets('grouped cards fit $width at text scale $scale on $platform', (
      tester,
    ) async {
      final catalog = BadgeCatalog.fromJson({
        ...badgeCatalogWire,
        'badges': [
          {
            ...badgeWire,
            'name': 'Nouvel utilisateur du mois',
            'description':
                'Contributions remarquables durant le premier mois. ' * 3,
          },
          {...badgeWire, 'id': 2, 'name': 'Premier lien', 'has_badge': false},
          {...badgeWire, 'id': 3, 'name': 'Éditeur wiki', 'has_badge': false},
        ],
      }, _site);
      final semantics = tester.ensureSemantics();
      DiscourseBadge? opened;
      await _pump(
        tester,
        BadgesState(catalog: catalog, loaded: true),
        size: Size(width, 2000),
        scale: scale,
        onOpenBadge: (badge) => opened = badge,
      );
      expect(find.text('Getting Started'), findsOneWidget);
      expect(find.text('3 badges · 1 earned'), findsOneWidget);
      final cards = [
        for (var id = 1; id <= 3; id++)
          tester.getRect(find.byKey(ValueKey('badge-card-$id'))),
      ];
      for (var i = 0; i < cards.length; i++) {
        expect(cards[i].left, greaterThanOrEqualTo(0));
        expect(cards[i].right, lessThanOrEqualTo(width));
        for (var j = i + 1; j < cards.length; j++) {
          expect(cards[i].overlaps(cards[j]), isFalse);
        }
      }
      expect(cards.map((rect) => rect.left).toSet().length, columns);
      expect(cards[0].height, greaterThan(cards[1].height));
      expect(find.bySemanticsLabel(RegExp('Earned')), findsWidgets);
      await tester.tap(find.text('Nouvel utilisateur du mois'));
      expect(opened?.id, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets(
    'anonymous badges omit earned status and preserve custom artwork',
    (tester) async {
      final raw = {...badgeWire, 'image_url': '/uploads/custom.png'}
        ..remove('has_badge');
      await _pump(
        tester,
        BadgesState(
          catalog: BadgeCatalog.fromJson({
            'badges': [raw],
          }, _site),
          loaded: true,
        ),
      );
      expect(find.text('1 badge'), findsOneWidget);
      expect(find.bySemanticsLabel('Earned'), findsNothing);
      final artwork = tester.widget<SiteImage>(find.byType(SiteImage));
      expect(artwork.url, '$_site/uploads/custom.png');
    },
  );

  testWidgets(
    'details expose description, repeat awards, filters, and awarded posts',
    (tester) async {
      final badge = DiscourseBadge.fromJson({
        ...badgeWire,
        'allow_title': true,
        'multiple_grant': true,
      }, _site);
      final grants = BadgeGrantPage.fromJson(
        badgeGrantsWire(count: 2),
        _site,
      ).grants;
      String? opened;
      var more = 0;
      await _pump(
        tester,
        BadgesState(badge: badge, grants: grants, loaded: true, hasMore: true),
        route: badge.route,
        onOpenUrl: (url) => opened = url,
        onLoadMore: () => more++,
      );
      expect(
        renderedText('This badge is granted for completing your profile.'),
        findsOneWidget,
      );
      expect(find.text('You earned this badge'), findsOneWidget);
      expect(find.text('Can be used as a title'), findsOneWidget);
      expect(find.text('Can be earned multiple times'), findsOneWidget);
      await tester.tap(find.text('Show your awards'));
      expect(opened, '$_site/badges/1/autobiographer?username=sam');
      await tester.tap(find.text('Welcome to the community').first);
      expect(opened, '$_site/t/welcome/100/3');
      await tester.tap(find.byKey(const ValueKey('badge-load-more')));
      expect(more, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading, empty, and failed pages offer the appropriate state', (
    tester,
  ) async {
    await _pump(tester, const BadgesState(loading: true), settle: false);
    expect(find.byKey(const ValueKey('badges-loading')), findsOneWidget);
    var retries = 0;
    await _pump(
      tester,
      const BadgesState(loaded: true, error: "Couldn't load badges."),
      onRefresh: () async => retries++,
    );
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    await _pump(
      tester,
      const BadgesState(loaded: true, loading: true),
      settle: false,
    );
    expect(find.byKey(const ValueKey('badges-loading')), findsOneWidget);
    await _pump(
      tester,
      BadgesState(catalog: BadgeCatalog(const []), loaded: true),
    );
    expect(find.text('No badges to display.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  BadgesState state, {
  Size size = const Size(825, 1000),
  double scale = 1,
  BadgeRoute route = const BadgeRoute.directory(),
  ValueChanged<DiscourseBadge>? onOpenBadge,
  ValueChanged<String>? onOpenUrl,
  VoidCallback? onLoadMore,
  Future<void> Function()? onRefresh,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: BadgesPage(
            siteUrl: _site,
            route: route,
            state: state,
            currentUsername: 'sam',
            onRefresh: onRefresh ?? () async {},
            onOpenBadge: onOpenBadge ?? (_) {},
            onOpenUrl: onOpenUrl ?? (_) {},
            onLoadMore: onLoadMore ?? () {},
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
