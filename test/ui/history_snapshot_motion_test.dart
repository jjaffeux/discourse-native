import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<double>> _strokeContrasts(WidgetTester tester) async {
  final underlay = tester
      .widget<DSheetViewport>(find.byType(DSheetViewport))
      .underlay!;
  final box = tester.renderObject<RenderBox>(find.byWidget(underlay));
  final centers = [
    for (var line = 0; line < 12; line++)
      box.localToGlobal(Offset(100, 60 + line * 6 + line / 12)) * 3,
  ];
  return (await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(900, 600);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final contrasts = <double>[];
    for (final center in centers) {
      final y = center.dy.round();
      final x = center.dx.round();
      final background = bytes.getUint8((y * 900 + 30) * 4);
      var darkest = background;
      for (var row = y - 3; row <= y + 3; row++) {
        darkest = math.min(darkest, bytes.getUint8((row * 900 + x) * 4));
      }
      contrasts.add(255 * (background - darkest) / background);
    }
    image.dispose();
    scene.dispose();
    return contrasts;
  }))!;
}

void main() {
  testWidgets(
    'thin history-preview strokes keep their contrast during a pull',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey<_HistoryHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: _HistoryHarness(key: key),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.open();
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 200));
      final frames = <List<double>>[];
      for (var frame = 0; frame < 32; frame++) {
        await drag.moveBy(const Offset(0, 4));
        await tester.pump(const Duration(milliseconds: 8));
        frames.add(await _strokeContrasts(tester));
      }
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(frames.expand((frame) => frame), everyElement(greaterThan(128)));
      final ranges = [
        for (var line = 0; line < 12; line++)
          frames.map((frame) => frame[line]).reduce(math.max) -
              frames.map((frame) => frame[line]).reduce(math.min),
      ];
      final meanRange = ranges.reduce((a, b) => a + b) / ranges.length;
      debugPrint(
        'HISTORY_STROKE_CONTRAST frames=${frames.length} '
        'meanRange=${meanRange.toStringAsFixed(2)}',
      );
      expect(
        meanRange,
        lessThan(4),
        reason: 'Thin control details must not pulse as the preview scales.',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _HistoryHarness extends StatefulWidget {
  const _HistoryHarness({super.key});
  @override
  State<_HistoryHarness> createState() => _HistoryHarnessState();
}

class _HistoryHarnessState extends State<_HistoryHarness> {
  var entry = 0;
  void open() => setState(() => entry = 1);

  @override
  Widget build(BuildContext context) => DHistoryTransition(
    history: 'history',
    entry: entry,
    previousEntry: entry == 0 ? null : 0,
    child: Builder(
      builder: (context) => entry == 0
          ? CustomPaint(
              painter: _ControlStrokes(),
              child: const SizedBox.expand(),
            )
          : DSheetViewport(
              onDismiss: () => setState(() => entry = 0),
              underlay: DHistoryTransition.previousPageUnderlayOf(context),
              content: const DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.page,
                showCloseButton: false,
                children: [Expanded(child: SizedBox.expand())],
              ),
            ),
    ),
  );
}

class _ControlStrokes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;
    for (var line = 0; line < 12; line++) {
      final y = 60 + line * 6 + line / 12;
      canvas.drawLine(Offset(20, y), Offset(180, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ControlStrokes oldDelegate) => false;
}
