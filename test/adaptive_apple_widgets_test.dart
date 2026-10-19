import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/adaptive_dialog_action.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('application confirmation uses Native actions on $platform', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                focusNode: focus,
                label: const Text('Open'),
                onPressed: () async {
                  result = await showDiscourseAlertDialog<bool>(
                    context: context,
                    title: const Text('Remove site?'),
                    description: const Text('This removes the local account.'),
                    cancelLabel: const Text('Cancel'),
                    actionLabel: const Text('Remove'),
                    cancelResult: false,
                    actionResult: true,
                    actionVariant: DButtonVariant.destructive,
                  );
                },
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(DAlertDialogContent), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DAlertDialogContent), findsNothing);
      expect(result, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
