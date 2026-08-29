import 'dart:convert';
import 'dart:typed_data';

import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

/// Cooked HTML on its own, with no shell above it — which is how a quote or an
/// onebox body can also be rendered, and is the case [CookedHtml] uses
/// `ShellScope.maybeRead` for.
Future<void> pumpCooked(
  WidgetTester tester,
  String html, {
  PluginRegistry? registry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CookedHtml(html: html, registry: registry),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The same, under a shell holding one connected site — which is what a post
/// in a topic is rendered in, and what an emoji needs to resolve its `src`.
Future<ShellController> pumpCookedInShell(
  WidgetTester tester,
  String html, {
  http.Client? emoji,
  FakeDiscourseApi? api,
  FakeAuthenticator? authenticator,
  SiteImageRepository? siteImages,
  SiteLifecycle? lifecycle,
  Widget? child,
}) async {
  EmojiCache.instance = EmojiCache(
    client: emoji ?? MockClient((_) async => http.Response('', 404)),
  );
  addTearDown(EmojiCache.instance.clear);

  final siteLifecycle = lifecycle ?? SiteLifecycle();
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: api ?? FakeDiscourseApi(),
    authenticator: authenticator ?? FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    lifecycle: siteLifecycle,
    siteImages: siteImages,
  );
  addTearDown(controller.dispose);
  await controller.load();

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(child: child ?? CookedHtml(html: html)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _CountingCookedHtml extends CookedHtml {
  const _CountingCookedHtml({required super.html, required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return super.build(context);
  }
}

/// A real 1×1 transparent PNG. It has to decode, not merely look like one:
/// [Image] falls back to the shortcode when it cannot, which is the very
/// thing the emoji tests are distinguishing.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// The flattened text of the paragraph containing [within].
///
/// Distinct from [renderedText], which matches *any* `RichText` — including the
/// one a pill's own `Text` builds. This is how to ask what the paragraph itself
/// says, where a pill shows up as the `￼` a `WidgetSpan` flattens to.
String paragraphOf(WidgetTester tester, String within) => tester
    .widgetList<RichText>(find.byType(RichText))
    .firstWhere((widget) => widget.text.toPlainText().contains(within))
    .text
    .toPlainText();

bool isUnderlined(WidgetTester tester, String text) =>
    styleOf(tester, text).decoration?.contains(TextDecoration.underline) ??
    false;

/// The style HtmlWidget resolved for the run of text reading [text].
TextStyle styleOf(WidgetTester tester, String text) {
  final richText = tester
      .widgetList<RichText>(find.byType(RichText))
      .firstWhere((widget) => widget.text.toPlainText().contains(text));

  TextStyle? found;
  richText.text.visitChildren((span) {
    if (span is TextSpan && span.text?.contains(text) == true) {
      found = span.style;
      return false;
    }
    return true;
  });

  return found ?? richText.text.style!;
}

void main() {
  testWidgets('loads a secure cooked image with the connected account', (
    tester,
  ) async {
    const siteUrl = 'https://meta.discourse.org';
    final authenticator = FakeAuthenticator()..keys[siteUrl] = 'account-key';
    final lifecycle = SiteLifecycle();
    late http.Request sent;
    final siteImages = SiteImageRepository(
      credentials: authenticator,
      lifecycle: lifecycle,
      client: MockClient((request) async {
        sent = request;
        return http.Response.bytes(onePixelPng, 200);
      }),
    );

    await pumpCookedInShell(
      tester,
      '<p><img src="/secure-uploads/original/image.png" alt="A secret"></p>',
      authenticator: authenticator,
      lifecycle: lifecycle,
      siteImages: siteImages,
    );

    expect(find.byType(SiteImage), findsOneWidget);
    expect(sent.url, Uri.parse('$siteUrl/secure-uploads/original/image.png'));
    expect(sent.headers['User-Api-Key'], 'account-key');
    expect(sent.headers['User-Api-Client-Id'], 'test-client');
    expect(
      tester.widgetList<Image>(find.byType(Image)).map((image) => image.image),
      contains(isA<MemoryImage>()),
    );
  });

  testWidgets('chat paragraphs use Discourse compact outer margins', (
    tester,
  ) async {
    const html = '<p>First</p><p>Second</p>';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: CookedHtml(html: html, compactParagraphs: true),
        ),
      ),
    );
    await tester.pump();

    final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    final styles = renderer.customStylesBuilder!;
    final paragraphs = html_parser
        .parseFragment(html)
        .nodes
        .whereType<dom.Element>()
        .toList(growable: false);

    expect(styles(paragraphs.first), {'margin': '0.1em 0 0.5em'});
    expect(styles(paragraphs.last), {'margin': '0.5em 0 0.1em'});
  });

  testWidgets('horizontal rules use Discourse content border color', (
    tester,
  ) async {
    const html = '<p>Before</p><hr><p>After</p>';
    await pumpCooked(tester, html);

    final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    final styles = renderer.customStylesBuilder!;
    final rule = html_parser.parseFragment(html).querySelector('hr')!;

    expect(styles(rule), {'border-top': '1px solid #2b2e35'});
  });

  testWidgets('revision diff markers receive insert and delete backgrounds', (
    tester,
  ) async {
    const html =
        '<p><del>before</del><ins>after</ins></p>'
        '<p class="diff-del">removed</p>'
        '<p class="diff-ins">added</p>';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: CookedHtml(html: html, revisionDiff: true)),
      ),
    );

    final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    final styles = renderer.customStylesBuilder!;
    final elements = html_parser.parseFragment(html).querySelectorAll('*');
    final deleted = styles(
      elements.firstWhere((node) => node.localName == 'del'),
    )!;
    final inserted = styles(
      elements.firstWhere((node) => node.localName == 'ins'),
    )!;
    final deletedBlock = styles(
      elements.firstWhere((node) => node.classes.contains('diff-del')),
    )!;
    final insertedBlock = styles(
      elements.firstWhere((node) => node.classes.contains('diff-ins')),
    )!;

    expect(deleted['background-color'], isNotEmpty);
    expect(inserted['background-color'], isNotEmpty);
    expect(deleted['background-color'], isNot(inserted['background-color']));
    expect(deleted['text-decoration'], 'none');
    expect(inserted['text-decoration'], 'none');
    expect(deletedBlock['background-color'], deleted['background-color']);
    expect(insertedBlock['background-color'], inserted['background-color']);
  });

  testWidgets('unrelated shell notifications do not rebuild post HTML', (
    tester,
  ) async {
    var builds = 0;
    final controller = await pumpCookedInShell(
      tester,
      '<p>Already rendered</p>',
      child: _CountingCookedHtml(
        html: '<p>Already rendered</p>',
        onBuild: () => builds += 1,
      ),
    );
    expect(builds, 1);

    // Selecting the current rail entry notifies the shell to reveal its
    // sidebar, but neither the site nor this post changed.
    controller.selectInstance(0);
    await tester.pump();

    expect(builds, 1);
    expect(renderedText('Already rendered'), findsOneWidget);
  });

  group('links', () {
    testWidgets('are not underlined, the way Discourse draws them', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<p>See <a href="https://meta.discourse.org">meta</a>.</p>',
      );

      expect(isUnderlined(tester, 'meta'), isFalse);
    });

    testWidgets('keep the decoration their own markup asks for', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<p><a href="https://meta.discourse.org"><del>gone</del></a></p>',
      );

      expect(styleOf(tester, 'gone').decoration, TextDecoration.lineThrough);
    });

    testWidgets('stay undecorated inside a quote', (tester) async {
      await pumpCooked(
        tester,
        '<blockquote><p><a href="https://meta.discourse.org">meta</a></p>'
        '</blockquote>',
      );

      expect(isUnderlined(tester, 'meta'), isFalse);
    });

    testWidgets('stay undecorated inside a onebox body', (tester) async {
      await pumpCooked(
        tester,
        '<aside class="onebox"><article class="onebox-body">'
        '<p>Read <a href="https://meta.discourse.org">meta</a></p>'
        '</article></aside>',
      );

      expect(isUnderlined(tester, 'meta'), isFalse);
    });
  });

  group('mentions', () {
    // What Discourse cooks for a name it resolved.
    const sam = '<p>ask <a class="mention" href="/u/sam">@sam</a> about it</p>';

    testWidgets('are drawn as a pill rather than as a link', (tester) async {
      await pumpCooked(tester, sam);

      expect(find.byType(MentionPill), findsOneWidget);
      expect(find.text('@sam'), findsOneWidget);

      // The label is drawn by the pill now, not by the paragraph — which is
      // the whole difference between a pill and a styled link. The paragraph
      // keeps one placeholder where the mention was.
      //
      // `renderedText` is no help here: it matches any RichText, and the
      // pill's own Text builds one saying exactly `@sam`.
      expect(paragraphOf(tester, 'about it'), contains('￼'));
      expect(paragraphOf(tester, 'about it'), isNot(contains('@sam')));
    });

    testWidgets('keep the case the post was written in', (tester) async {
      // Discourse lowercases the href and leaves the text alone, and the text
      // is what a reader recognises.
      await pumpCooked(
        tester,
        '<p><a class="mention" href="/u/sam">@sAm</a></p>',
      );

      expect(find.text('@sAm'), findsOneWidget);
      expect(
        tester.widget<MentionPill>(find.byType(MentionPill)).href,
        '/u/sam',
      );
    });

    testWidgets('a group mention is a pill too', (tester) async {
      await pumpCooked(
        tester,
        '<p><a class="mention-group notify" href="/groups/staff">@staff</a></p>',
      );

      expect(find.byType(MentionPill), findsOneWidget);
      expect(find.text('@staff'), findsOneWidget);
    });

    testWidgets('one the site could not resolve stays text', (tester) async {
      // A span, not an anchor: nobody by that name, or nobody this reader may
      // see. Discourse does not pill it, and neither should we — a pill would
      // promise a person who is not there.
      await pumpCooked(
        tester,
        '<p>ask <span class="mention">@nobody</span></p>',
      );

      expect(find.byType(MentionPill), findsNothing);
      expect(renderedText('@nobody'), findsOneWidget);
    });

    testWidgets('leave an ordinary link alone', (tester) async {
      await pumpCooked(
        tester,
        '<p><a href="https://meta.discourse.org">meta</a></p>',
      );

      expect(find.byType(MentionPill), findsNothing);
      expect(renderedText('meta'), findsOneWidget);
    });

    testWidgets('a name longer than the line is cut, not an overflow', (
      tester,
    ) async {
      // A pill does not wrap, so on a narrow enough line it is wider than the
      // Row it sits in — which throws rather than drawing. The name comes from
      // the site, and a post is not where that should be discovered.
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpCooked(
        tester,
        '<p>hi <a class="mention" href="/u/x">'
        '@a_username_far_longer_than_any_line_could_ever_hold</a></p>',
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(MentionPill), findsOneWidget);
    });
  });

  group('hashtags', () {
    /// What Discourse cooks. The `<svg>` is always `square-full`, whatever the
    /// type — it is a placeholder its own client replaces at runtime.
    String cooked({
      required String type,
      required String slug,
      required int id,
      required String href,
      String? styleType,
      String? icon,
      String? emoji,
      String? text,
    }) =>
        '<p>see <a class="hashtag-cooked" href="$href" data-type="$type" '
        'data-slug="$slug" data-id="$id"'
        '${styleType == null ? '' : ' data-style-type="$styleType"'}'
        '${icon == null ? '' : ' data-icon="$icon"'}'
        '${emoji == null ? '' : ' data-emoji="$emoji"'}'
        '><span class="hashtag-icon-placeholder"><svg class="fa d-icon '
        'd-icon-square-full svg-icon svg-node"><use href="#square-full">'
        '</use></svg></span><span>${text ?? slug}</span></a> for more</p>';

    final category = cooked(
      type: 'category',
      slug: 'bug',
      id: 5,
      href: '/c/bug/5',
      styleType: 'square',
    );

    FakeDiscourseApi withCategories(List<TopicCategory> categories) =>
        FakeDiscourseApi(
          feeds: {'/latest.json': const <Topic>[]},
          categoryList: categories,
        );

    testWidgets('a category is drawn as a pill with its own colour', (
      tester,
    ) async {
      await pumpCookedInShell(
        tester,
        category,
        api: withCategories(const [
          TopicCategory(id: 5, name: 'Bug', color: '0088CC', slug: 'bug'),
        ]),
      );

      expect(find.text('bug'), findsOneWidget);
      final square = tester.widget<CategorySquare>(find.byType(CategorySquare));
      expect(square.color, const Color(0xFF0088CC));
      expect(square.parentColor, isNull);
      // The label is the pill's, not the paragraph's.
      expect(paragraphOf(tester, 'for more'), isNot(contains('bug')));
    });

    testWidgets('a subcategory square is split, parent on the left', (
      tester,
    ) async {
      await pumpCookedInShell(
        tester,
        cooked(
          type: 'category',
          slug: 'child',
          id: 12,
          href: '/c/parent/child/12',
          styleType: 'square',
          text: 'Parent > Child',
        ),
        api: withCategories(const [
          TopicCategory(id: 7, name: 'Parent', color: 'FF0000', slug: 'parent'),
          TopicCategory(
            id: 12,
            name: 'Child',
            color: '00FF00',
            slug: 'child',
            parentCategoryId: 7,
          ),
        ]),
      );

      final square = tester.widget<CategorySquare>(find.byType(CategorySquare));
      expect(square.parentColor, const Color(0xFFFF0000));
      expect(square.color, const Color(0xFF00FF00));
      // Discourse writes the full name into the anchor; it beats the slug.
      expect(find.text('Parent > Child'), findsOneWidget);
    });

    testWidgets('a category nobody has fetched still draws', (tester) async {
      // The category list is capped on a large site, so this is ordinary
      // rather than exceptional. The label and the tap are what matter.
      await pumpCookedInShell(tester, category, api: withCategories(const []));

      expect(find.text('bug'), findsOneWidget);
      expect(
        tester.widget<CategorySquare>(find.byType(CategorySquare)).color,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tag draws its glyph and no swatch', (tester) async {
      await pumpCookedInShell(
        tester,
        cooked(
          type: 'tag',
          slug: 'ux',
          id: 3,
          href: '/tag/ux/3',
          styleType: 'icon',
          icon: 'tag',
        ),
      );

      expect(find.text('ux'), findsOneWidget);
      expect(find.byType(CategorySquare), findsNothing);
      expect(find.dIcon(DIcons.tag), findsOneWidget);
    });

    testWidgets('a none colour policy ignores contributed colour values', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: HashtagPill(
              label: 'issue',
              baseStyle: null,
              presentation: HashtagPresentation(
                type: 'issue',
                style: HashtagStyle.icon,
                fallbackIcon: DIcons.link,
                colorPolicy: HashtagColorPolicy.none,
                colorValues: const [0xFFFF0000],
              ),
            ),
          ),
        ),
      );

      final icon = tester.widget<DIcon>(find.dIcon(DIcons.link));
      expect(icon.color, isNot(const Color(0xFFFF0000)));
    });

    testWidgets('an installed room uses its microphone when no icon arrives', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        cooked(
          type: 'room',
          slug: 'town-hall',
          id: 14,
          href: '/resenha/r/town-hall',
          styleType: 'icon',
          text: 'Town Hall',
        ),
        registry: PluginRegistry.validated(const [_RoomHashtagPlugin()]),
      );

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.label, 'Town Hall');
      expect(pill.href, '/resenha/r/town-hall');
      expect(find.dIcon(DIcons.microphoneLines), findsOneWidget);
      expect(find.dIcon(DIcons.tag), findsNothing);
    });

    testWidgets(
      'an installed room uses its microphone when its wire icon is unknown',
      (tester) async {
        await pumpCooked(
          tester,
          cooked(
            type: 'room',
            slug: 'town-hall',
            id: 14,
            href: '/resenha/r/town-hall',
            styleType: 'icon',
            icon: 'not-an-icon-this-app-has',
            text: 'Town Hall',
          ),
          registry: PluginRegistry.validated(const [_RoomHashtagPlugin()]),
        );

        expect(find.dIcon(DIcons.microphoneLines), findsOneWidget);
        expect(find.dIcon(DIcons.link), findsNothing);
      },
    );

    testWidgets('a room without its plugin stays a neutral linked pill', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        cooked(
          type: 'room',
          slug: 'town-hall',
          id: 14,
          href: '/resenha/r/town-hall',
          styleType: 'icon',
          text: 'Town Hall',
        ),
        registry: PluginRegistry.empty,
      );

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.label, 'Town Hall');
      expect(pill.href, '/resenha/r/town-hall');
      expect(pill.presentation.type, 'room');
      expect(find.dIcon(DIcons.link), findsOneWidget);
      expect(find.dIcon(DIcons.tag), findsNothing);
      expect(find.dIcon(DIcons.microphoneLines), findsNothing);
    });

    testWidgets('an arbitrary unknown type stays a neutral linked pill', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        cooked(
          type: 'calendar-event',
          slug: 'launch-party',
          id: 42,
          href: '/calendar/event/42',
          styleType: 'icon',
          text: 'Launch party',
        ),
        registry: PluginRegistry.validated(const [_RoomHashtagPlugin()]),
      );

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.label, 'Launch party');
      expect(pill.href, '/calendar/event/42');
      expect(pill.presentation.type, 'calendar-event');
      expect(find.dIcon(DIcons.link), findsOneWidget);
      expect(find.dIcon(DIcons.tag), findsNothing);
      expect(find.dIcon(DIcons.microphoneLines), findsNothing);
    });

    testWidgets('an opaque type is not trimmed into an installed kind', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        cooked(
          type: ' room ',
          slug: 'town-hall',
          id: 14,
          href: '/resenha/r/town-hall',
          styleType: 'icon',
          text: 'Town Hall',
        ),
        registry: PluginRegistry.validated(const [_RoomHashtagPlugin()]),
      );

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.presentation.type, ' room ');
      expect(find.dIcon(DIcons.link), findsOneWidget);
      expect(find.dIcon(DIcons.microphoneLines), findsNothing);
    });

    testWidgets('an installed hashtag plugin leaves core kinds unchanged', (
      tester,
    ) async {
      final registry = PluginRegistry.validated(const [_RoomHashtagPlugin()]);
      await pumpCooked(
        tester,
        cooked(
          type: 'category',
          slug: 'known',
          id: 6,
          href: '/c/known/6',
          styleType: 'icon',
        ),
        registry: registry,
      );
      expect(find.dIcon(DIcons.folder), findsOneWidget);

      await pumpCooked(
        tester,
        cooked(
          type: 'tag',
          slug: 'ux',
          id: 3,
          href: '/tag/ux/3',
          styleType: 'icon',
        ),
        registry: registry,
      );
      expect(find.dIcon(DIcons.tag), findsOneWidget);
      expect(find.dIcon(DIcons.microphoneLines), findsNothing);
    });

    testWidgets('an icon the app does not carry falls back to the kind', (
      tester,
    ) async {
      // `data-icon` is whatever an admin picked, and the sprite here holds
      // what this app draws rather than all of Font Awesome.
      await pumpCookedInShell(
        tester,
        cooked(
          type: 'category',
          slug: 'known',
          id: 6,
          href: '/c/known/6',
          styleType: 'icon',
          icon: 'not-an-icon-this-app-has',
        ),
      );

      expect(find.dIcon(DIcons.folder), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an emoji style draws the artwork', (tester) async {
      await pumpCookedInShell(
        tester,
        cooked(
          type: 'category',
          slug: 'rocket',
          id: 8,
          href: '/c/rocket/8',
          styleType: 'emoji',
          emoji: 'rocket',
        ),
        emoji: MockClient((_) async => http.Response.bytes(onePixelPng, 200)),
      );

      expect(find.byType(EmojiImage), findsOneWidget);
      expect(find.byType(CategorySquare), findsNothing);
    });

    testWidgets('the placeholder svg leaves nothing behind', (tester) async {
      // Every cooked hashtag carries the same `square-full` glyph whatever it
      // is — a placeholder Discourse's own client replaces. Drawing it would
      // put a filled square on every tag on the site, beside the real prefix.
      await pumpCookedInShell(tester, category, api: withCategories(const []));

      expect(find.byType(CategorySquare), findsOneWidget);
      expect(find.byType(DIcon), findsNothing);
      expect(paragraphOf(tester, 'for more'), isNot(contains('square')));
    });

    testWidgets('one the site could not resolve stays text', (tester) async {
      await pumpCooked(
        tester,
        '<p>see <span class="hashtag-raw">#secret</span> for more</p>',
      );

      expect(find.byType(HashtagPill), findsNothing);
      expect(renderedText('#secret'), findsOneWidget);
    });

    testWidgets('are left alone with no shell to resolve the site', (
      tester,
    ) async {
      // A quote or an onebox rendered outside the shell. The pill still draws;
      // it simply has no categories to colour itself from.
      await pumpCooked(tester, category);

      expect(find.text('bug'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leave an ordinary link alone', (tester) async {
      await pumpCooked(tester, '<p><a href="/c/bug/5">the category</a></p>');

      expect(find.byType(HashtagPill), findsNothing);
      expect(renderedText('the category'), findsOneWidget);
    });

    testWidgets('a post that is nothing but a hashtag still draws a chip', (
      tester,
    ) async {
      // A paragraph with no text around the anchor reaches the renderer as a
      // block, with a tight width — where a chip that took the constraint at
      // face value would draw as a full-width bar.
      await pumpCookedInShell(
        tester,
        cooked(
          type: 'category',
          slug: 'bug',
          id: 5,
          href: '/c/bug/5',
          styleType: 'square',
        ).replaceAll('see ', '').replaceAll(' for more', ''),
        api: withCategories(const [
          TopicCategory(id: 5, name: 'Bug', color: '0088CC', slug: 'bug'),
        ]),
      );

      // The outermost Container in the pill is the chip itself; the inner one
      // is the colour swatch.
      final chip = tester.getSize(
        find
            .descendant(
              of: find.byType(HashtagPill),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(chip.width, lessThan(200));
    });
  });

  group('inline code', () {
    testWidgets('is drawn as a chip rather than bare monospace text', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<p>Try <code>tl3_requires_posts_read</code>.</p>',
      );

      final code = tester.widget<InlineCode>(find.byType(InlineCode));
      expect(code.text, 'tl3_requires_posts_read');
      expect(code.isLink, isFalse);

      final style = tester
          .widget<Text>(
            find.descendant(
              of: find.byType(InlineCode),
              matching: find.byType(Text),
            ),
          )
          .style!;
      expect(style.fontFamily, monospaceFontFamily);
      expect(style.fontFamilyFallback, monospaceFallback);
      expect(style.fontFeatures, contains(const FontFeature.disable('liga')));
      // Exactly `0.875rem` against Discourse's 16px cooked body.
      expect(style.fontSize, 14);
    });

    testWidgets('keeps the whitespace the author wrote', (tester) async {
      await pumpCooked(tester, '<p>Type <code>a  b</code>.</p>');

      expect(tester.widget<InlineCode>(find.byType(InlineCode)).text, 'a  b');
    });

    testWidgets('is colored as a link when it is one', (tester) async {
      await pumpCooked(
        tester,
        '<p><a href="https://meta.discourse.org"><code>meta</code></a></p>',
      );

      expect(tester.widget<InlineCode>(find.byType(InlineCode)).isLink, isTrue);
    });

    testWidgets('leaves a code block alone', (tester) async {
      await pumpCooked(
        tester,
        '<pre><code class="lang-ruby">puts 1</code></pre>',
      );

      expect(find.byType(InlineCode), findsNothing);
      expect(find.byType(CodeBlock), findsOneWidget);
    });
  });

  group('emoji', () {
    // What Discourse actually cooks: a root-relative src, the shortcode in both
    // `alt` and `title`, and a fixed 20px.
    const smile =
        '<p>Hello '
        '<img src="/images/emoji/twitter/slight_smile.png?v=15" '
        'title=":slight_smile:" class="emoji" alt=":slight_smile:" '
        'loading="lazy" width="20" height="20">'
        '</p>';

    testWidgets('are drawn from the site rather than left as a shortcode', (
      tester,
    ) async {
      await pumpCookedInShell(
        tester,
        smile,
        emoji: MockClient((_) async => http.Response.bytes(onePixelPng, 200)),
      );

      final image = tester.widget<EmojiImage>(find.byType(EmojiImage));
      expect(
        image.url,
        'https://meta.discourse.org/images/emoji/twitter/slight_smile.png?v=15',
      );
      // Before this existed, HtmlWidget could not resolve the src and rendered
      // the alt attribute — so the whole feature is that this is gone.
      expect(renderedText(':slight_smile:'), findsNothing);
    });

    testWidgets('a standalone emoji is large and stays at the leading edge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpCookedInShell(
        tester,
        '<p><img src="/images/emoji/twitter/smiley.png?v=15" '
        'title=":smiley:" class="emoji only-emoji" alt=":smiley:" '
        'loading="lazy" width="20" height="20"></p>',
        emoji: MockClient((_) async => http.Response.bytes(onePixelPng, 200)),
      );

      final emoji = find.byType(EmojiImage);
      expect(tester.getSize(emoji), const Size.square(32));
      expect(tester.getTopLeft(emoji).dx, 0);
    });

    testWidgets(
      'fall back to their shortcode when the site will not serve one',
      (tester) async {
        await pumpCookedInShell(tester, smile);

        expect(renderedText(':slight_smile:'), findsOneWidget);
      },
    );

    testWidgets('are left alone with no shell to resolve the site', (
      tester,
    ) async {
      // A quote or an onebox body rendered on its own. The alt text stands,
      // exactly as it did everywhere before emoji rendered at all.
      await pumpCooked(tester, smile);

      expect(find.byType(EmojiImage), findsNothing);
      expect(renderedText(':slight_smile:'), findsOneWidget);
    });

    testWidgets('leave an ordinary image alone', (tester) async {
      await pumpCookedInShell(
        tester,
        '<p><img src="/uploads/default/1.png" alt="a screenshot"></p>',
      );

      expect(find.byType(EmojiImage), findsNothing);
    });
  });
}

/// HtmlWidget renders into a bare RichText, which find.text ignores.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  description: 'rendered text containing "$text"',
);

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
