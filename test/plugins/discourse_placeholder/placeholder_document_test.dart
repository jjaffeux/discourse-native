import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/plugins/discourse_placeholder/fixtures/upstream.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  for (final entry in (fixture['cases'] as List).cast<Map<String, Object?>>()) {
    test('upstream fixture: ${entry['name']}', () {
      final document = PlaceholderDocument.parse(entry['cooked'] as String);
      final rendered = html.parseFragment(
        document.render(Map<String, String>.from(entry['values'] as Map)),
      );
      expect(rendered.querySelector('#result')!.text, entry['text']);
      if (entry['href'] != null) {
        expect(
          rendered.querySelector('#result a')!.attributes['href'],
          entry['href'],
        );
      }
    });
  }

  test('preserves source and replaces each eligible text node once', () {
    const source =
        '<div class="d-wrap" data-wrap="placeholder" data-key="X"></div>'
        '<h1>=X=</h1><p><strong>=X=</strong><code>=X=</code></p>'
        '<blockquote><p>=X=</p></blockquote><ul><li><b>=X=</b></li></ul>'
        '<div class="md-table"><table><tr><td>=X=</td></tr></table></div>'
        '<pre><code>=X=</code></pre><div id="excluded" title="=X=">=X=</div>';
    final document = PlaceholderDocument.parse(source);
    final rendered = html.parseFragment(document.render({'X': '=X= added'}));
    for (final selector in [
      'h1',
      'strong',
      'p > code',
      'blockquote',
      'li',
      'td',
      'pre',
    ]) {
      expect(
        rendered.querySelector(selector)!.text,
        '=X= added',
        reason: selector,
      );
    }
    expect(
      rendered.querySelector('#excluded')!.outerHtml,
      '<div id="excluded" title="=X=">=X=</div>',
    );
    expect(document.source, source);
    expect(
      html
          .parseFragment(document.render({'X': 'next'}))
          .querySelector('h1')!
          .text,
      'next',
    );
  });

  test('values are literal text and attributes, never parsed as HTML', () {
    final document = PlaceholderDocument.parse(
      '<span class="d-wrap" data-wrap="placeholder" data-key="[X]"></span>'
      '<p id="result"><a href="https://example.com/=[X]=">=[X]=</a></p>',
    );
    const value = r'<img src=x>&"$&$1';
    final rendered = html.parseFragment(document.render({'[X]': value}));
    expect(rendered.querySelector('p')!.text, value);
    expect(rendered.querySelectorAll('img'), isEmpty);
    expect(
      rendered.querySelector('a')!.attributes['href'],
      'https://example.com/$value',
    );
  });

  test(
    'last repeated definition wins and both fields keep distinct identities',
    () {
      final document = PlaceholderDocument.parse(
        '<div class="d-wrap" data-wrap="placeholder" data-key="X" data-default="first"></div>'
        '<span class="d-wrap" data-wrap="placeholder" data-key="X" data-default="last"></span><p>=X= =UNKNOWN=</p>',
      );
      final rendered = html.parseFragment(document.render({}));
      expect(rendered.querySelector('p')!.text, 'last =UNKNOWN=');
      expect(
        rendered
            .querySelectorAll('[data-native-placeholder-field]')
            .map((e) => e.attributes[placeholderFieldAttribute]),
        ['0', '1'],
      );
      expect(
        html
            .parseFragment(document.render({'X': 'none'}))
            .querySelector('p')!
            .text,
        '=X= =UNKNOWN=',
      );
    },
  );

  test(
    'ignores malformed declarations and leaves unrelated HTML byte-for-byte',
    () {
      for (final source in [
        '<p>=X=</p>',
        '<div data-wrap="placeholder" data-key="X"></div>',
        '<span class="d-wrap" data-wrap="placeholder"></span>',
        '<div class="d-wrap" data-wrap="placeholder" data-key=""></div>',
        '<code class="d-wrap" data-wrap="placeholder" data-key="X">=X=</code>',
      ]) {
        final document = PlaceholderDocument.parse(source);
        expect(document.fields, isEmpty, reason: source);
        expect(document.render({'X': 'changed'}), source);
      }
    },
  );
}
