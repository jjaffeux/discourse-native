import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final config = <String, DChartConfigEntry>{
  'desktop': DChartConfigEntry(
    label: 'Desktop',
    color: (c) => DTokens.of(c).primary,
  ),
  'mobile': DChartConfigEntry(
    label: 'Mobile',
    color: (c) => DTokens.of(c).colors.tertiary,
  ),
};
Widget chart({
  DChartController? controller,
  FocusNode? focusNode,
  List<int> data = const [186, 305, 73],
  ValueChanged<int?>? onChanged,
  bool tooltip = true,
}) => DBarChart<int>(
  data: data,
  controller: controller,
  focusNode: focusNode,
  series: [DChartSeries(key: 'desktop', value: (value) => value)],
  label: (value) => 'Month $value',
  semanticLabel: 'Visitors',
  grid: true,
  axis: true,
  tooltip: tooltip,
  onSelectionChanged: onChanged,
);

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double width = 360,
  double scale = 1,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme ?? AppTheme.light,
    themeAnimationDuration: Duration.zero,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: Directionality(
          textDirection: direction,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: DChartContainer(config: config, child: child),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('Escape dismisses chart inspection then reaches its parent', (
    tester,
  ) async {
    final focus = FocusNode();
    final selection = DChartController(0);
    addTearDown(focus.dispose);
    addTearDown(selection.dispose);
    var parentEscapes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                parentEscapes++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DChartContainer(
              config: const {'value': DChartConfigEntry(label: 'Value')},
              child: DBarChart<int>(
                data: const [1, 2],
                series: [DChartSeries(key: 'value', value: (value) => value)],
                label: (value) => '$value',
                semanticLabel: 'Example',
                focusNode: focus,
                controller: selection,
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(selection.value, isNull);
    expect(parentEscapes, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(parentEscapes, 1);
    selection.value = 99;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(parentEscapes, 2);
    expect(selection.value, 99); // Invalid borrowed state is not rewritten.
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Tab arrows endpoints Escape and semantics inspect the same data',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = DChartController();
      final changes = <int?>[];
      await pump(tester, chart(controller: controller, onChanged: changes.add));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.value, 0);
      expect(find.text('186'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Visitors')),
        matchesSemantics(
          label: 'Visitors',
          isFocused: true,
          isFocusable: true,
          hasFocusAction: true,
          value: 'Month 186: Desktop 186',
          increasedValue: 'Month 305: Desktop 305',
          decreasedValue: 'Month 186: Desktop 186',
          hint: 'Use left and right arrow keys to inspect values',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(find.text('73'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(DChartTooltipContent), findsNothing);
      expect(changes, [0, 2, 0, null]);
      await tester.pumpWidget(const SizedBox());
      controller.value = 1;
      controller.dispose();
      semantics.dispose();
    },
  );

  testWidgets('hover touch and RTL physical keys agree on category positions', (
    tester,
  ) async {
    final controller = DChartController();
    await pump(
      tester,
      chart(controller: controller),
      direction: TextDirection.rtl,
    );
    final bounds = tester.getRect(find.byType(DBarChart<int>));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(bounds.topRight + const Offset(-30, 40));
    await tester.pump();
    expect(controller.value, 0);
    await mouse.moveTo(const Offset(700, 500));
    await tester.pump();
    expect(controller.value, isNull);
    await tester.tapAt(bounds.topLeft + const Offset(30, 100));
    await tester.pump();
    expect(controller.value, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.value, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'borrowed resources survive replacement and invalid indexes hide content',
    (tester) async {
      final first = DChartController(1);
      final second = DChartController(0);
      final focus = FocusNode();
      await pump(tester, chart(controller: first, focusNode: focus));
      expect(find.text('305'), findsOneWidget);
      await pump(tester, chart(controller: second, focusNode: focus));
      first.value = 2;
      await tester.pump();
      expect(find.text('186'), findsOneWidget);
      second.value = 9;
      await tester.pump();
      expect(find.byType(DChartTooltipContent), findsNothing);
      await pump(
        tester,
        chart(controller: second, focusNode: focus, data: const []),
      );
      expect(find.text('No data'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      first.value = null;
      second.value = null;
      focus.requestFocus();
      first.dispose();
      second.dispose();
      focus.dispose();
    },
  );

  testWidgets(
    'custom payload keys hidden items icons and formatters resolve correctly',
    (tester) async {
      const items = [
        DChartItem(
          key: 'visitors',
          value: 1286,
          payload: {'browser': 'chrome'},
        ),
        DChartItem(key: 'visitors', value: 0, hidden: true),
      ];
      await pump(
        tester,
        DChartContainer(
          config: {
            'visitors': const DChartConfigEntry(label: 'Total Visitors'),
            'chrome': DChartConfigEntry(
              label: 'Chrome',
              icon: (_) => const Icon(Icons.public),
            ),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DChartTooltipContent(
                items: items,
                nameKey: 'browser',
                labelKey: 'visitors',
                indicator: DChartIndicator.line,
                valueFormatter: (v) => '$v people',
              ),
              const DChartLegendContent(items: items, nameKey: 'browser'),
            ],
          ),
        ),
      );
      expect(find.text('Total Visitors'), findsOneWidget);
      expect(find.text('Chrome'), findsNWidgets(2));
      expect(find.text('1286 people'), findsOneWidget);
      expect(find.byIcon(Icons.public), findsNWidgets(2));
      expect(find.text('0'), findsNothing);
      await pump(
        tester,
        DChartTooltipContent(
          items: items,
          hideLabel: true,
          hideIndicator: true,
          labelBuilder: (_, _, _) => const Text('Hidden label'),
          itemBuilder: (_, item, index) => Text('Custom $index: ${item.value}'),
        ),
      );
      expect(find.text('Hidden label'), findsNothing);
      expect(find.text('Custom 0: 1286'), findsOneWidget);
    },
  );

  testWidgets('open tooltip follows live palette radius font scale and alpha', (
    tester,
  ) async {
    final controller = DChartController(0);
    await pump(tester, chart(controller: controller));
    final tokens = DTokens.fromTheme(
      AppTheme.dark,
    ).copyWith(radius: 15, border: const Color(0x80445566));
    await pump(
      tester,
      chart(controller: controller),
      scale: 2,
      width: 260,
      direction: TextDirection.rtl,
      theme: AppTheme.dark.copyWith(extensions: [tokens]),
    );
    final container = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(DChartTooltipContent),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((w) => w.decoration is BoxDecoration);
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, tokens.background);
    expect(decoration.borderRadius, BorderRadius.circular(15));
    expect(
      (decoration.border! as Border).top.color.a,
      closeTo(tokens.border.a * .5, .001),
    );
    expect(find.text('186'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('quantitative marks clamp and fill from the directional start', (
    tester,
  ) async {
    await pump(
      tester,
      const DChartBar(fraction: .25),
      width: 200,
      direction: TextDirection.rtl,
    );
    final mark = find.descendant(
      of: find.byType(DChartBar),
      matching: find.byType(ColoredBox),
    );
    expect(tester.getSize(mark), const Size(50, 7));
    expect(
      tester.getTopRight(mark),
      tester.getTopRight(find.byType(DChartBar)),
    );
    await pump(tester, const DChartBar(fraction: 2), width: 200);
    expect(tester.getSize(mark), const Size(200, 7));
  });

  testWidgets(
    'negative missing and zero data render without invalid geometry',
    (tester) async {
      final controller = DChartController(2);
      await pump(
        tester,
        DBarChart<num?>(
          data: const [-20, 0, null, 80],
          series: [DChartSeries(key: 'desktop', value: (value) => value)],
          label: (value) => '$value',
          semanticLabel: 'Change',
          controller: controller,
          axis: true,
          valueAxis: true,
          grid: true,
        ),
        width: 200,
        scale: 2,
      );
      expect(find.text('Desktop'), findsOneWidget);
      expect(find.text('null'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('grid and grouped bars paint reference geometry into a real image', (
    tester,
  ) async {
    final key = GlobalKey();
    await pump(tester, RepaintBoundary(key: key, child: chart(tooltip: false)));
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 1),
    ))!;
    expect(image.width, 360);
    expect(image.height, 200);
    final bytes = await tester.runAsync(() => image.toByteData());
    // Two points inside the first bar and upper blank plot differ. This catches
    // lost/zero-height bars without treating a source-level painter as evidence.
    final firstBar = (140 * image.width + 50) * 4;
    final blank = (20 * image.width + 50) * 4;
    expect(bytes!.getUint32(firstBar), isNot(bytes.getUint32(blank)));
    image.dispose();
  });
}
