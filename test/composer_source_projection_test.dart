import 'package:discourse_native/src/shell/composer_source_projection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = '[component]body[/component]';
  const style = TextStyle(fontSize: 16, height: 1.5);
  final spans = <InlineSpan>[
    const WidgetSpan(child: SizedBox(width: 100, height: 400)),
    TextSpan(
      style: const TextStyle(fontSize: 0, height: 0),
      children: [TextSpan(text: source.substring(1, source.length - 1))],
    ),
    const TextSpan(text: '\n', style: style),
  ];

  test(
    'a synthetic end line retains a text character and every source offset',
    () {
      final normalized = TextSpan(
        children: normalizeCollapsedComponentSourceSpans(
          source: source,
          spans: spans,
        ),
      );
      final text = normalized.toPlainText(includeSemanticsLabels: false);
      expect(text.length, source.length);
      expect(text, endsWith('\n\u200b'));
      expect(normalized.children!.last.style, style);
    },
  );

  test('suppressing a synthetic end line does not introduce another break', () {
    final normalized = TextSpan(
      children: normalizeCollapsedComponentSourceSpans(
        source: source,
        spans: spans,
        suppressSyntheticLineBreaks: true,
      ),
    );
    final text = normalized.toPlainText(includeSemanticsLabels: false);
    expect(text.length, source.length);
    expect(text, isNot(contains('\n')));
  });

  test('an authored end line stays at its original source offset', () {
    final authoredSource = '${source.substring(0, source.length - 1)}\n';
    final normalized = TextSpan(
      children: normalizeCollapsedComponentSourceSpans(
        source: authoredSource,
        spans: spans,
      ),
    );
    final text = normalized.toPlainText(includeSemanticsLabels: false);
    expect(text.length, authoredSource.length);
    expect(text, endsWith('${authoredSource[authoredSource.length - 2]}\n'));
  });
}
