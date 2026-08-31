import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('caps only the child lane and applies each physical alignment', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();

      await tester.pumpWidget(_harness(controller));

      expect(tester.getSize(find.byKey(_viewportKey)).width, 1200);
      _expectLane(tester, left: 182.5, width: 825);

      await controller.setContentAlignment(ContentAlignment.left);
      await tester.pump();
      expect(tester.getSize(find.byKey(_viewportKey)).width, 1200);
      _expectLane(tester, left: 10, width: 825);

      await controller.setContentAlignment(ContentAlignment.right);
      await tester.pump();
      expect(tester.getSize(find.byKey(_viewportKey)).width, 1200);
      _expectLane(tester, left: 355, width: 825);
    });
  });

  testWidgets('does not widen a narrow desktop lane', (tester) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(700, 600));
      final controller = _controller();

      await tester.pumpWidget(_harness(controller));

      _expectLane(tester, left: 10, width: 670);
    });
  });

  testWidgets('physically aligns content with a narrower existing limit', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();

      await tester.pumpWidget(_narrowHarness(controller));
      _expectNarrowContent(tester, left: 390);

      await controller.setContentAlignment(ContentAlignment.left);
      await tester.pump();
      _expectNarrowContent(tester, left: 0);

      await controller.setContentAlignment(ContentAlignment.right);
      await tester.pump();
      _expectNarrowContent(tester, left: 780);
    });
  });

  testWidgets('keeps an auxiliary pane outside the centered lane', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _setViewport(tester, const Size(1400, 600));
      final controller = _controller();

      await tester.pumpWidget(
        _harness(controller, basePadding: const EdgeInsets.only(right: 344)),
      );

      expect(tester.getSize(find.byKey(_viewportKey)).width, 1400);
      _expectLane(tester, left: 115.5, width: 825);
      expect(tester.getBottomRight(find.byKey(_contentKey)).dx, 940.5);
    });
  });

  testWidgets('does not cap content on mobile platforms', (tester) async {
    await _withPlatform(TargetPlatform.iOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();

      await tester.pumpWidget(_harness(controller));

      _expectLane(tester, left: 10, width: 1170);
    });
  });

  testWidgets('keeps narrower content centered on mobile platforms', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.iOS, () async {
      await _setViewport(tester, const Size(1200, 600));
      final controller = _controller();

      await controller.setContentAlignment(ContentAlignment.left);
      await tester.pumpWidget(_narrowHarness(controller));
      _expectNarrowContent(tester, left: 390);

      await controller.setContentAlignment(ContentAlignment.right);
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
}) => MaterialApp(
  home: ContentAlignmentScope(
    controller: controller,
    child: Scaffold(
      body: ContentReadingLane(
        basePadding: basePadding,
        builder: (context, lane) => ColoredBox(
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
        ),
      ),
    ),
  ),
);

Widget _narrowHarness(AppSettingsController controller) => MaterialApp(
  home: ContentAlignmentScope(
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
