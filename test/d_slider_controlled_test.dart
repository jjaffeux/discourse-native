import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 212, child: child)),
  ),
);

void main() {
  testWidgets(
    'controlled parents reject, clamp and replace values during capture',
    (tester) async {
      var values = <double>[20, 80];
      var reject = true;
      late StateSetter update;
      final commits = <List<double>>[];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DMultiSlider(
                values: values,
                semanticLabels: const ['Low', 'High'],
                onChanged: (next) {
                  if (!reject) {
                    setState(
                      () => values = [next.first.clamp(0, 40), next.last],
                    );
                  }
                },
                onChangeEnd: commits.add,
              );
            },
          ),
        ),
      );
      final rect = tester.getRect(find.byType(DMultiSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + 66, rect.center.dy),
      );
      await tester.pump();
      expect(values, [20, 80]);
      final semantics = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Low'))
            .getSemanticsData()
            .value,
        '20.0',
      );
      update(() {
        reject = false;
        values = [10, 90];
      });
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Low'))
            .getSemanticsData()
            .value,
        '10.0',
      );
      await gesture.moveTo(Offset(rect.left + 126, rect.center.dy));
      await tester.pump();
      expect(values, [40, 90]);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Low'))
            .getSemanticsData()
            .value,
        '40.0',
      );
      await gesture.up();
      await tester.pump();
      expect(commits, [
        [40, 90],
      ]);
      semantics.dispose();
    },
  );

  testWidgets(
    'controlled fields save and reset authoritative values after rejected proposals',
    (tester) async {
      final form = GlobalKey<FormState>();
      double? scalarSaved;
      List<double>? rangeSaved;
      final proposals = <double>[];
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DSliderField(
                  value: 20,
                  initialValue: 5,
                  onChanged: proposals.add,
                  onSaved: (v) => scalarSaved = v,
                ),
                DMultiSliderField(
                  values: const [20, 80],
                  initialValue: const [0, 100],
                  onChanged: (_) {},
                  onSaved: (v) => rangeSaved = v,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DSlider));
      await tester.pump();
      expect(proposals, [50]);
      await tester.tapAt(
        tester.getTopLeft(find.byType(DMultiSlider).last) +
            const Offset(66, 24),
      );
      await tester.pump();
      form.currentState!.save();
      expect(scalarSaved, 20);
      expect(rangeSaved, [20, 80]);
      form.currentState!.reset();
      await tester.pump();
      expect(tester.widget<DSlider>(find.byType(DSlider)).value, 20);
      expect(
        tester.widget<DMultiSlider>(find.byType(DMultiSlider).last).values,
        [20, 80],
      );
    },
  );

  testWidgets(
    'thumb count changes cancel capture without disposing borrowed focus',
    (tester) async {
      final a = FocusNode(), b = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      var multiple = true, cancels = 0;
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DMultiSlider(
                values: multiple ? [20, 80] : [20],
                focusNodes: multiple ? [a, b] : [a],
                onChanged: (_) {},
                onChangeCancel: () => cancels++,
              );
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DMultiSlider)),
      );
      await tester.pump();
      update(() => multiple = false);
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump();
      expect(cancels, 1);
      expect(tester.takeException(), isNull);
      expect(() => b.addListener(() {}), returnsNormally);
    },
  );
  testWidgets(
    'pointer push preserves minimum gaps and stop policy keeps neighbours fixed',
    (tester) async {
      for (final policy in DSliderThumbCollisionBehavior.values) {
        var values = <double>[20, 40, 60];
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) => DMultiSlider(
                values: values,
                step: 5,
                minStepsBetweenValues: 2,
                thumbCollisionBehavior: policy,
                onChanged: (v) => setState(() => values = v),
              ),
            ),
          ),
        );
        final rect = tester.getRect(find.byType(DMultiSlider));
        final gesture = await tester.startGesture(
          Offset(rect.left + 46, rect.center.dy),
        );
        await tester.pump();
        await gesture.moveTo(Offset(rect.right + 100, rect.center.dy));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(
          values,
          policy == DSliderThumbCollisionBehavior.push
              ? [80, 90, 100]
              : [30, 40, 60],
        );
      }
    },
  );

  testWidgets(
    'horizontal RTL track jumps reverse and secondary pointers cannot steal capture',
    (tester) async {
      var value = 75.0;
      await tester.pumpWidget(
        host(
          Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setState) => DSlider(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(DSlider));
      final primary = await tester.startGesture(
        Offset(rect.left + 6, rect.center.dy),
        pointer: 1,
      );
      await tester.pump();
      expect(value, 100);
      final secondary = await tester.startGesture(
        Offset(rect.right - 6, rect.center.dy),
        pointer: 2,
      );
      await tester.pump();
      expect(value, 100);
      await secondary.up();
      await primary.up();
      await tester.pump();
      expect(value, 100);
    },
  );
}
