import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final testCase
      in <
        ({
          String name,
          ResizablePaneEdge edge,
          TextDirection direction,
          LogicalKeyboardKey growKey,
          bool handleOnLeft,
        })
      >[
        (
          name: 'LTR leading',
          edge: ResizablePaneEdge.leading,
          direction: TextDirection.ltr,
          growKey: LogicalKeyboardKey.arrowLeft,
          handleOnLeft: true,
        ),
        (
          name: 'LTR trailing',
          edge: ResizablePaneEdge.trailing,
          direction: TextDirection.ltr,
          growKey: LogicalKeyboardKey.arrowRight,
          handleOnLeft: false,
        ),
        (
          name: 'RTL leading',
          edge: ResizablePaneEdge.leading,
          direction: TextDirection.rtl,
          growKey: LogicalKeyboardKey.arrowRight,
          handleOnLeft: false,
        ),
        (
          name: 'RTL trailing',
          edge: ResizablePaneEdge.trailing,
          direction: TextDirection.rtl,
          growKey: LogicalKeyboardKey.arrowLeft,
          handleOnLeft: true,
        ),
      ]) {
    testWidgets('${testCase.name} puts the handle on its logical edge', (
      tester,
    ) async {
      final writes = <double>[];
      final controller = _controller(writes: writes);
      addTearDown(controller.dispose);
      await _pumpPane(
        tester,
        controller: controller,
        edge: testCase.edge,
        direction: testCase.direction,
      );

      final pane = tester.getRect(find.byKey(const ValueKey('pane')));
      final handle = tester.getRect(
        find.byKey(const ValueKey('shared-resize-handle')),
      );
      if (testCase.handleOnLeft) {
        expect(handle.left, pane.left, reason: testCase.name);
      } else {
        expect(handle.right, pane.right, reason: testCase.name);
      }

      await _requestResizeFocus(tester);
      await tester.sendKeyEvent(testCase.growKey);
      await tester.pump();

      expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 256);
      expect(writes, [256]);
    });
  }

  testWidgets('narrow constraints clamp without replacing the preference', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final writes = <double>[];
    final controller = _controller(initialWidth: 480, writes: writes);
    addTearDown(controller.dispose);
    await _pumpPane(tester, controller: controller, maximumWidth: 376);

    final handle = find.byKey(const ValueKey('shared-resize-handle'));
    expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 376);
    expect(
      tester
          .getSemantics(handle)
          .getSemanticsData()
          .hasAction(SemanticsAction.increase),
      isFalse,
    );
    expect(controller.resizeBy(16, maximum: 376), isFalse);
    await controller.flush();
    expect(writes, isEmpty);

    await _pumpPane(tester, controller: controller, maximumWidth: 600);
    expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 480);
    expect(controller.value, 480);
    semantics.dispose();
  });

  testWidgets('semantics actions resize and persist the shared controller', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final writes = <double>[];
    final controller = _controller(writes: writes);
    addTearDown(controller.dispose);
    await _pumpPane(tester, controller: controller);

    final handle = find.byKey(const ValueKey('shared-resize-handle'));
    var node = tester.getSemantics(handle);
    var data = node.getSemanticsData();
    expect(data.label, 'Resize shared pane');
    expect(data.value, '240 pixels wide');
    expect(data.increasedValue, '256 pixels wide');
    expect(data.decreasedValue, '224 pixels wide');

    tester.platformDispatcher.onSemanticsActionEvent!(
      SemanticsActionEvent(
        type: SemanticsAction.increase,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 256);
    expect(writes, [256]);

    node = tester.getSemantics(handle);
    data = node.getSemanticsData();
    expect(data.value, '256 pixels wide');
    tester.platformDispatcher.onSemanticsActionEvent!(
      SemanticsActionEvent(
        type: SemanticsAction.decrease,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 240);
    expect(writes, [256, 240]);
    semantics.dispose();
  });

  testWidgets('keyboard repeats persist once when the key ends', (
    tester,
  ) async {
    final writes = <double>[];
    final controller = _controller(writes: writes);
    addTearDown(controller.dispose);
    await _pumpPane(tester, controller: controller);
    await _requestResizeFocus(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 272);
    expect(writes, isEmpty);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(writes, [272]);
  });

  testWidgets('focus loss and disposal flush pending keyboard widths', (
    tester,
  ) async {
    final writes = <double>[];
    final controller = _controller(writes: writes);
    addTearDown(controller.dispose);
    final otherFocus = FocusNode(debugLabel: 'other control');
    addTearDown(otherFocus.dispose);
    await _pumpPane(
      tester,
      controller: controller,
      sibling: Focus(
        focusNode: otherFocus,
        child: const SizedBox(key: ValueKey('other-focus')),
      ),
    );
    await _requestResizeFocus(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(writes, isEmpty);
    otherFocus.requestFocus();
    await tester.pump();
    expect(writes, [256]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

    await _requestResizeFocus(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(writes, [256]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(writes, [256, 272]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
  });

  testWidgets('pointer resize highlight clears when the drag ends', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pumpPane(tester, controller: controller, dividerWidth: 1);

    final handle = find.byKey(const ValueKey('shared-resize-handle'));
    final focus = tester
        .widget<Focus>(find.byKey(const ValueKey('shared-resize-focus')))
        .focusNode!;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    var divider = find.descendant(
      of: handle,
      matching: find.byType(ColoredBox),
    );
    expect(focus.hasFocus, isTrue);
    expect(tester.getSize(divider).width, 3);
    expect(
      tester.widget<ColoredBox>(divider).color,
      Theme.of(tester.element(divider)).colorScheme.primary,
    );

    await gesture.up();
    await tester.pump();

    divider = find.descendant(of: handle, matching: find.byType(ColoredBox));
    expect(focus.hasFocus, isFalse);
    expect(tester.getSize(divider).width, 1);
    expect(
      tester.widget<ColoredBox>(divider).color,
      Theme.of(tester.element(divider)).shell.divider,
    );
  });

  testWidgets('live width changes rebuild neither the frame nor pane content', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var frameBuilds = 0;
    var paneContentBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            frameBuilds++;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 200,
                child: ResizablePane(
                  key: const ValueKey('pane'),
                  controller: controller,
                  edge: ResizablePaneEdge.trailing,
                  resizeKey: 'shared',
                  semanticsLabel: 'Resize shared pane',
                  child: Builder(
                    builder: (context) {
                      paneContentBuilds++;
                      return const ColoredBox(color: Colors.blue);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    expect((frameBuilds, paneContentBuilds), (1, 1));

    controller.resizeBy(16);
    await tester.pump();

    expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 256);
    expect((frameBuilds, paneContentBuilds), (1, 1));
  });
}

PanelWidthController _controller({
  double initialWidth = 240,
  List<double>? writes,
}) => PanelWidthController(
  initialWidth: initialWidth,
  minimumWidth: 200,
  maximumWidth: 480,
  writeWidth: writes == null ? null : (width) async => writes.add(width),
);

Future<void> _pumpPane(
  WidgetTester tester, {
  required PanelWidthController controller,
  ResizablePaneEdge edge = ResizablePaneEdge.trailing,
  TextDirection direction = TextDirection.ltr,
  double maximumWidth = double.infinity,
  double dividerWidth = 0,
  Widget sibling = const SizedBox.shrink(),
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Directionality(
      textDirection: direction,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          height: 200,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResizablePane(
                key: const ValueKey('pane'),
                controller: controller,
                edge: edge,
                resizeKey: 'shared',
                semanticsLabel: 'Resize shared pane',
                maximumWidth: maximumWidth,
                dividerWidth: dividerWidth,
                child: const ColoredBox(color: Colors.blue),
              ),
              sibling,
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<void> _requestResizeFocus(WidgetTester tester) async {
  tester
      .widget<Focus>(find.byKey(const ValueKey('shared-resize-focus')))
      .focusNode!
      .requestFocus();
  await tester.pump();
}
