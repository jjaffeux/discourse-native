import 'package:discourse_native/src/shell/user_menu_message.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retryable failure is announced and keyboard operable', (
    tester,
  ) async {
    var retries = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: UserMenuMessage(
              text: "Couldn't load bookmarks.",
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final error = find.bySemanticsLabel("Couldn't load bookmarks.");
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error),
        isSemantics(label: "Couldn't load bookmarks.", isLiveRegion: true),
      );

      final retry = find.widgetWithText(TextButton, 'Retry');
      expect(retry, findsOneWidget);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
      final focus = _focusButton(tester, retry);
      await tester.pumpAndSettle();

      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(retry),
        isSemantics(
          label: 'Retry',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          isFocused: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(retries, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('ordinary empty message is not a live announcement', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: UserMenuMessage(text: 'Nothing bookmarked yet.'),
          ),
        ),
      );

      final message = find.bySemanticsLabel('Nothing bookmarked yet.');
      expect(message, findsOneWidget);
      expect(
        tester
            .getSemantics(message)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });
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
