import 'package:csslib/visitor.dart' as css;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class _ProbeFactory extends WidgetFactory {
  final margins = <css.Declaration>[];
  final colors = <Object>[];
  int callbacks = 0;

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
  testWidgets('shares parsing across nested elements but resets for a new body',
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
    factory.margins.clear();
    factory.colors.clear();
    await tester
        .pumpWidget(host('<p data-color="blue">Edited</p><p>Other</p>'));
    expect(factory.margins, hasLength(2));
    expect(factory.margins.first.span, isNot(same(firstBody.span)));
    expect(factory.margins[0].span, same(factory.margins[1].span));
    expect(factory.callbacks, 4);
    expect(factory.colors, [0x0000ff, 0xff0000]);
    expect(find.text('Edited', findRichText: true), findsOneWidget);
    expect(find.text('Other', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
