import 'package:discourse_native/src/shell/inline_action.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inline actions use a hand cursor without a hover fill', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InlineAction(
              key: const ValueKey('inline-action'),
              onTap: () {},
              semanticLabel: 'Edit category',
              excludeChildSemantics: true,
              child: const Text('Support'),
            ),
          ),
        ),
      );

      final target = find.bySemanticsLabel('Edit category');
      final ink = find.descendant(
        of: find.byKey(const ValueKey('inline-action')),
        matching: find.byType(InkWell),
      );
      expect(ink, findsOneWidget);
      expect(tester.widget<InkWell>(ink).mouseCursor, SystemMouseCursors.click);
      expect(tester.widget<InkWell>(ink).hoverColor, Colors.transparent);
      expect(
        tester.widget<InkWell>(ink).focusColor,
        Theme.of(tester.element(target)).shell.hover,
      );
      expect(
        tester.getSemantics(target),
        isSemantics(isButton: true, isLink: false, hasTapAction: true),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('inline links expose link semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InlineAction.link(
              onTap: () {},
              semanticLabel: 'Open support',
              excludeChildSemantics: true,
              child: const Text('Support'),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Open support')),
        isSemantics(isButton: false, isLink: true, hasTapAction: true),
      );
    } finally {
      semantics.dispose();
    }
  });
}
