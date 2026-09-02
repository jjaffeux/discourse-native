import 'package:discourse_native/src/shell/curved_animation_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps one curve across rebuilds and disposes it on unmount', (
    tester,
  ) async {
    final parent = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(parent.dispose);
    final built = <Animation<double>>[];
    Widget subject(Animation<double> animation) => CurvedAnimationBuilder(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
      builder: (context, curved) {
        built.add(curved);
        return const SizedBox();
      },
    );

    await tester.pumpWidget(subject(parent));
    await tester.pumpWidget(subject(parent));

    expect(built, hasLength(2));
    final curve = built.first as CurvedAnimation;
    expect(identical(built.last, curve), isTrue);
    expect(curve.parent, same(parent));
    expect(curve.curve, Curves.easeOut);
    expect(curve.reverseCurve, Curves.easeIn);
    expect(curve.isDisposed, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(curve.isDisposed, isTrue);
  });

  testWidgets('replaces and disposes the curve when its parent changes', (
    tester,
  ) async {
    final first = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    final second = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final built = <Animation<double>>[];
    Widget subject(Animation<double> animation) => CurvedAnimationBuilder(
      parent: animation,
      curve: Curves.easeOut,
      builder: (context, curved) {
        built.add(curved);
        return const SizedBox();
      },
    );

    await tester.pumpWidget(subject(first));
    await tester.pumpWidget(subject(second));

    final before = built.first as CurvedAnimation;
    final after = built.last as CurvedAnimation;
    expect(identical(before, after), isFalse);
    expect(before.isDisposed, isTrue);
    expect(after.isDisposed, isFalse);
    expect(after.parent, same(second));
  });

  testWidgets('drives the built transition from the parent animation', (
    tester,
  ) async {
    final parent = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(parent.dispose);
    await tester.pumpWidget(
      CurvedAnimationBuilder(
        parent: parent,
        curve: Curves.linear,
        builder: (context, curved) =>
            FadeTransition(opacity: curved, child: const SizedBox()),
      ),
    );

    parent.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value,
      0.5,
    );
    parent.stop();
  });
}
