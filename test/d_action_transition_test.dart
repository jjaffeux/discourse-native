import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _slotKey = ValueKey('action-slot');

Future<void> _pump(
  WidgetTester tester,
  Widget? action, {
  bool reducedMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Neighbor'),
              SizedBox(
                key: _slotKey,
                width: 80,
                child: DActionTransition(child: action),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Widget _action(String name, {VoidCallback? onPressed, FocusNode? focusNode}) =>
    DButton(
      key: ValueKey(name),
      label: Text(name),
      focusNode: focusNode,
      onPressed: onPressed ?? () {},
    );

FadeTransition _fade(WidgetTester tester, String name) =>
    tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(ValueKey(name)),
            matching: find.byType(FadeTransition),
          )
          .first,
    );

void main() {
  testWidgets('initial action is visible without an entrance', (tester) async {
    await _pump(tester, _action('Reply'));
    expect(_fade(tester, 'Reply').opacity.value, 1);
    expect(tester.getSize(find.byKey(const ValueKey('Reply'))).width, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add and remove animate while neighboring controls stay still', (
    tester,
  ) async {
    await _pump(tester, null);
    final neighborX = tester.getRect(find.text('Neighbor')).left;
    await _pump(tester, _action('Reply'));
    expect(_fade(tester, 'Reply').opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_fade(tester, 'Reply').opacity.value, inExclusiveRange(0, 1));
    expect(tester.getRect(find.text('Neighbor')).left, neighborX);
    await tester.pump(const Duration(milliseconds: 180));
    expect(_fade(tester, 'Reply').opacity.value, 1);

    await _pump(tester, null);
    expect(find.byKey(const ValueKey('Reply')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(_fade(tester, 'Reply').opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('Reply')), findsNothing);
    expect(tester.getRect(find.text('Neighbor')).left, neighborX);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outgoing actions immediately lose input, focus and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    try {
      var oldPresses = 0;
      var newPresses = 0;
      await _pump(
        tester,
        _action('Create', onPressed: () => oldPresses++, focusNode: focus),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await _pump(tester, _action('Reply', onPressed: () => newPresses++));
      await tester.pump();
      expect(find.byKey(const ValueKey('Create')), findsOneWidget);
      expect(
        tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep(),
        isNot(contains('Create')),
      );
      expect(focus.hasFocus, isFalse);
      // Both the outgoing action and the still-transparent incoming action
      // must ignore this tap.
      await tester.tapAt(tester.getCenter(find.byKey(_slotKey)));
      expect(oldPresses, 0);
      expect(newPresses, 0);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(tester.getCenter(find.byKey(_slotKey)));
      expect(oldPresses, 0);
      expect(newPresses, 1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('Create')), findsNothing);
      expect(find.bySemanticsLabel('Reply'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('scaled action accepts taps only within its visible bounds', (
    tester,
  ) async {
    var presses = 0;
    await _pump(tester, null);
    await _pump(tester, _action('Reply', onPressed: () => presses++));
    await tester.pump(const Duration(milliseconds: 16));
    final slot = tester.getRect(find.byKey(_slotKey));
    await tester.tapAt(Offset(slot.right - 1, slot.center.dy));
    expect(presses, 0);
    await tester.tapAt(slot.center);
    expect(presses, 1);
    await tester.pumpAndSettle();
    await tester.tapAt(Offset(slot.right - 1, slot.center.dy));
    expect(presses, 2);
  });

  testWidgets('same action updates its callback without replaying motion', (
    tester,
  ) async {
    var oldPresses = 0;
    var newPresses = 0;
    await _pump(tester, _action('Reply', onPressed: () => oldPresses++));
    final element = tester.element(find.byKey(const ValueKey('Reply')));
    await _pump(tester, _action('Reply', onPressed: () => newPresses++));
    expect(tester.element(find.byKey(const ValueKey('Reply'))), same(element));
    expect(_fade(tester, 'Reply').opacity.value, 1);
    await tester.tap(find.byKey(const ValueKey('Reply')));
    expect(oldPresses, 0);
    expect(newPresses, 1);
  });

  testWidgets('rapid changes dispose every superseded action', (tester) async {
    await _pump(tester, _action('Create'));
    for (final name in [null, 'Create', 'Reply', null, 'Send']) {
      await _pump(tester, name == null ? null : _action(name));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    expect(find.byType(DButton), findsOneWidget);
    expect(find.byKey(const ValueKey('Send')), findsOneWidget);
    expect(_fade(tester, 'Send').opacity.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion changes immediately and clears an active exit', (
    tester,
  ) async {
    await _pump(tester, _action('Create'));
    await _pump(tester, _action('Reply'));
    await tester.pump(const Duration(milliseconds: 30));
    await _pump(tester, _action('Reply'), reducedMotion: true);
    expect(find.byKey(const ValueKey('Create')), findsNothing);
    expect(find.byKey(const ValueKey('Reply')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DActionTransition),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    await _pump(tester, null, reducedMotion: true);
    expect(find.byType(DButton), findsNothing);
    await _pump(tester, _action('Send'), reducedMotion: true);
    expect(find.byKey(const ValueKey('Send')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DActionTransition),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
