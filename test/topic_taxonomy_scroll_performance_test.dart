import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:flutter/gestures.dart';
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
  testWidgets('tag hover preserves the sheet and still selects rows', (
    tester,
  ) async {
    await fixture.fixture(tester, filterOptions: fixture.filterMenuOptions);
    await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
    await tester.pumpAndSettle();
    final command = tester
        .widget<DCommand<String>>(find.byType(DCommand<String>))
        .controller!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    final previous = debugOnRebuildDirtyWidget;
    var sheetBuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is TopicFilterInput) sheetBuilds++;
    };
    try {
      for (final name in ['Alpha', 'Beta', 'Alpha', 'Beta']) {
        await mouse.moveTo(
          tester.getCenter(
            find.descendant(
              of: find.byType(DCommandList<String>),
              matching: find.text(name),
            ),
          ),
        );
        await tester.pump();
        expect(command.value, 'tag:$name');
      }
      expect(sheetBuilds, 0);
      expect(tester.takeException(), isNull);
    } finally {
      debugOnRebuildDirtyWidget = previous;
      await mouse.removePointer();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final component in ['category', 'tag']) {
      testWidgets('$component scroll caches artwork on $platform flat', (
        tester,
      ) async {
        final data = await fixture.fixture(
          tester,
          size: platform == TargetPlatform.macOS ? desktop : phone,
          categories: List.generate(
            100,
            (i) => TopicCategory(
              id: i + 1,
              name: 'Category $i',
              color: '3188CC',
              slug: 'category-$i',
            ),
          ),
          knownTags: List.generate(
            200,
            (i) => SidebarTag(
              id: i + 1,
              name: 'tag-$i',
              slug: 'tag-$i',
              count: 200 - i,
            ),
          ),
          filterOptions: fixture.filterMenuOptions,
        );
        await data.shell.forumSettings.setShared(
          data.shell.forumSettings.shared.copyWith(),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('topic-list-$component-filter')));
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.iOS) {
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
        }
        final list = find.byType(DCommandList<String>);
        final results = find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        );
        expect(results, findsOneWidget);
        final position = tester.state<ScrollableState>(results).position;
        expect(position.maxScrollExtent, greaterThan(1000));
        position.jumpTo(position.maxScrollExtent / 2);
        await tester.pumpAndSettle();
        // Cursor blinking is independent from scrolling.
        fixture.textField(tester).focusNode!.unfocus();
        await tester.pumpAndSettle();
        final viewport = tester.getRect(results);
        final input = _artwork(fixture.field);
        final page = _artwork(primaryMainContent);
        final paragraphs = _artwork(list).whereType<RenderParagraph>().toList();
        expect(
          paragraphs.length,
          lessThan(160),
          reason: 'Long menus must keep mounted row artwork bounded.',
        );
        // Lazy rows in the cache have not painted yet. Only artwork already
        // visible is expected to remain cached while new rows enter view.
        final rows = paragraphs.where((paragraph) {
          final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
          return viewport.contains(rect.topLeft) &&
              viewport.contains(rect.bottomRight);
        }).toSet();
        var inputPaints = 0, pagePaints = 0, rowPaints = 0, totalPaints = 0;
        final previous = debugOnProfilePaint;
        debugOnProfilePaint = (object) {
          previous?.call(object);
          totalPaints++;
          if (input.contains(object)) inputPaints++;
          if (page.contains(object)) pagePaints++;
          if (rows.contains(object)) rowPaints++;
        };
        try {
          final gesture = await tester.startGesture(tester.getCenter(results));
          await gesture.moveBy(const Offset(0, -40));
          await gesture.moveBy(const Offset(0, -8));
          await tester.pump();
          inputPaints = pagePaints = rowPaints = totalPaints = 0;
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
            'TAXONOMY_SCROLL_PAINTS component=$component platform=$platform '
            'material=flat total=$totalPaints input=$inputPaints page=$pagePaints rows=$rowPaints',
          );
          expect(totalPaints, greaterThan(0));
          expect(inputPaints, 0);
          expect(pagePaints, 0);
          expect(rowPaints, 0);
          expect(tester.takeException(), isNull);
        } finally {
          debugOnProfilePaint = previous;
        }
      }, variant: TargetPlatformVariant.only(platform));
    }
  }
}
