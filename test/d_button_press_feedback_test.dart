import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pressIn = Duration(milliseconds: 80);
const _release = Duration(milliseconds: 400);

Finder get _button => find.byType(FilledButton);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

DButton _dButton({
  DButtonVariant variant = DButtonVariant.outline,
  VoidCallback? onPressed = _noop,
  bool loading = false,
}) => DButton(
  label: const Text('Save'),
  variant: variant,
  loading: loading,
  onPressed: onPressed,
);

void _noop() {}

/// How much smaller than its laid-out width the button is painted.
double _paintedScale(WidgetTester tester) =>
    tester.getRect(_button).width / tester.getSize(_button).width;

void main() {
  for (final (variant, scale) in const [
    (DButtonVariant.primary, .95),
    (DButtonVariant.outline, .92),
    (DButtonVariant.recessed, .94),
  ]) {
    testWidgets('$variant gives to $scale in 80ms and keeps its layout', (
      tester,
    ) async {
      await _mount(tester, _dButton(variant: variant));
      final resting = tester.getRect(_button);

      final press = await tester.startGesture(resting.center);
      await tester.pump();
      await tester.pump(_pressIn);

      expect(_paintedScale(tester), moreOrLessEquals(scale, epsilon: 1e-9));
      expect(tester.getSize(_button), resting.size);
      expect(tester.getRect(_button).center, resting.center);
      expect(tester.takeException(), isNull);

      await press.up();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('release overshoots and settles within 400ms', (tester) async {
    await _mount(tester, _dButton());
    final press = await tester.startGesture(tester.getCenter(_button));
    await tester.pump();
    await tester.pump(_pressIn);

    await press.up();
    await tester.pump();
    var overshoot = 0.0;
    for (var elapsed = Duration.zero; elapsed < _release;) {
      const frame = Duration(milliseconds: 16);
      elapsed += frame;
      await tester.pump(frame);
      overshoot = _paintedScale(tester) > overshoot
          ? _paintedScale(tester)
          : overshoot;
    }
    await tester.pump(const Duration(milliseconds: 16));

    expect(overshoot, greaterThan(1));
    expect(_paintedScale(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a tap whose down and up arrive together still gives', (
    tester,
  ) async {
    // A Scrollable holds the tap back until the pointer lifts, so the pressed
    // state turns on and off with no frame between them.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(children: [Center(child: _dButton())]),
        ),
      ),
    );
    final press = await tester.startGesture(tester.getCenter(_button));
    await press.up();

    await tester.pump();
    await tester.pump(_pressIn);

    expect(_paintedScale(tester), moreOrLessEquals(.92, epsilon: 1e-9));
    await tester.pumpAndSettle();
    expect(_paintedScale(tester), 1);
  });

  for (final (name, button) in [
    ('disabled', _dButton(onPressed: null)),
    ('loading', _dButton(loading: true)),
  ]) {
    testWidgets('a $name button does not animate', (tester) async {
      await _mount(tester, button);
      final press = await tester.startGesture(tester.getCenter(_button));
      await tester.pump();
      await tester.pump(_pressIn);

      expect(_paintedScale(tester), 1);

      await press.up();
    });
  }

  testWidgets('a press that disables its button springs back', (tester) async {
    var enabled = true;
    late StateSetter setEnabled;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          setEnabled = setState;
          return _dButton(onPressed: enabled ? _noop : null);
        },
      ),
    );
    final press = await tester.startGesture(tester.getCenter(_button));
    await tester.pump();
    await tester.pump(_pressIn);
    expect(_paintedScale(tester), moreOrLessEquals(.92, epsilon: 1e-9));

    setEnabled(() => enabled = false);
    await tester.pumpAndSettle();

    expect(_paintedScale(tester), 1);
    await press.up();
  });

  testWidgets('reduced motion shows the press without motion', (tester) async {
    await _mount(tester, _dButton(), reduced: true);
    final press = await tester.startGesture(tester.getCenter(_button));
    await tester.pump();

    expect(_paintedScale(tester), moreOrLessEquals(.92, epsilon: 1e-9));

    await press.up();
    await tester.pump();

    expect(_paintedScale(tester), 1);
  });

  testWidgets('the whole resting area stays pressable under the scale', (
    tester,
  ) async {
    await _mount(tester, _dButton());
    final resting = tester.getRect(_button);
    final press = await tester.startGesture(resting.center);
    await tester.pump();
    await tester.pump(_pressIn);
    expect(tester.getRect(_button).width, lessThan(resting.width));

    final corner = resting.topLeft + const Offset(1, 1);
    final hit = tester.hitTestOnBinding(corner);

    expect(
      hit.path.map((entry) => entry.target),
      contains(
        tester.renderObject(
          find.descendant(of: _button, matching: find.byType(InkWell)),
        ),
      ),
    );
    await press.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a press in the invisible phone area gives the button', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => DTouchTargets(child: child!),
        home: Scaffold(
          body: Center(child: _dButton(onPressed: () => presses++)),
        ),
      ),
    );
    final resting = tester.getRect(_button);
    expect(resting.height, lessThan(kDTouchTargetExtent));

    final press = await tester.startGesture(
      resting.bottomCenter + const Offset(0, 2),
    );
    await tester.pump();
    await tester.pump(_pressIn);

    expect(_paintedScale(tester), moreOrLessEquals(.92, epsilon: 1e-9));
    await press.up();
    await tester.pumpAndSettle();
    expect(presses, 1);
    expect(_paintedScale(tester), 1);
  });

  for (final density in [DButtonDensity.standard, DButtonDensity.postAction]) {
    testWidgets('an idle $density button holds no press ticker', (
      tester,
    ) async {
      await _mount(
        tester,
        DButton(label: const Text('Reply'), density: density, onPressed: _noop),
      );
      await tester.pumpAndSettle();

      var tickerStates = 0;
      void visit(Element element) {
        if (element.widget is FilledButton) return;
        if (element is StatefulElement && element.state is TickerProvider) {
          tickerStates++;
        }
        element.visitChildren(visit);
      }

      tester.element(find.byType(DButton)).visitChildren(visit);

      expect(tickerStates, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('a split view toggle gives through the same scale', (
    tester,
  ) async {
    await _mount(
      tester,
      DToggle.iconOnly(
        density: DToggleDensity.splitView,
        semanticLabel: 'Split',
        onPressedChanged: (_) {},
        icon: const SizedBox.square(dimension: 14),
      ),
    );
    final toggle = find.byType(DToggle);
    final resting = tester.getRect(toggle);
    final press = await tester.startGesture(resting.center);
    await tester.pump();
    await tester.pump(_pressIn);

    final surface = find.descendant(
      of: toggle,
      matching: find.byType(DecoratedBox),
    );
    expect(
      tester.getRect(surface.first).width / tester.getSize(surface.first).width,
      moreOrLessEquals(.92, epsilon: 1e-9),
    );
    expect(find.byType(AnimatedScale), findsNothing);

    await press.up();
    await tester.pumpAndSettle();
  });
}
