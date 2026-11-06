import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_category_selector.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _support = TopicCategory(
  id: 1,
  name: 'Support',
  slug: 'support',
  color: '123456',
  permission: 1,
);
const _design = TopicCategory(
  id: 2,
  name: 'Design',
  slug: 'design',
  color: '123456',
  permission: 1,
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<TopicCategory>> Function(String) search,
  required ValueChanged<TopicCategory?> onSelected,
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: TopicCategorySelector(
            siteUrl: 'https://example.invalid',
            categories: const [_support, _design],
            selected: null,
            search: search,
            onSelected: onSelected,
            valueKey: const ValueKey('open-categories'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-categories')));
  await tester.pumpAndSettle();
}

void main() {
  for (final keyboard in [false, true]) {
    testWidgets(
      'known categories remain selectable during lookup keyboard=$keyboard',
      (tester) async {
        final held = Completer<List<TopicCategory>>();
        final selected = <TopicCategory?>[];
        await _pump(
          tester,
          search: (_) => held.future,
          onSelected: selected.add,
        );
        await tester.enterText(
          find.byKey(const ValueKey('category-selector-query')),
          'supp',
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Support'), findsOneWidget);
        expect(find.text('Design'), findsNothing);
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Support'));
        }
        await tester.pumpAndSettle();
        expect(selected, [_support]);
        expect(held.isCompleted, isFalse);
        held.complete(const [_design]);
        await tester.pumpAndSettle();
        expect(selected, [_support]);
      },
    );
  }

  testWidgets(
    'lookup failure keeps eligible local categories and current highlight',
    (tester) async {
      final held = Completer<List<TopicCategory>>();
      final selected = <TopicCategory?>[];
      await _pump(tester, search: (_) => held.future, onSelected: selected.add);
      await tester.enterText(
        find.byKey(const ValueKey('category-selector-query')),
        'des',
      );
      await tester.pump(const Duration(milliseconds: 300));
      held.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Design'), findsOneWidget);
      expect(find.text('Support'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, [_design]);
    },
  );

  testWidgets(
    'server categories enrich matching local choices without duplicates',
    (tester) async {
      final held = Completer<List<TopicCategory>>();
      await _pump(tester, search: (_) => held.future, onSelected: (_) {});
      expect(find.text('Support'), findsOneWidget);
      held.complete(const [
        _support,
        TopicCategory(id: 3, name: 'Remote', color: '123456'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);
    },
  );
}
