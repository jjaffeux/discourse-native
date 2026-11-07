import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/post_plain_text.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post({String cooked = '', String? raw}) => Post.fromJson({
  'id': 1,
  'post_number': 1,
  'username': 'sam',
  'cooked': cooked,
  'raw': ?raw,
}, 'https://meta.example');

void main() {
  test(
    'regression fourth: raw previews retain literal bracketed prose and code',
    () {
      expect(
        postPlainText(_post(raw: 'Use [name] and `[u]literal[/u]`.')),
        'Use [name] and [u]literal[/u].',
      );
    },
  );

  test('regression fourth: cooked headings and table cells stay separate', () {
    expect(
      postPlainText(
        _post(
          cooked:
              '<h2>Results</h2><table><tr><th>Name</th><th>Count</th></tr><tr><td>Sam</td><td>2</td></tr></table><p>Done</p>',
        ),
      ),
      'Results Name Count Sam 2 Done',
    );
  });

  test('regression: reply previews retain cooked emoji content', () {
    expect(
      postPlainText(
        _post(
          cooked:
              '<p>Nice <img class="emoji" alt=":heart:" src="/heart.png"> work</p>',
        ),
      ),
      'Nice :heart: work',
    );
    expect(
      postPlainText(
        _post(
          cooked:
              '<p><img class="emoji only-emoji" title=":+1:" src="/thumb.png"></p>',
        ),
      ),
      ':+1:',
    );
  });

  test('regression: raw previews preserve literal punctuation', () {
    expect(
      postPlainText(
        _post(
          raw:
              '# Notes\nUse snake_case, C#, a*b and 2 > 1. **Bold** and _soft_.',
        ),
      ),
      'Notes Use snake_case, C#, a*b and 2 > 1. Bold and soft.',
    );
  });

  test('cooked posts give their words, blocks set apart, scripts unread', () {
    expect(
      postPlainText(
        _post(
          cooked:
              '<p>First <strong>line</strong></p><p>second</p>'
              '<ul><li>one</li><li>two</li></ul><script>x()</script>'
              '<style>p{}</style>a<br>b',
        ),
      ),
      'First line second one two a b',
    );
  });

  test('a post held only as markup gives its words without its marks', () {
    expect(
      postPlainText(
        _post(
          raw:
              '# Plan\n\n**Bold** and _soft_ `code` ~~gone~~\n'
              '> quoted [label](https://example.com/a) '
              '[date=2026-10-27 time=10:00] [u]under[/u]',
        ),
      ),
      'Plan Bold and soft code gone quoted label under',
    );
  });

  test('cooked words win over the markup they came from', () {
    expect(
      postPlainText(_post(cooked: '<p>Cooked</p>', raw: '**Raw**')),
      'Cooked',
    );
    expect(postPlainText(_post(cooked: '<p> </p>')), '');
  });

  test('unbalanced brackets stay a linear scan', () {
    String raw(int size) => '[a](' * size + '[' * size;
    Duration time(int size) {
      final watch = Stopwatch()..start();
      postPlainText(_post(raw: raw(size)));
      return watch.elapsed;
    }

    time(2000);
    final small = time(4000);
    final large = time(32000);
    expect(large, lessThan(small * 32));
  });
}
