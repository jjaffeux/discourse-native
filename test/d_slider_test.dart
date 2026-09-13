import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: direction,
            child: Center(
              child: SizedBox(
                width: 212,
                height: 160,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      );

  for (final orientation in Axis.values) {
    for (final direction in TextDirection.values) {
      testWidgets('active track reaches its origin: $orientation $direction', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            DSlider(
              value: 66,
              min: 1,
              max: 85,
              orientation: orientation,
              onChanged: (_) {},
            ),
            direction: direction,
          ),
        );
        final track = find
            .descendant(
              of: find.byType(DMultiSlider),
              matching: find.byWidgetPredicate(
                (widget) => widget is CustomPaint && widget.painter != null,
              ),
            )
            .first;
        final size = tester.getSize(track);
        final recorder = ui.PictureRecorder();
        tester
            .widget<CustomPaint>(track)
            .painter!
            .paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(
          size.width.ceil(),
          size.height.ceil(),
        );
        final bytes = (await tester.runAsync(() => image.toByteData()))!;
        final vertical = orientation == Axis.vertical;
        final reversed = vertical || direction == TextDirection.rtl;
        final extent = vertical ? size.height : size.width;
        final origin = reversed ? extent.toInt() - 3 : 2;
        final x = vertical ? 23 : origin;
        final y = vertical ? origin : 23;
        final offset = (y * image.width + x) * 4;
        final color = Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        expect(color, DTokens.of(tester.element(track)).primary);
        image.dispose();
        picture.dispose();
      });
    }
  }

  testWidgets('track jumps, captures drags outside bounds and commits once', (
    tester,
  ) async {
    var value = 20.0;
    final starts = <double>[], ends = <double>[];
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => DSlider(
            value: value,
            onChanged: (v) => setState(() => value = v),
            onChangeStart: starts.add,
            onChangeEnd: ends.add,
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(DSlider));
    await tester.tapAt(Offset(rect.left + 156, rect.center.dy));
    await tester.pump();
    expect(value, 75);
    expect(starts, [20]);
    expect(ends, [75]);
    await tester.dragFrom(
      Offset(rect.left + 156, rect.center.dy),
      const Offset(300, 0),
    );
    await tester.pump();
    expect(value, 100);
    expect(ends.last, 100);
  });

  testWidgets(
    'keyboard steps, page keys, shift, endpoints and RTL preserve borrowed focus',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var value = 30.0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DSlider(
              value: value,
              step: 5,
              focusNode: node,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
          direction: TextDirection.rtl,
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(value, 35);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(value, 45);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(value, 35);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(value, 100);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(value, 0);
      await tester.pumpWidget(const SizedBox());
      expect(() => node.addListener(() {}), returnsNormally);
    },
  );

  testWidgets(
    'overlapping thumbs separate in drag direction and retain ordered keyboard bounds',
    (tester) async {
      var values = <double>[50, 50, 50];
      final nodes = List.generate(3, (_) => FocusNode());
      for (final node in nodes) {
        addTearDown(node.dispose);
      }
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DMultiSlider(
              values: values,
              focusNodes: nodes,
              onChanged: (v) => setState(() => values = v),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(DMultiSlider));
      await tester.dragFrom(rect.center, const Offset(80, 0));
      await tester.pump();
      expect(values[0], 50);
      expect(values[1], 50);
      expect(values[2], greaterThan(50));
      nodes[1].requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(values[1], 50);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(values[1], values[2]);
    },
  );

  testWidgets(
    'vertical track starts at bottom and semantic actions change the named thumb',
    (tester) async {
      final semantics = tester.ensureSemantics();

      var values = <double>[20, 80];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              height: 160,
              child: DMultiSlider(
                values: values,
                orientation: Axis.vertical,
                semanticLabels: const ['Lower', 'Upper'],
                minStepsBetweenValues: 5,
                onChanged: (v) => setState(() => values = v),
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(DMultiSlider));
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 6));
      await tester.pump();
      expect(values.first, 0);
      final node = tester.getSemantics(find.bySemanticsLabel('Upper'));
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(values.last, 81);
      expect(node.getSemanticsData().flagsCollection.isSlider, isTrue);
      semantics.dispose();
    },
  );

  testWidgets(
    'disabled input withdraws focus and semantic actions, while live values update',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final node = FocusNode();
      addTearDown(node.dispose);
      var enabled = true, value = 20.0;
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DSlider(
                value: value,
                focusNode: node,
                semanticLabel: 'Volume',
                onChanged: enabled ? (v) => setState(() => value = v) : null,
              );
            },
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      update(() {
        enabled = false;
        value = 70;
      });
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.tap(find.byType(DSlider));
      await tester.pump();
      expect(value, 70);
      final data = tester
          .getSemantics(find.bySemanticsLabel('Volume'))
          .getSemanticsData();
      expect(data.value, '70.0');
      expect(data.hasAction(SemanticsAction.increase), isFalse);
      expect(node.hasFocus, isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'cancel releases preview without committing and removal during change is safe',
    (tester) async {
      var value = 10.0, cancelled = 0, committed = 0;
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return visible
                  ? DSlider(
                      value: value,
                      onChanged: (v) => setState(() => value = v),
                      onChangeCancel: () => cancelled++,
                      onChangeEnd: (_) => committed++,
                    )
                  : const SizedBox();
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DSlider)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      expect(cancelled, 1);
      expect(committed, 0);
      final next = await tester.startGesture(
        tester.getCenter(find.byType(DSlider)),
      );
      await next.moveBy(const Offset(20, 0));
      update(() => visible = false);
      await tester.pump();
      await next.up();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('form validates, saves, resets and accepts external updates', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    double? saved, external;
    late StateSetter update;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Form(
              key: form,
              child: DSliderField(
                initialValue: 10,
                value: external,
                validator: (v) => v! < 20 ? 'Too low' : null,
                onSaved: (v) => saved = v,
              ),
            );
          },
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Too low'), findsOneWidget);
    await tester.tap(find.byType(DSlider));
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.save();
    expect(saved, 50);
    form.currentState!.reset();
    await tester.pump();
    expect(tester.widget<DSlider>(find.byType(DSlider)).value, 10);
    update(() => external = 80);
    await tester.pump();
    expect(tester.widget<DSlider>(find.byType(DSlider)).value, 80);
  });

  testWidgets(
    'small widths and large text preserve thumb geometry under live themes',
    (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: const MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(3),
                disableAnimations: true,
              ),
              child: Center(
                child: SizedBox(
                  width: 32,
                  child: DSlider(value: 50, onChanged: null),
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byType(DSlider)), const Size(32, 48));
        final thumb = find.byWidgetPredicate(
          (w) => w is AnimatedContainer && w.constraints?.maxWidth == 12,
        );
        expect(tester.getSize(thumb), const Size(12, 12));
        expect(tester.takeException(), isNull);
      }
    },
  );

  test(
    'invalid bounds, unordered values and impossible spacing are rejected',
    () {
      for (final values in [
        <double>[],
        [double.nan],
        [101.0],
        [80.0, 20.0],
      ]) {
        expect(
          () => DMultiSlider(values: values, onChanged: (_) {}),
          throwsArgumentError,
        );
      }
      expect(
        () => DMultiSlider(
          values: const [20, 21],
          minStepsBetweenValues: 2,
          onChanged: (_) {},
        ),
        throwsArgumentError,
      );
      expect(
        () => DMultiSlider(values: const [20], step: 0, onChanged: (_) {}),
        throwsArgumentError,
      );
    },
  );
}
