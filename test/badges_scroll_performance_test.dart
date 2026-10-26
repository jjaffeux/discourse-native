import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/badge.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/shell/badges_controller.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';

Set<RenderObject> _artwork(Finder root) {
  final objects = <RenderObject>{};
  void collect(RenderObject object) {
    // Retained layers are reported too; only count actual artwork repaints.
    if (!object.isRepaintBoundary) objects.add(object);
    object.visitChildren(collect);
  }

  for (final element in root.evaluate()) {
    collect(element.findRenderObject()!);
  }
  return objects;
}

void main({
  bool nativeView = false,
  Future<void> Function(String name)? onCapture,
}) {
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final (platform, width) in [
    (TargetPlatform.iOS, 390.0),
    if (!nativeView) ...[
      (TargetPlatform.android, 390.0),
      (TargetPlatform.macOS, 1100.0),
    ],
  ]) {
    testWidgets('badges reuse artwork while scrolling ($platform, flat)', (
      tester,
    ) async {
      if (!nativeView) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
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
              'name': 'Community badge $id',
              'badge_grouping_id': (id - 1) ~/ 15 + 1,
              'badge_type_id': id % 3 + 1,
            },
        ],
      }, 'https://example.com');
      DiscourseBadge? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SafeArea(
              child: BadgesPage(
                siteUrl: 'https://example.com',
                route: const BadgeRoute.directory(),
                state: BadgesState(catalog: catalog, loaded: true),
                onRefresh: () async {},
                onOpenBadge: (badge) => opened = badge,
                onLoadMore: () {},
                onOpenUrl: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BadgeRow).evaluate().length, lessThan(catalog.total));
      await onCapture?.call('badges-flat-top');
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(2000));
      final results = <({int controls, int headings, int rows})>[];
      for (final offset in [0.0, 1000.0]) {
        position.jumpTo(offset);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(scrollable);
        final surface = tester.widget<DPageSurface>(find.byType(DPageSurface));
        final controls = _artwork(
          find
              .descendant(
                of: find.byWidget(surface.headerControls!),
                matching: find.byType(LayoutBuilder),
              )
              .first,
        );
        final rows = _artwork(find.byType(BadgeRow));
        final headings = _artwork(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && (widget.data?.startsWith('Group ') ?? false),
          ),
        );
        var totalPaints = 0;
        var controlPaints = 0;
        var rowPaints = 0;
        var headingPaints = 0;
        final previous = debugOnProfilePaint;
        debugOnProfilePaint = (object) {
          previous?.call(object);
          totalPaints++;
          if (controls.contains(object)) controlPaints++;
          if (rows.contains(object)) rowPaints++;
          if (headings.contains(object)) headingPaints++;
        };
        try {
          final gesture = await tester.startGesture(
            tester.getCenter(scrollable),
          );
          await gesture.moveBy(const Offset(0, -40));
          await tester.pump();
          totalPaints = controlPaints = rowPaints = headingPaints = 0;
          for (var frame = 0; frame < 24; frame++) {
            final before = position.pixels;
            final delta = frame < 12 ? -4.0 : 4.0;
            await gesture.moveBy(Offset(0, delta));
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              position.pixels,
              delta < 0 ? greaterThan(before) : lessThan(before),
            );
            expect(tester.getRect(scrollable), viewport);
          }
          debugPrint(
            'BADGES_SCROLL_PAINTS platform=$platform material=flat '
            'offset=$offset total=$totalPaints controls=$controlPaints '
            'headings=$headingPaints rows=$rowPaints',
          );
          expect(totalPaints, greaterThan(0));
          results.add((
            controls: controlPaints,
            headings: headingPaints,
            rows: rowPaints,
          ));
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          debugOnProfilePaint = previous;
        }
      }
      await onCapture?.call('badges-flat-scrolled');
      await tester.tap(find.byKey(const ValueKey('badge-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DPopoverContent),
          matching: find.text('Gold'),
        ),
      );
      await tester.pumpAndSettle();
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await onCapture?.call('badges-flat-filtered');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('badge-filter')),
          matching: find.text('Gold'),
        ),
        findsOneWidget,
      );
      expect(tester.widgetList<BadgeRow>(find.byType(BadgeRow)), isNotEmpty);
      expect(
        tester
            .widgetList<BadgeRow>(find.byType(BadgeRow).hitTestable())
            .every((row) => row.badge.tier == BadgeTier.gold),
        isTrue,
      );
      await tester.tap(find.byType(BadgeRow).hitTestable().first);
      expect(opened?.tier, BadgeTier.gold);
      expect(tester.takeException(), isNull);
      for (final result in results) {
        expect(result.controls, 0);
        expect(result.headings, 0);
        expect(result.rows, 0);
      }
    }, variant: TargetPlatformVariant.only(platform));
  }
}
