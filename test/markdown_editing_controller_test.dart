import 'dart:convert';
import 'dart:typed_data';

import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/composer_pills.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/syntax.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The composer draws markdown but posts it unchanged, and the two are the same
/// string. Everything Flutter does with an editable — placing the caret, hit
/// testing a tap, select-all, the clipboard — reads offsets into the laid-out
/// paragraph and hands them back as offsets into `controller.text`. Nothing
/// checks that those agree, so the tests that matter here are the ones that do.
void main() {
  late MarkdownEditingController controller;

  Future<void> pumpField(
    WidgetTester tester,
    String source, {
    String Function(String)? resolveEmoji,
    ComposerPills? pills,
  }) async {
    controller = MarkdownEditingController(
      text: source,
      resolveEmoji: resolveEmoji,
      pills: pills,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: TextField(controller: controller, maxLines: null),
          ),
        ),
      ),
    );
  }

  EditableTextState editable(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText));

  TextSpan painted(WidgetTester tester) =>
      editable(tester).renderEditable.text! as TextSpan;

  group('the painted text is the source', () {
    for (final source in const [
      'say **hello** to @sam',
      'a :smile: and `code` and <kbd>Esc</kbd>',
      '# Heading\n\n> quoted **bold**\n\n```ruby\nputs 1\n```',
      'plain',
    ]) {
      testWidgets(source.split('\n').first, (tester) async {
        await pumpField(tester, source);

        // Character for character. A WidgetSpan anywhere in the tree would
        // break this — a placeholder is worth exactly one code unit however
        // wide it draws — and every offset after it would mean two things.
        expect(
          painted(tester).toPlainText(includeSemanticsLabels: false),
          source,
        );
        expect(controller.text, source);
      });
    }
  });

  testWidgets('a tap lands on the character under it', (tester) async {
    const source = 'say **hello** to @sam';
    await pumpField(tester, source);

    final render = editable(tester).renderEditable;
    // A round trip rather than a pixel: where the caret is drawn for an offset
    // has to be where a tap at that spot puts the caret back.
    for (final offset in [0, 5, 9, 13, 18, source.length]) {
      final rect = render.getLocalRectForCaret(TextPosition(offset: offset));
      expect(
        render.getPositionForPoint(render.localToGlobal(rect.center)).offset,
        offset,
        reason: 'the caret at $offset does not come back as $offset',
      );
    }
  });

  testWidgets('the paragraph the caret is measured against is the text', (
    tester,
  ) async {
    const source = 'say **hello** to @sam';
    await pumpField(tester, source);

    // `RenderEditable.plainText` is what select-all, word boundaries and
    // `getPositionForPoint` are all computed from, and it is the flattened
    // span tree rather than the field's string. Where those two disagree,
    // Flutter neither asserts nor converts — it quietly means one by the
    // other.
    expect(editable(tester).renderEditable.plainText, source);
  });

  testWidgets('moving the caret does not read the source again', (
    tester,
  ) async {
    await pumpField(tester, 'say **hello** to @sam');
    final after = controller.scans;

    for (var offset = 0; offset < 8; offset++) {
      controller.selection = TextSelection.collapsed(offset: offset);
      await tester.pump();
    }

    // Scanning tokenizes fenced blocks, which `syntax.dart` documents as
    // expensive enough to drop frames. None of it depends on the caret.
    expect(controller.scans, after);
  });

  testWidgets('typing does read it again', (tester) async {
    await pumpField(tester, 'say');
    final before = controller.scans;

    controller.value = const TextEditingValue(
      text: 'say **hi**',
      selection: TextSelection.collapsed(offset: 10),
    );
    await tester.pump();

    expect(controller.scans, greaterThan(before));
  });

  /// The style the character at [offset] is painted with.
  TextStyle styleAt(WidgetTester tester, String source, int offset) {
    var at = 0;
    TextStyle? found;
    painted(tester).visitChildren((span) {
      final text = (span as TextSpan).text ?? '';
      if (offset >= at && offset < at + text.length) {
        found = span.style;
        return false;
      }
      at += text.length;
      return true;
    });
    return found!;
  }

  group('what gets drawn', () {
    testWidgets('bold text is bold and its markers are dimmed', (tester) async {
      const source = 'say **hello** now';
      await pumpField(tester, source);

      final theme = AppTheme.dark;
      expect(styleAt(tester, source, 6).fontWeight, FontWeight.w700);
      expect(styleAt(tester, source, 4).color, theme.shell.marker);
    });

    testWidgets('a mention takes the accent colour', (tester) async {
      const source = 'hey @sam';
      await pumpField(tester, source);

      expect(
        styleAt(tester, source, 5).color,
        AppTheme.dark.colorScheme.primary,
      );
    });

    testWidgets('inline and fenced code use Discourse code face', (
      tester,
    ) async {
      const source = '`inline`\n\n```ruby\nputs 1\n```';
      await pumpField(tester, source);

      for (final offset in [source.indexOf('inline'), source.indexOf('puts')]) {
        final style = styleAt(tester, source, offset);
        expect(style.fontFamily, monospaceFontFamily);
        expect(style.fontFamilyFallback, monospaceFallback);
        expect(style.fontFeatures, contains(const FontFeature.disable('liga')));
      }
    });

    testWidgets('nothing but <ins> is underlined', (tester) async {
      // Underline in an editable means "the IME has not committed this yet".
      // A link or a heading borrowing it would be lying about the text.
      const source = 'see [a](https://b.c) and **d** and `e`';
      await pumpField(tester, source);

      painted(tester).visitChildren((span) {
        expect(
          (span as TextSpan).style?.decoration,
          isNot(TextDecoration.underline),
        );
        return true;
      });
    });
  });

  group('deferred fence highlighting', () {
    setUp(clearSyntaxHighlightCacheForTesting);

    final largeBody = List.generate(
      40,
      (i) => 'final value$i = "line $i";',
    ).join('\n');
    final largeSource = '```dart\n$largeBody\n```';

    testWidgets('a small fence is highlighted on the frame it is scanned', (
      tester,
    ) async {
      const source = '```dart\nfinal x = 1;\n```';
      await pumpField(tester, source);

      // No debounce to pump past: a small fence must never flash plain.
      expect(
        styleAt(tester, source, source.indexOf('final')).color,
        AppTheme.dark.code.keyword,
      );
    });

    testWidgets('typing in a large fence paints plain now, colour later', (
      tester,
    ) async {
      await pumpField(tester, largeSource);
      await tester.pump(MarkdownEditingController.fenceHighlightDebounce);
      await tester.pump();

      final keyword = largeSource.indexOf('final value7');
      expect(
        styleAt(tester, largeSource, keyword).color,
        AppTheme.dark.code.keyword,
      );

      // A keystroke inside the fence. The frame it causes must not pay for a
      // parse of the whole body, so the fence drops to plain code styling —
      // monospace and the code block's default foreground, never bare prose.
      final edited = largeSource.replaceFirst('line 7', 'line 07');
      controller.value = TextEditingValue(
        text: edited,
        selection: TextSelection.collapsed(offset: edited.indexOf('07') + 1),
      );
      await tester.pump();

      final plain = styleAt(tester, edited, keyword);
      expect(plain.fontFamily, monospaceFontFamily);
      expect(plain.color, AppTheme.dark.colorScheme.onSurface);

      // Once the body has held still for the debounce, the highlighted spans
      // are back: the final state is always the fully coloured one.
      await tester.pump(MarkdownEditingController.fenceHighlightDebounce);
      await tester.pump();

      expect(
        styleAt(tester, edited, keyword).color,
        AppTheme.dark.code.keyword,
      );
    });

    testWidgets('more fences than the cache holds still settles', (
      tester,
    ) async {
      // The highlight cache is process-wide and bounded, so a document with
      // more large fences than it holds evicts its own earlier entries. The
      // rescan after a parse round then finds them uncached; re-deferring
      // those would restart the timer forever on an idle composer.
      final crowded = [
        for (var fence = 0; fence < syntaxHighlightCacheCapacity + 8; fence++)
          '```dart\n${List.generate(60, (line) => 'final v$fence$line = $line;').join('\n')}\n```',
      ].join('\n\n');

      await pumpField(tester, crowded);

      // Settle: each round may only parse bodies it has not parsed before, so
      // the deferred set shrinks to nothing instead of cycling. Teardown is
      // the assertion — flutter_test fails a test that leaves a Timer pending,
      // which a cycling debounce always does.
      for (var round = 0; round < 6; round++) {
        await tester.pump(MarkdownEditingController.fenceHighlightDebounce);
        await tester.pump();
      }

      // Settling is not the same as giving up: the fences the cache did keep
      // are still coloured.
      final keyword = crowded.lastIndexOf('final v');
      expect(
        styleAt(tester, crowded, keyword).color,
        AppTheme.dark.code.keyword,
      );
    });

    testWidgets('disposal cancels the pending tokenization', (tester) async {
      final local = MarkdownEditingController(text: largeSource);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: TextField(controller: local, maxLines: null),
            ),
          ),
        ),
      );

      // The debounce is pending now. Take the field down and dispose mid-wait
      // — the test harness fails on any timer still pending when this ends.
      await tester.pumpWidget(const SizedBox());
      local.dispose();
    });
  });

  testWidgets('the composing range keeps its underline', (tester) async {
    const source = 'say hello';
    await pumpField(tester, source);
    // `withComposing` is `!readOnly && _hasFocus`, so an unfocused field is
    // never told about a composing range at all.
    await tester.tap(find.byType(TextField));
    await tester.pump();

    controller.value = const TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: 9),
      composing: TextRange(start: 4, end: 9),
    );
    await tester.pump();

    // Still the same string, and the IME's own indicator survived being
    // drawn over syntax highlighting.
    final span = painted(tester);
    expect(span.toPlainText(includeSemanticsLabels: false), source);

    final underlined = <String>[];
    span.visitChildren((child) {
      final text = child as TextSpan;
      if (text.style?.decoration == TextDecoration.underline) {
        underlined.add(text.text ?? '');
      }
      return true;
    });
    expect(underlined.join(), 'hello');
  });

  testWidgets('a struck-through composing range keeps both', (tester) async {
    const source = '~~gone~~';
    await pumpField(tester, source);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    controller.value = const TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: 8),
      composing: TextRange(start: 2, end: 6),
    );
    await tester.pump();

    final decorations = <TextDecoration?>[];
    painted(tester).visitChildren((child) {
      decorations.add((child as TextSpan).style?.decoration);
      return true;
    });
    expect(
      decorations.any(
        (d) =>
            d != null &&
            d.contains(TextDecoration.underline) &&
            d.contains(TextDecoration.lineThrough),
      ),
      isTrue,
      reason: 'the underline replaced the strikethrough instead of joining it',
    );
  });

  group('emoji artwork', () {
    /// A cache that already holds the artwork for `smile`, so the field can
    /// paint it without going async — which is the only state it substitutes
    /// in. `wave` is a name the site does not have.
    void primeCache() {
      final previous = EmojiCache.instance;
      addTearDown(() => EmojiCache.instance = previous);
      EmojiCache.instance = EmojiCache(
        client: MockClient((request) async {
          if (request.url.path.contains('smile')) {
            return http.Response.bytes(_pngBytes, 200);
          }
          return http.Response('nope', 404);
        }),
      );
    }

    String urlFor(String name) => 'https://meta.discourse.org/$name.png';

    Future<void> pumpWithEmoji(WidgetTester tester, String source) async {
      primeCache();
      // Warm the cache the way a second screen of posts would have.
      await EmojiCache.instance.load(urlFor('smile'));
      await pumpField(tester, source, resolveEmoji: urlFor);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('draws the artwork where the shortcode is', (tester) async {
      await pumpWithEmoji(tester, 'hey :smile: there');

      expect(find.byType(EmojiImage), findsOneWidget);
    });

    testWidgets('and the text is still every character of it', (tester) async {
      const source = 'hey :smile: there';
      await pumpWithEmoji(tester, source);

      // This is the whole trick. A WidgetSpan is worth exactly one code unit,
      // so it stands in for exactly one character — the closing colon — and
      // the other six are drawn at zero size rather than dropped. The painted
      // paragraph therefore has the same *length* as the text, differing only
      // at the placeholder, which is what keeps every offset meaning the same
      // position in both.
      expect(controller.text, source);
      expect(editable(tester).renderEditable.plainText.length, source.length);
      expect(
        editable(tester).renderEditable.plainText.replaceAll('\uFFFC', ':'),
        source,
      );
    });

    testWidgets('the caret still lands where it is drawn', (tester) async {
      const source = 'hey :smile: there';
      await pumpWithEmoji(tester, source);

      final render = editable(tester).renderEditable;
      for (final offset in [0, 3, 11, 13, source.length]) {
        final rect = render.getLocalRectForCaret(TextPosition(offset: offset));
        expect(
          render.getPositionForPoint(render.localToGlobal(rect.center)).offset,
          offset,
          reason: 'the caret at $offset does not come back as $offset',
        );
      }
    });

    testWidgets('shows the characters again when the caret is inside', (
      tester,
    ) async {
      await pumpWithEmoji(tester, 'hey :smile: there');
      expect(find.byType(EmojiImage), findsOneWidget);

      // Strictly inside — arrowed into it to edit the name.
      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.pump();
      expect(find.byType(EmojiImage), findsNothing);

      // And back out again.
      controller.selection = const TextSelection.collapsed(offset: 11);
      await tester.pump();
      expect(find.byType(EmojiImage), findsOneWidget);
    });

    testWidgets('shows the artwork once it arrives, not only if it was here', (
      tester,
    ) async {
      // The path the app actually takes: nothing cached, someone types a
      // shortcode, the bytes are fetched, and the field has to repaint. Every
      // other test here warms the cache first and so never walks it.
      primeCache();
      await pumpField(tester, 'hey :smile:', resolveEmoji: urlFor);

      expect(find.byType(EmojiImage), findsNothing);

      await tester.pumpAndSettle();

      expect(find.byType(EmojiImage), findsOneWidget);
    });

    testWidgets('leaves a name the site does not have as text', (tester) async {
      await pumpWithEmoji(tester, 'hey :wave: there');

      // It 404s once, is remembered as a failure, and stays text.
      await tester.pump();
      expect(find.byType(EmojiImage), findsNothing);
      expect(controller.text, 'hey :wave: there');
    });

    testWidgets('draws two shortcodes side by side as two', (tester) async {
      await pumpWithEmoji(tester, ':smile::smile:');

      expect(find.byType(EmojiImage), findsNWidgets(2));
      expect(controller.text, ':smile::smile:');
    });
  });

  group('pills', () {
    late Map<String, FoundHashtag?> known;
    late Map<String, bool> real;
    late List<Set<String>> refBatches;
    late List<Set<String>> nameBatches;

    const bug = FoundHashtag(
      type: 'category',
      ref: 'bug',
      slug: 'bug',
      text: 'Bug',
      id: 5,
      colors: ['0088CC'],
    );

    setUp(() {
      known = {};
      real = {};
      refBatches = [];
      nameBatches = [];
    });

    /// The shell's half, with no site and no network behind it.
    ComposerPills pills() => (
      hashtag: (ref) => known[ref],
      mention: (name) => real[name],
      resolve: (refs, names) {
        if (refs.isNotEmpty) refBatches.add(refs);
        if (names.isNotEmpty) nameBatches.add(names);
      },
    );

    /// Puts the caret somewhere other than in the run being looked at, since a
    /// caret touching one is what keeps it as text.
    Future<void> pumpAway(WidgetTester tester, String source) async {
      await pumpField(tester, source, pills: pills());
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
    }

    testWidgets('a resolved hashtag is drawn as a pill', (tester) async {
      known['bug'] = bug;
      await pumpAway(tester, 'filed under #bug today');

      expect(find.byType(HashtagPill), findsOneWidget);
      // The characters that are in the field, not the site's own name for it:
      // what the composer draws is what will be posted.
      expect(
        tester.widget<HashtagPill>(find.byType(HashtagPill)).label,
        '#bug',
      );
    });

    testWidgets('a resolved mention is drawn as a pill', (tester) async {
      real['sam'] = true;
      await pumpAway(tester, 'ask @sam about it');

      expect(find.byType(MentionPill), findsOneWidget);
      expect(
        tester.widget<MentionPill>(find.byType(MentionPill)).label,
        '@sam',
      );
    });

    testWidgets('the painted text is still every character of the source', (
      tester,
    ) async {
      known['bug'] = bug;
      real['sam'] = true;
      await pumpAway(tester, 'ask @sam about #bug now');

      // A WidgetSpan flattens to one `￼` where the source has its own
      // character, so the two differ exactly at the placeholders — and every
      // offset after them would be wrong if they did not.
      final plain = painted(tester).toPlainText();
      expect(plain.length, controller.text.length);
      // Two pills, so exactly two placeholders — and putting the characters
      // they stand for back gives the source again.
      expect(plain.split('￼').length - 1, 2);
      expect(
        plain.replaceFirst('￼', 'm').replaceFirst('￼', 'g'),
        controller.text,
      );
    });

    testWidgets('the caret still lands where it is drawn', (tester) async {
      known['bug'] = bug;
      await pumpAway(tester, 'filed under #bug today');

      final at = controller.text.indexOf('today');
      controller.selection = TextSelection.collapsed(offset: at);
      await tester.pump();

      final render = editable(tester).renderEditable;
      final offset = render
          .getLocalRectForCaret(TextPosition(offset: at))
          .center;
      expect(
        render.getPositionForPoint(render.localToGlobal(offset)).offset,
        at,
      );
    });

    testWidgets('a name the site does not have stays text', (tester) async {
      // The post will cook `@nobody` as plain text. A pill here would be the
      // field promising a person who is not there.
      real['nobody'] = false;
      await pumpAway(tester, 'ask @nobody about it');

      expect(find.byType(MentionPill), findsNothing);
      expect(painted(tester).toPlainText(), 'ask @nobody about it');
    });

    testWidgets('an unresolved ref stays text and is asked about once', (
      tester,
    ) async {
      await pumpAway(tester, 'filed under #bug today');

      expect(find.byType(HashtagPill), findsNothing);
      expect(refBatches, [
        {'bug'},
      ]);
    });

    testWidgets('the pill appears once the answer arrives', (tester) async {
      await pumpAway(tester, 'filed under #bug today');
      expect(find.byType(HashtagPill), findsNothing);

      known['bug'] = bug;
      controller.artworkArrived();
      await tester.pump();

      expect(find.byType(HashtagPill), findsOneWidget);
    });

    testWidgets('a whole paragraph of refs is one question', (tester) async {
      await pumpAway(tester, 'see #one and #two and #three');

      expect(refBatches, [
        {'one', 'two', 'three'},
      ]);
    });

    testWidgets('typing a ref asks nothing until it is finished', (
      tester,
    ) async {
      // The reason the reveal rule is adjacency rather than strictly-inside.
      // The run grows under the caret as it is typed, so a strict rule would
      // pill it mid-word *and* ask the site about every prefix on the way.
      await pumpField(tester, '', pills: pills());

      for (final text in ['#', '#b', '#bu', '#bug']) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        await tester.pump();
      }
      expect(refBatches, isEmpty);
      expect(find.byType(HashtagPill), findsNothing);

      // The space that ends the ref is what asks.
      controller.value = const TextEditingValue(
        text: '#bug ',
        selection: TextSelection.collapsed(offset: 5),
      );
      await tester.pump();

      expect(refBatches, [
        {'bug'},
      ]);
    });

    testWidgets('the caret coming back reveals the characters', (tester) async {
      known['bug'] = bug;
      await pumpAway(tester, 'filed under #bug today');
      expect(find.byType(HashtagPill), findsOneWidget);

      // Adjacent counts as inside for a run with no closing character.
      controller.selection = const TextSelection.collapsed(offset: 16);
      await tester.pump();

      expect(find.byType(HashtagPill), findsNothing);
      expect(painted(tester).toPlainText(), 'filed under #bug today');
    });

    testWidgets('with no pills at all everything stays text', (tester) async {
      // The gate every existing test in this file relies on.
      await pumpField(tester, 'ask @sam about #bug');
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      expect(find.byType(MentionPill), findsNothing);
      expect(find.byType(HashtagPill), findsNothing);
      expect(painted(tester).toPlainText(), 'ask @sam about #bug');
    });

    testWidgets('copying gives back the source, not the placeholder', (
      tester,
    ) async {
      known['bug'] = bug;
      await pumpAway(tester, 'filed under #bug today');

      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();

      // `copySelection` reads `_value.text`, never the span — so what lands on
      // the clipboard is the markdown that will be posted.
      expect(
        editable(tester).textEditingValue.text.substring(0, 16),
        'filed under #bug',
      );
    });
  });
}

/// The smallest thing `Image.memory` will accept: a 1x1 transparent PNG.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
