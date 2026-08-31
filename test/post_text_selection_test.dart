import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
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
const _body = 'Read selected words here';

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
      // Real cooked HTML separates blocks with `\n` text nodes the renderer
      // never draws. The selection stream carries no such character, so the
      // index must not either.
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
      // A soft line break inside a paragraph renders as a single space.
      expect(
        postQuoteContentsFromSelection('<p>hello\nworld</p>', 'hello world'),
        'hello world',
      );
      // Whitespace between inline elements is drawn, so it stays indexed.
      expect(
        postQuoteContentsFromSelection(
          '<p><strong>a</strong>\n<em>b</em></p>',
          'a b',
        ),
        '**a** *b*',
      );
    });

    test('preserves preformatted whitespace inside code blocks', () {
      expect(
        postQuoteContentsFromSelection(
          '<pre><code>code\n  indented more</code></pre>',
          'code\n  indented more',
        ),
        '`code\n  indented more`',
      );
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

      final shell = await _pumpSelection(tester);
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
            '<p>Second <em>formatted</em> line.</p>',
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
        'First **bold** thought.\n\nSecond *formatted* line.\n'
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
}) async {
  final shell = await _shell();
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: PostTextSelection(post: post, topicId: 7, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

Future<ShellController> _shell({FakeDraftStore? drafts}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: drafts ?? FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  shell.store.put(
    _siteUrl,
    const TopicDetail(
      id: 7,
      title: 'A topic',
      stream: [22],
      canCreatePost: true,
    ),
  );
  shell.store.put(_siteUrl, _post);
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  return shell;
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
