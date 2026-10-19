import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_document.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

void main() {
  testWidgets('rich cell projections preserve attributes and the source tree', (
    tester,
  ) async {
    final element = _table('''
<table><tr><th>Content</th></tr><tr>
<td class="align-left" data-label="&quot;quoted&quot; &amp; &nbsp; &lt;tag&gt;" dir="rtl" lang="fr">
  Before &amp; <!-- kept markup -->
  <a href="/t/topic/42?x=1&amp;y=2" title="&quot;Open&quot;">Link</a>
  <strong>bold <em>emphasis</em></strong>
  <code>&lt;code&gt; &amp; value</code>
  <details open><summary>More</summary><span class="spoiler">Hidden</span></details>
  <svg viewBox="0 0 1 1"><use xlink:href="#shape"></use><text>svg &amp; text</text></svg>
</td></tr></table>
''');
    final cell = element.querySelector('td')!;
    final originalHtml = element.outerHtml;
    final originalChildren = cell.nodes.toList();
    final originalParent = cell.parentNode;
    final projections = <String>[];

    await _pump(tester, _adapt(element, projections));

    expect(projections, isNotEmpty);
    for (final projection in projections) {
      final wrapper = html.parseFragment(projection).children.single;
      expect(wrapper.localName, 'div');
      expect(wrapper.attributes, cell.attributes);
      expect(wrapper.innerHtml, cell.innerHtml);
      expect(
        projection,
        contains('data-label="&quot;quoted&quot; &amp; &nbsp; <tag>"'),
      );
      final svg = wrapper.querySelector('svg')!;
      expect(svg.namespaceUri, 'http://www.w3.org/2000/svg');
      expect(svg.attributes['viewBox'], '0 0 1 1');
      expect(
        svg.querySelector('use')!.attributes[const dom.AttributeName(
          'xlink',
          'href',
          'http://www.w3.org/1999/xlink',
        )],
        '#shape',
      );
    }
    expect(element.outerHtml, originalHtml);
    expect(cell.nodes, originalChildren);
    expect(cell.parentNode, same(originalParent));
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy preserves cell text, break tokens and Markdown escapes', (
    tester,
  ) async {
    final copied = _clipboardWrites(tester);
    final element = _table(r'''
<table><tr><th> Heading<br>line </th><th>Other</th></tr>
<tr><td> A&nbsp; &amp; &lt;tag&gt;<br> B|C \ D <!-- ignored | \ --><span>end</span> </td>
<td><script> const marker = "<br>|"; </script><style> .x{color:red} </style><svg><text> SVG &amp; label </text><foreignObject><div>HTML<br>after</div></foreignObject></svg></td></tr>
<tr><td> Last<br><br>line </td><td> &#124; &#92; &#160; &#x1f642; </td></tr></table>
''');
    final originalHtml = element.outerHtml;
    await _pump(tester, _adapt(element, []));

    await tester.tap(_copyButton);
    await tester.pump();

    expect(copied, [
      r'''| Heading<br>line | Other |
| --- | --- |
| A & <tag><br> B\|C \\ D end | const marker = "<br>\|"; .x{color:red} SVG & label HTML<br>after |
| Last<br><br>line | \| \\ 🙂 |''',
    ]);
    expect(element.outerHtml, originalHtml);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  for (final (tag, text, expected) in [
    (
      'plaintext',
      'literal',
      '<div><plaintext>literal</plaintext></plaintext></div>',
    ),
    (
      'script',
      '<!--<script>literal',
      '<div><script><!--<script>literal</script></script></div>',
    ),
  ]) {
    testWidgets('$tag retains its legacy nested normalization', (tester) async {
      final element = _table(
        '<table><tr><th>Value</th></tr><tr><td></td></tr></table>',
      );
      element.querySelector('td')!.append(dom.Element.tag(tag)..text = text);
      final projections = <String>[];
      await _pump(tester, _adapt(element, projections));
      expect(projections, everyElement(expected));
      expect(projections, isNotEmpty);
    });
  }

  testWidgets('table snapshots ignore source mutations before mounting', (
    tester,
  ) async {
    final copied = _clipboardWrites(tester);
    final element = _table(
      '<table><caption><em>Original caption</em></caption>'
      '<tr><th>Original heading</th></tr>'
      '<tr><td data-label="original">Original <strong>value</strong></td></tr>'
      '</table>',
    );
    final projections = <String>[];
    final table = _adapt(element, projections);
    element.querySelector('th')!.text = 'Changed heading';
    element.querySelector('caption')!.text = 'Changed caption';
    element.querySelector('td')!
      ..attributes['data-label'] = 'changed'
      ..text = 'Changed value';
    element.querySelectorAll('tr').last.remove();

    await _pump(tester, table);

    expect(find.text('Original heading'), findsOneWidget);
    expect(find.text('Changed heading'), findsNothing);
    expect(
      projections,
      containsAll([
        '<div data-label="original">Original <strong>value</strong></div>',
        '<em>Original caption</em>',
      ]),
    );
    await tester.tap(_copyButton);
    await tester.pump();
    expect(copied, ['| Original heading |\n| --- |\n| Original value |']);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}

dom.Element _table(String source) =>
    html.parseFragment(source).querySelector('table')!;

Widget _adapt(dom.Element element, List<String> projections) =>
    cookedTableWidgetBuilder(
      element,
      content: CookedDocument(element.outerHtml).bind((_, fragment, style) {
        projections.add(fragment.html);
        return const SizedBox(height: 1);
      }),
    )!;

Future<void> _pump(WidgetTester tester, Widget table) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: table)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _copyButton => find.byWidgetPredicate(
  (widget) => widget is DButton && widget.tooltip == 'Copy table',
);

List<String> _clipboardWrites(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  return copied;
}
