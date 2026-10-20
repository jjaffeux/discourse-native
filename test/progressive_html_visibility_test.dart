import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

Widget _body() => HtmlWidget(
  [
    for (var i = 0; i < 450; i++) '<p>Paragraph $i remains selectable.</p>',
  ].join(),
  buildAsync: false,
  renderMode: const ProgressiveHtmlMode(),
);

Finder _paragraphs() => find.byWidgetPredicate(
  (widget) =>
      widget is RichText && widget.text.toPlainText().startsWith('Paragraph '),
);

void main() {
  testWidgets(
    'hidden long bodies pause mounting and resume without replacing the prefix',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              child: _body(),
              builder: (_, enabled, child) =>
                  TickerMode(enabled: enabled, child: child!),
            ),
          ),
        ),
      );
      final paragraphs = _paragraphs();
      final first = tester.element(paragraphs.first);
      expect(paragraphs.evaluate().length, lessThan(450));
      visible.value = false;
      await tester.pump();
      final pausedCount = paragraphs.evaluate().length;
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        paragraphs.evaluate().length,
        pausedCount,
        reason:
            'Retained offscreen HTML must not mount more paragraphs while the reader scrolls elsewhere',
      );
      visible.value = true;
      await tester.pumpAndSettle();
      expect(paragraphs, findsNWidgets(450));
      expect(tester.element(paragraphs.first), same(first));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      visible.value = false;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reparented bodies follow the new ticker mode only', (
    tester,
  ) async {
    final location = ValueNotifier((first: true, left: false, right: true));
    addTearDown(location.dispose);
    final children = [
      for (var i = 0; i < 450; i++) Text('Paragraph $i remains selectable.'),
    ];
    final body = Builder(
      key: GlobalKey(),
      builder: (context) => const ProgressiveHtmlMode().buildBodyWidget(
        WidgetFactory(),
        context,
        children,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: ValueListenableBuilder<({bool first, bool left, bool right})>(
            valueListenable: location,
            builder: (_, value, _) => Column(
              children: [
                TickerMode(
                  enabled: value.left,
                  child: value.first ? body : const SizedBox.shrink(),
                ),
                TickerMode(
                  enabled: value.right,
                  child: value.first ? const SizedBox.shrink() : body,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final paragraphs = _paragraphs();
    final first = tester.element(paragraphs.first);
    final initial = paragraphs.evaluate().length;
    await tester.pumpAndSettle();
    expect(paragraphs, findsNWidgets(initial));

    location.value = (first: false, left: false, right: true);
    await tester.pump();
    await tester.pump();
    expect(paragraphs.evaluate().length, greaterThan(initial));
    expect(tester.element(paragraphs.first), same(first));

    location.value = (first: false, left: false, right: false);
    await tester.pump();
    final paused = paragraphs.evaluate().length;
    location.value = (first: false, left: true, right: false);
    await tester.pumpAndSettle();
    expect(paragraphs, findsNWidgets(paused));
    expect(tester.binding.transientCallbackCount, 0);

    location.value = (first: true, left: true, right: false);
    await tester.pump();
    await tester.pump();
    expect(paragraphs.evaluate().length, greaterThan(paused));
    expect(tester.element(paragraphs.first), same(first));
    await tester.pumpAndSettle();
    expect(paragraphs, findsNWidgets(450));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pausing cancels idle callbacks and enabling schedules new work',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              child: _body(),
              builder: (_, enabled, child) =>
                  TickerMode(enabled: enabled, child: child!),
            ),
          ),
        ),
      );
      expect(tester.binding.transientCallbackCount, 1);
      visible.value = false;
      await tester.pump();
      final paused = _paragraphs().evaluate().length;
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(_paragraphs(), findsNWidgets(paused));

      visible.value = true;
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 1);
      await tester.pump();
      expect(_paragraphs().evaluate().length, greaterThan(paused));

      await tester.pumpWidget(const SizedBox.shrink());
      visible.value = false;
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
