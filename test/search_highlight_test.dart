import 'package:discourse_native/src/shell/search_words.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  test(
    'regression fifth: search highlighting matches supplementary case pairs',
    () {
      expect(
        highlightSearchHtml('<p>𐐀</p>', '𐐨'),
        '<p><mark class="native-search-hit">𐐀</mark></p>',
      );
    },
  );

  test(
    'regression fourth: clock times are searchable text rather than filters',
    () {
      expect(searchWords('10:30 category:support -tags:hidden @sam'), [
        '10:30',
      ]);
      expect(
        highlightSearchHtml('<p>Meet at 10:30</p>', '10:30'),
        '<p>Meet at <mark class="native-search-hit">10:30</mark></p>',
      );
    },
  );

  test('absolute URL search terms are highlighted as text', () {
    const url = 'https://example.test/docs';
    const query = '$url category:support';
    expect(searchWords(query), [url]);
    final fragment = html_parser.parseFragment(
      highlightSearchHtml('<p>See $url</p>', query),
    );
    expect(fragment.querySelector('mark.native-search-hit')?.text, url);
  });

  test('regression: search snippets start at a whole grapheme', () {
    for (final grapheme in ['😀', 'e\u0301', '👩‍💻']) {
      final text = '${'x' * 65}$grapheme${' ' * 39}needle';
      expect(searchSnippet(text, 'needle'), '…$grapheme${' ' * 39}needle');
    }
  });

  test('empty and filter-only queries preserve the exact source', () {
    const html = "<P data-label='needle'>needle &amp; untouched</P>";
    for (final query in ['', ' \n\t ', 'category:support @sam "in:all"']) {
      expect(highlightSearchHtml(html, query), html);
      expect(highlightSearchHtml(html, query), html);
    }
  });

  test('repeated calls return the same highlighted markup', () {
    const html = '<p>needle &amp; thread</p>';
    const expected =
        '<p><mark class="native-search-hit">needle</mark> &amp; thread</p>';
    for (var repeat = 0; repeat < 3; repeat++) {
      expect(highlightSearchHtml(html, 'needle'), expected);
    }
  });

  test('changed queries and HTML use their own results', () {
    const html = '<p data-post="1">needle thread</p>';
    const changedHtml = '<p data-post="2">needle changed</p>';
    const needleResult =
        '<p data-post="1"><mark class="native-search-hit">needle</mark> thread</p>';
    const threadResult =
        '<p data-post="1">needle <mark class="native-search-hit">thread</mark></p>';
    const changedResult =
        '<p data-post="2"><mark class="native-search-hit">needle</mark> changed</p>';

    expect(highlightSearchHtml(html, 'needle'), needleResult);
    expect(highlightSearchHtml(html, 'thread'), threadResult);
    expect(highlightSearchHtml(changedHtml, 'needle'), changedResult);
    expect(highlightSearchHtml(html, 'needle'), needleResult);
    expect(highlightSearchHtml(html, 'thread'), threadResult);
  });

  test('query words stay literal and matched HTML characters stay escaped', () {
    const html =
        '<p data-search="[x] &amp; &lt;tag&gt;">'
        'C++ [x] &amp; &lt;tag&gt; a.b axb</p>';

    for (var repeat = 0; repeat < 2; repeat++) {
      final output = highlightSearchHtml(html, 'c++ [x] & <tag> a.b');
      final fragment = html_parser.parseFragment(output);
      expect(
        fragment.querySelectorAll('mark.native-search-hit').map((e) => e.text),
        ['C++', '[x]', '&', '<tag>', 'a.b'],
      );
      expect(
        fragment.querySelector('p')!.attributes['data-search'],
        '[x] & <tag>',
      );
      expect(fragment.text, 'C++ [x] & <tag> a.b axb');
      expect(fragment.querySelector('tag'), isNull);
      expect(output, contains('&lt;tag&gt;</mark>'));
    }
  });

  test('excluded subtrees and existing marks keep their contents', () {
    const html =
        '<script>needle</script><style>.needle {}</style>'
        '<code><span>needle</span></code><pre><b>needle</b></pre>'
        '<mark class="existing" data-token="needle"><i>needle</i></mark>'
        '<p>needle</p>';

    for (var repeat = 0; repeat < 2; repeat++) {
      final fragment = html_parser.parseFragment(
        highlightSearchHtml(html, 'needle'),
      );
      expect(fragment.querySelector('script')!.innerHtml, 'needle');
      expect(fragment.querySelector('style')!.innerHtml, '.needle {}');
      expect(fragment.querySelector('code')!.innerHtml, '<span>needle</span>');
      expect(fragment.querySelector('pre')!.innerHtml, '<b>needle</b>');
      final existing = fragment.querySelector('mark.existing')!;
      expect(existing.attributes['data-token'], 'needle');
      expect(existing.innerHtml, '<i>needle</i>');
      expect(fragment.querySelectorAll('mark.native-search-hit').length, 1);
      expect(fragment.querySelector('p mark')!.text, 'needle');
    }
  });

  test('nested concealed markup and checklist attributes remain intact', () {
    const html =
        '<details data-state="closed"><summary>needle summary</summary>'
        '<div class="spoiler" data-spoiler="needle" aria-hidden="true">'
        '<span class="chcklst-box checked" data-native-checklist-index="7" '
        'data-checklist-item="needle" role="checkbox" aria-checked="true" '
        'tabindex="0"></span><span hidden>needle concealed</span>'
        '<p><a href="/needle?token=needle">needle link</a></p>'
        '</div></details>';

    for (var repeat = 0; repeat < 2; repeat++) {
      final fragment = html_parser.parseFragment(
        highlightSearchHtml(html, 'needle'),
      );
      final details = fragment.querySelector('details')!;
      expect(details.attributes, {'data-state': 'closed'});
      expect(details.querySelector('summary mark')!.text, 'needle');
      final spoiler = details.querySelector('div.spoiler')!;
      expect(spoiler.attributes, {
        'class': 'spoiler',
        'data-spoiler': 'needle',
        'aria-hidden': 'true',
      });
      expect(spoiler.querySelector('.chcklst-box')!.attributes, {
        'class': 'chcklst-box checked',
        'data-native-checklist-index': '7',
        'data-checklist-item': 'needle',
        'role': 'checkbox',
        'aria-checked': 'true',
        'tabindex': '0',
      });
      expect(spoiler.querySelector('[hidden] mark')!.text, 'needle');
      expect(
        spoiler.querySelector('a')!.attributes['href'],
        '/needle?token=needle',
      );
      expect(spoiler.querySelectorAll('mark.native-search-hit').length, 2);
    }
  });

  test('many distinct inputs keep their correct results after churn', () {
    for (final reverse in [false, true]) {
      for (var offset = 0; offset < 48; offset++) {
        final index = reverse ? 47 - offset : offset;
        final html = '<p data-row="$index">needle row $index</p>';
        final expected =
            '<p data-row="$index"><mark class="native-search-hit">needle</mark> row $index</p>';
        expect(highlightSearchHtml(html, 'needle in:row$index'), expected);
      }
    }
  });

  test('oversized source and queries still produce complete output', () {
    final filler = 'x' * (256 * 1024);
    final largeHtml = '<p>${filler}needle</p>';
    final largeExpected =
        '<p>$filler<mark class="native-search-hit">needle</mark></p>';
    final largeQuery = 'needle category:$filler';
    const smallHtml = '<p>needle thread</p>';
    const smallExpected =
        '<p><mark class="native-search-hit">needle</mark> thread</p>';

    for (var repeat = 0; repeat < 2; repeat++) {
      expect(highlightSearchHtml(largeHtml, 'needle'), largeExpected);
      expect(highlightSearchHtml(smallHtml, largeQuery), smallExpected);
    }
  });

  test('expanded output remains complete when it exceeds the entry limit', () {
    final html = '<p>${'needle ' * 6000}</p>';
    final expected =
        '<p>${'<mark class="native-search-hit">needle</mark> ' * 6000}</p>';

    for (var repeat = 0; repeat < 2; repeat++) {
      expect(highlightSearchHtml(html, 'needle'), expected);
    }
  });
}
