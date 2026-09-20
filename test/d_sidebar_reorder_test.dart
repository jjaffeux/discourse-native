import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _fixture({
  required List<int> values,
  required ReorderCallback onReorder,
  FocusNode? focus,
  ScrollController? scroll,
  bool dark = false,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
  VoidCallback? onPressed,
}) => MaterialApp(
  theme: ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    platform: platform,
  ),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(800, 600),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(
      body: SizedBox(
        width: 260,
        height: 220,
        child: DSidebarProvider(
          mobileBreakpoint: 0,
          child: DSidebar(
            collapsible: DSidebarCollapsible.none,
            child: DSidebarContent.slivers(
              controller: scroll,
              slivers: [
                DSidebarReorderableMenu.sliverBuilder(
                  itemCount: values.length,
                  onReorder: onReorder,
                  itemBuilder: (context, index) => DSidebarMenuButton(
                    key: ValueKey(values[index]),
                    focusNode: values[index] == 0 ? focus : null,
                    onPressed: onPressed ?? () {},
                    child: Text('Link ${values[index]}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('keyboard reordering retains row focus and stops at boundaries', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = [0, 1, 2];
    final calls = <(int, int)>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _fixture(
          values: values,
          focus: focus,
          onReorder: (from, to) => setState(() {
            calls.add((from, to));
            final value = values.removeAt(from);
            values.insert(to > from ? to - 1 : to, value);
          }),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(calls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(values, [1, 0, 2]);
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(values, [0, 1, 2]);
    expect(calls, [(0, 2), (1, 0)]);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('touch taps and swipes do not reorder on $platform', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final calls = <(int, int)>[];
      var taps = 0;
      await tester.pumpWidget(
        _fixture(
          values: List.generate(40, (index) => index),
          platform: platform,
          scroll: scroll,
          onPressed: () => taps++,
          onReorder: (from, to) => calls.add((from, to)),
        ),
      );
      await tester.tap(find.text('Link 0'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.drag(find.text('Link 2'), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(calls, isEmpty);
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'drag scrolls the shared viewport with ${dark ? 'dark' : 'light'} large text',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final calls = <(int, int)>[];
        await tester.pumpWidget(
          _fixture(
            values: List.generate(40, (index) => index),
            scroll: scroll,
            dark: dark,
            scale: 2,
            onReorder: (from, to) => calls.add((from, to)),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Link 0')),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
        await gesture.moveTo(const Offset(100, 215));
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(scroll.offset, greaterThan(0));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(calls.single.$1, 0);
        expect(calls.single.$2, greaterThan(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
