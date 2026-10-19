import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class _RecordingFactory extends WidgetFactory {
  _RecordingFactory({this.omitText});

  final String? omitText;
  final texts = <String>[];

  @override
  InlineSpan? buildTextSpan({
    List<InlineSpan>? children,
    GestureRecognizer? recognizer,
    TextStyle? style,
    String? text,
  }) {
    if (text != null) {
      texts.add(text);
      if (text == omitText) {
        return null;
      }
    }
    return super.buildTextSpan(
      children: children,
      recognizer: recognizer,
      style: style,
      text: text,
    );
  }
}

Widget _host(Widget child) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xff000000),
            fontSize: 14,
            fontWeight: FontWeight.normal,
            fontStyle: FontStyle.normal,
          ),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

InlineSpan _paragraph(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText)).text;

List<InlineSpan> _runs(InlineSpan span) => [
      if (span is TextSpan) ...[
        if (span.text?.isNotEmpty == true) span,
        for (final child in span.children ?? const <InlineSpan>[])
          ..._runs(child),
      ] else
        span,
    ];

void main() {
  testWidgets('keeps nested styles and factory callback order', (tester) async {
    final factory = _RecordingFactory();
    await tester.pumpWidget(_host(HtmlWidget(
      '<p>one<b>two<i>three</i>four</b>five</p>',
      buildAsync: false,
      factoryBuilder: () => factory,
    )));

    final span = _paragraph(tester);
    final runs = _runs(span).cast<TextSpan>();
    expect(span.toPlainText(), 'onetwothreefourfive');
    expect(
        runs.map((run) => run.text), ['one', 'two', 'three', 'four', 'five']);
    expect(runs.map((run) => run.style?.fontWeight), [
      FontWeight.normal,
      FontWeight.bold,
      FontWeight.bold,
      FontWeight.bold,
      FontWeight.normal,
    ]);
    expect(runs.map((run) => run.style?.fontStyle), [
      FontStyle.normal,
      FontStyle.normal,
      FontStyle.italic,
      FontStyle.normal,
      FontStyle.normal,
    ]);
    expect(factory.texts, ['five', 'four', 'three', 'two', 'one']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trims whitespace through empty trailing styles', (tester) async {
    for (final (html, expected) in [
      (
        '<p><b>kept   </b><i> \t </i>'
            '<span style="color: red"> \n </span></p>',
        'kept',
      ),
      ('<p><b>left</b><i> </i><b>right </b><span> </span></p>', 'left right'),
      ('<p>plain <b> </b><i> </i></p>', 'plain'),
    ]) {
      await tester.pumpWidget(_host(HtmlWidget(html, buildAsync: false)));
      expect(_paragraph(tester).toPlainText(), expected, reason: html);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('elided custom spans keep earlier text last for whitespace',
      (tester) async {
    final factory = _RecordingFactory(omitText: 'drop');
    await tester.pumpWidget(_host(HtmlWidget(
      '<p><b>keep   </b><i>drop</i></p>',
      buildAsync: false,
      factoryBuilder: () => factory,
    )));

    expect(_paragraph(tester).toPlainText(), 'keep');
    expect(factory.texts, ['drop', 'keep', '']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves link recognizers through nested styles',
      (tester) async {
    final urls = <String>[];
    await tester.pumpWidget(_host(HtmlWidget(
      '<p>before <a href="https://example.com/first">first <b>bold</b></a>'
      ' between <a href="https://example.com/second">second</a> after</p>',
      buildAsync: false,
      onTapUrl: (url) {
        urls.add(url);
        return true;
      },
    )));

    final span = _paragraph(tester);
    expect(span.toPlainText(), 'before first bold between second after');
    final links = _runs(span)
        .whereType<TextSpan>()
        .where((run) => run.recognizer is TapGestureRecognizer)
        .toList();
    expect(links.map((run) => run.text), ['first ', 'bold', 'second']);
    expect(links[0].recognizer, same(links[1].recognizer));
    expect(links[2].recognizer, isNot(same(links[0].recognizer)));
    (links[1].recognizer! as TapGestureRecognizer).onTap!();
    (links[2].recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(urls, ['https://example.com/first', 'https://example.com/second']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolls to an inline anchor after many formatted runs',
      (tester) async {
    final key = GlobalKey<HtmlWidgetState>();
    final prefix = List.generate(
      512,
      (i) => '<b>before$i </b><i>more$i </i>',
    ).join();
    await tester.pumpWidget(_host(HtmlWidget(
      '<p>$prefix<span id="destination">destination</span> after</p>',
      key: key,
      buildAsync: false,
    )));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, 0);
    final result = key.currentState!.scrollToAnchor('destination');
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(scroll.position.pixels, greaterThan(0));
    expect(_paragraph(tester).toPlainText(), contains('destination after'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps inline widgets between their styled text runs',
      (tester) async {
    const inlineKey = ValueKey('inline');
    await tester.pumpWidget(_host(HtmlWidget(
      '<p><b>left</b><test-inline></test-inline><i>right</i></p>',
      buildAsync: false,
      customWidgetBuilder: (element) => element.localName == 'test-inline'
          ? const InlineCustomWidget(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(key: inlineKey, width: 12, height: 10),
            )
          : null,
    )));

    final span = _paragraph(tester);
    final runs = _runs(span);
    expect(span.toPlainText(), 'left\uFFFCright');
    expect(runs, hasLength(3));
    expect((runs[0] as TextSpan).text, 'left');
    expect(runs[1], isA<WidgetSpan>());
    expect((runs[1] as WidgetSpan).alignment, PlaceholderAlignment.middle);
    expect((runs[2] as TextSpan).text, 'right');
    expect(find.byKey(inlineKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps every formatted run in one large block', (tester) async {
    const count = 1024;
    final html = StringBuffer('<p>start|');
    final expected = StringBuffer('start|');
    for (var i = 0; i < count; i++) {
      final color = i.isEven ? 'ff0000' : '0000ff';
      html.write('<span style="color: #$color">token$i</span>');
      expected.write('token$i');
    }
    html.write('|end</p>');
    expected.write('|end');
    await tester
        .pumpWidget(_host(HtmlWidget(html.toString(), buildAsync: false)));

    final span = _paragraph(tester);
    final runs = _runs(span).cast<TextSpan>();
    expect(span.toPlainText(), expected.toString());
    expect(runs, hasLength(count + 2));
    expect(runs.first.text, 'start|');
    expect(runs.last.text, '|end');
    for (var i = 0; i < count; i++) {
      expect(runs[i + 1].text, 'token$i', reason: 'run $i');
      expect(
        runs[i + 1].style?.color,
        i.isEven ? const Color(0xffff0000) : const Color(0xff0000ff),
        reason: 'run $i',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
