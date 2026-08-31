import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:discourse_native/src/shell/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

String? tokenOf(String source) {
  for (final run in scanMarkdown(source)) {
    if (run.token != null) return run.token;
  }
  return null;
}

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

const int _minimumBenchmarkSampleMicros = 25000;

/// Measures batches long enough to keep JIT and scheduler noise from
/// dominating the linear-versus-quadratic ratio.
double _stableScanCost(String source) {
  var checksum = scanMarkdown(source).length;

  var iterations = 1;
  late int firstSampleMicros;
  while (true) {
    final calibration = _scanBatch(source, iterations);
    checksum += calibration.checksum;
    if (calibration.elapsedMicros >= _minimumBenchmarkSampleMicros ||
        iterations >= 256) {
      firstSampleMicros = calibration.elapsedMicros;
      break;
    }
    iterations *= 2;
  }

  var best = firstSampleMicros.toDouble();
  for (var sample = 1; sample < 3; sample += 1) {
    final batch = _scanBatch(source, iterations);
    checksum += batch.checksum;
    if (batch.elapsedMicros < best) {
      best = batch.elapsedMicros.toDouble();
    }
  }
  expect(checksum, isPositive);
  return best / iterations;
}

({int elapsedMicros, int checksum}) _scanBatch(String source, int iterations) {
  var checksum = 0;
  final elapsed = Stopwatch()..start();
  for (var iteration = 0; iteration < iterations; iteration += 1) {
    checksum += scanMarkdown(source).length;
  }
  elapsed.stop();
  return (elapsedMicros: elapsed.elapsedMicroseconds, checksum: checksum);
}

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
  '* not italic *',
  '*a*b*c*',
  '**a**b**c**',
  '_a_b_c_',
  'a_b_c',
  '_a\u{00a0}b_',
  '~~a~~~~b~~',
  '***a**b*',
  '**',
  '__',
  '_ x _',
  'x*y*z',
  '<kbd>Esc\n\nlater</kbd>',
  '<kbd>a\n```\ncode\n```\nb</kbd>',
  'a `b\n\nc` d',
  r'a \`b\` c',
  r'a \\`code`',
  '`a``',
  '``a`',
  r'\`',
  r'`\`',
  r'a \*not italic\* b',
  r'a \@sam \#tag b',
  r'a \[text](url) b',
  r'a \\*italic* b',
  r'trailing \',
  r'\n',
  '__bold__',
  '___both___',
  'a ** b ** c',
  'a __ b __ c',
  'snake__case__name',
  '__a__b__c__',
  '___',
  'thanks @sam.',
  '@sam-',
  '@_x',
  '@a',
  'word:smile: here',
  'Standup at 10:30:45',
  '(:smile:)',
  'a-:smile:',
  'a `b\n\n**bold** and @sam\n\nc` d',
  'let `x = 1`\n\nand ``y``',
  'one `two\nthree` four',
  'tick ` alone\n\n# Heading\n\nother ` tick',
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

    test('three asterisks compose bold and italic, as the toolbar does', () {
      expect(annotate('***both***'), '<m>***</><b+i>both</><m>***</>');
    });

    test('lets a mark open inside another', () {
      expect(
        annotate('**bold with `code` inside**'),
        '<m>**</><b>bold with </><m+b>`</><b+code>code</><m+b>`</>'
        '<b> inside</><m>**</>',
      );
    });

    test('reads a double underscore the way the site does', () {
      expect(annotate('__bold__'), '<m>__</><b>bold</><m>__</>');
      expect(annotate('___both___'), '<m>___</><b+i>both</><m>___</>');
      expect(
        annotate('__bold__ and _italic_'),
        '<m>__</><b>bold</><m>__</> and <m>_</><i>italic</><m>_</>',
      );
      expect(annotate('snake__case__name'), 'snake__case__name');
    });

    test('a run of delimiters is one mark or none, never a piece of one', () {
      expect(annotate('a ** b ** c'), 'a ** b ** c');
      expect(annotate('****'), '****');
      expect(annotate('a __ b __ c'), 'a __ b __ c');
      expect(annotate('***both***'), '<m>***</><b+i>both</><m>***</>');
      expect(annotate('*a**b*'), '<m>*</><i>a**b</><m>*</>');
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

    test('needs something other than space against each marker', () {
      expect(annotate('* not italic *'), '* not italic *');
      expect(annotate('_ x _'), '_ x _');
      expect(annotate('~~ x ~~'), '~~ x ~~');
      expect(annotate('*\u{00a0}x\u{00a0}*'), '*\u{00a0}x\u{00a0}*');
    });

    test('pairs markers left to right and shortest first', () {
      expect(
        annotate('*a*b*c*'),
        '<m>*</><i>a</><m>*</>b<m>*</><i>c</><m>*</>',
      );
    });

    test('needs a word boundary either side of an underscore pair', () {
      expect(annotate('_a_b_c_'), '<m>_</><i>a_b_c</><m>_</>');
      expect(annotate('x_y_z'), 'x_y_z');
      expect(annotate('_a_ b'), '<m>_</><i>a</><m>_</> b');
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
      // Fences split inline delimiter pairing into separate blocks.
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

    test('an escaped backtick opens nothing', () {
      // CommonMark treats an escaped backtick as text outside code spans.
      expect(annotate(r'a \`b\` c'), r'a <m>\</>`b<m>\</>` c');
      expect(
        annotate(r'say \`this **bold** stays\` bold'),
        r'say <m>\</>`this <m>**</><b>bold</><m>**</> stays<m>\</>` bold',
      );
    });

    test('a backslash spends itself on the next character', () {
      expect(annotate(r'a \\`code`'), r'a <m>\</>\<m>`</><code>code</><m>`</>');
    });

    test('a delimiter is a whole run of backticks, not a prefix of one', () {
      expect(annotate('`a``'), '`a``');
      expect(annotate('``a`'), '``a`');
    });

    test('wraps a line break inside its paragraph', () {
      expect(
        annotate('one `two\nthree` four'),
        'one <m>`</><code>two\nthree</><m>`</> four',
      );
    });

    test(
      'does not reach across a paragraph break for its closing backtick',
      () {
        expect(annotate('a `b\n\nc` d'), 'a `b\n\nc` d');
        expect(
          annotate('a `b\n\n**bold** and @sam\n\nc` d'),
          'a `b\n\n<m>**</><b>bold</><m>**</> and <at>@sam</>\n\nc` d',
        );
      },
    );

    test('each paragraph pairs its own backticks', () {
      expect(
        annotate('let `x = 1`\n\nand ``y``'),
        'let <m>`</><code>x = 1</><m>`</>\n\nand <m>``</><code>y</><m>``</>',
      );
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
      expect(runs.where((run) => run.has(Md.codeBlock)), isNotEmpty);
      expect(scoped(runs), isEmpty);
    });

    test('a large fence already in the cache keeps its colour', () {
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

  group('escapes', () {
    test('an escaped delimiter opens nothing markdown-it would open', () {
      expect(
        annotate(r'a \*not italic\* b'),
        r'a <m>\</>*not italic<m>\</>* b',
      );
      expect(
        annotate(r'a \_not italic\_ b'),
        r'a <m>\</>_not italic<m>\</>_ b',
      );
      expect(
        annotate(r'a \~~not struck\~~ b'),
        r'a <m>\</>~~not struck<m>\</>~~ b',
      );
      expect(
        annotate(r'a \[text](https://e.com) b'),
        r'a <m>\</>[text](<url>https://e.com</>) b',
      );
      expect(
        annotate(r'a \<kbd>x\</kbd> b'),
        r'a <m>\</><kbd>x<m>\</></kbd> b',
      );
    });

    test('escaped Discourse tokens remain recognizable after parsing', () {
      // Discourse discovers these tokens after markdown-it consumes escapes.
      expect(annotate(r'a \@sam b'), r'a <m>\</><at>@sam</> b');
      expect(annotate(r'a \#tag b'), r'a <m>\</><hash>#tag</> b');
      expect(annotate(r'a \:smile: b'), r'a <m>\</><emoji>:smile:</> b');
    });

    test('an escaped delimiter does not consume the real one after it', () {
      // Refusing a pair after matching it would consume another pair's closer.
      expect(
        annotate(r'real *italic* after \*escaped\* one'),
        r'real <m>*</><i>italic</><m>*</> after <m>\</>*escaped<m>\</>* one',
      );
    });

    test('a backslash spends itself, and only on punctuation', () {
      expect(
        annotate(r'a \\*italic* b'),
        r'a <m>\</>\<m>*</><i>italic</><m>*</> b',
      );
      expect(annotate(r'a \n not punctuation'), r'a \n not punctuation');
      expect(annotate(r'trailing backslash \'), r'trailing backslash \');
    });

    test('a backslash inside code is a backslash', () {
      expect(
        annotate(r'`not \* escaped in code`'),
        r'<m>`</><code>not \* escaped in code</><m>`</>',
      );
      expect(
        annotate('```\nnot \\* escaped\n```'),
        '<m>```</>\n<block>not \\* escaped\n</><m>```</>',
      );
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

    test('a name may not end in a dot, a dash or an underscore', () {
      expect(annotate('thanks @sam.'), 'thanks <at>@sam</>.');
      expect(annotate('@sam-'), '<at>@sam</>-');
      expect(annotate('@sam_'), '<at>@sam</>_');
      expect(tokenOf('thanks @sam.'), 'sam');
    });

    test('a one-character name is core’s second alternative', () {
      expect(annotate('@a'), '<at>@a</>');
      expect(annotate('@_'), '<at>@_</>');
      expect(tokenOf('@a'), 'a');
      expect(tokenOf('@_'), '_');
    });

    test('a name stops at sixty characters, as the site does', () {
      final long = 'a' * 80;
      expect(tokenOf('@$long'), 'a' * 60);
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
      // A run can carry both an HTML tag and an emoji token.
      final run = scanMarkdown(
        'press <kbd>:smile:</kbd> now',
      ).firstWhere((run) => run.has(Md.emoji));
      expect(run.token, 'smile');
      expect(run.detail, 'kbd');
    });

    test('a shortcode needs a boundary before its opening colon', () {
      // The scanner cannot see the optional inline-emoji site setting, so it
      // follows core's conservative boundary rule.
      expect(annotate('word:smile: here'), 'word:smile: here');
      expect(annotate('Standup at 10:30:45'), 'Standup at 10:30:45');
      expect(annotate('a :smile: b'), 'a <emoji>:smile:</> b');
      expect(annotate(':smile:'), '<emoji>:smile:</>');
      expect(annotate('(:smile:)'), '(<emoji>:smile:</>)');
      expect(annotate('a-:smile:'), 'a-<emoji>:smile:</>');
      expect(annotate('a\n:smile:'), 'a\n<emoji>:smile:</>');
      expect(annotate(':smile::smile:'), '<emoji>:smile:</><emoji>:smile:</>');
    });

    test('a name stops where core stops reading one', () {
      expect(annotate(':${'a' * 70}:'), ':${'a' * 70}:');
      expect(annotate(':${'a' * 59}:'), '<emoji>:${'a' * 59}:</>');
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
      expect(
        scanMarkdown(
          'see #parent:child',
        ).firstWhere((r) => r.has(Md.hashtag)).token,
        'parent:child',
      );
    });

    test('a heading is not a hashtag', () {
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

    test('leaves a URL fragment alone', () {
      expect(
        annotate('https://example.com/a#top'),
        '<url>https://example.com/a#top</>',
      );
    });

    test('a second sigil inside the run does not start another', () {
      final runs = scanMarkdown('#a#b').where((r) => r.has(Md.hashtag));
      expect(runs.map((r) => r.token), ['a']);
      expect(annotate('#a#b'), '<hash>#a</>#b');
    });

    test('keeps two apart when they really are two', () {
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

    test('does not reach across a paragraph break for its closing tag', () {
      expect(annotate('<kbd>Esc\n\nlater</kbd>'), '<kbd>Esc\n\nlater</kbd>');
    });

    test('does not wrap a fenced block', () {
      expect(
        annotate('<kbd>a\n```\ncode\n```\nb</kbd>'),
        '<kbd>a\n<m>```</>\n<block>code\n</><m>```</>\nb</kbd>',
      );
    });
  });

  group('markdownBlocks', () {
    List<String> textsOf(
      String source, {
      Iterable<(int, int)> excluding = const [],
    }) => [
      for (final block in markdownBlocks(source, excluding: excluding))
        block.text,
    ];

    test('splits on a blank line and keeps the offsets honest', () {
      const source = 'one\n\ntwo\n\n\nthree';
      expect(textsOf(source), ['one', 'two', 'three']);
      for (final block in markdownBlocks(source)) {
        expect(
          source.substring(block.offset, block.offset + block.text.length),
          block.text,
        );
      }
    });

    test('splits around what it is told to exclude', () {
      const source = 'before\nFENCE\nafter';
      expect(textsOf(source, excluding: [(7, 12)]), ['before\n', '\nafter']);
    });

    test('a source that is one block stays one block', () {
      expect(textsOf('a\nb\nc'), ['a\nb\nc']);
      expect(textsOf(''), isEmpty);
      expect(textsOf('\n\n'), isEmpty);
    });
  });

  group('markdownPairs', () {
    List<(int, int)> pairs(
      String text,
      String delimiter, {
      bool word = false,
    }) => markdownPairs(text, delimiter, wordBounded: word).toList();

    test('takes the leftmost opener and its shortest closer', () {
      expect(pairs('*a*b*c*', '*'), [(0, 3), (4, 7)]);
    });

    test('refuses a space against the inside of either delimiter', () {
      expect(pairs('* a*', '*'), isEmpty);
      expect(pairs('*a *', '*'), isEmpty);
      expect(pairs('*\u{00a0}a*', '*'), isEmpty);
    });

    test('needs something between the delimiters', () {
      expect(pairs('**', '*'), isEmpty);
      expect(pairs('****', '**'), isEmpty);
    });

    test('honours the word boundary on both outsides', () {
      expect(pairs('_a_', '_', word: true), [(0, 3)]);
      expect(pairs('x_a_', '_', word: true), isEmpty);
      expect(pairs('_a_x', '_', word: true), isEmpty);
      expect(pairs('_a_x _b_', '_', word: true), [(0, 8)]);
    });

    test('gives up on the block once an opener runs out of closers', () {
      // Exhausted closers terminate the block scan in linear time.
      expect(pairs('_a _b _c', '_', word: true), isEmpty);
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
      // Seeded so fuzz failures remain reproducible.
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

    test('the link scan agrees with the pattern it replaced', () {
      // Escapes and syntax claimed by earlier passes intentionally differ from
      // this legacy pattern, so their characters are excluded here and covered
      // by dedicated cases below.
      final pattern = RegExp(r'\[([^\]\n]*)\]\(([^)\s]*)\)');
      const alphabet = [
        '[',
        ']',
        '(',
        ')',
        'a',
        ' ',
        '\n',
        'https://x/',
        '*',
        'b',
        '](',
        ')[',
        '[a](b)',
        '\t',
        '_',
        '![',
        '|',
      ];
      final random = Random(20260823);
      var sourcesWithExpectedLinks = 0;
      var sourcesWithoutExpectedLinks = 0;
      var expectedLinkCount = 0;

      for (var attempt = 0; attempt < 20000; attempt += 1) {
        final buffer = StringBuffer();
        for (var i = random.nextInt(24); i > 0; i -= 1) {
          buffer.write(alphabet[random.nextInt(alphabet.length)]);
        }
        final source = buffer.toString();

        // Empty link text produces no run to compare.
        final expected = [
          for (final match in pattern.allMatches(source))
            if (match.group(1)!.isNotEmpty)
              '${match.start + 1}:${match.start + 1 + match.group(1)!.length}',
        ];
        if (expected.isEmpty) {
          sourcesWithoutExpectedLinks++;
        } else {
          sourcesWithExpectedLinks++;
          expectedLinkCount += expected.length;
        }

        // Inline markup can split one link's text across adjacent link runs.
        final found = <String>[];
        int? start;
        int? end;
        for (final run in scanMarkdown(source)) {
          if (!run.has(Md.linkText)) continue;
          if (end == run.start) {
            end = run.end;
            continue;
          }
          if (start != null) found.add('$start:$end');
          start = run.start;
          end = run.end;
        }
        if (start != null) found.add('$start:$end');

        expect(found, expected, reason: 'differed on ${source.codeUnits}');
      }

      expect(sourcesWithExpectedLinks, greaterThan(1000));
      expect(sourcesWithoutExpectedLinks, greaterThan(1000));
      expect(expectedLinkCount, greaterThan(1000));
    });

    test('a claimed bracket does not hide the link after it', () {
      const source = '`code [` and [text](https://x/) end';
      final marked = [
        for (final run in scanMarkdown(source))
          if (run.has(Md.linkText) || run.has(Md.linkUrl))
            source.substring(run.start, run.end),
      ];

      expect(marked, ['text', 'https://x/']);
    });

    test(
      'an escaped bracket is not a link, and does not hide the next one',
      () {
        const source = r'a \[not a link](x) and [text](https://x/) end';
        final marked = [
          for (final run in scanMarkdown(source))
            if (run.has(Md.linkText) || run.has(Md.linkUrl))
              source.substring(run.start, run.end),
        ];

        expect(marked, ['text', 'https://x/']);
      },
    );

    test('deferring a fence does not move where code is', () {
      // Deferred fences must still populate the CodeRanges shared by later
      // projection parsers.
      final body = List.generate(
        400,
        (index) => 'var x$index = $index;',
      ).join('\n');
      final source = 'before\n\n```dart\n$body\n```\n\nafter `x` end';

      final direct = CodeRanges.of(scanMarkdown(source));
      final deferred = CodeRanges.of(
        scanMarkdown(source, deferHighlight: (_, _) {}),
      );

      expect(direct.isEmpty, isFalse);
      expect(deferred.ranges.toList(), direct.ranges.toList());
    });

    test('a line of openers costs its length, not its square', () {
      // Unclosed delimiters must not rescan the rest of the line per opener.
      for (final unit in const [
        '[abc ',
        '[abc] ',
        '[abc](x) ',
        '<kbd>x ',
        '`abc ',
        '`abc` ',
        r'\`abc\` ',
        '``abc`` ',
        r'\* ',
        r'\\ ',
        r'a\*b ',
        r'\[a\] ',
      ]) {
        final small = _stableScanCost(unit * 800);
        final large = _stableScanCost(unit * 6400);
        expect(
          large,
          lessThan(small * 25),
          reason: 'eight times "$unit" took ${large / small} times as long',
        );
      }
    });

    test('scales with the length of what is pasted, not its square', () {
      // This is timed because the relevant cost is inside the regexp engine;
      // an 8x input separates linear growth from the former quadratic case.
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

      final small = _stableScanCost(paste(100));
      final large = _stableScanCost(paste(800));

      expect(
        large,
        lessThan(small * 25),
        reason: 'eight times the paste took ${large / small} times as long',
      );
    });
  });
}
