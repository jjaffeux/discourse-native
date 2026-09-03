import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_blockquote.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/composer_pills.dart';
import 'package:discourse_native/src/shell/composer_quotes.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/syntax.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/finders.dart';
import 'support/media_pipeline.dart';

/// Flutter silently assumes offsets in the laid-out span tree and controller
/// text describe the same string; every projection here must preserve that.
void main() {
  late MarkdownEditingController controller;

  Future<void> pumpField(
    WidgetTester tester,
    String source, {
    String Function(String)? resolveEmoji,
    ComposerPills? pills,
    PluginHashtagPresentationResolver? pluginHashtagPresentation,
  }) async {
    controller = MarkdownEditingController(
      text: source,
      resolveEmoji: resolveEmoji,
      pills: pills,
      pluginHashtagPresentation: pluginHashtagPresentation,
      syntaxPolicies: const [_FakeSyntaxPolicy()],
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
      '# Heading\n\n```ruby\nputs 1\n```',
      'plain',
    ]) {
      testWidgets(source.split('\n').first, (tester) async {
        await pumpField(tester, source);

        expect(
          painted(tester).toPlainText(includeSemanticsLabels: false),
          source,
        );
        expect(controller.text, source);
      });
    }
  });

  group('editable Markdown quotes', () {
    testWidgets('shows a quote on space and keeps body offsets editable', (
      tester,
    ) async {
      await pumpField(tester, '');
      await tester.enterText(find.byType(TextField), '>');
      await tester.pump();
      expect(find.byType(ComposerBlockquoteMarker), findsNothing);

      await tester.enterText(find.byType(TextField), '> ');
      await tester.pump();
      expect(find.byType(ComposerBlockquoteMarker), findsOneWidget);
      expect(controller.selection, const TextSelection.collapsed(offset: 2));

      const source = '> xxxx';
      await tester.enterText(find.byType(TextField), source);
      await tester.pump();
      expect(controller.text, source);
      expect(painted(tester).toPlainText().length, source.length);
      final render = editable(tester).renderEditable;
      final marker = tester.getRect(find.byType(ComposerBlockquoteMarker));
      for (var offset = 2; offset <= source.length; offset++) {
        final rect = render.getLocalRectForCaret(TextPosition(offset: offset));
        final caret = render.localToGlobal(rect.center);
        expect(caret.dx, greaterThanOrEqualTo(marker.right));
        expect(render.getPositionForPoint(caret).offset, offset);
      }

      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      editable(tester).userUpdateTextEditingValue(
        const TextEditingValue(
          text: '> edited',
          selection: TextSelection.collapsed(offset: 8),
        ),
        SelectionChangedCause.keyboard,
      );
      await tester.pump();
      expect(controller.text, '> edited');
      expect(find.byType(ComposerBlockquoteMarker), findsOneWidget);

      await tester.enterText(find.byType(TextField), '>');
      await tester.pump();
      expect(find.byType(ComposerBlockquoteMarker), findsNothing);
      expect(painted(tester).toPlainText(), '>');
    });

    testWidgets('only projects line prefixes outside code and composition', (
      tester,
    ) async {
      const source =
          'a > b\n\\> escaped\n    > indented code\n'
          '```\n> fenced code\n```\n'
          '> first\n> > nested';
      await pumpField(tester, source);
      expect(find.byType(ComposerBlockquoteMarker), findsNWidgets(2));
      expect(controller.text, source);
      expect(painted(tester).toPlainText().length, source.length);

      await tester.showKeyboard(find.byType(TextField));
      controller.value = const TextEditingValue(
        text: '> ',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await tester.pump();
      expect(find.byType(ComposerBlockquoteMarker), findsNothing);
      expect(painted(tester).toPlainText(), '> ');

      controller.clearComposing();
      await tester.pump();
      expect(find.byType(ComposerBlockquoteMarker), findsOneWidget);
    });
  });

  testWidgets('a tap lands on the character under it', (tester) async {
    const source = 'say **hello** to @sam';
    await pumpField(tester, source);

    final render = editable(tester).renderEditable;
    // Round-trip offsets because glyph positions vary by platform.
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

    // RenderEditable derives editing offsets from its flattened span tree.
    expect(editable(tester).renderEditable.plainText, source);
  });

  testWidgets(
    'multiline plugin components keep their trailing caret beside the widget',
    (tester) async {
      final componentSource = [
        '[component]',
        for (var index = 0; index < 30; index++) 'source row $index',
        '[/component]',
      ].join('\n');
      final source = '$componentSource \tafter';
      final componentController = MarkdownEditingController(
        text: source,
        syntaxPolicies: const [_MultilineSyntaxPolicy()],
      );
      addTearDown(componentController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: TextField(controller: componentController, maxLines: null),
            ),
          ),
        ),
      );

      final component = componentController.syntaxBlocks.single;
      final componentRect = tester.getRect(
        find.byKey(const ValueKey('multiline-syntax-component')),
      );
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final caret = render
          .getLocalRectForCaret(TextPosition(offset: component.end))
          .shift(render.localToGlobal(Offset.zero));

      expect(
        (caret.center.dy - componentRect.center.dy).abs(),
        lessThanOrEqualTo(8),
      );
      expect(render.getPositionForPoint(caret.center).offset, component.end);
      expect(render.plainText.length, source.length);
    },
  );

  testWidgets('scaled block components keep their trailing caret adjacent', (
    tester,
  ) async {
    Future<void> verify({
      required String source,
      required Finder component,
      required int Function(MarkdownEditingController) componentEnd,
    }) async {
      final componentController = MarkdownEditingController(text: source);
      addTearDown(componentController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Scaffold(
                body: SizedBox(
                  width: 600,
                  child: TextField(
                    controller: componentController,
                    maxLines: null,
                    style: Theme.of(context).textTheme.bodyMedium,
                    strutStyle: StrutStyle.fromTextStyle(
                      Theme.of(context).textTheme.bodyMedium!,
                      forceStrutHeight: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final render = editable(tester).renderEditable;
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: componentEnd(componentController)),
      );
      final globalCaret = caret.shift(render.localToGlobal(Offset.zero));
      expect(
        globalCaret.top - tester.getRect(component).bottom,
        inInclusiveRange(-render.preferredLineHeight, 40),
      );
      expect(render.plainText.length, source.length);
    }

    await verify(
      source: '![alt|320x180](upload://image)',
      component: find.byType(ComposerImagePreview),
      componentEnd: (controller) => controller.imageBlocks.single.end,
    );
    await verify(
      source: '[quote="sam"]\nquoted\n[/quote]',
      component: find.byType(ComposerQuotePreview),
      componentEnd: (controller) => controller.quoteBlocks.single.end,
    );
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

    expect(controller.scans, after);
  });

  test('every keyboard-selected projection hides the cursor', () {
    final selectedController = MarkdownEditingController(
      text: '![alt](https://example.com/a.png) [[token]]',
      syntaxPolicies: const [_FakeSyntaxPolicy()],
    );
    addTearDown(selectedController.dispose);

    expect(selectedController.selectedProjectionHidesCursor, isFalse);
    for (final projection in [
      selectedController.imageBlocks.single,
      selectedController.syntaxBlocks.single,
    ]) {
      selectedController.selectPillForKeyboard(projection);
      expect(selectedController.selectedProjectionHidesCursor, isTrue);
      selectedController.clearKeyboardPillSelection();
      expect(selectedController.selectedProjectionHidesCursor, isFalse);
    }
  });

  testWidgets('changing text rescans the markdown source', (tester) async {
    await pumpField(tester, 'say');
    final before = controller.scans;

    controller.value = const TextEditingValue(
      text: 'say **hi**',
      selection: TextSelection.collapsed(offset: 10),
    );
    await tester.pump();

    expect(controller.scans, greaterThan(before));
  });

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
      // Flutter reserves editable underlines for IME composing ranges.
      const source = 'see plain text and **d** and `e`';
      await pumpField(tester, source);

      painted(tester).visitChildren((span) {
        expect(
          (span as TextSpan).style?.decoration,
          isNot(TextDecoration.underline),
        );
        return true;
      });
    });

    testWidgets('a markdown link collapses to its clickable anchor', (
      tester,
    ) async {
      const source = 'see [Discourse](https://discourse.org) now';
      await pumpField(tester, source);

      final pill = tester.widget<ComposerLinkPill>(
        find.byType(ComposerLinkPill),
      );
      expect(pill.anchor, 'Discourse');
      expect(pill.url, 'https://discourse.org');
      expect(controller.text, source);
      expect(editable(tester).renderEditable.plainText.length, source.length);

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: source.length,
      );
      await tester.pump();
      expect(find.byType(ComposerLinkPill), findsOneWidget);

      controller.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();
      expect(find.byType(ComposerLinkPill), findsNothing);

      controller.selection = TextSelection.collapsed(
        offset: source.indexOf(')') + 1,
      );
      await tester.pump();
      expect(find.byType(ComposerLinkPill), findsOneWidget);
    });

    testWidgets('a fuzzy domain is projected as a source-preserving link', (
      tester,
    ) async {
      const source = 'visit google.fr now';
      await pumpField(tester, source);

      final pill = tester.widget<ComposerLinkPill>(
        find.byType(ComposerLinkPill),
      );
      expect(pill.anchor, 'google.fr');
      expect(pill.url, 'http://google.fr');
      expect(controller.text, source);
      expect(editable(tester).renderEditable.plainText.length, source.length);

      controller.updateMarkdownLinkify(enabled: false, tlds: const []);
      await tester.pump();

      expect(find.byType(ComposerLinkPill), findsNothing);
      expect(controller.text, source);
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

      final edited = largeSource.replaceFirst('line 7', 'line 07');
      controller.value = TextEditingValue(
        text: edited,
        selection: TextSelection.collapsed(offset: edited.indexOf('07') + 1),
      );
      await tester.pump();

      final plain = styleAt(tester, edited, keyword);
      expect(plain.fontFamily, monospaceFontFamily);
      expect(plain.color, AppTheme.dark.colorScheme.onSurface);

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
      // A bounded process-wide cache can evict earlier fences from the same
      // document; re-deferring those on every pass would cycle forever.
      final crowded = [
        for (var fence = 0; fence < syntaxHighlightCacheCapacity + 8; fence++)
          '```dart\n${List.generate(60, (line) => 'final v$fence$line = $line;').join('\n')}\n```',
      ].join('\n\n');

      await pumpField(tester, crowded);

      // flutter_test also fails teardown if the debounce keeps a Timer alive.
      for (var round = 0; round < 6; round++) {
        await tester.pump(MarkdownEditingController.fenceHighlightDebounce);
        await tester.pump();
      }

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

      await tester.pumpWidget(const SizedBox());
      local.dispose();
    });
  });

  testWidgets('the composing range keeps its underline', (tester) async {
    const source = 'say hello';
    await pumpField(tester, source);
    // EditableText only forwards composing ranges while focused.
    await tester.tap(find.byType(TextField));
    await tester.pump();

    controller.value = const TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: 9),
      composing: TextRange(start: 4, end: 9),
    );
    await tester.pump();

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
    String urlFor(String name) => 'https://meta.discourse.org/$name.png';

    MediaPipeline primeCache() => installTestMediaPipeline(
      client: MockClient((request) async {
        if (request.url.path.contains('smile')) {
          return http.Response.bytes(_pngBytes, 200);
        }
        return http.Response('nope', 404);
      }),
    );

    Future<void> pumpWithEmoji(WidgetTester tester, String source) async {
      final pipeline = primeCache();
      await pipeline.emoji.load(urlFor('smile'));
      await pumpField(tester, source, resolveEmoji: urlFor);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('draws the artwork where the shortcode is', (tester) async {
      await pumpWithEmoji(tester, 'hey :smile: there');

      expect(find.byType(EmojiImage), findsOneWidget);
    });

    testWidgets('preserves every source character', (tester) async {
      const source = 'hey :smile: there';
      await pumpWithEmoji(tester, source);

      // WidgetSpan contributes one placeholder code unit; the remaining
      // shortcode characters must stay in the flattened span tree.
      expect(controller.text, source);
      expect(editable(tester).renderEditable.plainText.length, source.length);
      expect(
        editable(tester).renderEditable.plainText.replaceAll('\uFFFC', ':'),
        source,
      );
    });

    testWidgets('preserves caret hit testing', (tester) async {
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

    testWidgets('selection keeps artwork while an interior caret reveals it', (
      tester,
    ) async {
      await pumpWithEmoji(tester, 'hey :smile: there');
      expect(find.byType(EmojiImage), findsOneWidget);

      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();
      expect(find.byType(EmojiImage), findsOneWidget);

      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.pump();
      expect(find.byType(EmojiImage), findsNothing);

      controller.selection = const TextSelection.collapsed(offset: 11);
      await tester.pump();
      expect(find.byType(EmojiImage), findsOneWidget);
    });

    testWidgets('shows the artwork once it arrives, not only if it was here', (
      tester,
    ) async {
      primeCache();
      await pumpField(tester, 'hey :smile:', resolveEmoji: urlFor);

      expect(find.byType(EmojiImage), findsNothing);

      await tester.pumpAndSettle();

      expect(find.byType(EmojiImage), findsOneWidget);
    });

    testWidgets('leaves a name the site does not have as text', (tester) async {
      await pumpWithEmoji(tester, 'hey :wave: there');

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

  group('pill projection', () {
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

    ComposerPills pills() => (
      hashtag: (ref) => known[ref],
      mention: (name) => real[name],
      resolve: (refs, names) {
        if (refs.isNotEmpty) refBatches.add(refs);
        if (names.isNotEmpty) nameBatches.add(names);
      },
    );

    test('suggestion art shares installed and fallback kind policies', () {
      const registry = PluginRegistry([_RoomHashtagPlugin()]);
      final request = HashtagPresentationRequest(
        type: 'room',
        style: HashtagStyle.square,
      );
      final installed = hashtagSuggestionArt(
        resolveHashtagPresentation(
          request,
          pluginPresentation: registry.pluginHashtagPresentation,
        ),
        resolveEmoji: (name) => 'https://example.com/$name.png',
      );
      final absent = hashtagSuggestionArt(
        resolveHashtagPresentation(request),
        resolveEmoji: (name) => 'https://example.com/$name.png',
      );
      final future = hashtagSuggestionArt(
        resolveHashtagPresentation(
          HashtagPresentationRequest(type: 'board', style: HashtagStyle.square),
        ),
        resolveEmoji: (name) => 'https://example.com/$name.png',
      );

      expect((installed as ArtIcon).fallback, DIcons.microphoneLines);
      expect((absent as ArtIcon).fallback, DIcons.link);
      expect((future as ArtIcon).fallback, DIcons.link);
    });

    test('emoji-style hashtag suggestions use the emoji artwork', () {
      final art = hashtagSuggestionArt(
        resolveHashtagPresentation(
          HashtagPresentationRequest(
            type: 'board',
            style: HashtagStyle.emoji,
            emoji: 'rocket',
          ),
        ),
        resolveEmoji: (name) => 'https://example.com/$name.png',
      );

      expect(art, isA<ArtImage>());
      expect((art as ArtImage).url, 'https://example.com/rocket.png');
    });

    test('an emoji style without an emoji keeps an uncoloured kind icon', () {
      final art = hashtagSuggestionArt(
        resolveHashtagPresentation(
          HashtagPresentationRequest(
            type: 'category',
            style: HashtagStyle.emoji,
            colorValues: const [0xFF112233],
          ),
        ),
        resolveEmoji: (name) => 'https://example.com/$name.png',
      );

      expect(art, isA<ArtIcon>());
      expect((art as ArtIcon).fallback, DIcons.folder);
      expect(art.colorValue, isNull);
    });

    // A caret touching a token keeps its source text visible.
    Future<void> pumpAway(
      WidgetTester tester,
      String source, {
      PluginHashtagPresentationResolver? pluginHashtagPresentation,
    }) async {
      await pumpField(
        tester,
        source,
        pills: pills(),
        pluginHashtagPresentation: pluginHashtagPresentation,
      );
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
    }

    testWidgets('a resolved hashtag is drawn as a pill', (tester) async {
      known['bug'] = bug;
      await pumpAway(tester, 'filed under #bug today');

      expect(find.byType(HashtagPill), findsOneWidget);
      expect(
        tester.widget<HashtagPill>(find.byType(HashtagPill)).label,
        '#bug',
      );
    });

    testWidgets('an installed room plugin uses its microphone policy', (
      tester,
    ) async {
      known['lounge'] = const FoundHashtag(
        type: 'room',
        ref: 'lounge',
        slug: 'lounge',
        text: 'Lounge',
        id: 9,
      );
      const registry = PluginRegistry([_RoomHashtagPlugin()]);

      await pumpAway(
        tester,
        'join #lounge now',
        pluginHashtagPresentation: registry.pluginHashtagPresentation,
      );

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.presentation.type, 'room');
      expect(pill.presentation.fallbackIcon, DIcons.microphoneLines);
      expect(find.dIcon(DIcons.microphoneLines), findsOneWidget);
      expect(find.dIcon(DIcons.tag), findsNothing);
    });

    testWidgets('an absent room plugin keeps its unknown identity', (
      tester,
    ) async {
      known['lounge'] = const FoundHashtag(
        type: 'room',
        ref: 'lounge',
        slug: 'lounge',
        text: 'Lounge',
        id: 9,
      );

      await pumpAway(tester, 'join #lounge now');

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.presentation.type, 'room');
      expect(pill.presentation.fallbackIcon, DIcons.link);
      expect(find.dIcon(DIcons.link), findsOneWidget);
      expect(find.dIcon(DIcons.tag), findsNothing);
      expect(find.dIcon(DIcons.microphoneLines), findsNothing);
    });

    testWidgets('an arbitrary server kind uses the neutral fallback', (
      tester,
    ) async {
      known['roadmap'] = const FoundHashtag(
        type: 'board',
        ref: 'roadmap',
        slug: 'roadmap',
        text: 'Roadmap',
        id: 10,
      );

      await pumpAway(tester, 'see #roadmap next');

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.presentation.type, 'board');
      expect(pill.presentation.fallbackIcon, DIcons.link);
      expect(find.dIcon(DIcons.link), findsOneWidget);
      expect(find.dIcon(DIcons.tag), findsNothing);
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

      final plain = painted(tester).toPlainText();
      expect(plain.length, controller.text.length);
      expect(plain.split('￼').length - 1, 2);
      expect(
        plain.replaceFirst('￼', 'm').replaceFirst('￼', 'g'),
        controller.text,
      );
    });

    testWidgets('preserves caret hit testing', (tester) async {
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
      // Adjacency keeps a growing token visible until its delimiter is typed.
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

      controller.selection = const TextSelection.collapsed(offset: 16);
      await tester.pump();

      expect(find.byType(HashtagPill), findsNothing);
      expect(painted(tester).toPlainText(), 'filed under #bug today');
    });

    testWidgets('with no pills at all everything stays text', (tester) async {
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

      expect(
        editable(tester).textEditingValue.text.substring(0, 16),
        'filed under #bug',
      );
      expect(find.byType(HashtagPill), findsOneWidget);
    });

    testWidgets('range selection keeps mention and hashtag pills rendered', (
      tester,
    ) async {
      known['bug'] = bug;
      real['sam'] = true;
      await pumpAway(tester, 'ask @sam about #bug today');

      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();

      expect(find.byType(MentionPill), findsOneWidget);
      expect(find.byType(HashtagPill), findsOneWidget);
    });
  });

  testWidgets('typing leaves the pills already in the document alone', (
    tester,
  ) async {
    // Projection GlobalKeys must preserve their elements across span-tree
    // rebuilds or Flutter discards their measured render objects.
    const source =
        '![shot|400x300](https://example.com/a.png)\n'
        '\n'
        'Meeting [[first:2026-01-02]] here.\n'
        '\n'
        'Choose [[second:one|two]] now.\n'
        '\n'
        '[quote="sam, post:1, topic:2"]\n'
        'Quoted line.\n'
        '[/quote]\n'
        '\n';

    await pumpField(tester, source);
    await tester.pump();

    final finders = <String, Finder>{
      'image': find.byType(ComposerImagePreview),
      'first syntax': find.widgetWithText(_FakeSyntaxPill, 'first:2026-01-02'),
      'second syntax': find.widgetWithText(_FakeSyntaxPill, 'second:one|two'),
      'quote': find.byType(ComposerQuotePreview),
    };
    final before = <String, Element>{};
    for (final entry in finders.entries) {
      expect(entry.value, findsOneWidget, reason: entry.key);
      before[entry.key] = tester.element(entry.value);
    }

    for (final typed in const ['R', 'Re', 'Rep', 'Repl', 'Reply']) {
      final text = '$source$typed';
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      await tester.pump();
    }

    for (final entry in finders.entries) {
      expect(
        tester.element(entry.value),
        same(before[entry.key]),
        reason: 'the ${entry.key} pill was recreated rather than left alone',
      );
    }
  });

  group('the invariant, with everything substituting at once', () {
    const pieces = [
      ':smile:',
      ':wave:',
      ':smile:t3:',
      '@sam',
      '@nobody',
      '#bug',
      '#none',
      '#parent:child',
      '**',
      '*',
      '_',
      '`',
      '``',
      '~~',
      '[',
      ']',
      '(',
      ')',
      'a',
      'b',
      ' ',
      '\n',
      '\n\n',
      '<kbd>',
      '</kbd>',
      '#',
      '@',
      ':',
      'x',
      'https://e.com',
      '```\n',
      '```',
      '> ',
      '# ',
    ];

    const bug = FoundHashtag(
      type: 'category',
      ref: 'bug',
      slug: 'bug',
      text: 'Bug',
      id: 5,
      colors: ['0088CC'],
    );
    const child = FoundHashtag(
      type: 'category',
      ref: 'parent:child',
      slug: 'child',
      text: 'Child',
      id: 6,
      colors: ['FF0000'],
    );

    String urlFor(String name) => 'https://meta.discourse.org/$name.png';

    testWidgets('every placeholder is worth exactly one code unit', (
      tester,
    ) async {
      final pipeline = installTestMediaPipeline(
        client: MockClient((request) async {
          if (request.url.path.contains('smile')) {
            return http.Response.bytes(_pngBytes, 200);
          }
          return http.Response('nope', 404);
        }),
      );
      await pipeline.emoji.load(urlFor('smile'));
      await pipeline.emoji.load(urlFor('smile:t3'));

      final ComposerPills pills = (
        hashtag: (ref) => switch (ref) {
          'bug' => bug,
          'parent:child' => child,
          _ => null,
        },
        mention: (name) => switch (name) {
          'sam' => true,
          'nobody' => false,
          _ => null,
        },
        resolve: (refs, names) {},
      );

      late BuildContext spanContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              spanContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final random = Random(31337);
      for (var round = 0; round < 400; round++) {
        final buffer = StringBuffer();
        for (var i = 0; i < random.nextInt(40); i++) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        final source = buffer.toString();

        final candidate = MarkdownEditingController(
          text: source,
          resolveEmoji: urlFor,
          pills: pills,
          syntaxPolicies: const [_FakeSyntaxPolicy()],
        );

        try {
          for (final caret in <int>{0, source.length ~/ 2, source.length}) {
            candidate.selection = TextSelection.collapsed(offset: caret);
            final painted = candidate
                .buildTextSpan(
                  context: spanContext,
                  style: const TextStyle(),
                  withComposing: false,
                )
                .toPlainText(includeSemanticsLabels: false);
            if (painted.length != source.length) {
              fail(
                'caret $caret on ${jsonEncode(source)} painted '
                '${jsonEncode(painted)}',
              );
            }
            for (var i = 0; i < painted.length; i++) {
              if (painted.codeUnitAt(i) == 0xFFFC || painted[i] == source[i]) {
                continue;
              }
              fail(
                'offset $i, caret $caret on ${jsonEncode(source)} '
                'painted ${jsonEncode(painted)}',
              );
            }
          }
        } finally {
          candidate.dispose();
        }
      }
    });

    testWidgets('every projected block preserves the source-length invariant', (
      tester,
    ) async {
      // Whole-block WidgetSpans must preserve every replaced source offset;
      // TextPainter also needs a measurable final glyph after hidden spaces.
      const blocks = [
        '[quote="sam, post:1, topic:2"]\nquoted\n[/quote]\n\n',
        '[quote="a"]\nx\n[/quote]\n\n',
        '![alt|10x20](upload://abc.png)',
        '![a](https://e.com/a.png)',
        '[[alpha:2026-01-02]]',
        '[[choice:one|two]]',
        '[[choice:one|two]] ',
        '[[choice:one|two]]\t\t',
        '[/quote]',
        '[[/unknown]]',
        '[quote',
        '[[choice',
        '![',
        '](',
        ')',
        ']',
        'a',
        ' ',
        '\t',
        '\n',
        '\n\n',
        '**',
        '`',
        '```\n',
        '```',
        '> ',
      ];

      await pumpField(tester, '');

      final random = Random(4242);
      final reachedProjectionKinds = <String>{};
      for (var round = 0; round < 300; round++) {
        final buffer = StringBuffer();
        for (var i = 0; i < random.nextInt(10); i++) {
          buffer.write(blocks[random.nextInt(blocks.length)]);
        }
        final source = buffer.toString();

        controller.value = TextEditingValue(text: source);
        await tester.pump();
        if (controller.quoteBlocks.isNotEmpty) {
          reachedProjectionKinds.add('quote');
        }
        if (controller.imageBlocks.isNotEmpty) {
          reachedProjectionKinds.add('image');
        }
        if (controller.syntaxBlocks.isNotEmpty) {
          reachedProjectionKinds.add('plugin syntax');
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'building ${jsonEncode(source)}',
        );

        for (final caret in <int>{0, source.length ~/ 2, source.length}) {
          controller.selection = TextSelection.collapsed(offset: caret);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'caret $caret on ${jsonEncode(source)}',
          );
          expect(
            editable(tester).renderEditable.plainText.length,
            source.length,
            reason: 'caret $caret on ${jsonEncode(source)}',
          );
        }
      }

      expect(reachedProjectionKinds, {'quote', 'image', 'plugin syntax'});
    });
  });
}

const _fakeSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('fake-syntax'),
  name: 'token',
);

final class _FakeSyntaxPolicy implements ComposerSyntaxPolicy {
  const _FakeSyntaxPolicy();

  @override
  ComposerSyntaxKind get kind => _fakeSyntaxKind;

  @override
  Object? get projectionState => null;

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final match in RegExp(r'\[\[[^\]\n]+\]\]').allMatches(source))
      _FakeSyntaxProjection(match.start, match.end, match.group(0)!),
  ];
}

final class _RoomHashtagPlugin implements SitePlugin, HashtagKindPlugin {
  const _RoomHashtagPlugin();

  @override
  String get name => 'room-hashtag-test';

  @override
  List<PluginHashtagKind> get hashtagKinds => const [
    PluginHashtagKind('room', _presentRoomHashtag),
  ];
}

HashtagPresentation _presentRoomHashtag(HashtagPresentationRequest request) =>
    HashtagPresentation.fromRequest(
      request,
      fallbackIcon: DIcons.microphoneLines,
      colorPolicy: HashtagColorPolicy.none,
    );

final class _FakeSyntaxProjection implements ComposerSyntaxProjection {
  const _FakeSyntaxProjection(this.start, this.end, this.source);

  @override
  final int start;
  @override
  final int end;
  @override
  final String source;

  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      !suppressCollapsedCaret &&
      document.selection.extentOffset > start &&
      document.selection.extentOffset < end;

  @override
  int caretAfter(String document) => end;

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: end),
        composing: TextRange.empty,
      );

  @override
  bool get supportsHover => false;

  @override
  bool get protectsAdjacentDelete => false;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) => [
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _FakeSyntaxPill(
        key: context.pillKey,
        label: source.substring(2, source.length - 2),
      ),
    ),
    if (source.length > 1)
      TextSpan(
        text: source.substring(1),
        style: context.baseStyle.copyWith(
          color: Colors.transparent,
          fontSize: 0,
          height: 0,
        ),
      ),
  ];

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {}

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {}
}

const _multilineSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('multiline-syntax'),
  name: 'component',
);

final class _MultilineSyntaxPolicy implements ComposerSyntaxPolicy {
  const _MultilineSyntaxPolicy();

  @override
  ComposerSyntaxKind get kind => _multilineSyntaxKind;

  @override
  Object? get projectionState => null;

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final match in RegExp(
      r'\[component\][\s\S]*?\[/component\][ \t]*',
    ).allMatches(source))
      _MultilineSyntaxProjection(match.start, match.end, match.group(0)!),
  ];
}

final class _MultilineSyntaxProjection implements ComposerSyntaxProjection {
  const _MultilineSyntaxProjection(this.start, this.end, this.source);

  @override
  final int start;

  @override
  final int end;

  @override
  final String source;

  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      !suppressCollapsedCaret &&
      document.selection.extentOffset > start &&
      document.selection.extentOffset < end;

  @override
  int caretAfter(String document) => end;

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: end),
        composing: TextRange.empty,
      );

  @override
  bool get supportsHover => false;

  @override
  bool get protectsAdjacentDelete => false;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) => [
    const WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        key: ValueKey('multiline-syntax-component'),
        width: 80,
        height: 32,
      ),
    ),
    TextSpan(
      text: source.substring(1),
      style: context.baseStyle.copyWith(
        color: Colors.transparent,
        fontSize: 0,
        height: 0,
      ),
    ),
  ];

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {}

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {}
}

final class _FakeSyntaxPill extends StatelessWidget {
  const _FakeSyntaxPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
