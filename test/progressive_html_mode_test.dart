import 'dart:async';

import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

String _html(String label, [int count = 450]) => List.generate(
  count,
  (i) => '<p>$label $i: A paragraph with <strong>bold</strong> words.</p>',
).join();

Finder _paragraphs(String label, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().startsWith(label),
      skipOffstage: skipOffstage,
    );

Widget _host(
  String html, {
  RenderMode mode = const ProgressiveHtmlMode(),
  bool dark = false,
  ScrollController? scroll,
  ValueChanged<SelectedContent?>? onSelection,
}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  home: Scaffold(
    body: SelectionArea(
      onSelectionChanged: onSelection,
      child: SingleChildScrollView(
        controller: scroll,
        child: SizedBox(
          width: 500,
          child: CookedHtml(html: html, buildAsync: false, renderMode: mode),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('retained bodies follow visibility changes without remounting', (
    tester,
  ) async {
    final firstVisible = ValueNotifier(false);
    addTearDown(firstVisible.dispose);
    Widget body(String label, bool first) => ValueListenableBuilder<bool>(
      valueListenable: firstVisible,
      child: _host(_html(label)),
      builder: (context, visible, child) {
        final enabled = visible == first;
        return Offstage(
          offstage: !enabled,
          child: TickerMode(enabled: enabled, child: child!),
        );
      },
    );
    await tester.pumpWidget(
      Stack(
        textDirection: TextDirection.ltr,
        children: [body('First', true), body('Second', false)],
      ),
    );
    int count(String label) =>
        _paragraphs(label, skipOffstage: false).evaluate().length;
    final first = tester.element(
      _paragraphs('First', skipOffstage: false).first,
    );
    final initial = count('First');
    await tester.pump();
    expect(count('First'), initial);
    expect(count('Second'), greaterThan(initial));
    firstVisible.value = true;
    await tester.pump();
    final hiddenCount = count('Second');
    await tester.pump();
    expect(count('First'), greaterThan(initial));
    expect(count('Second'), hiddenCount);
    expect(tester.element(_paragraphs('First').first), same(first));
    await tester.pumpAndSettle();
    expect(count('First'), 450);
    expect(count('Second'), 450);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden mounting completes and edits without a visibility wait', (
    tester,
  ) async {
    final completions = <Future<void>>{};
    Widget body(String label) =>
        NotificationListener<HtmlBodyMountingNotification>(
          onNotification: (notification) {
            completions.add(notification.completion);
            return false;
          },
          child: Offstage(
            child: TickerMode(enabled: false, child: _host(_html(label))),
          ),
        );
    await tester.pumpWidget(body('Original'));
    expect(completions, hasLength(1));
    var complete = false;
    unawaited(completions.single.then((_) => complete = true));
    await tester.pump();
    await tester.pumpWidget(body('Replacement'));
    expect(complete, isFalse);
    await tester.pumpAndSettle();
    expect(complete, isTrue);
    expect(completions, hasLength(1));
    expect(_paragraphs('Original', skipOffstage: false), findsNothing);
    expect(_paragraphs('Replacement', skipOffstage: false), findsNWidgets(450));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing deferred hidden work settles its completion', (
    tester,
  ) async {
    Future<void>? completion;
    await tester.pumpWidget(
      Stack(
        textDirection: TextDirection.ltr,
        children: [
          NotificationListener<HtmlBodyMountingNotification>(
            onNotification: (notification) {
              completion = notification.completion;
              return false;
            },
            child: Offstage(
              child: TickerMode(enabled: false, child: _host(_html('Hidden'))),
            ),
          ),
          _host(_html('Visible')),
        ],
      ),
    );
    expect(completion, isNotNull);
    var complete = false;
    unawaited(completion!.then((_) => complete = true));
    await tester.pump();
    expect(complete, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(complete, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible bodies take queue turns before hidden bodies', (
    tester,
  ) async {
    Widget body(String label, {bool visible = true}) => Offstage(
      offstage: !visible,
      child: TickerMode(enabled: visible, child: _host(_html(label))),
    );
    await tester.pumpWidget(
      Stack(
        textDirection: TextDirection.ltr,
        children: [
          body('Hidden', visible: false),
          body('Visible first'),
          body('Visible second'),
        ],
      ),
    );
    int count(String label) =>
        _paragraphs(label, skipOffstage: false).evaluate().length;
    final initial = count('Visible first');
    expect(count('Hidden'), initial);
    expect(count('Visible second'), initial);
    await tester.pump();
    expect(count('Hidden'), initial);
    expect(count('Visible first'), greaterThan(initial));
    expect(count('Visible second'), initial);
    final firstTurn = count('Visible first');
    await tester.pump();
    expect(count('Hidden'), initial);
    expect(count('Visible first'), firstTurn);
    expect(count('Visible second'), firstTurn);
    for (var frame = 0; frame < 30; frame++) {
      final before = count('Visible first') + count('Visible second');
      if (before == 900) break;
      await tester.pump();
      final added = count('Visible first') + count('Visible second') - before;
      expect(added, inInclusiveRange(1, 32));
      expect(count('Hidden'), initial);
    }
    expect(count('Visible first'), 450);
    expect(count('Visible second'), 450);
    await tester.pumpAndSettle();
    expect(count('Hidden'), 450);
    expect(count('Visible first'), 450);
    expect(count('Visible second'), 450);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows a prefix first and keeps its elements and final geometry',
    (tester) async {
      final html = _html('Paragraph');
      await tester.pumpWidget(_host(html));
      final initial = _paragraphs('Paragraph').evaluate().length;
      expect(initial, inExclusiveRange(0, 450));
      final first = tester.element(_paragraphs('Paragraph').first);
      final firstPosition = tester.getTopLeft(_paragraphs('Paragraph').first);
      await tester.pump();
      expect(_paragraphs('Paragraph').evaluate().length, greaterThan(initial));
      await tester.pumpAndSettle();
      expect(_paragraphs('Paragraph'), findsNWidgets(450));
      expect(tester.element(_paragraphs('Paragraph').first), same(first));
      expect(tester.getTopLeft(_paragraphs('Paragraph').first), firstPosition);
      final height = tester.getSize(find.byType(CookedHtml)).height;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(html, mode: RenderMode.column));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CookedHtml)).height, height);
    },
  );

  testWidgets('preserves a sized CSS wrapper around a long body', (
    tester,
  ) async {
    final html = '<div style="width: 240px">${_html('Wrapped')}</div>';
    await tester.pumpWidget(_host(html, mode: RenderMode.column));
    await tester.pumpAndSettle();
    final size = tester.getSize(_paragraphs('Wrapped').first);
    final bodySize = tester.getSize(find.byType(CookedHtml));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(html));
    await tester.pumpAndSettle();
    expect(tester.getSize(_paragraphs('Wrapped').first), size);
    expect(tester.getSize(find.byType(CookedHtml)), bodySize);
  });

  testWidgets(
    'replaces HTML during mounting without resurrecting old content',
    (tester) async {
      await tester.pumpWidget(_host(_html('Old')));
      await tester.pump();
      await tester.pumpWidget(_host(_html('Replacement', 320)));
      await tester.pumpAndSettle();
      expect(_paragraphs('Old'), findsNothing);
      expect(_paragraphs('Replacement'), findsNWidgets(320));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('completed bodies apply edits and palette changes as a whole', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_html('Original')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(_html('Edited', 460), dark: true));
    expect(_paragraphs('Original'), findsNothing);
    expect(_paragraphs('Edited'), findsNWidgets(460));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling during mounting preserves visible paragraph offsets', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_host(_html('Paragraph'), scroll: scroll));
    scroll.jumpTo(300);
    await tester.pump();
    final firstPosition = tester.getTopLeft(_paragraphs('Paragraph').first);
    await tester.pumpAndSettle();
    expect(scroll.offset, 300);
    expect(tester.getTopLeft(_paragraphs('Paragraph').first), firstPosition);
  });

  testWidgets(
    'select all includes the completed body across batch boundaries',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        _host(
          _html('Paragraph'),
          onSelection: (content) => selected = content?.plainText,
        ),
      );
      await tester.pumpAndSettle();
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(selected, contains('Paragraph 0:'));
      expect(selected, contains('Paragraph 449:'));
      expect('Paragraph'.allMatches(selected!).length, 450);
    },
  );

  testWidgets('disposal cancels pending work even with several large bodies', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                CookedHtml(
                  html: _html('Body $i'),
                  buildAsync: false,
                  renderMode: const ProgressiveHtmlMode(),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      expect(
        _paragraphs('Body $i').evaluate().length,
        inExclusiveRange(0, 450),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('small bodies and one large block render without staging', (
    tester,
  ) async {
    var notifications = 0;
    Widget observe(Widget child) =>
        NotificationListener<HtmlBodyMountingNotification>(
          onNotification: (_) {
            notifications++;
            return false;
          },
          child: child,
        );
    await tester.pumpWidget(observe(_host(_html('Small', 20))));
    expect(_paragraphs('Small'), findsNWidgets(20));
    await tester.pumpWidget(
      observe(_host('<p>${List.filled(5000, 'Single ').join()}</p>')),
    );
    expect(_paragraphs('Single'), findsOneWidget);
    expect(notifications, 0);
  });
}
