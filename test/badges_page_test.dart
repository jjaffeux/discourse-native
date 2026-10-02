import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/badge.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/shell/badges_controller.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';
import 'support/shell_test_harness.dart' show renderedText;
import 'support/skeleton_expectations.dart';

const _site = 'https://example.com';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1200)]) {
    for (final route in [const BadgeRoute.directory(), BadgeRoute.detail(1)]) {
      testWidgets('badge skeleton fills ${route.path} at $size', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          const BadgesState(loading: true),
          route: route,
          size: size,
          settle: false,
        );
        expectSkeletonFillsViewport(
          tester,
          label: 'Loading badges',
          bottom: size.height,
        );
        expect(find.bySemanticsLabel('Loading badges'), findsOneWidget);
        semantics.dispose();
      });
    }
  }

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
          final lastRow = find.byKey(ValueKey('badge-row-${group * 15}'));
          for (
            var step = 0;
            step < 150 && lastRow.hitTestable().evaluate().isEmpty;
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
          expect(lastRow.hitTestable(), findsOneWidget);
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
          find.byKey(const ValueKey('badge-row-1')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final (width, scale, platform) in [
    (390.0, 1.0, TargetPlatform.macOS),
    (760.0, 1.0, TargetPlatform.macOS),
    (1100.0, 1.0, TargetPlatform.macOS),
    (1100.0, 1.0, TargetPlatform.android),
    (390.0, 2.0, TargetPlatform.android),
  ]) {
    testWidgets('grouped rows fit $width at text scale $scale on $platform', (
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
      final rows = [
        for (var id = 1; id <= 3; id++)
          tester.getRect(find.byKey(ValueKey('badge-row-$id'))),
      ];
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].left, greaterThanOrEqualTo(0));
        expect(rows[i].right, lessThanOrEqualTo(width));
        for (var j = i + 1; j < rows.length; j++) {
          expect(rows[i].overlaps(rows[j]), isFalse);
        }
      }
      expect(rows.map((rect) => rect.left).toSet().length, 1);
      expect(rows.every((rect) => rect.width == width), isTrue);
      expect(rows[0].height, greaterThan(rows[1].height));
      expect(find.bySemanticsLabel(RegExp('Earned')), findsWidgets);
      await tester.tap(find.text('Nouvel utilisateur du mois'));
      expect(opened?.id, 1);
      opened = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened?.id, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('filters badges while preserving groups and catalog totals', (
    tester,
  ) async {
    await _pump(
      tester,
      BadgesState(
        catalog: BadgeCatalog.fromJson(badgeCatalogWire, _site),
        loaded: true,
      ),
    );
    Future<void> select(String label) async {
      await tester.tap(find.byKey(const ValueKey('badge-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await select('Earned');
    expect(find.text('Autobiographer'), findsOneWidget);
    expect(find.text('Nice Reply'), findsOneWidget);
    expect(find.text('Reader'), findsNothing);
    expect(find.text('3 badges · 2 earned'), findsOneWidget);

    await select('Not earned');
    expect(find.text('Reader'), findsOneWidget);
    expect(find.text('Autobiographer'), findsNothing);
    expect(find.text('Community'), findsNothing);

    await select('Silver');
    expect(find.text('Nice Reply'), findsOneWidget);
    expect(find.text('Getting Started'), findsNothing);

    await select('Gold');
    expect(find.text('No badges match this filter.'), findsOneWidget);
    expect(find.byType(BadgeRow), findsNothing);

    await select('All badges');
    expect(find.byType(BadgeRow), findsNWidgets(3));
  });

  testWidgets('clears personal filters when earned state is removed', (
    tester,
  ) async {
    await _pump(
      tester,
      BadgesState(
        catalog: BadgeCatalog.fromJson(badgeCatalogWire, _site),
        loaded: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('badge-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Earned').last);
    await tester.pumpAndSettle();
    await _pump(
      tester,
      BadgesState(
        catalog: BadgeCatalog.fromJson({
          'badges': [
            {...badgeWire}..remove('has_badge'),
          ],
        }, _site),
        loaded: true,
      ),
    );
    expect(find.text('All badges'), findsOneWidget);
    expect(find.text('Autobiographer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('badge-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Earned'), findsNothing);
    expect(find.text('Not earned'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.byType(DAlert), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
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
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recipient refresh keeps loaded rows visible', (tester) async {
    final badge = DiscourseBadge.fromJson(badgeWire, _site);
    final grants = BadgeGrantPage.fromJson(badgeGrantsWire(), _site).grants;
    await _pump(
      tester,
      BadgesState(badge: badge, grants: grants, loaded: true, loading: true),
      route: badge.route,
    );
    expect(find.byKey(const ValueKey('badge-grant-1')), findsOneWidget);
    expect(find.text('sam'), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(find.text('No awards to display.'), findsNothing);
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
