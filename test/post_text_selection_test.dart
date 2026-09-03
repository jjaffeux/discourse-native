import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
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
      rejects('<p>Same then same</p>', 'Same');
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

    testWidgets('keeps failed edits visible with their input', (tester) async {
      final api = FakeDiscourseApi(
        postsById: const {22: _editablePost},
        writeFailure: const WriteException(WriteFailure.conflict),
      );
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
    });

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
  SiteConfig config = const SiteConfig.unknown(),
}) async {
  final shell = await _shell(post: post, api: api, config: config);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark,
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
  SiteConfig config = const SiteConfig.unknown(),
}) async {
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
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
