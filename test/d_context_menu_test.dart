import 'dart:ui' show CheckedState, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('secondary click opens at the pointer and selects an item', (
    tester,
  ) async {
    var selected = '';
    await _pumpMenu(
      tester,
      children: [
        DContextMenuItem(
          onPressed: () => selected = 'Back',
          child: const Text('Back'),
        ),
        const DContextMenuItem(child: Text('Forward')),
      ],
    );

    const point = Offset(330, 260);
    await tester.tapAt(point, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);
    final popup = tester.getRect(find.byType(DContextMenuContent));
    expect(popup.left, greaterThanOrEqualTo(point.dx - 2));
    expect(popup.top, greaterThanOrEqualTo(point.dy));
    expect(
      tester.getSemantics(find.text('Forward')).flagsCollection.isEnabled,
      Tristate.isFalse,
    );

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(selected, 'Back');
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('long press opens at the touch location', (tester) async {
    await _pumpMenu(
      tester,
      children: [
        DContextMenuItem(onPressed: () {}, child: const Text('Inspect')),
      ],
    );

    await tester.longPressAt(const Offset(300, 250));
    await tester.pumpAndSettle();

    expect(find.text('Inspect'), findsOneWidget);
  });

  testWidgets('Shift+F10 opens and Escape restores trigger focus', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpMenu(
      tester,
      focusNode: focus,
      children: [
        DContextMenuItem(onPressed: () {}, child: const Text('Reload')),
      ],
    );
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsNothing);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('Context Menu key opens and focuses the first enabled item', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpMenu(
      tester,
      focusNode: focus,
      children: [
        const DContextMenuItem(child: Text('Disabled')),
        DContextMenuItem(onPressed: () {}, child: const Text('Enabled')),
      ],
    );
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    final itemFocus = Focus.of(tester.element(find.text('Enabled')));
    expect(itemFocus.hasFocus, isTrue);
  });

  testWidgets('context invocation preserves scoped typeahead navigation', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpMenu(
      tester,
      focusNode: focus,
      children: [
        DContextMenuItem(onPressed: () {}, child: const Text('Back')),
        DContextMenuItem(onPressed: () {}, child: const Text('Reload')),
      ],
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Reload'))).hasFocus, isTrue);
  });

  testWidgets('disabled root ignores all invocation methods', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpMenu(
      tester,
      disabled: true,
      focusNode: focus,
      children: [
        DContextMenuItem(onPressed: () {}, child: const Text('Hidden')),
      ],
    );

    await tester.tapAt(const Offset(300, 250), buttons: kSecondaryButton);
    await tester.longPressAt(const Offset(300, 250));
    focus.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    expect(find.text('Hidden'), findsNothing);
  });

  testWidgets(
    'checkbox default state and radio state remain open on selection',
    (tester) async {
      var person = 'Pedro';
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => _menu(
              children: [
                const DContextMenuCheckboxItem(
                  defaultChecked: true,
                  child: Text('Bookmarks'),
                ),
                DContextMenuRadioGroup<String>(
                  value: person,
                  onChanged: (value) => setState(() => person = value),
                  children: const [
                    DContextMenuRadioItem(value: 'Pedro', child: Text('Pedro')),
                    DContextMenuRadioItem(value: 'Colm', child: Text('Colm')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(300, 250), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.text('Bookmarks')).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Bookmarks')).flagsCollection.isChecked,
        CheckedState.isFalse,
      );

      await tester.tap(find.text('Colm'));
      await tester.pumpAndSettle();
      expect(person, 'Colm');
      expect(find.text('Pedro'), findsOneWidget);
    },
  );

  testWidgets('submenu opens directionally and deepest Escape closes first', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      children: [
        DContextMenuSub(
          trigger: const Text('More Tools'),
          children: [
            DContextMenuItem(
              onPressed: () {},
              child: const Text('Developer Tools'),
            ),
          ],
        ),
      ],
    );
    await tester.tapAt(const Offset(300, 250), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsNothing);
    expect(find.text('More Tools'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('More Tools'), findsNothing);
  });

  testWidgets('RTL keyboard anchor and submenu direction are logical', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpMenu(
      tester,
      direction: TextDirection.rtl,
      focusNode: focus,
      children: [
        DContextMenuSub(
          trigger: const Text('التنقل'),
          children: [
            DContextMenuItem(onPressed: () {}, child: const Text('رجوع')),
          ],
        ),
      ],
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('رجوع'), findsOneWidget);
  });

  testWidgets(
    'side preferences still collision-shift inside a narrow viewport',
    (tester) async {
      tester.view.physicalSize = const Size(360, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpMenu(
        tester,
        side: DPopoverSide.right,
        children: [
          DContextMenuItem(onPressed: () {}, child: const Text('Edge action')),
        ],
      );

      await tester.tapAt(const Offset(295, 225), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final popup = tester.getRect(find.byType(DContextMenuContent));
      expect(popup.right, lessThanOrEqualTo(355));
      expect(popup.bottom, lessThanOrEqualTo(295));
    },
  );
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  required List<Widget> children,
  FocusNode? focusNode,
  bool disabled = false,
  TextDirection direction = TextDirection.ltr,
  DPopoverSide side = DPopoverSide.right,
}) async {
  await tester.pumpWidget(
    _host(
      _menu(
        children: children,
        focusNode: focusNode,
        disabled: disabled,
        side: side,
      ),
      direction: direction,
    ),
  );
  await tester.pumpAndSettle();
}

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) {
  return MaterialApp(
    theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

Widget _menu({
  required List<Widget> children,
  FocusNode? focusNode,
  bool disabled = false,
  DPopoverSide side = DPopoverSide.right,
}) {
  return SizedBox(
    width: 240,
    height: 160,
    child: DContextMenu(
      disabled: disabled,
      content: DContextMenuContent(
        side: side,
        semanticLabel: 'Page actions',
        children: children,
      ),
      child: DContextMenuTrigger(
        focusNode: focusNode,
        child: const ColoredBox(
          color: Colors.transparent,
          child: Center(child: Text('Right click here')),
        ),
      ),
    ),
  );
}
