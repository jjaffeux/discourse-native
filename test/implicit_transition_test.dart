import 'package:discourse_native/src/ui/foundation/implicit_transition.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _duration = Duration(milliseconds: 200);

BoxDecoration _decoration(Color color, [double radius = 4]) =>
    BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius));

/// The transition beside the AnimatedContainer it replaces, both driven by
/// the same value, curve and duration.
class _Pair extends StatelessWidget {
  const _Pair({required this.decoration, required this.duration});

  final Decoration decoration;
  final Duration duration;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        AnimatedContainer(
          key: const ValueKey('reference'),
          duration: duration,
          curve: Curves.ease,
          decoration: decoration,
          child: const SizedBox(width: 20, height: 20),
        ),
        DImplicitTransition<Decoration>(
          value: decoration,
          duration: duration,
          curve: Curves.ease,
          lerp: (a, b, t) => Decoration.lerp(a, b, t)!,
          builder: (context, value) => Container(
            key: const ValueKey('transition'),
            decoration: value,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      ],
    ),
  );
}

Decoration _shown(WidgetTester tester, String key) => tester
    .widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(DecoratedBox),
      ),
    )
    .decoration;

void _expectSame(WidgetTester tester) =>
    expect(_shown(tester, 'transition'), _shown(tester, 'reference'));

void main() {
  testWidgets('mounting and rebuilding with the same value animates nothing', (
    tester,
  ) async {
    final created = <String>[];
    void listen(ObjectEvent event) {
      if (event is ObjectCreated) created.add(event.className);
    }

    FlutterMemoryAllocations.instance.addListener(listen);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(listen));
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DImplicitTransition<Decoration>(
            value: _decoration(const Color(0xFF112233)),
            duration: _duration,
            lerp: (a, b, t) => Decoration.lerp(a, b, t)!,
            builder: (context, value) => DecoratedBox(decoration: value),
          ),
        ),
      );
    }
    expect(created, isNot(contains('AnimationController')));
    expect(created, isNot(contains('Ticker')));
    expect(created, isNot(contains('CurvedAnimation')));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a change follows the implicit animation it replaces', (
    tester,
  ) async {
    const from = Color(0xFF000000);
    const to = Color(0xFFFFFFFF);
    await tester.pumpWidget(
      _Pair(decoration: _decoration(from), duration: _duration),
    );
    _expectSame(tester);
    await tester.pumpWidget(
      _Pair(decoration: _decoration(to, 12), duration: _duration),
    );
    for (var ms = 0; ms <= 220; ms += 20) {
      _expectSame(tester);
      await tester.pump(const Duration(milliseconds: 20));
    }
    _expectSame(tester);
    expect(_shown(tester, 'transition'), _decoration(to, 12));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a change mid-transition restarts from the value shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Pair(
        decoration: _decoration(const Color(0xFF000000)),
        duration: _duration,
      ),
    );
    await tester.pumpWidget(
      _Pair(
        decoration: _decoration(const Color(0xFFFF0000)),
        duration: _duration,
      ),
    );
    await tester.pump(const Duration(milliseconds: 70));
    _expectSame(tester);
    await tester.pumpWidget(
      _Pair(
        decoration: _decoration(const Color(0xFF0000FF)),
        duration: _duration,
      ),
    );
    for (var ms = 0; ms <= 220; ms += 20) {
      _expectSame(tester);
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(_shown(tester, 'transition'), _decoration(const Color(0xFF0000FF)));
  });

  testWidgets('a change with no duration shows the new value at once', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Pair(
        decoration: _decoration(const Color(0xFF000000)),
        duration: _duration,
      ),
    );
    await tester.pumpWidget(
      _Pair(
        decoration: _decoration(const Color(0xFFFF0000)),
        duration: _duration,
      ),
    );
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pumpWidget(
      _Pair(
        decoration: _decoration(const Color(0xFF00FF00)),
        duration: Duration.zero,
      ),
    );
    _expectSame(tester);
    expect(_shown(tester, 'transition'), _decoration(const Color(0xFF00FF00)));
    await tester.pump(const Duration(milliseconds: 20));
    _expectSame(tester);
  });

  testWidgets('a text style follows AnimatedDefaultTextStyle', (tester) async {
    Widget pair(TextStyle style) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          AnimatedDefaultTextStyle(
            style: style,
            duration: _duration,
            child: const Text('reference', key: ValueKey('reference')),
          ),
          DImplicitTransition<TextStyle>(
            value: style,
            duration: _duration,
            lerp: (a, b, t) => TextStyle.lerp(a, b, t)!,
            builder: (context, value) => DefaultTextStyle(
              style: value,
              child: const Text('transition', key: ValueKey('transition')),
            ),
          ),
        ],
      ),
    );
    TextStyle shown(String key) =>
        DefaultTextStyle.of(tester.element(find.byKey(ValueKey(key)))).style;

    await tester.pumpWidget(
      pair(const TextStyle(color: Color(0xFF000000), fontSize: 12)),
    );
    await tester.pumpWidget(
      pair(const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14)),
    );
    for (var ms = 0; ms <= 220; ms += 20) {
      expect(shown('transition'), shown('reference'));
      await tester.pump(const Duration(milliseconds: 20));
    }
  });
}
