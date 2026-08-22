import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:discourse_native/src/shell/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

/// The source with each run wrapped in what it was marked as, so a failure
/// reads as what someone would see rather than as a list of offsets.
///
/// Unmarked runs are written bare, which keeps the expectations short: most of
/// a post is prose, and only the marked-up parts are worth spelling out.
String annotate(String source) {
  final buffer = StringBuffer();
  for (final run in scanMarkdown(source)) {
    final text = source.substring(run.start, run.end);
    final names = _names(run);
    buffer.write(names.isEmpty ? text : '<${names.join('+')}>$text</>');
  }
  return buffer.toString();
}

List<String> _names(MarkdownRun run) => [
  for (final (flag, name) in const [
    (Md.marker, 'm'),
    (Md.bold, 'b'),
    (Md.italic, 'i'),
    (Md.strikethrough, 's'),
    (Md.code, 'code'),
    (Md.codeBlock, 'block'),
    (Md.heading, 'h'),
    (Md.quote, 'q'),
    (Md.linkText, 'text'),
    (Md.linkUrl, 'url'),
    (Md.mention, 'at'),
    (Md.hashtag, 'hash'),
    (Md.emoji, 'emoji'),
    (Md.htmlTag, 'tag'),
  ])
    if (run.has(flag)) name,
];

/// Everything the scanner is asked about anywhere in this file, plus the awkward
/// cases that have no assertion of their own — the invariant below has to hold
/// for all of it.
const List<String> samples = [
  '',
  'plain prose with no marks at all',
  '**bold**',
  '*italic*',
  '***both***',
  '~~struck~~',
  '`code`',
  '``a ` b``',
  '# A heading',
  '###### Six',
  '> quoted',
  '>> twice',
  '[text](https://example.com)',
  'see https://example.com/a_b for more',
  'hey @sam and @martin.j',
  'joffrey@example.com is an address',
  'see #support and #parent:child and #name::tag',
  '#support',
  '# Heading is not a hashtag',
  '###### deep',
  'a#b is not one either',
  'https://example.com/a#top',
  '#a#b',
  'press <kbd>Esc</kbd> now',
  '<mark>look <kbd>here</kbd></mark>',
  'a :smile: and a :wave:t3: here',
  ':smile::smile:',
  '```ruby\nputs 1\n```',
  '```\nno language\n```',
  '```ruby\nunterminated',
  'a * b * c',
  '2 * 3 * 4 = 24',
  'snake_case_name stays a name',
  '**bold with `code` inside**',
  '`**not bold**`',
  'one\n\ntwo',
  '| a | b |\n| - | - |',
  '* one\n* two',
  '\n\n\n',
  '****',
  '~~~',
  '@',
  ':',
  '**unterminated',
  '*over\ntwo lines*',
  '*open\n\nclosed*',
  '*open\n```\ncode\n```\nclosed*',
];

void main() {
  group('scanMarkdown', () {
    test('leaves prose alone', () {
      expect(
        annotate('plain prose with no marks at all'),
        'plain prose '
        'with no marks at all',
      );
    });

    test('dims the markers and styles what is between them', () {
      expect(annotate('**bold**'), '<m>**</><b>bold</><m>**</>');
      expect(annotate('*italic*'), '<m>*</><i>italic</><m>*</>');
      expect(annotate('~~struck~~'), '<m>~~</><s>struck</><m>~~</>');
    });

    test('reads three asterisks as both marks, not as a stray one', () {
      expect(annotate('***both***'), '<m>***</><b+i>both</><m>***</>');
    });

    test('marks compose, the way the toolbar composes them', () {
      // What pressing bold and then italic actually leaves in the field.
      expect(annotate('***say***'), '<m>***</><b+i>say</><m>***</>');
    });

    test('lets a mark open inside another', () {
      expect(
        annotate('**bold with `code` inside**'),
        '<m>**</><b>bold with </><m+b>`</><b+code>code</><m+b>`</>'
        '<b> inside</><m>**</>',
      );
    });

    test('does not mistake arithmetic for emphasis', () {
      expect(annotate('2 * 3 * 4 = 24'), '2 * 3 * 4 = 24');
      expect(annotate('a * b * c'), 'a * b * c');
    });

    test('leaves an underscore inside a word alone', () {
      expect(
        annotate('snake_case_name stays a name'),
        'snake_case_name '
        'stays a name',
      );
    });

    test('leaves an unterminated marker as text', () {
      expect(annotate('**unterminated'), '**unterminated');
    });

    test('lets a mark wrap a line break inside its paragraph', () {
      expect(
        annotate('*over\ntwo lines*'),
        '<m>*</><i>over\ntwo lines</><m>*</>',
      );
    });

    test('stops a mark at a paragraph break', () {
      expect(annotate('*open\n\nclosed*'), '*open\n\nclosed*');
    });

    test('stops a mark at a fenced block', () {
      // A fence ends the paragraph around it, so the asterisks either side of
      // one are two stray characters rather than a pair. Letting them pair up
      // italicised the code between them, and made every opener before a large
      // fence rescan the whole of it on the next keystroke.
      expect(
        annotate('*open\n```\ncode\n```\nclosed*'),
        '*open\n<m>```</>\n<block>code\n</><m>```</>\nclosed*',
      );
    });
  });

  group('code', () {
    test('takes everything inside it literally', () {
      expect(annotate('`**not bold**`'), '<m>`</><code>**not bold**</><m>`</>');
    });

    test('lets a longer fence hold a backtick', () {
      expect(annotate('``a ` b``'), '<m>``</><code>a ` b</><m>``</>');
    });

    test('claims a whole fenced block', () {
      final runs = scanMarkdown('```\nno language\n```');
      final body = runs.where((run) => run.has(Md.codeBlock));
      expect(body, isNotEmpty);
      expect(
        body
            .map((r) => '```\nno language\n```'.substring(r.start, r.end))
            .join(),
        'no language\n',
      );
    });

    test('tokenises a fence that names its language', () {
      const source = '```ruby\nputs 1\n```';
      final scopes = scanMarkdown(source)
          .where((run) => run.has(Md.codeBlock) && run.detail != null)
          .map((run) => run.detail!)
          .toSet();
      // Whatever highlight.js calls them, it had *some* opinion about Ruby.
      expect(scopes, isNotEmpty);
    });

    test('reads an unterminated fence as code while it is being typed', () {
      const source = '```ruby\nunterminated';
      final body = scanMarkdown(
        source,
      ).where((run) => run.has(Md.codeBlock)).toList();
      expect(body, isNotEmpty);
      expect(
        body.map((r) => source.substring(r.start, r.end)).join(),
        'unterminated',
      );
    });
  });

  group('deferred fence highlighting', () {
    setUp(clearSyntaxHighlightCacheForTesting);

    // As `_highlightFence` sees it: everything between the fence lines, the
    // newline that closed the last body line included.
    final largeBody =
        '${List.generate(40, (i) => 'final value$i = "line $i";').join('\n')}'
        '\n';
    final largeSource = '```dart\n$largeBody```';

    Iterable<MarkdownRun> scoped(List<MarkdownRun> runs) =>
        runs.where((run) => run.has(Md.codeBlock) && run.detail != null);

    test('the fixture is big enough to be worth deferring', () {
      expect(largeBody.length, greaterThan(maxSynchronousFenceChars));
    });

    test('a small fence is tokenized synchronously even with the callback', () {
      var deferred = 0;
      final runs = scanMarkdown(
        '```dart\nfinal x = 1;\n```',
        deferHighlight: (_, _) => deferred++,
      );

      expect(deferred, 0);
      expect(scoped(runs), isNotEmpty);
    });

    test('a large unparsed fence is left plain and handed back', () {
      final deferred = <(String, String?)>[];
      final runs = scanMarkdown(
        largeSource,
        deferHighlight: (body, language) => deferred.add((body, language)),
      );

      expect(deferred, [(largeBody, 'dart')]);
      // Still code — monospace, code colour — just without scopes yet.
      expect(runs.where((run) => run.has(Md.codeBlock)), isNotEmpty);
      expect(scoped(runs), isEmpty);
    });

    test('a large fence already in the cache keeps its colour', () {
      // What the debounce owes the scan: exactly this call, with exactly the
      // body it was handed.
      highlightLines(largeBody, 'dart');

      var deferred = 0;
      final runs = scanMarkdown(
        largeSource,
        deferHighlight: (_, _) => deferred++,
      );

      expect(deferred, 0);
      expect(scoped(runs), isNotEmpty);
    });

    test('without the callback every fence tokenizes in place', () {
      expect(scoped(scanMarkdown(largeSource)), isNotEmpty);
    });
  });

  group('blocks', () {
    test('dims the hashes and lifts the heading', () {
      expect(annotate('# A heading'), '<m># </><h>A heading</>');
    });

    test('carries the level, so six is not drawn like one', () {
      final heading = scanMarkdown(
        '###### Six',
      ).firstWhere((run) => run.has(Md.heading));
      expect(heading.detail, '6');
    });

    test('dims the quote marker', () {
      expect(annotate('> quoted'), '<m>> </><q>quoted</>');
      expect(annotate('>> twice'), '<m>>> </><q>twice</>');
    });

    test('marks up the prose inside a quote', () {
      expect(
        annotate('> a **bold** point'),
        '<m>> </><q>a </><m+q>**</>'
        '<b+q>bold</><m+q>**</><q> point</>',
      );
    });
  });

  group('links, mentions and emoji', () {
    test('separates the text from the address', () {
      expect(
        annotate('[text](https://example.com)'),
        '<m>[</><text>text</><m>](</><url>https://example.com</><m>)</>',
      );
    });

    test('finds a bare address', () {
      expect(
        annotate('see https://example.com/a_b for more'),
        'see <url>https://example.com/a_b</> for more',
      );
    });

    test('finds people', () {
      expect(annotate('hey @sam'), 'hey <at>@sam</>');
      expect(annotate('hey @martin.j'), 'hey <at>@martin.j</>');
    });

    test('does not read an email address as a mention', () {
      expect(
        annotate('joffrey@example.com is an address'),
        'joffrey@example.com is an address',
      );
    });

    test('finds shortcodes, tone and all', () {
      expect(annotate('a :smile: here'), 'a <emoji>:smile:</> here');
      expect(annotate('a :wave:t3: here'), 'a <emoji>:wave:t3:</> here');
    });

    test('keeps two shortcodes side by side apart', () {
      // Collapsed by mask alone they would be one run, and anything drawing a
      // picture per run would draw one over both.
      final runs = scanMarkdown(
        ':smile::smile:',
      ).where((run) => run.has(Md.emoji)).toList();
      expect(runs.length, 2);
      expect(runs.first.end, 7);
    });

    test('carries the name, colons stripped', () {
      expect(
        scanMarkdown('a :smile: b').firstWhere((r) => r.has(Md.emoji)).token,
        'smile',
      );
      expect(
        scanMarkdown('a :wave:t3: b').firstWhere((r) => r.has(Md.emoji)).token,
        'wave:t3',
      );
    });

    test('a shortcode inside a tag does not steal the tag', () {
      // The name and the tag are two different facts about the same
      // characters. Held in one slot the shortcode overwrote the tag, and
      // `<kbd>` lost its monospace chip — see [MarkdownRun.token].
      final run = scanMarkdown(
        'press <kbd>:smile:</kbd> now',
      ).firstWhere((run) => run.has(Md.emoji));
      expect(run.token, 'smile');
      expect(run.detail, 'kbd');
    });

    test('leaves a lone colon alone', () {
      expect(annotate('this: that'), 'this: that');
    });

    test('carries the username', () {
      expect(
        scanMarkdown('hey @sam').firstWhere((r) => r.has(Md.mention)).token,
        'sam',
      );
    });
  });

  group('hashtags', () {
    test('finds categories and tags', () {
      expect(annotate('see #support'), 'see <hash>#support</>');
      expect(annotate('see #parent:child'), 'see <hash>#parent:child</>');
      expect(annotate('see #name::tag'), 'see <hash>#name::tag</>');
    });

    test('carries the ref, sigil stripped', () {
      // The ref and not the slug: it is what was typed, and the only form that
      // finds a subcategory or a name two things share.
      expect(
        scanMarkdown(
          'see #parent:child',
        ).firstWhere((r) => r.has(Md.hashtag)).token,
        'parent:child',
      );
    });

    test('a heading is not a hashtag', () {
      // The heading pattern already demands whitespace after the hashes, so
      // the two never have to be told apart by anything else.
      expect(annotate('# Heading'), '<m># </><h>Heading</>');
      expect(annotate('#Heading'), '<hash>#Heading</>');
    });

    test('a hashtag inside a heading is still a hashtag', () {
      expect(
        annotate('# See #support'),
        '<m># </><h>See </><h+hash>#support</>',
      );
    });

    test('is not a hash inside a word', () {
      expect(annotate('a#b'), 'a#b');
      expect(annotate('##foo'), '##foo');
    });

    test('leaves a url fragment alone', () {
      expect(
        annotate('https://example.com/a#top'),
        '<url>https://example.com/a#top</>',
      );
    });

    test('a second sigil inside the run does not start another', () {
      // `#a#b` is one hashtag called `a`, not two. The `#` is a word
      // character as far as the boundary rule is concerned, which is the same
      // rule that refuses `##foo` — and the same one the composer's trigger
      // uses, so what gets drawn and what offers a completion agree.
      final runs = scanMarkdown('#a#b').where((r) => r.has(Md.hashtag));
      expect(runs.map((r) => r.token), ['a']);
      expect(annotate('#a#b'), '<hash>#a</>#b');
    });

    test('keeps two apart when they really are two', () {
      // Collapsed by mask alone these would be one run, and something drawing
      // a pill per run would draw one over both.
      final runs = scanMarkdown('#a #b').where((r) => r.has(Md.hashtag));
      expect(runs.map((r) => r.token), ['a', 'b']);
    });

    test('code and link addresses take it literally', () {
      expect(annotate('`#support`'), '<m>`</><code>#support</><m>`</>');
      expect(
        annotate('[x](https://a.b/#c)'),
        '<m>[</><text>x</><m>](</><url>https://a.b/#c</><m>)</>',
      );
    });

    test('keeps its underscores out of emphasis', () {
      expect(annotate('#a_b_c'), '<hash>#a_b_c</>');
    });

    test('stops before trailing punctuation', () {
      expect(annotate('see #support.'), 'see <hash>#support</>.');
      expect(annotate('(#support)'), '(<hash>#support</>)');
    });
  });

  group('inline HTML', () {
    test('draws the tags Discourse keeps', () {
      expect(
        annotate('press <kbd>Esc</kbd> now'),
        'press <m>&lt;kbd&gt;</><tag>Esc</><m>&lt;/kbd&gt;</> now'
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>'),
      );
    });

    test('carries which tag it was', () {
      final tag = scanMarkdown(
        'press <kbd>Esc</kbd> now',
      ).firstWhere((run) => run.has(Md.htmlTag));
      expect(tag.detail, 'kbd');
    });

    test('nests', () {
      final tags = scanMarkdown(
        '<mark>look <kbd>here</kbd></mark>',
      ).where((run) => run.has(Md.htmlTag)).map((run) => run.detail).toSet();
      expect(tags, containsAll(<String>['mark', 'mark,kbd']));
    });
  });

  group('the invariant', () {
    test('paints every character of the source, and no others', () {
      for (final source in samples) {
        final runs = scanMarkdown(source);
        expect(
          runs.map((run) => source.substring(run.start, run.end)).join(),
          source,
          reason: 'the painted text drifted from the source: $source',
        );
      }
    });

    test('holds for markdown nobody would write', () {
      // The sample list above covers what the scanner was designed against,
      // which is exactly the input least likely to break it. This throws
      // syntax at it in whatever order a seeded random picks — half-open
      // marks, fences inside links, a `[` with no `]` — because the field
      // losing a character is the one failure that cannot be shipped.
      //
      // Seeded, so a failure is reproducible rather than a story about a run
      // that happened once on someone's laptop.
      final random = Random(20260807);
      const alphabet = [
        '**',
        '*',
        '_',
        '~~',
        '`',
        '```',
        '#',
        '> ',
        '[',
        ']',
        '(',
        ')',
        '@sam',
        '#support',
        '#a:b',
        ':smile:',
        '<kbd>',
        '</kbd>',
        'word',
        ' ',
        '\n',
        '\n\n',
        'https://a.b',
        '!',
        '\\',
        'ruby',
      ];

      for (var i = 0; i < 2000; i++) {
        final buffer = StringBuffer();
        for (var n = random.nextInt(24); n > 0; n--) {
          buffer.write(alphabet[random.nextInt(alphabet.length)]);
        }
        final source = buffer.toString();

        expect(
          scanMarkdown(
            source,
          ).map((r) => source.substring(r.start, r.end)).join(),
          source,
          reason:
              'the painted text drifted from the source: ${jsonEncode(source)}',
        );
      }
    });

    test('runs are contiguous and non-overlapping', () {
      for (final source in samples) {
        var at = 0;
        for (final run in scanMarkdown(source)) {
          expect(run.start, at, reason: 'gap or overlap in: $source');
          expect(
            run.end,
            greaterThan(run.start),
            reason: 'empty run in: $source',
          );
          at = run.end;
        }
        expect(at, source.length, reason: 'ran short of: $source');
      }
    });

    test('scales with the length of what is pasted, not its square', () {
      // A stack trace is the shape that used to be quadratic: one block with
      // no blank line in it, and one `_private` opener per frame that never
      // finds a closer. Every keystroke rescans the whole document, so an
      // opener that walks to the end of the block for each of its peers is
      // felt as the composer freezing.
      //
      // Timed rather than counted because the cost is inside the regexp
      // engine, so the tolerance is wide: eight times the input is eight times
      // the work when this is linear and sixty-four when it is not.
      String paste(int frames) {
        final buffer = StringBuffer('Getting this on launch:\n\n```\n');
        for (var i = 0; i < frames; i += 1) {
          buffer.writeln(
            '#$i      _SiteTracker._onMessage (package:app/src/data/'
            'site_tracker.dart:${100 + i}:${i % 40})',
          );
        }
        return (buffer..writeln('```')).toString();
      }

      // The best of several runs, so a garbage collection landing in one of
      // them cannot decide the result.
      int cost(String source) {
        var best = -1;
        for (var run = 0; run < 3; run += 1) {
          final elapsed = Stopwatch()..start();
          scanMarkdown(source);
          elapsed.stop();
          final taken = elapsed.elapsedMicroseconds;
          if (best < 0 || taken < best) best = taken;
        }
        return best;
      }

      final small = cost(paste(100));
      final large = cost(paste(800));

      expect(
        large,
        lessThan(small * 25),
        reason: 'eight times the paste took ${large / small} times as long',
      );
    });
  });
}
