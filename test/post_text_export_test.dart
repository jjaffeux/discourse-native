import 'package:discourse_native/src/shell/post_quote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('full post text export', () {
    final cases = <({String name, String cooked, String text})>[
      (
        name: 'paragraph and explicit line boundaries',
        cooked: '<p>Alpha</p><p>Beta<br>Gamma</p>',
        text: 'Alpha\n\nBeta\nGamma',
      ),
      (
        name: 'collapsed HTML whitespace around blocks',
        cooked: '\n<p>  Alpha  words </p>\n <p> Beta </p>\n',
        text: 'Alpha words\n\nBeta',
      ),
      (
        name: 'list and nested list boundaries',
        cooked:
            '<ol><li>First<ul><li>Nested</li></ul></li>'
            '<li>Second</li></ol>',
        text: 'First\n\nNested\n\nSecond',
      ),
      (
        name: 'consecutive explicit line breaks',
        cooked: '<p>Alpha<br><br><br>Beta</p>',
        text: 'Alpha\n\n\nBeta',
      ),
      (
        name: 'line breaks separated by collapsed source whitespace',
        cooked: '<p>Alpha<br> \n <br>Beta</p>',
        text: 'Alpha\n\nBeta',
      ),
      (
        name: 'leading and trailing explicit line breaks',
        cooked: '<p><br>Alpha<br><br></p>',
        text: '\nAlpha\n\n',
      ),
      (name: 'line-break-only content', cooked: '<br><br>', text: '\n\n'),
      (
        name: 'standalone code whitespace',
        cooked: '<pre><code>  first\n\n\tsecond  \n</code></pre>',
        text: '  first\n\n\tsecond  \n',
      ),
      (
        name: 'code terminal newlines at paragraph boundaries',
        cooked:
            '<p>Before</p><pre><code>  first\n</code></pre>'
            '<p>After</p>',
        text: 'Before\n\n  first\n\nAfter',
      ),
      (
        name: 'authored blank code lines before a paragraph',
        cooked: '<pre><code>first\n\n\n</code></pre><p>After</p>',
        text: 'first\n\n\nAfter',
      ),
      (
        name: 'explicit breaks after literal code newlines',
        cooked: '<pre><code>first\n<br>second</code></pre>',
        text: 'first\n\nsecond',
      ),
      (
        name: 'inline formatting without Markdown or quote escapes',
        cooked:
            '<p>*literal* &amp; <strong>bold</strong> '
            '<a href="https://example.com">link</a> '
            '<code>a`b</code> [quote] &lt;x&gt;</p>',
        text: '*literal* & bold link a`b [quote] <x>',
      ),
      (
        name: 'ignored control and script content',
        cooked:
            '<p>Visible</p><div class="quote-controls">Quote</div>'
            '<script>script</script><style>style</style>',
        text: 'Visible',
      ),
      (name: 'empty HTML', cooked: '', text: ''),
      (
        name: 'empty ordinary blocks',
        cooked: '<p></p><div></div><script>ignored</script>',
        text: '',
      ),
    ];

    for (final fixture in cases) {
      test('preserves ${fixture.name}', () {
        expect(
          PostQuoteSelectionResolver(fixture.cooked).exportText,
          fixture.text,
        );
      });
    }
  });

  test(
    'text export keeps selection matching and quote boundaries unchanged',
    () {
      final resolver = PostQuoteSelectionResolver(
        '<p>Alpha</p><p>Beta<br><br>Gamma</p>',
      );

      expect(resolver.exportText, 'Alpha\n\nBeta\n\nGamma');
      expect(resolver.plainText, 'AlphaBetaGamma');
      expect(resolver.entirePost, 'Alpha\n\nBeta\nGamma');
      expect(resolver.contentsFor('BetaGamma'), 'Beta\nGamma');
      expect(resolver.resolve('Gamma').supportsFastEdit, isTrue);
    },
  );

  test('text export keeps quote literal escaping unchanged', () {
    final resolver = PostQuoteSelectionResolver(
      '<p>*literal* &amp; [quote] &lt;x&gt;</p>',
    );

    expect(resolver.exportText, '*literal* & [quote] <x>');
    expect(resolver.plainText, '*literal* & [quote] <x>');
    expect(
      resolver.entirePost,
      r'\*literal\* &#38; &#91;quote&#93; &#60;x&#62;',
    );
  });
}
