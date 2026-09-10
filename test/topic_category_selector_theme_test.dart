import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/topic_taxonomy_review_main.dart' as fixture;

void main() {
  testWidgets('category editing survives live palette and viewport changes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.discourse.native/window'),
        (_) async => null,
      );
      await tester.runAsync(() async {
        await fixture.main();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      final shell = ShellScope.read(
        tester.element(find.byType(TopicInboxHeader)),
      );
      addTearDown(shell.dispose);
      expect(shell.currentTopic?.categoryId, 2);

      await tester.tap(find.byTooltip('Edit topic category'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-category-picker-query')),
        'todo',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentTopic!.categoryId, 4);

      for (final label in ['Reset topic', 'Light', 'Results: ready']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Edit topic subcategory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove subcategory'));
      await tester.pumpAndSettle();
      expect(shell.currentTopic!.categoryId, 1);

      for (final label in ['Plum site', 'Width: 740', 'Text: 100%', 'LTR']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Edit topic category'));
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });
}
