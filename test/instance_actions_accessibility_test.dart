import 'package:discourse_native/src/shell/instance_actions.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _showForumActions = CustomSemanticsAction(label: 'Show forum actions');

void main() {
  testWidgets('Shift+F10 opens the forum context actions', (tester) async {
    await _pumpFocusedActions(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    _expectDesktopActions();
  });

  testWidgets('the Context Menu key opens the forum context actions', (
    tester,
  ) async {
    await _pumpFocusedActions(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    _expectDesktopActions();
  });

  testWidgets('the forum semantics action opens its context actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final button = await _pumpFocusedActions(tester);

      final node = tester.getSemantics(button);
      final customActions = [
        for (final id
            in node.getSemanticsData().customSemanticsActionIds ??
                const <int>[])
          CustomSemanticsAction.getAction(id),
      ];
      expect(customActions, [_showForumActions]);

      final semanticsOwner = find.descendant(
        of: find.byType(InstanceActions),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.customSemanticsActions?.containsKey(
                    _showForumActions,
                  ) ??
                  false),
        ),
      );
      expect(semanticsOwner, findsOneWidget);
      tester
          .widget<Semantics>(semanticsOwner)
          .properties
          .customSemanticsActions![_showForumActions]!();
      await tester.pumpAndSettle();

      _expectDesktopActions();
    } finally {
      semantics.dispose();
    }
  });
}

Future<Finder> _pumpFocusedActions(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Center(
          child: InstanceActions(
            instance: instance('meta.example', title: 'Meta'),
            onMoveDown: () {},
            child: TextButton(
              key: const ValueKey('forum-button'),
              onPressed: () {},
              child: const Text('Meta'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final button = find.byKey(const ValueKey('forum-button'));
  final focus = _focusButton(tester, button);
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
  return button;
}

void _expectDesktopActions() {
  expect(find.text('Move down'), findsOneWidget);
  expect(find.text('Remove forum'), findsOneWidget);
  expect(find.text('More Options'), findsNothing);
}

FocusNode _focusButton(WidgetTester tester, Finder button) {
  final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}
