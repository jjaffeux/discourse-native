import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 30 by 30 control: its invisible area reaches 7 past each drawn edge.
class _Control extends StatelessWidget {
  const _Control(this.name, this.presses);

  final String name;
  final List<String> presses;

  @override
  Widget build(BuildContext context) => DTouchTarget(
    child: GestureDetector(
      key: ValueKey(name),
      behavior: HitTestBehavior.opaque,
      onTap: () => presses.add(name),
      child: const SizedBox.square(dimension: 30),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TargetPlatform platform = TargetPlatform.iOS,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    builder: (context, child) => DTouchTargets(child: child!),
    home: Scaffold(body: child),
  ),
);

Rect _rect(WidgetTester tester, String name) =>
    tester.getRect(find.byKey(ValueKey(name)));

void main() {
  testWidgets('a phone press reaches 7 past a 30 point control, not 8', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(tester, Center(child: _Control('a', presses)));
    final rect = _rect(tester, 'a');

    for (final (point, pressed) in [
      (rect.topCenter.translate(0, -6.5), true),
      (rect.bottomCenter.translate(0, 6.5), true),
      (rect.centerLeft.translate(-6.5, 0), true),
      (rect.centerRight.translate(6.5, 0), true),
      (rect.topLeft.translate(-6.5, -6.5), true),
      (rect.topCenter.translate(0, -7.5), false),
      (rect.centerRight.translate(7.5, 0), false),
    ]) {
      presses.clear();
      await tester.tapAt(point);
      expect(presses, pressed ? ['a'] : isEmpty, reason: '$point');
    }
  });

  testWidgets('the area keeps the control drawn at its own size', (
    tester,
  ) async {
    await _pump(tester, const Center(child: _Control('a', [])));

    expect(_rect(tester, 'a').size, const Size(30, 30));
  });

  testWidgets('a control already 44 in one axis only grows in the other', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: DTouchTarget(
          child: GestureDetector(
            key: const ValueKey('wide'),
            behavior: HitTestBehavior.opaque,
            onTap: () => presses.add('wide'),
            child: const SizedBox(width: 120, height: 20),
          ),
        ),
      ),
    );
    final rect = _rect(tester, 'wide');

    await tester.tapAt(rect.topCenter.translate(0, -11.5));
    await tester.tapAt(rect.centerRight.translate(1, 0));

    expect(presses, ['wide']);
  });

  testWidgets('a desktop press stays inside what the control draws', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(child: _Control('a', presses)),
      platform: TargetPlatform.macOS,
    );

    await tester.tapAt(_rect(tester, 'a').topCenter.translate(0, -3));

    expect(presses, isEmpty);
  });

  testWidgets('a press on one control never goes to a neighbour', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [_Control('a', presses), _Control('b', presses)],
        ),
      ),
    );

    await tester.tapAt(_rect(tester, 'a').centerRight.translate(-1, 0));
    await tester.tapAt(_rect(tester, 'b').centerLeft.translate(1, 0));

    expect(presses, ['a', 'b']);
  });

  testWidgets('where two areas overlap the later painted control takes it', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [_Control('a', presses), _Control('b', presses)],
        ),
      ),
    );

    await tester.tapAt(_rect(tester, 'a').centerRight.translate(2, 0));
    await tester.tapAt(_rect(tester, 'a').topRight.translate(2, -4));

    expect(presses, ['b', 'b']);
  });

  testWidgets('a surface painted over the area holds the press', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: SizedBox.square(
          dimension: 100,
          child: Stack(
            children: [
              // Painted before the control: its area lies over this.
              const Positioned.fill(child: ColoredBox(color: Colors.red)),
              Center(child: _Control('a', presses)),
              // Painted after it: this covers its area above.
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 33,
                child: ColoredBox(color: Colors.blue),
              ),
            ],
          ),
        ),
      ),
    );
    final rect = _rect(tester, 'a');

    await tester.tapAt(rect.bottomCenter.translate(0, 5));
    await tester.tapAt(rect.topCenter.translate(0, -5));

    expect(presses, ['a']);
  });

  testWidgets('a clip hides the area as overflow hides the mockup layer', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ClipRect(child: _Control('a', presses)),
          ),
        ),
      ),
    );

    await tester.tapAt(_rect(tester, 'a').topCenter.translate(0, -5));

    expect(presses, isEmpty);
  });

  testWidgets('a route over the page covers the areas under it', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(tester, Center(child: _Control('a', presses)));
    final rect = _rect(tester, 'a');
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(rect.topCenter.translate(0, -5));

    expect(presses, isEmpty);
  });

  testWidgets('a control nothing can press has no area either', (tester) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: IgnorePointer(child: _Control('a', presses)),
          ),
        ),
      ),
    );

    await tester.tapAt(_rect(tester, 'a').topCenter.translate(0, -5));

    expect(presses, isEmpty);
  });

  testWidgets('a control holding another gives up its own area', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: DTouchTarget(
          child: GestureDetector(
            key: const ValueKey('outer'),
            behavior: HitTestBehavior.opaque,
            onTap: () => presses.add('outer'),
            child: SizedBox(
              width: 100,
              height: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _Control('inner', presses),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(_rect(tester, 'outer').topRight.translate(-5, -5));
    await tester.tapAt(_rect(tester, 'inner').topCenter.translate(0, -5));

    expect(presses, ['inner']);
  });

  testWidgets('a control in a pressable row takes the press from the row', (
    tester,
  ) async {
    final presses = <String>[];
    await _pump(
      tester,
      Center(
        child: GestureDetector(
          onTap: () => presses.add('row'),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [const Text('Row'), _Control('a', presses)],
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(_rect(tester, 'a').topCenter.translate(0, -5));
    await tester.tapAt(_rect(tester, 'a').topCenter.translate(0, -12));

    expect(presses, ['a', 'row']);
  });

  testWidgets('a drag starting in the area scrolls instead of pressing', (
    tester,
  ) async {
    final presses = <String>[];
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _pump(
      tester,
      ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _Control('a', presses),
          ),
          const SizedBox(height: 2000),
        ],
      ),
    );

    await tester.dragFrom(
      _rect(tester, 'a').bottomCenter.translate(0, 5),
      const Offset(0, -100),
    );

    expect(presses, isEmpty);
    expect(scroll.offset, greaterThan(0));
  });

  group('kit controls drawn under 44 take presses from their area', () {
    final controls = <String, Widget Function(VoidCallback pressed)>{
      'switch': (pressed) => DSwitch(value: false, onChanged: (_) => pressed()),
      'checkbox': (pressed) =>
          DCheckbox(value: false, onChanged: (_) => pressed()),
      'toggle': (pressed) => DToggle(
        onPressedChanged: (_) => pressed(),
        child: const Text('Bold'),
      ),
      'badge': (pressed) =>
          DBadge.action(onPressed: pressed, child: const Text('New')),
      'breadcrumb link': (pressed) =>
          DBreadcrumbLink(onPressed: pressed, child: const Text('Home')),
      'radio': (pressed) => DRadioGroup<int>(
        onChanged: (_) => pressed(),
        child: const DRadioGroupItem<int>(value: 1, semanticLabel: 'One'),
      ),
    };
    for (final MapEntry(key: name, value: build) in controls.entries) {
      testWidgets(name, (tester) async {
        var presses = 0;
        await _pump(
          tester,
          Center(
            child: KeyedSubtree(
              key: const ValueKey('control'),
              child: build(() => presses++),
            ),
          ),
        );
        final rect = _rect(tester, 'control');
        final reach = (kDTouchTargetExtent - rect.height) / 2;
        expect(reach, greaterThan(1), reason: '$rect');

        await tester.tapAt(rect.topCenter.translate(0, 1 - reach));
        await tester.pump(const Duration(milliseconds: 500));

        expect(presses, 1);
      });
    }
  });
}
