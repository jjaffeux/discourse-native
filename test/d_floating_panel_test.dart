import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tucking removes hidden controls from keyboard focus', (
    tester,
  ) async {
    final controller = DFloatingPanelController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(
        controller,
        DButton(
          label: const Text('Action'),
          focusNode: focus,
          onPressed: () {},
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    controller.tuck();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(focus.canRequestFocus, isFalse);
    controller.restore();
    await tester.pumpAndSettle();
    expect(focus.canRequestFocus, isTrue);
  });

  testWidgets('snaps across the screen and tucks without disposing content', (
    tester,
  ) async {
    final controller = DFloatingPanelController();
    addTearDown(controller.dispose);
    var disposals = 0;
    await tester.pumpWidget(
      _host(controller, _Probe(onDispose: () => disposals++)),
    );
    final surface = find.byKey(const ValueKey('surface'));
    final initial = tester.getRect(surface);
    await tester.drag(surface, const Offset(-130, -140));
    await tester.pumpAndSettle();
    expect(tester.getRect(surface).left, lessThan(initial.left));
    expect(tester.getRect(surface).top, lessThan(initial.top));
    expect(controller.tucked, isFalse);
    await tester.drag(surface, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(controller.tucked, isTrue);
    expect(disposals, 0);
    expect(surface, findsNothing);
    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();
    expect(surface, findsOneWidget);
    expect(disposals, 0);
  });

  testWidgets('does not intercept gaps or the screen behind a tucked panel', (
    tester,
  ) async {
    final controller = DFloatingPanelController();
    addTearDown(controller.dispose);
    var taps = 0;
    await tester.pumpWidget(
      _host(
        controller,
        const SizedBox(height: 130),
        onBackground: () => taps++,
      ),
    );
    await tester.tap(find.text('Behind'));
    expect(taps, 1);
    controller.tuck();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Behind'));
    expect(taps, 2);
  });

  testWidgets('keeps content inside resized bounds', (tester) async {
    final controller = DFloatingPanelController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, const SizedBox(key: ValueKey('surface'), height: 130)),
    );
    controller.moveToEdge(right: false);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        controller,
        const SizedBox(key: ValueKey('surface'), height: 130),
        width: 230,
        height: 200,
      ),
    );
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byKey(const ValueKey('surface')));
    final host = tester.getRect(find.byKey(const ValueKey('host')));
    expect(panel.left, greaterThanOrEqualTo(host.left));
    expect(panel.right, lessThanOrEqualTo(host.right));
    expect(panel.bottom, lessThanOrEqualTo(host.bottom));
    expect(tester.takeException(), isNull);
  });
}

Widget _host(
  DFloatingPanelController controller,
  Widget child, {
  double width = 390,
  double height = 650,
  VoidCallback? onBackground,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      key: const ValueKey('host'),
      width: width,
      height: height,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: DButton(
              label: const Text('Behind'),
              onPressed: onBackground,
            ),
          ),
          DFloatingPanel(
            controller: controller,
            restoreLabel: 'Restore',
            child: DCard(child: child),
          ),
        ],
      ),
    ),
  ),
);

class _Probe extends StatefulWidget {
  const _Probe({required this.onDispose});
  final VoidCallback onDispose;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox(
    key: ValueKey('surface'),
    height: 130,
    child: Text('Call'),
  );
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
