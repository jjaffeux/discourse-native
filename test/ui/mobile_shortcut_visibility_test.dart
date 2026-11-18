import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/keyboard_shortcuts_help.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a touch platform does not open shortcut help', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => DButton(
              label: const Text('Help'),
              onPressed: () => showKeyboardShortcuts(context),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keyboard-shortcuts-help')), findsNothing);
  });
}
