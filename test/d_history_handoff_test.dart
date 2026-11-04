import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _handoff = ValueKey('history-page-handoff');
const _capture = ValueKey('handoff-capture');

Future<_HarnessState> _pump(WidgetTester tester, {bool reduced = false}) async {
  await tester.binding.setSurfaceSize(const Size(400, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: _Harness(key: key),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final state = key.currentState!;
  state.visit(1);
  await tester.pumpAndSettle();
  state.visit(0);
  await tester.pumpAndSettle();
  state.beginRestore();
  await tester.pump();
  final gesture = await tester.startGesture(const Offset(395, 250));
  await gesture.moveBy(
    const Offset(-180, 0),
    timeStamp: const Duration(milliseconds: 200),
  );
  await tester.pump();
  await gesture.up();
  for (var frame = 0; frame < 30 && state.entry == 0; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(state.entry, 1);
  await tester.pump();
  expect(tester.widget<Opacity>(find.byKey(_handoff)).opacity, 1);
  return state;
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'swipe image covers loading until all pages are ready (reduced: $reduced)',
      (tester) async {
        final state = await _pump(tester, reduced: reduced);
        final liveStates = tester
            .stateList<_ReadyPageState>(find.byType(_ReadyPage))
            .toList();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<Opacity>(find.byKey(_handoff)).opacity, 1);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_capture),
        );
        final image = boundary.toImageSync(pixelRatio: 1);
        final pixels = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        for (final y in [200, 590]) {
          final offset = (y * image.width + 20) * 4;
          expect(
            List.generate(3, (channel) => pixels!.getUint8(offset + channel)),
            [0, 0, 255],
            reason:
                'the blue cached page must cover the red loading page at y=$y',
          );
        }
        image.dispose();
        expect(
          find.widgetWithText(DButton, 'Page 1').hitTestable(),
          findsNothing,
        );
        state.finish(0);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<Opacity>(find.byKey(_handoff)).opacity, 1);
        state.finish(1);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        if (!reduced) {
          expect(
            tester.widget<Opacity>(find.byKey(_handoff)).opacity,
            inExclusiveRange(0, 1),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byKey(_handoff), findsNothing);
        expect(
          tester.stateList<_ReadyPageState>(find.byType(_ReadyPage)),
          orderedEquals(liveStates),
        );
        expect(
          find.widgetWithText(DButton, 'Page 1').hitTestable(),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in [
    'owner',
    'navigation',
    'back swipe',
    'lifecycle',
    'memory pressure',
  ]) {
    testWidgets(
      '$change cancels a pending handoff and makes its releases inert',
      (tester) async {
        final state = await _pump(tester);
        final retainedImage = tester
            .widget<RawImage>(
              find.descendant(
                of: find.byKey(_handoff),
                matching: find.byType(RawImage),
              ),
            )
            .image!
            .clone();
        addTearDown(retainedImage.dispose);
        final releases = tester
            .stateList<_ReadyPageState>(find.byType(_ReadyPage))
            .map((page) => page.release!)
            .toList();
        switch (change) {
          case 'owner':
            state.changeOwner();
          case 'navigation':
            state.visit(0);
          case 'back swipe':
            final gesture = await tester.startGesture(const Offset(5, 250));
            await gesture.moveBy(
              const Offset(180, 0),
              timeStamp: const Duration(milliseconds: 200),
            );
            await tester.pump();
            await gesture.up();
          case 'lifecycle':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          case 'memory pressure':
            tester.binding.handleMemoryPressure();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(_handoff), findsNothing);
        if (change == 'back swipe') expect(state.entry, 0);
        for (final release in releases) {
          release();
          release();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(_handoff), findsNothing);
        if (change == 'navigation') {
          final gesture = await tester.startGesture(const Offset(395, 250));
          await gesture.moveBy(
            const Offset(-180, 0),
            timeStamp: const Duration(milliseconds: 200),
          );
          await tester.pump();
          final preview = tester
              .widget<RawImage>(
                find.descendant(
                  of: find.byKey(const ValueKey('history-next-preview')),
                  matching: find.byType(RawImage),
                ),
              )
              .image!;
          expect(
            preview.isCloneOf(retainedImage),
            isTrue,
            reason:
                'leaving during restoration must not replace the cached page with loading content',
          );
          await gesture.cancel();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int entry = 0;
  Object owner = Object();
  final ready = {0, 1};
  void visit(int value) => setState(() => entry = value);
  void finish(int part) => setState(() => ready.add(part));
  void beginRestore() => setState(ready.clear);
  void changeOwner() => setState(() => owner = Object());
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _capture,
    child: DHistoryTransition(
      history: 'journey',
      frameBuilder: (context, page) => Column(
        children: [
          SizedBox(height: entry == 1 ? 8 : 60),
          Expanded(child: page),
        ],
      ),
      entry: entry,
      tabOwner: owner,
      previousEntry: entry == 1 ? 0 : null,
      nextEntry: entry == 0 ? 1 : null,
      onBack: () => visit(0),
      onForward: () => visit(1),
      child: Column(
        children: [
          for (var part = 0; part < 2; part++)
            Expanded(
              child: _ReadyPage(
                key: ValueKey((entry, part)),
                ready: entry == 0 || ready.contains(part),
                entry: entry,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ReadyPage extends StatefulWidget {
  const _ReadyPage({super.key, required this.ready, required this.entry});
  final bool ready;
  final int entry;
  @override
  State<_ReadyPage> createState() => _ReadyPageState();
}

class _ReadyPageState extends State<_ReadyPage> {
  VoidCallback? release;
  @override
  Widget build(BuildContext context) {
    if (widget.ready) {
      release?.call();
      release = null;
    } else {
      release ??= DHistoryTransition.deferPageRevealOf(context);
    }
    return ColoredBox(
      color: widget.ready ? const Color(0xFF0000FF) : const Color(0xFFFF0000),
      child: Center(
        child: DButton(label: Text('Page ${widget.entry}'), onPressed: () {}),
      ),
    );
  }

  @override
  void dispose() {
    release?.call();
    super.dispose();
  }
}
