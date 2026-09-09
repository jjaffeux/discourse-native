import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final controlled in [false, true]) {
    for (final accept in [false, true]) {
      testWidgets(
        'mounted reset baseline controlled=$controlled accept=$accept owns save and validation',
        (tester) async {
          final form = GlobalKey<FormState>();
          double scalar = 60, baseline = 10;
          List<double> range = [40, 80], rangeBaseline = [10, 30];
          double? savedScalar;
          List<double>? savedRange;
          final scalarProposals = <double>[];
          final rangeProposals = <List<double>>[];
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return Form(
                      key: form,
                      child: Column(
                        children: [
                          DSliderField(
                            initialValue: baseline,
                            value: controlled ? scalar : null,
                            validator: (v) => v! < 20 ? 'Low scalar' : null,
                            onSaved: (v) => savedScalar = v,
                            onChanged: (v) {
                              scalarProposals.add(v);
                              form.currentState!.save();
                              if (controlled) expect(savedScalar, scalar);
                              if (accept) setState(() => scalar = v);
                            },
                          ),
                          DMultiSliderField(
                            initialValue: rangeBaseline,
                            values: controlled ? range : null,
                            validator: (v) =>
                                v!.first < 20 ? 'Low range' : null,
                            onSaved: (v) => savedRange = v,
                            onChanged: (v) {
                              rangeProposals.add(v);
                              form.currentState!.save();
                              if (controlled) expect(savedRange, range);
                              if (accept) setState(() => range = v);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          update(() {
            baseline = 25;
            rangeBaseline = [25, 50];
            scalar = 70;
            range = [50, 90];
          });
          await tester.pump();
          form.currentState!.reset();
          expect(scalarProposals, [10]);
          expect(rangeProposals, [
            [10, 30],
          ]);
          form.currentState!.save();
          // Until the parent frame, controlled values remain authoritative.
          expect(savedScalar, controlled ? 70 : 10);
          expect(savedRange, controlled ? [50, 90] : [10, 30]);
          await tester.pump();
          form.currentState!.save();
          expect(savedScalar, controlled && !accept ? 70 : 10);
          expect(savedRange, controlled && !accept ? [50, 90] : [10, 30]);
          expect(form.currentState!.validate(), controlled && !accept);
          await tester.pump();
          expect(
            find.text('Low scalar'),
            controlled && !accept ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('Low range'),
            controlled && !accept ? findsNothing : findsOneWidget,
          );
        },
      );
    }
  }
}
