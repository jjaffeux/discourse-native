import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_filter_parity_test.dart' as fixture;
import 'support/shell_test_harness.dart';

Set<RenderObject> _artwork(Finder root) {
  final objects = <RenderObject>{};
  void collect(RenderObject object) {
    // PaintingContext reports retained boundaries when compositing their
    // layers too. Only count the artwork actually painted inside them.
    if (!object.isRepaintBoundary) objects.add(object);
    object.visitChildren(collect);
  }

  for (final element in root.evaluate()) {
    collect(element.findRenderObject()!);
  }
  return objects;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const keyboard = MethodChannel('org.discourse.native/keyboard');
    const notifications = MethodChannel(
      'org.discourse.native/notification_opens',
    );
    messenger.setMockMethodCallHandler(
      keyboard,
      (_) async => throw MissingPluginException(),
    );
    messenger.setMockMethodCallHandler(notifications, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(keyboard, null);
      messenger.setMockMethodCallHandler(notifications, null);
    });
  });
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final material in DAppearanceMaterial.values) {
      testWidgets(
        'Filters scroll reuses stationary artwork on $platform ($material)',
        (tester) async {
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
          final (shell: shell, api: _) = await fixture.fixture(
            tester,
            size: const Size(390, 700),
            filterOptions: fixture.filterMenuOptions,
          );
          await shell.forumSettings.setShared(
            shell.forumSettings.shared.copyWith(material: material),
          );
          await tester.pumpAndSettle();
          await fixture.openFilters(tester);
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
          final results = find.descendant(
            of: find.byType(DCommandList<String>),
            matching: find.byType(Scrollable),
          );
          expect(results, findsOneWidget);
          final position = tester.state<ScrollableState>(results).position;
          expect(position.maxScrollExtent, greaterThan(100));
          position.jumpTo(position.maxScrollExtent / 2);
          await tester.pumpAndSettle();
          final viewport = tester.getRect(results);
          final input = _artwork(fixture.field);
          final handle = _artwork(
            find.byKey(const ValueKey('sheet-drag-handle')),
          );
          final page = _artwork(primaryMainContent);
          final rows = _artwork(
            find.byType(DCommandList<String>),
          ).whereType<RenderParagraph>().toSet();
          var inputPaints = 0;
          var handlePaints = 0;
          var pagePaints = 0;
          var rowPaints = 0;
          var totalPaints = 0;
          final previous = debugOnProfilePaint;
          debugOnProfilePaint = (object) {
            previous?.call(object);
            totalPaints++;
            if (input.contains(object)) inputPaints++;
            if (handle.contains(object)) handlePaints++;
            if (page.contains(object)) pagePaints++;
            if (rows.contains(object)) rowPaints++;
          };
          try {
            final gesture = await tester.startGesture(
              tester.getCenter(results),
            );
            await gesture.moveBy(const Offset(0, -40));
            await gesture.moveBy(const Offset(0, -8));
            await tester.pump();
            inputPaints = handlePaints = pagePaints = rowPaints = totalPaints =
                0;
            for (var frame = 0; frame < 24; frame++) {
              final before = position.pixels;
              final delta = frame < 12 ? -4.0 : 4.0;
              await gesture.moveBy(Offset(0, delta));
              await tester.pump(const Duration(milliseconds: 16));
              expect(
                position.pixels,
                delta < 0 ? greaterThan(before) : lessThan(before),
              );
              expect(tester.getRect(results), viewport);
            }
            await gesture.cancel();
            await tester.pumpAndSettle();
            debugPrint(
              'FILTER_SCROLL_PAINTS platform=$platform material=$material '
              'total=$totalPaints input=$inputPaints handle=$handlePaints '
              'page=$pagePaints rows=$rowPaints',
            );
            expect(totalPaints, greaterThan(0));
            expect(inputPaints, 0);
            expect(handlePaints, 0);
            expect(pagePaints, 0);
            expect(rowPaints, 0);
            expect(tester.takeException(), isNull);
          } finally {
            debugOnProfilePaint = previous;
          }
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }
}
