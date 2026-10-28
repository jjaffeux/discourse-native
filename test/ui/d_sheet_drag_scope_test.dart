import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _headerKey = ValueKey('stationary-header');
final _header = find.byKey(_headerKey);
final _sheet = find.byType(DSheetContent);

Future<_DragFrameState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<_DragFrameState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: _DragFrame(key: key),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

void main() {
  testWidgets(
    'stationary header retains its controls and drives page dismissal',
    (tester) async {
      final state = await _pump(tester);
      final button = find.widgetWithText(DButton, 'Header action');
      final element = tester.element(button);
      await tester.tap(button);
      expect(state.taps, 1);
      final header = tester.getRect(_header);
      final page = tester.getRect(_sheet);
      final drag = await tester.startGesture(header.center);
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 70));
      await tester.pump();
      expect(tester.getRect(_sheet).top, greaterThan(page.top));
      expect(tester.getRect(_header), header);
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(_sheet), page);
      expect(state.closed, isEmpty);
      await tester.drag(_header, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(state.closed, [1]);
      expect(_sheet, findsNothing);
      expect(tester.element(button), same(element));
      await tester.tap(button);
      expect(state.taps, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden pages are inert and a gesture cannot transfer to a new page',
    (tester) async {
      final state = await _pump(tester);
      state.show(1, visible: false);
      await tester.pumpAndSettle();
      await tester.drag(_header, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(state.closed, isEmpty);
      state.show(1);
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(tester.getCenter(_header));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 70));
      await tester.pump();
      state.show(2);
      await tester.pumpAndSettle();
      final nextPage = tester.getRect(_sheet);
      await drag.moveBy(const Offset(0, 200));
      await drag.up();
      await tester.pumpAndSettle();
      expect(state.closed, isEmpty);
      expect(tester.getRect(_sheet), nextPage);
      await tester.drag(_header, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(state.closed, [2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing a page during an external drag leaves no stale callback',
    (tester) async {
      final state = await _pump(tester);
      final drag = await tester.startGesture(tester.getCenter(_header));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 70));
      await tester.pump();
      state.show(null);
      await tester.pumpAndSettle();
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(state.closed, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _DragFrame extends StatefulWidget {
  const _DragFrame({super.key});

  @override
  State<_DragFrame> createState() => _DragFrameState();
}

class _DragFrameState extends State<_DragFrame> {
  int? page = 1;
  bool visible = true;
  int taps = 0;
  final closed = <int>[];

  void show(int? value, {bool visible = true}) => setState(() {
    page = value;
    this.visible = visible;
  });

  @override
  Widget build(BuildContext context) {
    final id = page;
    return DSheetDragScope(
      child: Column(
        children: [
          DSheetDragRegion(
            key: _headerKey,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  DButton(
                    label: const Text('Header action'),
                    onPressed: () => taps++,
                  ),
                  const Expanded(child: Text('Drag the header')),
                ],
              ),
            ),
          ),
          Expanded(
            child: id == null
                ? const SizedBox()
                : Offstage(
                    offstage: !visible,
                    child: TickerMode(
                      enabled: visible,
                      child: DSheetViewport(
                        key: ValueKey(id),
                        onDismiss: () {
                          if (page != id) return;
                          closed.add(id);
                          show(null);
                        },
                        content: DSheetContent(
                          side: DSheetSide.bottom,
                          variant: DSheetVariant.page,
                          showCloseButton: false,
                          children: [Expanded(child: Text('Page $id'))],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
