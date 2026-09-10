import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/keyboard_shortcuts_help.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 1000.0]) {
    testWidgets(
      'shortcut help wraps at $width px with 200 percent text and restores focus on Escape',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: DDirection(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  focusNode: focus,
                  autofocus: true,
                  onPressed: () => showKeyboardShortcuts(context),
                  child: const Text('Help'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('keyboard-shortcuts-help')),
          findsOneWidget,
        );
        expect(find.byType(DShortcutKeycaps), findsWidgets);
        expect(
          tester
              .widgetList<DShortcutKeycaps>(find.byType(DShortcutKeycaps))
              .where((hint) => hint.shortcut.length == 2),
          hasLength(2),
        );
        expect(find.widgetWithText(DKbd, '?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final firstRow = find.text('Next topic in the list');
        final beforeScroll = tester.getTopLeft(firstRow).dy;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: Offset(width / 2, 400),
            scrollDelta: const Offset(0, 600),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(firstRow).dy, lessThan(beforeScroll - 50));
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('keyboard-shortcuts-help')),
          findsNothing,
        );
        expect(focus.hasFocus, isTrue);
      },
    );
  }
}
