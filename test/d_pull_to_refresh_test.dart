import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/application_component_catalogue.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('macOS trackpad pulls refresh with the default scroll behavior', (
    tester,
  ) async {
    final response = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.macOS,
        onRefresh: () {
          calls++;
          return response.future;
        },
      ),
    );
    final position = tester.getCenter(find.byType(ListView));
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await trackpad.panZoomStart(position);
    for (var step = 1; step <= 12; step++) {
      await trackpad.panZoomUpdate(position, pan: Offset(0, step * 30.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.bySemanticsLabel('Release to refresh'), findsOneWidget);
    expect(calls, 0);
    await trackpad.panZoomEnd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    expect(find.bySemanticsLabel('Refreshing'), findsOneWidget);
    response.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DSpinner), findsNothing);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('refresh reserves content space and collapses on $platform', (
      tester,
    ) async {
      final response = Completer<void>();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          platform: platform,
          controller: scroll,
          onRefresh: () => response.future,
        ),
      );
      final row = tester.getRect(find.text('Row 0'));
      final viewport = scroll.position.viewportDimension;
      await _pull(tester);
      await tester.pump(const Duration(seconds: 1));
      final refreshedRow = tester.getRect(find.text('Row 0'));
      expect(refreshedRow.top, closeTo(row.top + 60, 0.1));
      expect(
        tester.getRect(find.byType(DSpinner)).bottom,
        lessThan(refreshedRow.top),
      );
      expect(scroll.position.viewportDimension, closeTo(viewport - 60, 0.1));
      expect(scroll.offset, closeTo(0, 0.1));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(find.text('Row 0')), refreshedRow);
      response.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final collapsingTop = tester.getTopLeft(find.text('Row 0')).dy;
      expect(collapsingTop, greaterThan(row.top));
      expect(collapsingTop, lessThan(refreshedRow.top));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Row 0')), row);
      expect(find.byType(DSpinner), findsNothing);
      expect(scroll.position.viewportDimension, viewport);
    });

    testWidgets('pull refreshes a short list once on $platform', (
      tester,
    ) async {
      final response = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        _host(
          platform: platform,
          onRefresh: () {
            calls++;
            return response.future;
          },
        ),
      );
      expect(find.byType(DSpinner), findsNothing);
      await _pull(tester);
      expect(calls, 1);
      expect(find.bySemanticsLabel('Refreshing'), findsOneWidget);
      await _pull(tester);
      expect(calls, 1);
      response.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DSpinner), findsNothing);
    });
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets('scrolling down never flashes the indicator on $platform', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _host(platform: platform, count: 40, onRefresh: () async => calls++),
      );
      final position = tester.getCenter(find.byType(ListView));
      final gesture = await tester.createGesture(
        kind: platform == TargetPlatform.macOS
            ? PointerDeviceKind.trackpad
            : PointerDeviceKind.touch,
      );
      if (platform == TargetPlatform.macOS) {
        await gesture.panZoomStart(position);
      } else {
        await gesture.down(position);
      }
      for (var step = 1; step <= 12; step++) {
        if (platform == TargetPlatform.macOS) {
          await gesture.panZoomUpdate(position, pan: Offset(0, -step * 10.0));
        } else {
          await gesture.moveTo(position + Offset(0, -step * 10.0));
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(DSpinner), findsNothing, reason: 'Frame $step');
      }
      if (platform == TargetPlatform.macOS) {
        await gesture.panZoomEnd();
      } else {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('an unarmed pull hides when reversed on $platform', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _host(platform: platform, count: 40, onRefresh: () async => calls++),
      );
      final row = tester.getRect(find.text('Row 0'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(find.bySemanticsLabel('Pull to refresh'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Row 0')).dy, greaterThan(row.top));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(find.byType(DSpinner), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  }

  testWidgets('iOS bounce supplies pull space without a second gap', (
    tester,
  ) async {
    final response = Completer<void>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.iOS,
        controller: scroll,
        onRefresh: () => response.future,
      ),
    );
    final rowTop = tester.getTopLeft(find.text('Row 0')).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
    }
    expect(scroll.offset, lessThan(-60));
    expect(
      tester.getTopLeft(find.text('Row 0')).dy,
      closeTo(rowTop - scroll.offset, 0.1),
    );
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(
      _host(platform: TargetPlatform.iOS, controller: scroll, onRefresh: null),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text('Row 0')).dy, closeTo(rowTop + 60, 0.1));
    response.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the last row stays reachable while refreshing', (tester) async {
    final response = Completer<void>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(controller: scroll, count: 40, onRefresh: () => response.future),
    );
    final position = scroll.position;
    await _pull(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(scroll.position, same(position));
    final bounds = tester.getRect(find.byType(DPullToRefresh));
    final lastRow = tester.getRect(
      find
          .ancestor(of: find.text('Row 39'), matching: find.byType(SizedBox))
          .first,
    );
    expect(lastRow.bottom, closeTo(bounds.bottom, 0.1));
    expect(find.text('Row 39').hitTestable(), findsOneWidget);
    response.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a small pull cancels without refreshing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        onRefresh: () async {
          calls++;
        },
      ),
    );
    final row = tester.getRect(find.text('Row 0'));
    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(DSpinner), findsNothing);
    expect(tester.getRect(find.text('Row 0')), row);
  });

  testWidgets('disabling refresh during a pull collapses its space', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(_host(onRefresh: () async => calls++));
    final row = tester.getRect(find.text('Row 0'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Row 0')).dy, greaterThan(row.top));
    await tester.pumpWidget(_host(onRefresh: null));
    expect(find.byType(DSpinner), findsNothing);
    expect(tester.getRect(find.text('Row 0')), row);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling away from the top does not refresh', (tester) async {
    var calls = 0;
    final scroll = ScrollController(initialScrollOffset: 700);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        onRefresh: () async {
          calls++;
        },
        controller: scroll,
        count: 40,
      ),
    );
    await _pull(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('disabling refresh preserves scroll position and blocks pulls', (
    tester,
  ) async {
    var calls = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        onRefresh: () async {
          calls++;
        },
        controller: scroll,
        count: 40,
      ),
    );
    scroll.jumpTo(300);
    await tester.pumpWidget(
      _host(onRefresh: null, controller: scroll, count: 40),
    );
    expect(scroll.offset, 300);
    scroll.jumpTo(0);
    await _pull(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(DSpinner), findsNothing);
  });

  testWidgets('refresh completion after removal is safe', (tester) async {
    final response = Completer<void>();
    await tester.pumpWidget(_host(onRefresh: () => response.future));
    await _pull(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested scrollables do not refresh their parent', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DPullToRefresh(
            onRefresh: () async {
              calls++;
            },
            child: ListView(
              children: [
                SizedBox(
                  height: 250,
                  child: ListView(
                    key: const ValueKey('nested-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [Text('Nested row')],
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('nested-list')),
      const Offset(0, 350),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(DSpinner), findsNothing);
  });

  testWidgets('the indicator appears below a floating page header', (
    tester,
  ) async {
    final response = Completer<void>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    late DPageHeaderGeometry geometry;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: DPageSurface.headed(
            title: const Text('Page title'),
            controls: const Text('Page controls'),
            bodyBuilder: (context, header) {
              geometry = header;
              return DPullToRefresh(
                onRefresh: () => response.future,
                child: ListView(
                  controller: scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    header.spacer,
                    for (var i = 0; i < 20; i++)
                      SizedBox(height: 60, child: Text('Row $i')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    final controls = tester.getRect(find.text('Page controls'));
    await _pull(tester);
    expect(find.bySemanticsLabel('Refreshing'), findsOneWidget);
    final page = tester.getRect(find.byType(DPageSurface));
    final indicator = tester.getRect(find.byType(DSpinner));
    expect(geometry.visibleExtent, greaterThan(0));
    expect(
      indicator.top,
      greaterThanOrEqualTo(page.top + geometry.visibleExtent),
    );
    expect(
      tester.getTopLeft(find.text('Row 0')).dy,
      greaterThan(indicator.bottom),
    );
    expect(tester.getRect(find.text('Page controls')), controls);
    scroll.jumpTo(geometry.naturalExtent + 40);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Row 0').hitTestable(), findsNothing);
    expect(find.text('Row 3').hitTestable(), findsOneWidget);
    response.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('an active indicator follows live theme changes', (tester) async {
    final response = Completer<void>();
    Future<void> refresh() => response.future;
    await tester.pumpWidget(_host(onRefresh: refresh));
    await _pull(tester);
    for (final theme in [
      AppTheme.dark,
      ThemeData(colorSchemeSeed: Colors.purple),
    ]) {
      await tester.pumpWidget(_host(onRefresh: refresh, theme: theme));
      await tester.pump(const Duration(milliseconds: 300));
      final spinner = tester.widget<DSpinner>(find.byType(DSpinner));
      final tokens = DTokens.of(tester.element(find.byType(DSpinner)));
      expect(spinner.color, tokens.foreground);
    }
    response.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'screen readers can refresh and reduced motion keeps the spinner still',
    (tester) async {
      final response = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        _host(
          onRefresh: () {
            calls++;
            return response.future;
          },
          reducedMotion: true,
        ),
      );
      final refreshSemantics = find
          .descendant(
            of: find.byType(DPullToRefresh),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.customSemanticsActions?.isNotEmpty == true,
            ),
          )
          .first;
      final node = tester.getSemantics(refreshSemantics);
      final actions = node.getSemanticsData().customSemanticsActionIds!;
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.customAction,
          nodeId: node.id,
          viewId: tester.view.viewId,
          arguments: actions.single,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
      final rotation = find.descendant(
        of: find.byType(DSpinner),
        matching: find.byType(RotationTransition),
      );
      final before = tester.widget<RotationTransition>(rotation).turns.value;
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<RotationTransition>(rotation).turns.value, before);
      response.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('styleguide examples are registered and fit narrow RTL', (
    tester,
  ) async {
    expect(
      applicationComponentCatalogue.map((entry) => entry.id),
      contains('pull-to-refresh'),
    );
    final examples = componentExamples['pull-to-refresh']!;
    for (final example in examples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });
}

Widget _host({
  required Future<void> Function()? onRefresh,
  ThemeData? theme,
  TargetPlatform platform = TargetPlatform.android,
  ScrollController? controller,
  int count = 1,
  bool reducedMotion = false,
}) => MaterialApp(
  theme: (theme ?? AppTheme.light).copyWith(platform: platform),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        height: 400,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: DPullToRefresh(
            onRefresh: onRefresh,
            child: ListView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(height: 60, child: Text('Row $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _pull(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 350));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
