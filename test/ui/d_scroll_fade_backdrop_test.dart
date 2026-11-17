import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _fill = Color(0xFFF4EFE6);
const _frame = ValueKey('fade-frame');

// The two orders of blending round differently in 8-bit channels.
const _rounding = 3;

Widget _page({
  required ScrollController controller,
  required Color? backdrop,
  required ValueNotifier<double> foot,
}) {
  final frame = GlobalKey();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RepaintBoundary(
      key: _frame,
      child: ColoredBox(
        color: _fill,
        child: DScrollFootScope(
          foot: DScrollFoot(
            extent: foot,
            ground: () =>
                frame.currentContext?.findRenderObject() as RenderBox?,
          ),
          child: SizedBox.expand(
            key: frame,
            child: DScrollFadeScope(
              topInset: () => 24,
              backdrop: backdrop,
              child: ScrollConfiguration(
                behavior: const DScrollBehavior(),
                child: ListView(
                  controller: controller,
                  children: [
                    for (var i = 0; i < 60; i++)
                      Container(
                        height: 48,
                        color: i.isEven
                            ? const Color(0xFFB0302A)
                            : const Color(0x663050C0),
                        alignment: Alignment.centerLeft,
                        child: Text('Row $i with some text'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frame),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

Future<Uint8List> _render(
  WidgetTester tester, {
  required Color? backdrop,
  required double foot,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  final footExtent = ValueNotifier(foot);
  addTearDown(footExtent.dispose);
  await tester.pumpWidget(
    _page(controller: controller, backdrop: backdrop, foot: footExtent),
  );
  controller.jumpTo(600);
  await tester.pumpAndSettle();
  return _pixels(tester);
}

int _largestDifference(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final difference = (a[i] - b[i]).abs();
    if (difference > largest) largest = difference;
  }
  return largest;
}

int _shaderMasks(WidgetTester tester) {
  var count = 0;
  void visit(Layer layer) {
    if (layer is ShaderMaskLayer) count++;
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  visit(tester.binding.renderViews.first.debugLayer!);
  return count;
}

void main() {
  for (final foot in [0.0, 80.0]) {
    testWidgets('an opaque backdrop draws the same edge fades without a mask'
        '${foot > 0 ? ' under a floating foot' : ''}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final masked = await _render(tester, backdrop: null, foot: foot);
      expect(_shaderMasks(tester), 1);
      final covered = await _render(tester, backdrop: _fill, foot: foot);
      expect(_shaderMasks(tester), 0);

      expect(_largestDifference(masked, covered), lessThanOrEqualTo(_rounding));
    });
  }

  testWidgets('a translucent backdrop keeps the mask', (tester) async {
    await _render(tester, backdrop: _fill.withValues(alpha: .9), foot: 0);
    expect(_shaderMasks(tester), 1);
  });
}
