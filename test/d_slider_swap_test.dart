import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, Axis axis, TextDirection direction) => MaterialApp(
  home: Scaffold(
    body: Directionality(
      textDirection: direction,
      child: Center(
        child: SizedBox(
          width: axis == Axis.horizontal ? 212 : 48,
          height: axis == Axis.horizontal ? 48 : 212,
          child: child,
        ),
      ),
    ),
  ),
);

Offset position(Rect rect, double value, Axis axis, TextDirection direction) {
  final reversed = axis == Axis.vertical || direction == TextDirection.rtl;
  final fraction = reversed ? 1 - value / 100 : value / 100;
  return axis == Axis.horizontal
      ? Offset(rect.left + 6 + fraction * (rect.width - 12), rect.center.dy)
      : Offset(rect.center.dx, rect.top + 6 + fraction * (rect.height - 12));
}

void main() {
  for (final axis in Axis.values) {
    for (final direction in TextDirection.values) {
      testWidgets(
        '$axis $direction swap follows accepted crossing with borrowed focus and semantic slots',
        (tester) async {
          var values = <double>[20, 40, 60];
          final nodes = List.generate(3, (_) => FocusNode());
          for (final node in nodes) {
            addTearDown(node.dispose);
          }
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            host(
              StatefulBuilder(
                builder: (context, setState) => DMultiSlider(
                  values: values,
                  orientation: axis,
                  focusNodes: nodes,
                  step: 5,
                  minStepsBetweenValues: 2,
                  thumbCollisionBehavior: DSliderThumbCollisionBehavior.swap,
                  semanticLabels: const ['Low', 'Middle', 'High'],
                  onChanged: (next) => setState(() => values = next),
                ),
              ),
              axis,
              direction,
            ),
          );
          final rect = tester.getRect(find.byType(DMultiSlider));
          final gesture = await tester.startGesture(
            position(rect, 20, axis, direction),
          );
          await tester.pump();
          expect(nodes[0].hasFocus, isTrue);
          await gesture.moveTo(position(rect, 90, axis, direction));
          await tester.pump();
          expect(values, [40, 60, 90]);
          expect(nodes[2].hasFocus, isTrue);
          expect(nodes[0].hasFocus, isFalse);
          expect(
            tester
                .getSemantics(find.bySemanticsLabel('High'))
                .getSemanticsData()
                .value,
            '90.0',
          );
          await gesture.moveTo(position(rect, 10, axis, direction));
          await tester.pump();
          expect(values, [10, 40, 60]);
          expect(nodes[0].hasFocus, isTrue);
          await gesture.up();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(nodes[1].hasFocus, isTrue);
          await tester.pumpWidget(const SizedBox());
          for (final node in nodes) {
            expect(() => node.addListener(() {}), returnsNormally);
          }
          semantics.dispose();
        },
      );
    }
  }

  testWidgets(
    'swap proposals rejected or clamped by a parent retain authoritative focus and values',
    (tester) async {
      var values = <double>[20, 40, 60];
      var accept = false;
      final nodes = List.generate(3, (_) => FocusNode());
      for (final node in nodes) {
        addTearDown(node.dispose);
      }
      late StateSetter update;
      final ends = <List<double>>[];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DMultiSlider(
                values: values,
                focusNodes: nodes,
                thumbCollisionBehavior: DSliderThumbCollisionBehavior.swap,
                onChanged: (next) => setState(() {
                  if (accept) values = [next[0], next[1], next[2].clamp(0, 70)];
                }),
                onChangeEnd: ends.add,
              );
            },
          ),
          Axis.horizontal,
          TextDirection.ltr,
        ),
      );
      final rect = tester.getRect(find.byType(DMultiSlider));
      final gesture = await tester.startGesture(
        position(rect, 20, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      await gesture.moveTo(
        position(rect, 90, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      expect(values, [20, 40, 60]);
      expect(nodes[0].hasFocus, isTrue);
      update(() => accept = true);
      await tester.pump();
      await gesture.moveTo(
        position(rect, 85, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      expect(values, [40, 60, 70]);
      expect(nodes[2].hasFocus, isTrue);
      update(() => values = [10, 30, 50]);
      await tester.pump();
      expect(nodes[2].hasFocus, isTrue);
      await gesture.moveTo(
        position(rect, 20, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      expect(values, [10, 20, 30]);
      expect(nodes[1].hasFocus, isTrue);
      await gesture.up();
      await tester.pump();
      expect(ends, [
        [10, 20, 30],
      ]);
    },
  );

  testWidgets(
    'swap clamps into legal spacing intervals without moving neighbours',
    (tester) async {
      var values = <double>[20, 40, 60];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DMultiSlider(
              values: values,
              step: 5,
              minStepsBetweenValues: 2,
              thumbCollisionBehavior: DSliderThumbCollisionBehavior.swap,
              onChanged: (next) => setState(() => values = next),
            ),
          ),
          Axis.horizontal,
          TextDirection.ltr,
        ),
      );
      final rect = tester.getRect(find.byType(DMultiSlider));
      final gesture = await tester.startGesture(
        position(rect, 20, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      await gesture.moveTo(
        position(rect, 45, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      expect(values, [40, 50, 60]);
      await gesture.moveTo(
        position(rect, 65, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      expect(values, [40, 60, 70]);
      await gesture.up();
    },
  );

  testWidgets(
    'large steps default to absolute ten units and allow an explicit override',
    (tester) async {
      for (final largeStep in <double?>[null, 20]) {
        var value = 30.0;
        final node = FocusNode();
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) => DSlider(
                value: value,
                step: 5,
                largeStep: largeStep,
                focusNode: node,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
            Axis.horizontal,
            TextDirection.ltr,
          ),
        );
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pump();
        expect(value, largeStep == null ? 40 : 50);
        await tester.pumpWidget(const SizedBox());
        node.dispose();
      }
    },
  );
  testWidgets(
    'rejected swaps still finish native interaction with unchanged accepted values',
    (tester) async {
      final commits = <List<double>>[];
      await tester.pumpWidget(
        host(
          DMultiSlider(
            values: const [20, 40, 60],
            thumbCollisionBehavior: DSliderThumbCollisionBehavior.swap,
            onChanged: (_) {},
            onChangeEnd: commits.add,
          ),
          Axis.horizontal,
          TextDirection.ltr,
        ),
      );
      final rect = tester.getRect(find.byType(DMultiSlider));
      final gesture = await tester.startGesture(
        position(rect, 20, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      await gesture.moveTo(
        position(rect, 90, Axis.horizontal, TextDirection.ltr),
      );
      await gesture.up();
      await tester.pump();
      expect(commits, [
        [20, 40, 60],
      ]);
    },
  );

  testWidgets(
    'multi-value Form saves accepted swaps and resets its initial range',
    (tester) async {
      final form = GlobalKey<FormState>();
      List<double>? saved;
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: DMultiSliderField(
              initialValue: const [20, 40, 60],
              thumbCollisionBehavior: DSliderThumbCollisionBehavior.swap,
              onSaved: (value) => saved = value,
            ),
          ),
          Axis.horizontal,
          TextDirection.ltr,
        ),
      );
      final rect = tester.getRect(find.byType(DMultiSlider));
      final gesture = await tester.startGesture(
        position(rect, 20, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      await gesture.moveTo(
        position(rect, 90, Axis.horizontal, TextDirection.ltr),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      form.currentState!.save();
      expect(saved, [40, 60, 90]);
      form.currentState!.reset();
      await tester.pump();
      expect(tester.widget<DMultiSlider>(find.byType(DMultiSlider)).values, [
        20,
        40,
        60,
      ]);
    },
  );
}
