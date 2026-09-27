import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_sheet.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Sheet title';

void main() {
  for (final dialog in [true, false]) {
    final presentation = dialog ? 'dialog' : 'sheet';

    for (final keyboard in [true, false]) {
      final input = keyboard ? 'keyboard' : 'pointer';

      testWidgets(
        'a $presentation opened from a menu by $input takes focus from the '
        'menu trigger and returns it on Escape',
        (tester) async {
          final trigger = await _pumpMenu(tester, dialog: dialog);
          final sheetRoute = dialog
              ? isA<DialogRoute<void>>()
              : isA<ModalBottomSheetRoute<void>>();

          await _openFromMenu(tester, trigger, keyboard: keyboard);
          expect(find.text(_title), findsOneWidget);
          expect(_primaryFocusRoute(), sheetRoute);

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text(_title), findsNothing);
          expect(trigger.hasPrimaryFocus, isTrue);

          await _openFromMenu(tester, trigger, keyboard: keyboard);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(_primaryFocusRoute(), sheetRoute);
          expect(_focusWithin(find.byTooltip('Close')), isTrue);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }

    testWidgets(
      'a $presentation opened from a menu keeps an autofocused field focused',
      (tester) async {
        final trigger = await _pumpMenu(tester, dialog: dialog, field: true);
        await _openFromMenu(tester, trigger, keyboard: true);

        final field = find.byKey(const ValueKey('sheet-field'));
        expect(field, findsOneWidget);
        expect(_focusWithin(field), isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}

Future<FocusNode> _pumpMenu(
  WidgetTester tester, {
  required bool dialog,
  bool field = false,
}) async {
  final menu = DPopoverController();
  addTearDown(menu.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: DDropdownMenu(
            controller: menu,
            content: DDropdownMenuContent(
              semanticLabel: 'More',
              children: [
                Builder(
                  builder: (itemContext) => DDropdownMenuItem(
                    key: const ValueKey('open-sheet'),
                    onPressed: () => showShellSheet<void>(
                      context: itemContext,
                      title: _title,
                      dialogOnDesktop: dialog,
                      builder: (context) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DButton(
                            label: const Text('Option'),
                            onPressed: () {},
                          ),
                          if (field)
                            DInput(
                              key: const ValueKey('sheet-field'),
                              autofocus: true,
                            ),
                        ],
                      ),
                    ),
                    child: const Text('Open sheet'),
                  ),
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, trigger) => DButton(
                key: const ValueKey('menu-trigger'),
                focusNode: trigger.focusNode,
                label: const Text('More'),
                onPressed: trigger.toggle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester
      .widget<DButton>(find.byKey(const ValueKey('menu-trigger')))
      .focusNode!;
}

Future<void> _openFromMenu(
  WidgetTester tester,
  FocusNode trigger, {
  required bool keyboard,
}) async {
  if (keyboard) {
    trigger.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_focusWithin(find.byKey(const ValueKey('open-sheet'))), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await tester.tap(find.byKey(const ValueKey('menu-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
  }
  await tester.pumpAndSettle();
}

ModalRoute<Object?>? _primaryFocusRoute() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context == null ? null : ModalRoute.of(context);
}

bool _focusWithin(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: finder,
        matching: find.byElementPredicate(
          (element) => identical(element, focused),
        ),
      )
      .evaluate()
      .isNotEmpty;
}
