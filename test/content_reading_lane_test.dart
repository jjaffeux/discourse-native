import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('height-only layout preserves the lane child and its state', (
    tester,
  ) async {
    final size = ValueNotifier(const Size(700, 400));
    addTearDown(size.dispose);
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: ValueListenableBuilder<Size>(
              valueListenable: size,
              builder: (context, value, child) =>
                  SizedBox.fromSize(size: value, child: child),
              child: DPageReadingLane(
                builder: (context, lane) {
                  builds++;
                  return Padding(
                    padding: lane.padding,
                    child: DInput(key: _contentKey),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'Retained input');
    final element = tester.element(find.byKey(_contentKey));
    final initialBuilds = builds;
    for (final height in [420.0, 450.0, 500.0, 400.0]) {
      size.value = Size(700, height);
      await tester.pump();
    }
    expect(builds, initialBuilds);
    expect(tester.element(find.byKey(_contentKey)), same(element));
    expect(find.text('Retained input'), findsOneWidget);
    size.value = const Size(600, 400);
    await tester.pump();
    expect(builds, initialBuilds + 1);
    expect(tester.element(find.byKey(_contentKey)), same(element));
    expect(find.text('Retained input'), findsOneWidget);
  });

  testWidgets('cached lane builder still updates inherited values and caller', (
    tester,
  ) async {
    final direction = ValueNotifier(TextDirection.ltr);
    addTearDown(direction.dispose);
    Widget lane(String label) => DPageReadingLane(
      builder: (context, geometry) =>
          Text('$label ${Directionality.of(context).name}'),
    );
    Widget host(Widget child) => MaterialApp(
      home: ValueListenableBuilder<TextDirection>(
        valueListenable: direction,
        builder: (context, value, child) =>
            Directionality(textDirection: value, child: child!),
        child: child,
      ),
    );
    await tester.pumpWidget(host(lane('First')));
    expect(find.text('First ltr'), findsOneWidget);
    direction.value = TextDirection.rtl;
    await tester.pump();
    expect(find.text('First rtl'), findsOneWidget);
    await tester.pumpWidget(host(lane('Updated')));
    expect(find.text('Updated rtl'), findsOneWidget);
  });

  for (final direction in TextDirection.values) {
    testWidgets('sidebar lane keeps the viewport at the edge in $direction', (
      tester,
    ) async {
      await _withPlatform(TargetPlatform.macOS, () async {
        await _setViewport(tester, const Size(2000, 600));
        final controller = _controller();
        await tester.pumpWidget(
          MaterialApp(
            home: ContentSettingsScope(
              controller: controller,
              child: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: ContentReadingLaneWithSidebar(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sidebarWidth: 190,
                    sidebar: const SizedBox(key: ValueKey('lane-sidebar')),
                    child: ContentReadingLane(
                      basePadding: const EdgeInsets.symmetric(horizontal: 16),
                      builder: (context, lane) => DScrollArea(
                        key: _viewportKey,
                        padding: lane.padding,
                        child: const ContentReadingLaneBox(
                          child: SizedBox(key: _contentKey, height: 2000),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final scale in [
          AppTextScale.percent80,
          AppTextScale.percent100,
          AppTextScale.percent200,
        ]) {
          await controller.setTextScale(scale);
          for (final alignment in [false, true]) {
            await controller.setLimitContentSize(alignment);
            await tester.pump();
            final width = alignment ? 825.0 : 1968.0;
            final left = alignment ? (2000 - width) / 2 : 16.0;
            final rtl = direction == TextDirection.rtl;
            final viewport = tester.getRect(find.byKey(_viewportKey));
            expect(rtl ? viewport.left : viewport.right, rtl ? 0 : 2000);
            _expectLane(
              tester,
              left: left + (rtl ? 16 : 206),
              width: width - 222,
            );
            expect(tester.takeException(), isNull);
          }
        }
      });
    });
  }

  testWidgets('limits content by default and can expand to fill the panel', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();

      await tester.pumpWidget(_harness(controller));

      expect(tester.getSize(find.byKey(_viewportKey)).width, 1200);
      _expectLane(tester, left: 182.5, width: 825);
      await controller.setLimitContentSize(true);
      await tester.pump();
      expect(tester.getSize(find.byKey(_viewportKey)).width, 1200);
      _expectLane(tester, left: 182.5, width: 825);
      await controller.setLimitContentSize(false);
      await tester.pump();
      _expectLane(tester, left: 10, width: 1170);
    });
  });

  testWidgets('does not widen a narrow desktop lane', (tester) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(700, 600));
      final controller = _controller();

      await tester.pumpWidget(_harness(controller));

      _expectLane(tester, left: 10, width: 670);
      await controller.setLimitContentSize(true);
      await tester.pump();
      _expectLane(tester, left: 10, width: 670);
    });
  });

  testWidgets('keeps the enabled limit at 825 px regardless of text zoom', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(2000, 600));
      final controller = _controller();
      late double breakpointWidth;
      await controller.setLimitContentSize(true);

      await tester.pumpWidget(
        _harness(
          controller,
          onBreakpointWidth: (value) => breakpointWidth = value,
        ),
      );

      for (final (scale, expectedWidth) in [
        (AppTextScale.percent80, 825.0),
        (AppTextScale.percent150, 825.0),
        (AppTextScale.percent200, 825.0),
      ]) {
        await controller.setTextScale(scale);
        await tester.pump();

        _expectLane(
          tester,
          left: 10 + (1970 - expectedWidth) / 2,
          width: expectedWidth,
        );
        expect(breakpointWidth, 825 / scale.factor);
      }

      await _setViewport(tester, const Size(1200, 600));
      await tester.pump();
      _expectLane(tester, left: 182.5, width: 825);
      expect(breakpointWidth, 412.5);
    });
  });

  testWidgets('keeps narrower content centered with either size setting', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();

      await tester.pumpWidget(_narrowHarness(controller));
      _expectNarrowContent(tester, left: 390);

      await controller.setLimitContentSize(false);
      await tester.pump();
      _expectNarrowContent(tester, left: 390);

      await controller.setLimitContentSize(true);
      await tester.pump();
      _expectNarrowContent(tester, left: 390);
    });
  });

  testWidgets('keeps an auxiliary pane outside the centered lane', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(1400, 600));
      final controller = _controller();
      await controller.setLimitContentSize(true);

      await tester.pumpWidget(
        _harness(controller, basePadding: const EdgeInsets.only(right: 344)),
      );

      expect(tester.getSize(find.byKey(_viewportKey)).width, 1400);
      _expectLane(tester, left: 115.5, width: 825);
      expect(tester.getBottomRight(find.byKey(_contentKey)).dx, 940.5);
    });
  });

  testWidgets('fills mobile panels while the limit is disabled', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.iOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();
      late double breakpointWidth;
      await controller.setTextScale(AppTextScale.percent200);
      await controller.setLimitContentSize(false);

      await tester.pumpWidget(
        _harness(
          controller,
          onBreakpointWidth: (value) => breakpointWidth = value,
        ),
      );

      _expectLane(tester, left: 10, width: 1170);
      expect(breakpointWidth, 1170);
    });
  });

  testWidgets('keeps narrower content centered on mobile platforms', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.iOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();

      await controller.setLimitContentSize(false);
      await tester.pumpWidget(_narrowHarness(controller));
      _expectNarrowContent(tester, left: 390);

      await controller.setLimitContentSize(true);
      await tester.pump();
      _expectNarrowContent(tester, left: 390);
    });
  });
}

const _viewportKey = ValueKey('reading-lane-viewport');
const _contentKey = ValueKey('reading-lane-content');
const _narrowContentKey = ValueKey('narrow-reading-lane-content');

AppSettingsController _controller() {
  final controller = AppSettingsController(
    store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _harness(
  AppSettingsController controller, {
  EdgeInsets basePadding = const EdgeInsets.fromLTRB(10, 2, 20, 4),
  ValueChanged<double>? onBreakpointWidth,
}) => MaterialApp(
  home: ContentSettingsScope(
    controller: controller,
    child: Scaffold(
      body: ContentReadingLane(
        basePadding: basePadding,
        builder: (context, lane) {
          onBreakpointWidth?.call(
            ContentReadingLane.breakpointWidthOf(context, lane.width),
          );
          return ColoredBox(
            key: _viewportKey,
            color: Colors.black,
            child: Padding(
              padding: lane.padding,
              child: const SizedBox(
                key: _contentKey,
                width: double.infinity,
                height: double.infinity,
                child: ColoredBox(color: Colors.white),
              ),
            ),
          );
        },
      ),
    ),
  ),
);

Widget _narrowHarness(AppSettingsController controller) => MaterialApp(
  home: ContentSettingsScope(
    controller: controller,
    child: Scaffold(
      body: ContentReadingLane(
        builder: (context, lane) => ColoredBox(
          key: _viewportKey,
          color: Colors.black,
          child: Padding(
            padding: lane.padding,
            child: Align(
              alignment: lane.alignment,
              child: const SizedBox(
                key: _narrowContentKey,
                width: 420,
                height: 100,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

void _expectLane(
  WidgetTester tester, {
  required double left,
  required double width,
}) {
  expect(tester.getTopLeft(find.byKey(_contentKey)).dx, moreOrLessEquals(left));
  expect(
    tester.getSize(find.byKey(_contentKey)).width,
    moreOrLessEquals(width),
  );
}

void _expectNarrowContent(WidgetTester tester, {required double left}) {
  expect(
    tester.getTopLeft(find.byKey(_narrowContentKey)).dx,
    moreOrLessEquals(left),
  );
  expect(tester.getSize(find.byKey(_narrowContentKey)).width, 420);
}
