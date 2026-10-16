import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  TextScaler scaler = TextScaler.noScaling,
  TargetPlatform platform = TargetPlatform.macOS,
}) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: platform),
  home: MediaQuery(
    data: MediaQueryData(size: const Size(800, 600), textScaler: scaler),
    child: Scaffold(body: child),
  ),
);

void main() {
  for (final count in [1000, 5000]) {
    testWidgets('bounds line work through a $count-line document', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final lines = List.generate(count, (index) => 'source line $index');
      final requested = <int>{};
      var requests = 0;
      await tester.pumpWidget(
        _host(
          DScrollArea(
            controller: scroll,
            child: RepaintBoundary(
              child: DCodeViewer(
                source: lines.join('\n'),
                lineSpanBuilder: (index) {
                  requested.add(index);
                  requests++;
                  return TextSpan(text: lines[index]);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested, contains(0));
      expect(requested.length, lessThan(60));
      expect(requests, lessThan(60));
      debugPrint(
        'DCodeViewer sourceLines=$count initialLineSpanRequests=$requests',
      );
      expect(requested, isNot(contains(count - 1)));
      expect(scroll.position.maxScrollExtent, greaterThan(count * 15));

      requested.clear();
      requests = 0;
      scroll.jumpTo(scroll.position.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      expect(requested.any((index) => index > count ~/ 3), isTrue);
      expect(requested.length, lessThan(60));
      expect(requests, lessThan(60));

      requested.clear();
      requests = 0;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(requested, contains(count - 1));
      expect(requested.length, lessThan(60));
      expect(requests, lessThan(60));

      requested.clear();
      requests = 0;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(requested, contains(0));
      expect(requested.length, lessThan(60));
      expect(requests, lessThan(60));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('outer select all includes unseen source and excludes gutters', (
    tester,
  ) async {
    final lines = List.generate(5000, (index) => '  source line $index');
    lines[1] = '';
    lines[2] = '  👩🏽‍💻 e\u0301 中文';
    final source = lines.join('\n');
    final requested = <int>{};
    String? selected;
    await tester.pumpWidget(
      _host(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: DScrollArea(
            child: Column(
              children: [
                const Text('prose before'),
                DCodeViewer(
                  source: source,
                  lineNumbers: List.generate(5000, (index) => index + 98765),
                  highlightedLines: const {2, 4999},
                  lineSpanBuilder: (index) {
                    requested.add(index);
                    return TextSpan(text: lines[index]);
                  },
                ),
                const Text('prose after'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea))
        .selectableRegion
        .selectAll(SelectionChangedCause.toolbar);
    await tester.pumpAndSettle();
    expect(selected, contains('prose before'));
    expect(selected, contains(source));
    expect(selected, contains('prose after'));
    expect(selected, isNot(contains('98765')));
    expect(requested.length, lessThan(65));
    expect(tester.takeException(), isNull);
  });

  testWidgets('outer scrolling reveals rows inside a retained inner viewport', (
    tester,
  ) async {
    final outer = ScrollController();
    addTearDown(outer.dispose);
    final lines = List.generate(1000, (index) => 'source $index');
    final requested = <int>{};
    await tester.pumpWidget(
      _host(
        DScrollArea(
          controller: outer,
          child: Column(
            children: [
              const SizedBox(height: 500),
              RepaintBoundary(
                child: SizedBox(
                  height: 280,
                  child: DScrollArea(
                    child: DCodeViewer(
                      source: lines.join('\n'),
                      lineSpanBuilder: (index) {
                        requested.add(index);
                        return TextSpan(text: lines[index]);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 500),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requested, isNot(contains(10)));
    outer.jumpTo(300);
    await tester.pumpAndSettle();
    expect(requested, contains(10));
    expect(requested.length, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pane resizing paints rows in a retained viewer', (tester) async {
    final height = ValueNotifier<double>(100);
    addTearDown(height.dispose);
    final lines = List.generate(1000, (index) => 'line $index');
    final requested = <int>{};
    final retained = RepaintBoundary(
      child: DScrollArea(
        child: DCodeViewer(
          source: lines.join('\n'),
          lineSpanBuilder: (index) {
            requested.add(index);
            return TextSpan(text: lines[index]);
          },
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: height,
            child: retained,
            builder: (context, value, child) =>
                SizedBox(width: 500, height: value, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requested, isNot(contains(12)));
    height.value = 350;
    await tester.pumpAndSettle();
    expect(requested, contains(12));
    expect(requested.length, lessThan(30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hard breaks retain every row and exact source offsets', (
    tester,
  ) async {
    const source =
        'alpha\r\nbeta\vcharlie\fdelta\u2028echo\u2029foxtrot\rsuffix\u0085tail';
    const lines = [
      'alpha',
      'beta',
      'charlie',
      'delta',
      'echo',
      'foxtrot\rsuffix\u0085tail',
    ];
    final requested = <int>{};
    await tester.pumpWidget(
      _host(
        SelectionArea(
          child: DScrollArea(
            child: DCodeViewer(
              source: source,
              lineNumbers: const [90, 91, 92, 93, 94, 95],
              lineSpanBuilder: (index) {
                requested.add(index);
                return TextSpan(text: lines[index]);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      requested,
      containsAll(List.generate(lines.length, (index) => index)),
    );
    final selectable = tester.allRenderObjects.whereType<Selectable>().single;
    selectable.dispatchSelectionEvent(const SelectAllSelectionEvent());
    expect(selectable.getSelectedContent()!.plainText, source);
    selectable.dispatchSelectionEvent(const ClearSelectionEvent());
    final top = tester.getTopLeft(find.byType(DCodeViewer));
    selectable.dispatchSelectionEvent(
      SelectWordSelectionEvent(globalPosition: top + const Offset(55, 98)),
    );
    expect(selectable.getSelectedContent()!.plainText, 'echo');
    expect(selectable.getSelection()!.startOffset, source.indexOf('echo'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide unseen tail becomes horizontally reachable', (
    tester,
  ) async {
    final vertical = ScrollController();
    final horizontal = ScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    final lines = List.generate(1000, (index) => 'line $index');
    lines.last = '${'w' * 400}尾';
    await tester.pumpWidget(
      _host(
        DScrollArea(
          controller: vertical,
          child: DCodeViewer(
            source: lines.join('\n'),
            horizontalController: horizontal,
          ),
        ),
        scaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();
    expect(horizontal.position.maxScrollExtent, 0);
    vertical.jumpTo(vertical.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(horizontal.position.maxScrollExtent, greaterThan(1000));
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(horizontal.offset, horizontal.position.maxScrollExtent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse selection spans rows that leave the viewport', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final lines = List.generate(1000, (index) => 'row $index');
    String? selected;
    await tester.pumpWidget(
      _host(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: DScrollArea(
            controller: scroll,
            child: DCodeViewer(source: lines.join('\n')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(
      tester.getTopLeft(find.byType(DCodeViewer)) + const Offset(9, 14),
    );
    await mouse.moveBy(const Offset(80, 0));
    await tester.pump();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await mouse.moveTo(
      tester.getBottomLeft(find.byType(DCodeViewer)) + const Offset(500, -24),
    );
    await mouse.up();
    await tester.pumpAndSettle();
    expect(selected, startsWith('row 0\n'));
    expect(selected, contains('row 500\n'));
    expect(selected, endsWith('row 999'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  });

  testWidgets('styling refresh keeps a learned width and horizontal position', (
    tester,
  ) async {
    final vertical = ScrollController();
    final horizontal = ScrollController();
    final color = ValueNotifier(Colors.red);
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    addTearDown(color.dispose);
    final lines = List.generate(1000, (index) => 'line $index');
    lines.first = 'w' * 400;
    final source = lines.join('\n');
    var requests = 0;
    InlineSpan span(int index) {
      requests++;
      return TextSpan(
        text: lines[index],
        style: TextStyle(color: color.value),
      );
    }

    await tester.pumpWidget(
      _host(
        DScrollArea(
          controller: vertical,
          child: ValueListenableBuilder<Color>(
            valueListenable: color,
            builder: (context, value, child) => DCodeViewer(
              source: source,
              horizontalController: horizontal,
              lineSpanBuilder: span,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    horizontal.jumpTo(1000);
    vertical.jumpTo(vertical.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    requests = 0;
    color.value = Colors.blue;
    await tester.pumpAndSettle();
    expect(requests, greaterThan(0));
    expect(requests, lessThan(60));
    expect(horizontal.offset, 1000);
    expect(horizontal.position.maxScrollExtent, greaterThan(1000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('code scrolling remains left to right in an RTL interface', (
    tester,
  ) async {
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      _host(
        Directionality(
          textDirection: TextDirection.rtl,
          child: DScrollArea(
            child: DCodeViewer(
              source: 'w' * 400,
              horizontalController: horizontal,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(horizontal.position.axisDirection, AxisDirection.right);
    expect(horizontal.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard selection keeps grapheme and document boundaries', (
    tester,
  ) async {
    const source = 'a👩🏽‍💻e\u0301\nlast';
    await tester.pumpWidget(
      _host(
        const SelectionArea(
          child: DScrollArea(child: DCodeViewer(source: source)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selectable = tester.allRenderObjects.whereType<Selectable>().single;
    selectable.dispatchSelectionEvent(const SelectAllSelectionEvent());
    selectable.dispatchSelectionEvent(
      const GranularlyExtendSelectionEvent(
        forward: false,
        isEnd: true,
        granularity: TextGranularity.document,
      ),
    );
    expect(selectable.getSelection()!.endOffset, 0);
    for (final expected in [
      'a',
      'a👩🏽‍💻',
      'a👩🏽‍💻e\u0301',
      'a👩🏽‍💻e\u0301\n',
    ]) {
      selectable.dispatchSelectionEvent(
        const GranularlyExtendSelectionEvent(
          forward: true,
          isEnd: true,
          granularity: TextGranularity.character,
        ),
      );
      expect(selectable.getSelectedContent()!.plainText, expected);
    }
    selectable.dispatchSelectionEvent(const ClearSelectionEvent());
    expect(selectable.getSelectedContent(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch selection anchors handles and drops offscreen leaders', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    String? selected;
    final source = [
      'alpha beta',
      ...List.generate(1000, (index) => 'row $index'),
    ].join('\n');
    await tester.pumpWidget(
      _host(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: DScrollArea(
            controller: scroll,
            child: DCodeViewer(source: source),
          ),
        ),
        platform: TargetPlatform.iOS,
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPressAt(
      tester.getTopLeft(find.byType(DCodeViewer)) + const Offset(25, 14),
    );
    await tester.pumpAndSettle();
    expect(selected, 'alpha');
    final leaders = tester.layers.whereType<LeaderLayer>().length;
    expect(leaders, greaterThanOrEqualTo(2));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.layers.whereType<LeaderLayer>().length, lessThan(leaders));
    expect(selected, 'alpha');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  });

  for (final granularity in [TextGranularity.word, TextGranularity.paragraph]) {
    for (final isEnd in [true, false]) {
      testWidgets(
        '$granularity drag retains its opposite edge after scroll replay ($isEnd)',
        (tester) async {
          await tester.pumpWidget(
            _host(
              const SelectionArea(
                child: DScrollArea(
                  child: DCodeViewer(
                    source: 'alpha beta\nsecond third\nlast word',
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final selectable = tester.allRenderObjects
              .whereType<Selectable>()
              .single;
          final top = tester.getTopLeft(find.byType(DCodeViewer));
          final origin = top + const Offset(25, 35);
          final target = top + Offset(25, isEnd ? 56 : 14);
          if (granularity == TextGranularity.word) {
            selectable.dispatchSelectionEvent(
              SelectWordSelectionEvent(globalPosition: origin),
            );
          } else {
            selectable.dispatchSelectionEvent(
              SelectParagraphSelectionEvent(globalPosition: origin),
            );
          }
          SelectionEdgeUpdateEvent update(
            Offset position,
            bool end,
            TextGranularity value,
          ) => end
              ? SelectionEdgeUpdateEvent.forEnd(
                  globalPosition: position,
                  granularity: value,
                )
              : SelectionEdgeUpdateEvent.forStart(
                  globalPosition: position,
                  granularity: value,
                );
          selectable.dispatchSelectionEvent(update(target, isEnd, granularity));
          final extended = selectable.getSelectedContent()!.plainText;
          expect(extended, contains('second'));
          expect(extended, contains(isEnd ? 'last' : 'alpha'));
          final opposite = isEnd
              ? selectable.value.startSelectionPoint!
              : selectable.value.endSelectionPoint!;
          final stationary = (selectable as RenderBox).localToGlobal(
            opposite.localPosition - Offset(0, opposite.lineHeight / 2),
          );
          selectable.dispatchSelectionEvent(
            update(stationary, !isEnd, TextGranularity.character),
          );
          selectable.dispatchSelectionEvent(update(target, isEnd, granularity));
          expect(selectable.getSelectedContent()!.plainText, extended);
          selectable.dispatchSelectionEvent(
            update(stationary, !isEnd, granularity),
          );
          expect(selectable.getSelectedContent()!.plainText, extended);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'selection crosses code and prose boundaries in both directions',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final source = List.generate(1000, (index) => 'row $index').join('\n');
      String? selected;
      await tester.pumpWidget(
        _host(
          SelectionArea(
            onSelectionChanged: (content) => selected = content?.plainText,
            child: DScrollArea(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('prose before'),
                  DCodeViewer(source: source),
                  const Text('prose after'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(
        tester.getTopLeft(find.text('prose before')) + const Offset(1, 8),
      );
      await mouse.moveBy(const Offset(60, 0));
      await tester.pump();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getTopRight(find.text('prose after')) + const Offset(1, 8),
      );
      await mouse.up();
      await tester.pumpAndSettle();
      expect(selected, contains(source));
      expect(selected, startsWith('prose before'));
      expect(selected, endsWith('prose after'));

      await mouse.down(
        tester.getTopRight(find.text('prose after')) + const Offset(-1, 8),
      );
      await mouse.moveBy(const Offset(-60, 0));
      await tester.pump();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getTopLeft(find.text('prose before')) + const Offset(1, 8),
      );
      await mouse.up();
      await tester.pumpAndSettle();
      expect(selected, contains(source));
      expect(selected, startsWith('prose before'));
      expect(selected, endsWith('prose after'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('word and paragraph selection use source coordinates', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SelectionArea(
          child: DScrollArea(child: DCodeViewer(source: 'alpha beta\nsecond')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selectable = tester.allRenderObjects.whereType<Selectable>().single;
    final position =
        tester.getTopLeft(find.byType(DCodeViewer)) + const Offset(25, 14);
    selectable.dispatchSelectionEvent(
      SelectWordSelectionEvent(globalPosition: position),
    );
    expect(selectable.getSelectedContent()!.plainText, 'alpha');
    selectable.dispatchSelectionEvent(
      SelectParagraphSelectionEvent(globalPosition: position),
    );
    expect(selectable.getSelectedContent()!.plainText, 'alpha beta\n');
    selectable.dispatchSelectionEvent(
      SelectWordSelectionEvent(globalPosition: position),
    );
    expect(selectable.getSelectedContent()!.plainText, 'alpha beta\n');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'same-source styling preserves selection and replacement clears it',
    (tester) async {
      Future<void> pump(String source, Color color, TextScaler scaler) =>
          tester.pumpWidget(
            _host(
              SelectionArea(
                child: DScrollArea(
                  child: DCodeViewer(
                    source: source,
                    lineSpanBuilder: (index) => TextSpan(
                      text: source.split('\n')[index],
                      style: TextStyle(color: color),
                    ),
                  ),
                ),
              ),
              scaler: scaler,
            ),
          );
      await pump('first\nlast', Colors.red, TextScaler.noScaling);
      await tester.pumpAndSettle();
      final selectable = tester.allRenderObjects.whereType<Selectable>().single;
      selectable.dispatchSelectionEvent(const SelectAllSelectionEvent());
      await pump('first\nlast', Colors.blue, const TextScaler.linear(2));
      await tester.pumpAndSettle();
      expect(selectable.getSelectedContent()!.plainText, 'first\nlast');
      await pump('replacement', Colors.blue, const TextScaler.linear(2));
      await tester.pumpAndSettle();
      expect(selectable.getSelectedContent(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('semantics retains the complete read-only source', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final horizontal = ScrollController();
      addTearDown(horizontal.dispose);
      final lines = List.generate(1000, (index) => 'source $index');
      lines.last = '${'w' * 400}source 999';
      final source = lines.join('\n');
      await tester.pumpWidget(
        _host(
          DScrollArea(
            controller: scroll,
            child: DCodeViewer(
              source: source,
              horizontalController: horizontal,
              semanticLabel: 'Post code',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.bySemanticsLabel('Post code'));
      expect(node.getSemanticsData().value, source);
      node.owner!.performAction(node.id, SemanticsAction.setSelection, {
        'base': source.lastIndexOf('source 999'),
        'extent': source.length,
      });
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(10000));
      expect(horizontal.offset, greaterThan(1000));
      expect(
        tester.allRenderObjects
            .whereType<Selectable>()
            .single
            .getSelectedContent()!
            .plainText,
        'source 999',
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
