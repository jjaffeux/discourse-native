import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final family in _MenuFamily.values) {
    group(family.name, () {
      for (final placement in _Placement.values) {
        testWidgets('protects diagonal movement with ${placement.name}', (
          tester,
        ) async {
          var selected = '';
          await _pumpMenu(
            tester,
            family,
            placement: placement,
            onSelected: (value) => selected = value,
          );
          final path = await _openShare(tester);
          expect(
            path.opensRight,
            placement == _Placement.right || placement == _Placement.shifted,
          );

          await path.mouse.moveTo(path.over(tester, 'Move to', .55));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Share 5'), findsOneWidget);
          expect(find.text('Folder'), findsNothing);

          await path.mouse.moveTo(path.over(tester, 'Rename', .8));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Share 5'), findsOneWidget);

          await path.mouse.moveTo(tester.getCenter(find.text('Share 5')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Share 5'), findsOneWidget);
          await path.mouse.down(tester.getCenter(find.text('Share 5')));
          await path.mouse.up();
          await tester.pumpAndSettle();
          expect(selected, 'Share 5');
          expect(find.text('Share'), findsNothing);
        });
      }

      testWidgets('protects the next level of a nested menu', (tester) async {
        var selected = '';
        await _pumpMenu(
          tester,
          family,
          nested: true,
          onSelected: (value) => selected = value,
        );
        final first = await _openShare(tester);
        final path = await _openSubmenu(tester, first.mouse, 'Advanced');
        await path.mouse.moveTo(path.over(tester, 'Nested move', .55));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Advanced 5'), findsOneWidget);
        expect(find.text('Nested folder'), findsNothing);
        await path.mouse.moveTo(path.over(tester, 'Nested rename', .8));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Advanced 5'), findsOneWidget);
        final target = tester.getCenter(find.text('Advanced 5'));
        await path.mouse.moveTo(target);
        await path.mouse.down(target);
        await path.mouse.up();
        await tester.pumpAndSettle();
        expect(selected, 'Advanced 5');
        expect(find.text('Share'), findsNothing);
      });

      testWidgets('protects upward movement into a vertically shifted popup', (
        tester,
      ) async {
        await _pumpMenu(tester, family, placement: _Placement.shifted);
        final path = await _openShare(tester);
        final trigger = tester.getRect(find.byKey(const ValueKey('Share')));
        final popup = tester.getRect(find.byType(DDropdownMenuContent).last);
        expect(popup.top, lessThan(trigger.top));
        await path.mouse.moveTo(path.over(tester, 'Open', .85));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Share 0'), findsOneWidget);
        await path.mouse.moveTo(tester.getCenter(find.text('Share 0')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Share 0'), findsOneWidget);
      });

      testWidgets('a pause over a sibling opens it', (tester) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        await path.mouse.moveTo(path.over(tester, 'Move to', .55));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Share 5'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(find.text('Share 5'), findsNothing);
        expect(find.text('Folder'), findsOneWidget);
      });

      testWidgets('continued progress keeps a slow diagonal path safe', (
        tester,
      ) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        for (final fraction in [.4, .5, .6, .7, .8]) {
          await path.mouse.moveTo(path.over(tester, 'Move to', fraction));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('Share 5'), findsOneWidget);
          expect(find.text('Folder'), findsNothing);
        }
        await path.mouse.moveTo(tester.getCenter(find.text('Share 5')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Share 5'), findsOneWidget);
        expect(find.text('Folder'), findsNothing);
      });

      testWidgets('reversing inside the sibling switches immediately', (
        tester,
      ) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        final point = path.over(tester, 'Move to', .65);
        await path.mouse.moveTo(point);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Share 5'), findsOneWidget);
        await path.mouse.moveTo(point - const Offset(4, 0));
        await tester.pumpAndSettle();
        expect(find.text('Share 5'), findsNothing);
        expect(find.text('Folder'), findsOneWidget);
      });

      testWidgets('vertical movement switches without a grace delay', (
        tester,
      ) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        await path.mouse.moveTo(path.over(tester, 'Move to', 0));
        await tester.pumpAndSettle();
        expect(find.text('Share 5'), findsNothing);
        expect(find.text('Folder'), findsOneWidget);
      });

      testWidgets('clicking a protected sibling activates it immediately', (
        tester,
      ) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        final point = path.over(tester, 'Move to', .55);
        await path.mouse.moveTo(point);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Share 5'), findsOneWidget);
        await path.mouse.down(point);
        await path.mouse.up();
        await tester.pumpAndSettle();
        expect(find.text('Share 5'), findsNothing);
        expect(find.text('Folder'), findsOneWidget);
      });

      testWidgets('Escape cancels a pending sibling hover', (tester) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        await path.mouse.moveTo(path.over(tester, 'Move to', .55));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Share 5'), findsNothing);
        expect(find.text('Folder'), findsNothing);
      });

      testWidgets('keyboard navigation cancels an ancestor pending hover', (
        tester,
      ) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        await path.mouse.moveTo(path.over(tester, 'Move to', .55));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Share 5'), findsOneWidget);
        expect(find.text('Folder'), findsNothing);
        expect(
          tester.binding.focusManager.primaryFocus?.debugLabel,
          contains('Share 1'),
        );
      });

      testWidgets('outside dismissal cancels pending work', (tester) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        await path.mouse.moveTo(path.over(tester, 'Move to', .55));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(const Offset(5, 5));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('Share 5'), findsNothing);
        expect(find.text('Folder'), findsNothing);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.text('Share'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('removing an open menu cancels pending work', (tester) async {
        await _pumpMenu(tester, family);
        final path = await _openShare(tester);
        await path.mouse.moveTo(path.over(tester, 'Move to', .55));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    });
  }
}

enum _MenuFamily { dropdown, context, menubar }

enum _Placement { right, rtl, flipped, shifted }

Future<void> _pumpMenu(
  WidgetTester tester,
  _MenuFamily family, {
  _Placement placement = _Placement.right,
  ValueChanged<String>? onSelected,
  bool nested = false,
}) async {
  Widget item(String label) => switch (family) {
    _MenuFamily.dropdown => DDropdownMenuItem(
      key: ValueKey(label),
      onPressed: () => onSelected?.call(label),
      child: Text(label),
    ),
    _MenuFamily.context => DContextMenuItem(
      key: ValueKey(label),
      onPressed: () => onSelected?.call(label),
      child: Text(label),
    ),
    _MenuFamily.menubar => DMenubarItem(
      key: ValueKey(label),
      onPressed: () => onSelected?.call(label),
      child: Text(label),
    ),
  };
  Widget sub(String label, List<Widget> children) => switch (family) {
    _MenuFamily.dropdown => DDropdownMenuSub(
      key: ValueKey(label),
      trigger: Text(label),
      width: 160,
      children: children,
    ),
    _MenuFamily.context => DContextMenuSub(
      key: ValueKey(label),
      trigger: Text(label),
      width: 160,
      children: children,
    ),
    _MenuFamily.menubar => DMenubarSub(
      key: ValueKey(label),
      trigger: DMenubarSubTrigger(child: Text(label)),
      content: DMenubarSubContent(children: children),
    ),
  };
  final children = [
    item('Open'),
    sub('Share', [
      for (var i = 0; i < 6; i++) item('Share $i'),
      if (nested) ...[
        sub('Advanced', [for (var i = 0; i < 6; i++) item('Advanced $i')]),
        sub('Nested move', [item('Nested folder')]),
        item('Nested rename'),
      ],
    ]),
    sub('Move to', [item('Folder')]),
    item('Rename'),
    item('Delete'),
  ];
  final menu = switch (family) {
    _MenuFamily.dropdown => DDropdownMenu(
      content: DDropdownMenuContent(width: 220, children: children),
      child: DDropdownMenuTrigger(
        builder: (context, state) => DButton(
          label: const Text('Menu'),
          focusNode: state.focusNode,
          onPressed: state.toggle,
        ),
      ),
    ),
    _MenuFamily.context => DContextMenu(
      content: DContextMenuContent(width: 220, children: children),
      child: const DContextMenuTrigger(child: Text('Menu')),
    ),
    _MenuFamily.menubar => DMenubar(
      children: [
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('Menu')),
          content: DMenubarContent(width: 220, children: children),
        ),
      ],
    ),
  };
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Directionality(
          textDirection: placement == _Placement.rtl
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: placement == _Placement.shifted ? 24 : 100,
            ),
            child: Align(
              alignment: switch (placement) {
                _Placement.right => Alignment.topLeft,
                _Placement.shifted => Alignment.bottomLeft,
                _ => Alignment.topRight,
              },
              child: menu,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(
    find.text('Menu'),
    buttons: family == _MenuFamily.context ? kSecondaryButton : kPrimaryButton,
  );
  await tester.pumpAndSettle();
}

Future<_PointerPath> _openShare(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer();
  final path = await _openSubmenu(tester, mouse, 'Share');
  expect(find.text('Share 5'), findsOneWidget);
  return path;
}

Future<_PointerPath> _openSubmenu(
  WidgetTester tester,
  TestGesture mouse,
  String label,
) async {
  final trigger = tester.getRect(find.byKey(ValueKey(label)));
  await mouse.moveTo(trigger.center);
  await tester.pumpAndSettle();
  final popup = tester.getRect(find.byType(DDropdownMenuContent).last);
  final opensRight = popup.center.dx > trigger.center.dx;
  final origin = Offset(
    opensRight ? trigger.left + 24 : trigger.right - 24,
    trigger.center.dy,
  );
  await mouse.moveTo(origin);
  await tester.pump();
  return _PointerPath(mouse, origin, opensRight ? popup.left : popup.right);
}

class _PointerPath {
  const _PointerPath(this.mouse, this.origin, this.edge);

  final TestGesture mouse;
  final Offset origin;
  final double edge;

  bool get opensRight => edge > origin.dx;

  Offset over(WidgetTester tester, String label, double progress) => Offset(
    origin.dx + (edge - origin.dx) * progress,
    tester.getCenter(find.byKey(ValueKey(label))).dy,
  );
}
