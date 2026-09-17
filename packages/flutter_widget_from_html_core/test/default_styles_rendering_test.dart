import 'package:csslib/visitor.dart' as css;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class _ProbeFactory extends WidgetFactory {
  final margins = <css.Declaration>[];
  final colors = <Object>[];
  int callbacks = 0;

  List<css.Declaration> get customMargins => margins
      .where((style) => style.span?.text.contains('3px') ?? false)
      .toList();

  @override
  void parse(BuildTree tree) {
    super.parse(tree);
    if (tree.element.localName != 'p') {
      return;
    }
    tree.register(BuildOp(defaultStyles: (element) {
      callbacks++;
      return {'color': element.attributes['data-color'] ?? 'red'};
    }));
  }

  @override
  void parseStyle(BuildTree tree, css.Declaration style) {
    if (tree.element.localName == 'p') {
      if (style.property == 'margin') {
        margins.add(style);
      }
      if (style.property == 'color') {
        colors.add((style.value! as css.LiteralTerm).value);
      }
    }
    super.parseStyle(tree, style);
  }
}

void main() {
  testWidgets('custom CSS reuses syntax without sharing mutable declarations',
      (tester) async {
    final factory = _ProbeFactory();
    var callbacks = 0;
    Widget host(String html, String color) => MaterialApp(
          home: Scaffold(
            body: HtmlWidget(
              html,
              factoryBuilder: () => factory,
              buildAsync: false,
              customStylesBuilder: (element) {
                if (element.localName != 'p') return null;
                callbacks++;
                return {'margin': '3px', 'color': color};
              },
              rebuildTriggers: [color],
            ),
          ),
        );
    await tester.pumpWidget(host('<p>One</p><p>Two</p>', 'green'));
    expect(callbacks, 2);
    expect(factory.customMargins, hasLength(2));
    final first = factory.customMargins.first;
    expect(first.span, same(factory.customMargins.last.span));
    expect(first, isNot(same(factory.customMargins.last)));
    expect(factory.colors.last, 0x008000);
    (first.expression! as css.Expressions).expressions.clear();
    first.dartStyle!.priority = 99;

    factory.margins.clear();
    factory.colors.clear();
    // The same HTML with a changed callback must still pick up the new style.
    await tester.pumpWidget(host('<p>One</p><p>Two</p>', 'blue'));
    expect(callbacks, 4);
    expect(factory.colors.last, 0x0000ff);
    final changed = factory.customMargins.first;
    expect((changed.expression! as css.Expressions).expressions, isNotEmpty);
    expect(changed.dartStyle!.priority, isNot(99));

    factory.margins.clear();
    // A later body must be able to reuse the original syntax safely, too.
    await tester.pumpWidget(host('<p>Third</p>', 'green'));
    expect(callbacks, 5);
    final reused = factory.customMargins.single;
    expect(reused.span, same(first.span));
    expect((reused.expression! as css.Expressions).expressions, isNotEmpty);
    expect(reused.dartStyle!.priority, isNot(99));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares default parsing across bodies without sharing mutations',
      (tester) async {
    final factory = _ProbeFactory();
    Widget host(String html) => MaterialApp(
          home: Scaffold(
            body: HtmlWidget(html,
                factoryBuilder: () => factory, buildAsync: false),
          ),
        );
    await tester.pumpWidget(host('<div><p>One</p><div><p>Two</p></div></div>'));
    expect(factory.margins, hasLength(2));
    expect(factory.margins[0].span, same(factory.margins[1].span));
    expect(factory.margins[0], isNot(same(factory.margins[1])));
    expect(factory.callbacks, 2);
    final firstBody = factory.margins.first;
    final oldExpressions = firstBody.expression! as css.Expressions;
    (oldExpressions.expressions.first as css.LiteralTerm).value = 99;
    oldExpressions.expressions.clear();
    firstBody.dartStyle!.priority = 99;
    factory.margins.clear();
    factory.colors.clear();
    await tester
        .pumpWidget(host('<p data-color="blue">Edited</p><p>Other</p>'));
    expect(factory.margins, hasLength(2));
    expect(factory.margins.first.span, same(firstBody.span));
    expect(factory.margins.first, isNot(same(firstBody)));
    final newExpressions = factory.margins.first.expression! as css.Expressions;
    expect(newExpressions.expressions, hasLength(2));
    expect((newExpressions.expressions.first as css.LiteralTerm).value, 1);
    expect(factory.margins.first.dartStyle!.priority, isNot(99));
    expect(factory.margins[0].span, same(factory.margins[1].span));
    expect(factory.callbacks, 4);
    expect(factory.colors, [0x0000ff, 0xff0000]);
    expect(find.text('Edited', findRichText: true), findsOneWidget);
    expect(find.text('Other', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
