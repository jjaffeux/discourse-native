import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_quote.dart';
import 'package:discourse_native/src/shell/post_text_selection.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _post = Post(
  id: 22,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Read selected words here</p>',
);
const _editablePost = Post(
  id: 22,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Read selected words here</p>',
  raw: 'Read selected words here',
  canEdit: true,
);
const _body = 'Read selected words here';
const _replacementUser = DiscourseUser(id: 99, username: 'replacement');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('post quote serialization', () {
    test('builds Discourse-compatible markup', () {
      expect(
        buildPostQuote(post: _post, topicId: 7, contents: '  selected words  '),
        '[quote="sam, post:2, topic:7"]\nselected words\n[/quote]\n\n',
      );
    });

    test('keeps a display name attributable to its username', () {
      const named = Post(
        id: 22,
        postNumber: 2,
        username: 'sam',
        name: 'Sam “Saffron”',
        cooked: '',
      );

      expect(
        buildPostQuote(post: named, topicId: 7, contents: 'hello'),
        '[quote="Sam Saffron, post:2, topic:7, username:sam"]\n'
        'hello\n[/quote]\n\n',
      );
    });
  });

  group('cooked selection reconstruction', () {
    test('restores paragraphs and inline formatting', () {
      expect(
        postQuoteContentsFromSelection(
          '<p>First <strong>bold</strong> thought.</p>'
              '<p>Second <em>formatted</em> line.<br>Still second.</p>',
          'First bold thought.Second formatted line.Still second.',
        ),
        'First **bold** thought.\n\n'
        'Second *formatted* line.\nStill second.',
      );
    });

    test('matches across newlines introduced between cooked blocks', () {
      // Cooked block separators are not part of Flutter's selection stream.
      expect(
        postQuoteContentsFromSelection(
          '<p>First <strong>bold</strong> thought.</p>\n'
              '<p>Second <em>formatted</em> line.</p>',
          'First bold thought.Second formatted line.',
        ),
        'First **bold** thought.\n\nSecond *formatted* line.',
      );
      expect(
        postQuoteContentsFromSelection(
          '<ul>\n<li>one</li>\n<li>two</li>\n</ul>',
          'onetwo',
        ),
        'one\n\ntwo',
      );
    });

    test('collapses whitespace the way the renderer draws it', () {
      expect(
        postQuoteContentsFromSelection('<p>hello\nworld</p>', 'hello world'),
        'hello world',
      );
      expect(
        postQuoteContentsFromSelection(
          '<p><strong>a</strong>\n<em>b</em></p>',
          'a b',
        ),
        '**a** *b*',
      );
    });

    test('preserves preformatted whitespace inside code blocks', () {
      // markdown-it recooks this as <pre><code> with the newline and two
      // indentation spaces intact. Inline ticks would flatten the newline.
      expect(
        postQuoteContentsFromSelection(
          '<pre><code>code\n  indented more</code></pre>',
          'code\n  indented more',
        ),
        '```\ncode\n  indented more\n```',
      );
    });

    test('round trips literal backticks and boundary spaces in inline code', () {
      // These delimiters recook to <p><code>selected</code></p> in Discourse's
      // markdown-it, with exactly the selected characters inside <code>.
      const selections = {
        'a`b': '``a`b``',
        'a``b': '```a``b```',
        '`left': '`` `left ``',
        'right`': '`` right` ``',
        '`edge`': '`` `edge` ``',
        '``': '``` `` ```',
        'a`b``c': '```a`b``c```',
        ' padded ': '`  padded  `',
        '  padded  ': '`   padded   `',
        ' left': '` left`',
        'right ': '`right `',
        'a  b': '`a  b`',
        'a\tb': '`a\tb`',
        ' ` ': '``  `  ``',
        '   ': '`     `',
      };
      for (final entry in selections.entries) {
        expect(
          postQuoteContentsFromSelection(
            '<p><code>${entry.key}</code></p>',
            entry.key,
          ),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('chooses code delimiters from each partial selection', () {
      final resolver = PostQuoteSelectionResolver(
        '<p>Before <code>start a`b ``edge`` end</code> after.</p>',
      );

      expect(resolver.contentsFor('a`b'), '``a`b``');
      expect(resolver.contentsFor('``edge``'), '``` ``edge`` ```');
      expect(resolver.contentsFor(' a`b '), '``  a`b  ``');
      expect(resolver.contentsFor('edge'), '`edge`');
      expect(
        postQuoteContentsFromSelection('<p><code>a   b</code></p>', ' '),
        '`   `',
      );
      expect(resolver.contentsFor('a`b'), '``a`b``');
      expect(resolver.resolve('a`b').supportsFastEdit, isFalse);
    });

    test('excludes code whitespace at selection edges from fast edit', () {
      final leading = PostQuoteSelectionResolver(
        '<p><code>prefix </code>word</p>',
      ).resolve(' word');
      expect(leading.markdown, '`   `word');
      expect(leading.supportsFastEdit, isFalse);

      final trailing = PostQuoteSelectionResolver(
        '<p>word<code> suffix</code></p>',
      ).resolve('word ');
      expect(trailing.markdown, 'word`   `');
      expect(trailing.supportsFastEdit, isFalse);
    });

    test('keeps code inline within selected prose and surrounding marks', () {
      expect(
        postQuoteContentsFromSelection(
          '<p>Before <strong><code>a`b</code></strong> and '
              '<a href="https://example.com"><code>`edge`</code></a> after.</p>',
          'Before a`b and `edge` after.',
        ),
        'Before **``a`b``** and [`` `edge` ``](https://example.com) after.',
      );
      expect(
        postQuoteContentsFromSelection(
          '<p>Before <code>start a`b end</code> after.</p>',
          'a`b end after.',
        ),
        '``a`b end`` after.',
      );
    });

    test('keeps prose backticks from consuming reconstructed inline code', () {
      expect(
        postQuoteContentsFromSelection(
          '<p>`before <code>a`b</code> after`</p>',
          '`before a`b after`',
        ),
        r'\`before ``a`b`` after\`',
      );
      expect(
        postQuoteContentsFromSelection('<p>`plain`</p>', '`plain`'),
        '`plain`',
      );
    });

    test('preserves odd and even prose backslash runs around code', () {
      for (var count = 1; count <= 4; count++) {
        final slashes = List.filled(count, r'\').join();
        final escapedSlashes = List.filled(count, r'\\').join();
        final resolver = PostQuoteSelectionResolver(
          '<p>$slashes`before <code>a`b</code> after$slashes`</p>',
        );

        final result = resolver.resolve('$slashes`before a`b after$slashes`');

        // Each literal slash needs its own escape, leaving the prose ticks
        // escaped and the generated code delimiters active in markdown-it.
        expect(
          result.markdown,
          '$escapedSlashes\\`before ``a`b`` after$escapedSlashes\\`',
          reason: '$count prose backslashes',
        );
        expect(result.supportsFastEdit, isFalse);
      }
    });

    test('preserves prose backslashes directly beside code delimiters', () {
      const codeSelections = {
        'plain': '`plain`',
        'a`b': '``a`b``',
        '`edge`': '`` `edge` ``',
        r'\a\`b\\': r'``\a\`b\\``',
      };
      for (var count = 1; count <= 4; count++) {
        final slashes = List.filled(count, r'\').join();
        final escapedSlashes = List.filled(count, r'\\').join();
        for (final code in codeSelections.entries) {
          expect(
            postQuoteContentsFromSelection(
              '<p>before$slashes<code>${code.key}</code>${slashes}after</p>',
              'before$slashes${code.key}${slashes}after',
            ),
            'before$escapedSlashes${code.value}${escapedSlashes}after',
            reason: '$count prose backslashes beside ${code.key}',
          );
        }
      }
    });

    test('escapes prose backslashes across surrounding mark boundaries', () {
      final resolver = PostQuoteSelectionResolver(
        r'<p>before\<strong>bold\<code>a`b</code>end\</strong>'
        r' <em>em\`<code>`edge`</code>\tail</em>'
        r' <a href="https://example.com">link\<code>x</code>\</a> after\</p>',
      );
      expect(
        resolver.contentsFor(
          r'before\bold\a`bend\ em\``edge`\tail link\x\ after\',
        ),
        r'before\\**bold\\``a`b``end\\**'
        r' *em\\\``` `edge` ``\\tail*'
        r' [link\\`x`\\](https://example.com) after\\',
      );
      expect(resolver.contentsFor(r'ld\a`be'), r'**ld\\``a`b``e**');
      expect(
        resolver.contentsFor(r'`edge`\tail link\x'),
        r'*`` `edge` ``\\tail* [link\\`x`](https://example.com)',
      );
    });

    test('scopes backslash escaping to the current cached selection', () {
      const before = r'before\` ';
      const code = r'a\`b\\';
      const after = r' after\\`';
      final resolver = PostQuoteSelectionResolver(
        '<p>$before<code>$code</code>$after</p>',
      );

      for (var repeat = 0; repeat < 2; repeat++) {
        expect(
          resolver.contentsFor('$before$code$after'),
          r'before\\\` ``a\`b\\`` after\\\\\`',
        );
        expect(resolver.contentsFor(r'\` a\'), r'\\\` `a\`');
        expect(resolver.contentsFor(r'b\\ after\\'), r'`b\\` after\\\\');
        expect(resolver.contentsFor(code), r'``a\`b\\``');
        expect(resolver.resolve(code).supportsFastEdit, isFalse);

        for (final prose in [before, after]) {
          final result = resolver.resolve(prose);
          expect(result.markdown, prose.trim());
          expect(result.supportsFastEdit, isTrue);
          expect(
            resolver.resolve(prose, isLocalized: true).supportsFastEdit,
            isFalse,
          );
        }
      }
      expect(
        postQuoteContentsFromSelection('<p>$before$after</p>', '$before$after'),
        '$before$after'.trim(),
      );
    });

    test(
      'keeps adjacent code spans from joining their backtick delimiters',
      () {
        expect(
          postQuoteContentsFromSelection(
            '<p>Before <code>a`</code><code>`b</code> after.</p>',
            'Before a``b after.',
          ),
          'Before ```a``b``` after.',
        );
        expect(
          postQuoteContentsFromSelection(
            '<p><strong><code>a`</code></strong>'
                '<strong><code>`b</code></strong></p>',
            'a``b',
          ),
          '**```a``b```**',
        );
      },
    );

    test('retains preformatted selection edges and embedded fences', () {
      // A fenced block recooks with a final newline, including when the
      // selection ends mid-line. Existing final newlines must not be doubled.
      const selections = {
        '  first\n\tsecond  ': '```\n  first\n\tsecond  \n```',
        '\n  first\n\n': '```\n\n  first\n\n```',
        'first\n```\n  last': '````\nfirst\n```\n  last\n````',
        'first\n````\n~~~\nlast\n': '`````\nfirst\n````\n~~~\nlast\n`````',
      };
      for (final entry in selections.entries) {
        expect(
          postQuoteContentsFromSelection(
            '<pre><code>${entry.key}</code></pre>',
            entry.key,
          ),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('keeps partial and mixed selections from a pre block fenced', () {
      final resolver = PostQuoteSelectionResolver(
        '<p>Before.</p><pre><code>first\n  second\nlast</code></pre>'
        '<p>After <code>a`b</code>.</p>',
      );

      expect(resolver.contentsFor('  second'), '```\n  second\n```');
      expect(resolver.contentsFor('second\nla'), '```\nsecond\nla\n```');
      expect(
        resolver.contentsFor('Before.first\n  second\nlastAfter a`b.'),
        'Before.\n\n```\nfirst\n  second\nlast\n```\n\nAfter ``a`b``.',
      );
      expect(
        resolver.contentsFor('second\nlastAfter a`b.'),
        '```\nsecond\nlast\n```\n\nAfter ``a`b``.',
      );
      expect(resolver.resolve('second').supportsFastEdit, isFalse);
    });

    test('restores deeply nested formatting without recursion', () {
      const depth = 1000;
      final cooked =
          '${List.filled(depth, '<strong>').join()}'
          'selected'
          '${List.filled(depth, '</strong>').join()}';

      final contents = postQuoteContentsFromSelection(cooked, 'selected');

      expect(
        contents,
        '${List.filled(depth, '**').join()}selected'
        '${List.filled(depth, '**').join()}',
      );
    });

    test('reuses one resolver across repeated selections', () {
      final resolver = PostQuoteSelectionResolver(
        '<p>First <strong>bold</strong> thought.</p>'
        '<p>Second <em>formatted</em> line.</p>',
      );

      expect(resolver.contentsFor('bold'), '**bold**');
      expect(
        resolver.contentsFor('First bold thought.Second formatted line.'),
        'First **bold** thought.\n\nSecond *formatted* line.',
      );
      expect(resolver.contentsFor('missing selection'), 'missing selection');
    });

    test('marks unique plain selections as safe for fast edit', () {
      for (final value in ['désolé', '这是一个测试', 'great 👍']) {
        final result = PostQuoteSelectionResolver(
          '<p>Before $value after</p>',
        ).resolve(value);

        expect(result.markdown, value);
        expect(result.supportsFastEdit, isTrue, reason: value);
      }
    });

    test('rejects ambiguous or structurally complex fast edits', () {
      void rejects(String cooked, String selected, {bool localized = false}) {
        expect(
          PostQuoteSelectionResolver(
            cooked,
          ).resolve(selected, isLocalized: localized).supportsFastEdit,
          isFalse,
          reason: cooked,
        );
      }

      rejects('<p>same then same</p>', 'same');
      rejects('<p>same then same</p>', ' same ');
      rejects('<p>Same then same</p>', 'Same');
      rejects('<p><code>a`b</code> then a`b</p>', 'a`b');
      rejects('<p>first</p><p>second</p>', 'firstsecond');
      rejects('<p><strong>bold</strong></p>', 'bold');
      rejects('<aside class="quote">quoted</aside>', 'quoted');
      rejects('<aside class="onebox">preview</aside>', 'preview');
      rejects('<span class="cooked-date">tomorrow</span>', 'tomorrow');
      rejects('<table><tr><td>cell</td></tr></table>', 'cell');
      rejects('<p>left | right</p>', 'left | right');
      rejects('<p>That’s right</p>', 'That’s');
      rejects('<p>translated</p>', 'translated', localized: true);
    });

    test('rejects oversized selections without building an input regex', () {
      final selected = List.filled(20000, 'a').join();
      final result = PostQuoteSelectionResolver(
        '<p>$selected</p>',
      ).resolve(selected);

      expect(result.markdown, selected);
      expect(result.supportsFastEdit, isFalse);
    });
  });

  group('selection actions', () {
    testWidgets('copy portable markup for a pointer selection', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final shell = await _pumpSelection(tester, withToaster: true);
      addTearDown(shell.dispose);
      await _selectWord(tester);

      expect(find.byKey(const ValueKey('quote-selection')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('copy-quote-selection')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('copy-quote-selection')));
      await tester.pumpAndSettle();

      expect(
        clipboard,
        '[quote="sam, post:2, topic:7"]\nselected\n[/quote]\n\n',
      );
      expect(find.text('Quote copied to clipboard.'), findsOneWidget);
    });

    testWidgets('preserve Markdown structure across cooked blocks', (
      tester,
    ) async {
      const cookedPost = Post(
        id: 23,
        postNumber: 3,
        username: 'sam',
        cooked:
            '<p>First <strong>bold</strong> thought.</p>'
            '<p>Second <em>formatted</em> <code>a`b</code> line.</p>',
      );
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final shell = await _pumpSelection(
        tester,
        post: cookedPost,
        child: CookedHtml(html: cookedPost.cooked),
      );
      addTearDown(shell.dispose);
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectAll(SelectionChangedCause.toolbar);
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('copy-quote-selection')));
      await tester.pumpAndSettle();

      expect(
        clipboard,
        '[quote="sam, post:3, topic:7"]\n'
        'First **bold** thought.\n\nSecond *formatted* ``a`b`` line.\n'
        '[/quote]\n\n',
      );
    });

    testWidgets('open the quote toolbar from a touch long press', (
      tester,
    ) async {
      final shell = await _pumpSelection(tester);
      addTearDown(shell.dispose);

      await tester.longPress(find.text(_body));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quote-selection')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('copy-quote-selection')),
        findsOneWidget,
      );
    });

    testWidgets('open a reply with the selected block', (tester) async {
      final shell = await _pumpSelection(tester);
      addTearDown(shell.dispose);
      await _selectWord(tester);

      await tester.tap(find.byKey(const ValueKey('quote-selection')));
      await tester.pumpAndSettle();

      expect(
        shell.visibleComposer?.raw,
        '[quote="sam, post:2, topic:7"]\nselected\n[/quote]',
      );
      expect(shell.visibleComposer?.target.replyToPostNumber, 2);
      expect(shell.visibleComposer?.target.replyToUsername, 'sam');

      // Closing cancels the draft debounce started by inserting the quote.
      shell.closeComposer();
      await tester.pump();
    });

    testWidgets('offers compact edit only with the setting and permission', (
      tester,
    ) async {
      final api = FakeDiscourseApi(postsById: const {22: _editablePost});
      final shell = await _pumpSelection(tester, post: _editablePost, api: api);
      addTearDown(shell.dispose);
      await _selectWord(tester);

      expect(find.byKey(const ValueKey('edit-selection')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edit-selection')));
      await tester.pumpAndSettle();

      final input = find.byKey(const ValueKey('fast-edit-input'));
      expect(input, findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, 'selected');

      // The unchanged value cannot be submitted.
      await tester.tap(find.byKey(const ValueKey('fast-edit-save')));
      await tester.pump();
      expect(api.updated, isEmpty);

      await tester.enterText(input, 'changed');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fast-edit-save')));
      await tester.pumpAndSettle();

      expect(input, findsNothing);
      expect(api.postFetchIncludesRaw, [isTrue]);
      expect(api.updated.single['raw'], 'Read changed words here');
      expect(api.updated.single['originalText'], 'Read selected words here');
    });

    testWidgets('allows deleting a selected passage', (tester) async {
      final api = FakeDiscourseApi(postsById: const {22: _editablePost});
      final shell = await _pumpSelection(tester, post: _editablePost, api: api);
      addTearDown(shell.dispose);
      await _selectWord(tester);
      await tester.tap(find.byKey(const ValueKey('edit-selection')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('fast-edit-input')), '');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fast-edit-save')));
      await tester.pumpAndSettle();

      expect(api.updated.single['raw'], 'Read  words here');
    });

    for (final disconnect in [false, true]) {
      for (final retry in [false, true]) {
        testWidgets(
          'compact edit ${retry ? 'retry' : 'save'} refuses the opening account '
          'after ${disconnect ? 'disconnect and reconnect' : 'replacement'}',
          (tester) async {
            final api = _FastEditApi();
            final auth = _CountingAuthenticator();
            final shell = await _pumpSelection(
              tester,
              post: _editablePost,
              api: api,
              authenticator: auth,
            );
            addTearDown(shell.dispose);
            await _openFastEditor(tester);
            final input = find.byKey(const ValueKey('fast-edit-input'));
            final text = tester.widget<TextField>(input).controller!;
            await tester.enterText(input, 'my replacement');
            if (retry) {
              api.nextWriteFailure = const WriteException(
                WriteFailure.conflict,
              );
              await _saveFastEdit(tester);
              expect(
                find.text('Someone else changed that first.'),
                findsOneWidget,
              );
              expect(api.editKeys, ['api-key']);
            }

            if (disconnect) await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
            await tester.pumpAndSettle();
            expect(shell.currentInstance?.user, _replacementUser);
            expect(auth.keys[_siteUrl], 'replacement-key');
            expect(shell.store.read<Post>(_siteUrl, _editablePost.id), isNull);
            _showTopic(shell, _editablePost);
            await tester.pumpAndSettle();

            // Restore every eligibility check that would otherwise mask an
            // old sheet using the replacement account's credentials.
            expect(shell.currentContent?.topicId, 7);
            expect(shell.currentTopic?.stream, contains(_editablePost.id));
            expect(shell.store.read<Post>(_siteUrl, 22)?.canEdit, isTrue);
            expect(shell.siteConfigFor(_siteUrl).fastEditEnabled, isTrue);
            expect(tester.widget<TextField>(input).controller, same(text));
            final keyReads = auth.keyReads;
            final clientReads = auth.clientReads;
            final fetches = api.postFetches.length;
            final writes = api.updated.length;

            await _saveFastEdit(tester);

            expect(api.editKeys, retry ? ['api-key'] : isEmpty);
            expect(auth.keyReads, keyReads);
            expect(auth.clientReads, clientReads);
            expect(api.postFetches, hasLength(fetches));
            expect(api.updated, hasLength(writes));
            expect(shell.store.read<Post>(_siteUrl, 22), same(_editablePost));
            expect(shell.postWriteInFlight(22), isFalse);
            expect(input, findsOneWidget);
            expect(text.text, 'my replacement');
            expect(tester.widget<TextField>(input).enabled, isTrue);
            expect(
              find.text('The topic changed before the edit could be saved.'),
              findsOneWidget,
            );

            await tester.tap(find.byKey(const ValueKey('fast-edit-cancel')));
            await tester.pumpAndSettle();
            await _openFastEditor(tester);
            await tester.enterText(input, 'fresh replacement');
            await _saveFastEdit(tester);

            expect(api.editKeys.last, 'replacement-key');
            expect(
              api.updated.last['raw'],
              'Read fresh replacement words here',
            );
            expect(input, findsNothing);
          },
        );
      }
    }

    testWidgets('keeps failed edits visible and retries their input', (
      tester,
    ) async {
      final api = _FastEditApi()
        ..nextWriteFailure = const WriteException(WriteFailure.conflict);
      final shell = await _pumpSelection(tester, post: _editablePost, api: api);
      addTearDown(shell.dispose);
      await _selectWord(tester);
      await tester.tap(find.byKey(const ValueKey('edit-selection')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('fast-edit-input'));
      await tester.enterText(input, 'my replacement');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fast-edit-save')));
      await tester.pumpAndSettle();

      expect(input, findsOneWidget);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'my replacement',
      );
      expect(find.byKey(const ValueKey('fast-edit-error')), findsOneWidget);
      expect(find.text('Someone else changed that first.'), findsOneWidget);

      await _saveFastEdit(tester);

      expect(api.editKeys, ['api-key', 'api-key']);
      expect(api.updated.last['raw'], 'Read my replacement words here');
      expect(input, findsNothing);
    });

    testWidgets(
      'can retry after returning to the topic under the same account',
      (tester) async {
        final api = _FastEditApi();
        final auth = _CountingAuthenticator();
        final shell = await _pumpSelection(
          tester,
          post: _editablePost,
          api: api,
          authenticator: auth,
        );
        addTearDown(shell.dispose);
        await _openFastEditor(tester);
        final input = find.byKey(const ValueKey('fast-edit-input'));
        await tester.enterText(input, 'my replacement');
        final openingRoute = shell.currentContent!;
        shell.replaceCurrentContent(
          ContentRoute.topic(topicId: 8, slug: 'other', title: 'Other'),
        );
        await tester.pumpAndSettle();
        final keyReads = auth.keyReads;

        await _saveFastEdit(tester);

        expect(find.text('This post can no longer be edited.'), findsOneWidget);
        expect(auth.keyReads, keyReads);
        expect(api.editKeys, isEmpty);
        expect(
          tester.widget<TextField>(input).controller!.text,
          'my replacement',
        );

        shell.replaceCurrentContent(openingRoute);
        await tester.enterText(input, 'revised replacement');
        await tester.pump();
        expect(find.byKey(const ValueKey('fast-edit-error')), findsNothing);
        await _saveFastEdit(tester);

        expect(api.editKeys, ['api-key']);
        expect(
          api.updated.single['raw'],
          'Read revised replacement words here',
        );
        expect(input, findsNothing);
      },
    );

    for (final fails in [false, true]) {
      testWidgets(
        'reports the retired account after an in-flight ${fails ? 'failure' : 'success'}',
        (tester) async {
          final gate = Completer<void>();
          final api = _FastEditApi(updatePostGate: gate);
          if (fails) {
            api.nextWriteFailure = const WriteException(WriteFailure.conflict);
          }
          final shell = await _pumpSelection(
            tester,
            post: _editablePost,
            api: api,
            authenticator: _CountingAuthenticator(),
          );
          addTearDown(shell.dispose);
          await _openFastEditor(tester);
          final input = find.byKey(const ValueKey('fast-edit-input'));
          await tester.enterText(input, 'my replacement');
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('fast-edit-save')));
          await tester.pump();
          expect(api.editKeys, ['api-key']);

          await shell.connectCurrentInstance();
          await tester.pump();
          _showTopic(shell, _editablePost);
          expect(shell.currentInstance?.user, _replacementUser);
          gate.complete();
          await tester.pumpAndSettle();

          expect(input, findsOneWidget);
          expect(tester.widget<TextField>(input).enabled, isTrue);
          expect(
            tester.widget<TextField>(input).controller!.text,
            'my replacement',
          );
          expect(
            find.text('The topic changed before the edit could be saved.'),
            findsOneWidget,
          );
          expect(shell.store.read<Post>(_siteUrl, 22), same(_editablePost));
          await _saveFastEdit(tester);
          expect(api.editKeys, ['api-key']);
          expect(shell.postWriteInFlight(22), isFalse);
        },
      );
    }

    testWidgets('disables editing while a save is in flight', (tester) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        postsById: const {22: _editablePost},
        postGate: gate,
      );
      final shell = await _pumpSelection(tester, post: _editablePost, api: api);
      addTearDown(shell.dispose);
      await _selectWord(tester);
      await tester.tap(find.byKey(const ValueKey('edit-selection')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('fast-edit-input'));
      await tester.enterText(input, 'changed');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fast-edit-save')));
      await tester.pump();

      expect(tester.widget<TextField>(input).enabled, isFalse);
      expect(find.text('Saving…'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(input, findsNothing);
    });

    testWidgets('hides edit when disabled or the post is not editable', (
      tester,
    ) async {
      final disabledShell = await _pumpSelection(
        tester,
        post: _editablePost,
        config: const SiteConfig(fastEditEnabled: false),
      );
      await _selectWord(tester);
      expect(find.byKey(const ValueKey('edit-selection')), findsNothing);
      disabledShell.dispose();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final deniedShell = await _pumpSelection(tester);
      addTearDown(deniedShell.dispose);
      await _selectWord(tester);
      expect(find.byKey(const ValueKey('edit-selection')), findsNothing);
    });

    testWidgets('falls back to the full composer for formatted text', (
      tester,
    ) async {
      const formattedPost = Post(
        id: 22,
        postNumber: 2,
        username: 'sam',
        cooked: '<p>Read <strong>selected</strong> words here</p>',
        raw: 'Read **selected** words here',
        canEdit: true,
      );
      final shell = await _pumpSelection(tester, post: formattedPost);
      addTearDown(shell.dispose);
      await _selectWord(tester);
      await tester.tap(find.byKey(const ValueKey('edit-selection')));
      await tester.pump();

      expect(find.byKey(const ValueKey('fast-edit-input')), findsNothing);
      expect(shell.visibleComposer?.target.isEdit, isTrue);
      expect(shell.visibleComposer?.raw, formattedPost.raw);
    });

    testWidgets('supports E to open and Escape to cancel', (tester) async {
      final shell = await _pumpSelection(tester, post: _editablePost);
      addTearDown(shell.dispose);
      await _selectWord(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fast-edit-input')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fast-edit-input')), findsNothing);
    });

    testWidgets('supports Ctrl+Enter to save', (tester) async {
      final api = FakeDiscourseApi(postsById: const {22: _editablePost});
      final shell = await _pumpSelection(tester, post: _editablePost, api: api);
      addTearDown(shell.dispose);
      await _selectWord(tester);
      await tester.tap(find.byKey(const ValueKey('edit-selection')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fast-edit-input')),
        'changed',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(api.updated.single['raw'], 'Read changed words here');
      expect(find.byKey(const ValueKey('fast-edit-input')), findsNothing);
    });
  });

  group('quote composer integration', () {
    test('restores an unfinished draft before appending', () async {
      final drafts = FakeDraftStore();
      drafts.saved['$_siteUrl::topic_7'] = const ComposerDraft(
        reply: 'Existing draft',
      ).encode();
      final shell = await _shell(drafts: drafts);
      addTearDown(shell.dispose);

      await shell.openQuote(
        _post,
        buildPostQuote(post: _post, topicId: 7, contents: 'selected'),
      );

      expect(
        shell.visibleComposer?.raw,
        'Existing draft\n\n'
        '[quote="sam, post:2, topic:7"]\nselected\n[/quote]',
      );
    });
  });
}

Future<ShellController> _pumpSelection(
  WidgetTester tester, {
  Post post = _post,
  Widget child = const Text(_body),
  FakeDiscourseApi? api,
  FakeAuthenticator? authenticator,
  SiteConfig config = const SiteConfig.unknown(),
  bool withToaster = false,
}) async {
  final shell = await _shell(
    post: post,
    api: api,
    authenticator: authenticator,
    config: config,
  );
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark,
        builder: withToaster
            ? (context, child) => DToaster(child: child!)
            : null,
        home: Scaffold(
          body: Center(
            child: PostTextSelection(
              siteUrl: _siteUrl,
              post: post,
              topicId: 7,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

Future<ShellController> _shell({
  FakeDraftStore? drafts,
  Post post = _post,
  FakeDiscourseApi? api,
  FakeAuthenticator? authenticator,
  SiteConfig config = const SiteConfig.unknown(),
}) async {
  authenticator ??= FakeAuthenticator();
  authenticator.keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(config: config),
    ]),
    api: api ?? FakeDiscourseApi(),
    authenticator: authenticator,
    drafts: drafts ?? FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  _showTopic(shell, post);
  return shell;
}

void _showTopic(ShellController shell, Post post) {
  shell.store.put(
    _siteUrl,
    TopicDetail(
      id: 7,
      title: 'A topic',
      stream: [post.id],
      canCreatePost: true,
    ),
  );
  shell.store.put(_siteUrl, post);
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
}

Future<void> _openFastEditor(WidgetTester tester) async {
  await _selectWord(tester);
  await tester.tap(find.byKey(const ValueKey('edit-selection')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('fast-edit-input')), findsOneWidget);
}

Future<void> _saveFastEdit(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('fast-edit-save')));
  await tester.pumpAndSettle();
}

Future<void> _selectWord(WidgetTester tester) async {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(_body), matching: find.byType(RichText)),
  );

  Offset positionAt(int offset) {
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        )
        .single;
    return paragraph.localToGlobal(
      Offset(box.left + 0.5, (box.top + box.bottom) / 2),
    );
  }

  final gesture = await tester.startGesture(
    positionAt(5),
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(positionAt(13));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 151));
  await tester.pump();
}

class _CountingAuthenticator extends FakeAuthenticator {
  _CountingAuthenticator()
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );

  var keyReads = 0;
  var clientReads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    keyReads++;
    return super.apiKeyFor(siteUrl);
  }

  @override
  Future<String> clientId() {
    clientReads++;
    return super.clientId();
  }
}

class _FastEditApi extends FakeDiscourseApi {
  _FastEditApi({super.updatePostGate})
    : super(postsById: const {22: _editablePost});

  final editKeys = <String>[];
  WriteException? nextWriteFailure;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == 'replacement-key'
      ? _replacementUser
      : await super.currentUser(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
        );

  @override
  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  }) async {
    editKeys.add(apiKey);
    final failure = nextWriteFailure;
    nextWriteFailure = null;
    final updated = await super.updatePost(
      siteUrl: siteUrl,
      apiKey: apiKey,
      postId: postId,
      raw: raw,
      originalText: originalText,
      editReason: editReason,
      clientId: clientId,
    );
    if (failure != null) throw failure;
    return updated;
  }
}
