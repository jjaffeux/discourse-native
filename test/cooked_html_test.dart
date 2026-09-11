import 'dart:convert';
import 'dart:typed_data';

import 'package:discourse_native/discourse_ui.dart'
    show DAvatar, DAvatarFallback;
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_status.dart';
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
import 'package:discourse_native/src/shell/user_status.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/finders.dart';
import 'support/media_pipeline.dart';

Future<void> pumpCooked(
  WidgetTester tester,
  String html, {
  PluginRegistry? registry,
  Post? post,
  bool compactParagraphs = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CookedHtml(
            html: html,
            registry: registry,
            post: post,
            compactParagraphs: compactParagraphs,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<ShellController> pumpCookedInShell(
  WidgetTester tester,
  String html, {
  http.Client? emoji,
  FakeDiscourseApi? api,
  FakeAuthenticator? authenticator,
  SiteImageRepository? siteImages,
  SiteLifecycle? lifecycle,
  AppSettingsPersistence? appSettingsPersistence,
  Widget? child,
}) async {
  installTestMediaPipeline(
    client: emoji ?? MockClient((_) async => http.Response('', 404)),
  );

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
    appSettingsStore: appSettingsPersistence == null
        ? null
        : AppSettingsStore(persistence: appSettingsPersistence),
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

class _CountingSibling extends dom.Element {
  _CountingSibling() : super.tag('div');

  var nameReads = 0;

  @override
  String? get localName {
    nameReads += 1;
    return super.localName;
  }
}

class _CountingLinkCount extends PostLinkCount {
  const _CountingLinkCount({
    required super.url,
    required super.clicks,
    super.internal,
    required this.onUrlRead,
  });

  final VoidCallback onUrlRead;

  @override
  String get url {
    onUrlRead();
    return super.url;
  }
}

final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

final Uint8List onePixelGif = base64Decode(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEKAAAALAAAAAABAAEAAAIBRAAh+QQBCgAAACwAAAAAAQABAAACAUQAOw==',
);

String paragraphOf(WidgetTester tester, String within) => tester
    .widgetList<RichText>(find.byType(RichText))
    .firstWhere((widget) => widget.text.toPlainText().contains(within))
    .text
    .toPlainText();

bool isUnderlined(WidgetTester tester, String text) =>
    styleOf(tester, text).decoration?.contains(TextDecoration.underline) ??
    false;

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
  testWidgets(
    'link surface styling updates and resets without changing other callers',
    (tester) async {
      Future<void> render(TextStyle? linkStyle) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: CookedHtml(
                html: '<p>Visit <a href="https://example.com">the link</a></p>',
                linkStyle: linkStyle,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(null);
      final originalColor = styleOf(tester, 'the link').color;
      expect(isUnderlined(tester, 'the link'), isFalse);
      for (final color in [Colors.white, Colors.black]) {
        await render(
          TextStyle(color: color, decoration: TextDecoration.underline),
        );
        expect(styleOf(tester, 'the link').color, color);
        expect(isUnderlined(tester, 'the link'), isTrue);
      }
      await render(null);
      expect(styleOf(tester, 'the link').color, originalColor);
      expect(isUnderlined(tester, 'the link'), isFalse);
    },
  );

  testWidgets('GIFs honor the app default and can be controlled individually', (
    tester,
  ) async {
    const siteUrl = 'https://meta.discourse.org';
    final lifecycle = SiteLifecycle();
    final siteImages = SiteImageRepository(
      credentials: FakeAuthenticator(),
      lifecycle: lifecycle,
      client: MockClient(
        (_) async => http.Response.bytes(
          onePixelGif,
          200,
          headers: {'content-type': 'image/gif'},
        ),
      ),
    );
    final persistence = MemoryAppSettingsPersistence(
      disableGifAnimations: true,
    );

    final controller = await pumpCookedInShell(
      tester,
      '',
      lifecycle: lifecycle,
      siteImages: siteImages,
      appSettingsPersistence: persistence,
      child: const Row(
        children: [
          SiteImage(
            url: '/uploads/first.gif',
            siteUrl: siteUrl,
            width: 100,
            height: 100,
            gifPlaybackControls: true,
          ),
          SiteImage(
            url: '/uploads/second.gif',
            siteUrl: siteUrl,
            width: 100,
            height: 100,
            gifPlaybackControls: true,
          ),
        ],
      ),
    );

    expect(find.bySemanticsLabel('Play GIF'), findsNWidgets(2));
    var images = find.byType(Image).evaluate().toList();
    expect(MediaQuery.of(images[0]).disableAnimations, isTrue);
    expect(MediaQuery.of(images[1]).disableAnimations, isTrue);

    await tester.tap(find.bySemanticsLabel('Play GIF').first);
    await tester.pump();

    expect(find.bySemanticsLabel('Pause GIF'), findsOneWidget);
    expect(find.bySemanticsLabel('Play GIF'), findsOneWidget);
    images = find.byType(Image).evaluate().toList();
    expect(MediaQuery.of(images[0]).disableAnimations, isFalse);
    expect(MediaQuery.of(images[1]).disableAnimations, isTrue);

    await controller.appSettings.setDisableGifAnimations(false);
    await tester.pump();

    expect(find.bySemanticsLabel('Pause GIF'), findsNWidgets(2));
  });

  testWidgets('loads a secure cooked image with the connected account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
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
    final image = tester
        .widgetList<Image>(find.byType(Image))
        .firstWhere((image) => image.image is ResizeImage);
    final provider = image.image as ResizeImage;
    expect(provider.width, 800);
    expect(provider.imageProvider, isA<MemoryImage>());
  });

  for (final avatarClass in [
    'avatar',
    'onebox-avatar',
    'onebox-avatar-inline',
  ]) {
    testWidgets('$avatarClass keeps embedded image dimensions and label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final src = Uri.dataFromBytes(onePixelPng, mimeType: 'image/png');

        await pumpCooked(
          tester,
          '<p><img class="$avatarClass" src="$src" '
          'width="24" height="24" alt="Sam"></p>'
          '<p><img src="$src" width="60" height="40" alt="Landscape"></p>',
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(DAvatar)), const Size.square(24));
        expect(find.bySemanticsLabel('Sam'), findsOneWidget);
        expect(tester.getSize(find.byType(Image).last), const Size(60, 40));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('inline avatars retain authenticated loading and fixed bounds', (
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
      '<p><img class="avatar" src="/secure-uploads/avatar.png" '
      'width="32" height="32" alt="Sam"></p>',
      authenticator: authenticator,
      lifecycle: lifecycle,
      siteImages: siteImages,
    );

    expect(tester.getSize(find.byType(DAvatar)), const Size.square(32));
    expect(sent.url, Uri.parse('$siteUrl/secure-uploads/avatar.png'));
    expect(sent.headers['User-Api-Key'], 'account-key');
    expect(sent.headers['User-Api-Client-Id'], 'test-client');
    expect(tester.takeException(), isNull);
  });

  for (final source in [
    'https://cdn.example.com/missing.png',
    'data:image/png;base64,YmFk',
  ]) {
    testWidgets('failed avatar $source keeps its label and compact fallback', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpCooked(
          tester,
          '<p><img class="avatar" src="$source" '
          'width="24" height="24" alt="Sam"></p>',
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(DAvatar)), const Size.square(24));
        expect(find.byType(DAvatarFallback), findsOneWidget);
        expect(find.bySemanticsLabel('Sam'), findsOneWidget);
        expect(find.text('Sam'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  test('containing topics have value semantics for HTML rebuild triggers', () {
    final id = int.parse('1');
    final first = PluginContainingTopic(id: id, slug: 'topic', archived: false);
    final second = PluginContainingTopic(
      id: id,
      slug: 'topic',
      archived: false,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  for (final (description, source, margins) in [
    ('empty HTML', '', <String?>[]),
    ('a lone paragraph', '<p>Only</p>', ['0.1em 0 0.1em']),
    (
      'multiple paragraphs',
      '<p>First</p><p>Middle</p><p>Last</p>',
      ['0.1em 0 0.5em', '0.5em 0 0.5em', '0.5em 0 0.1em'],
    ),
    (
      'text, comments and non-paragraph siblings',
      'Leading<!-- before --><div>Before</div><p>First</p>'
          '<!-- between -->Between<span>Inline</span><p>Last</p>'
          '<hr><!-- after -->Trailing',
      ['0.1em 0 0.5em', '0.5em 0 0.1em'],
    ),
    (
      'a lone paragraph among other siblings',
      'Leading<!-- before --><div>Before</div><p>Only</p><hr>Trailing',
      ['0.1em 0 0.1em'],
    ),
    (
      'nested paragraphs',
      '<div><p>Nested first</p></div><p>First</p>'
          '<div><p>Nested middle</p></div><p>Last</p>'
          '<div><p>Nested last</p></div>',
      [null, '0.1em 0 0.5em', null, '0.5em 0 0.1em', null],
    ),
    ('only nested paragraphs', '<div><p>Nested</p></div>', <String?>[null]),
  ]) {
    testWidgets('compact spacing handles $description', (tester) async {
      await pumpCooked(tester, source, compactParagraphs: true);

      final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      final styles = renderer.customStylesBuilder!;
      final paragraphs = html_parser
          .parseFragment(source)
          .querySelectorAll('p');

      expect([
        for (final paragraph in paragraphs) styles(paragraph)?['margin'],
      ], margins);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact spacing scans each document once per widget build', (
    tester,
  ) async {
    await pumpCooked(tester, '<p>Rendered</p>', compactParagraphs: true);
    final styles = tester
        .widget<HtmlWidget>(find.byType(HtmlWidget))
        .customStylesBuilder!;
    final siblings = [_CountingSibling(), _CountingSibling()];
    final documents = [
      for (final sibling in siblings)
        dom.DocumentFragment()
          ..nodes.addAll([
            sibling,
            for (var index = 0; index < 200; index++) dom.Element.tag('p'),
          ]),
    ];
    final paragraphs = [
      for (final document in documents) document.children.skip(1).toList(),
    ];

    // Interleave documents and visit paragraphs backwards: the bounds must
    // come from document order, independent of the callback's visit order.
    for (var index = 199; index >= 0; index--) {
      for (final elements in paragraphs) {
        final top = index == 0 ? '0.1em' : '0.5em';
        final bottom = index == 199 ? '0.1em' : '0.5em';
        expect(styles(elements[index]), {'margin': '$top 0 $bottom'});
      }
    }
    expect(siblings.map((sibling) => sibling.nameReads), [1, 1]);

    await pumpCooked(tester, '<p>Updated</p>', compactParagraphs: true);
    final rebuiltStyles = tester
        .widget<HtmlWidget>(find.byType(HtmlWidget))
        .customStylesBuilder!;
    expect(rebuiltStyles(paragraphs.first.first), {'margin': '0.1em 0 0.5em'});
    expect(siblings.map((sibling) => sibling.nameReads), [2, 1]);
  });

  testWidgets('paragraph styles and content follow HTML and compact updates', (
    tester,
  ) async {
    Future<void> check(
      String source,
      List<String?> margins, {
      bool compact = true,
    }) async {
      await pumpCooked(tester, source, compactParagraphs: compact);
      final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      final styles = renderer.customStylesBuilder!;
      expect([
        for (final paragraph in html_parser.parseFragment(source).children)
          styles(paragraph)?['margin'],
      ], margins);
    }

    await check('<p>Only</p>', ['0.1em 0 0.1em']);
    expect(renderedText('Only'), findsOneWidget);
    final loneHeight = tester.getSize(find.byType(CookedHtml)).height;

    await check('<p>First</p><p>Middle</p><p>Last</p>', [
      '0.1em 0 0.5em',
      '0.5em 0 0.5em',
      '0.5em 0 0.1em',
    ]);
    expect(renderedText('Only'), findsNothing);
    expect(renderedText('Middle'), findsOneWidget);

    await check('<p>First</p><p>Last</p>', [null, null], compact: false);
    expect(renderedText('Middle'), findsNothing);

    await check('<p>First</p><p>Last</p>', ['0.1em 0 0.5em', '0.5em 0 0.1em']);
    await check('<p>Only</p>', ['0.1em 0 0.1em']);
    expect(renderedText('First'), findsNothing);
    expect(tester.getSize(find.byType(CookedHtml)).height, loneHeight);
    expect(tester.takeException(), isNull);
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
    expect(deletedBlock['margin'], isNull);
    expect(insertedBlock['margin'], isNull);
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

    controller.selectInstance(0);
    await tester.pump();

    expect(builds, 1);
    expect(renderedText('Already rendered'), findsOneWidget);
  });

  group('links', () {
    for (final (label, markup) in [
      (
        'inline text',
        '<p>Read <a href="/t/another-topic/42/8">another topic</a> here.</p>',
      ),
      (
        'block text',
        '<a href="/t/another-topic/42/8"><div>another topic</div></a>',
      ),
      (
        'inline code',
        '<p><a href="/t/another-topic/42/8"><code>another topic</code></a></p>',
      ),
      (
        'onebox card',
        '<aside class="onebox" data-onebox-src="/t/another-topic/42/8">'
            '<article class="onebox-body"><h3><a href="/t/another-topic/42/8">'
            'another topic</a></h3></article></aside>',
      ),
    ]) {
      testWidgets('middle-click opens a background tab from $label', (
        tester,
      ) async {
        final controller = await pumpCookedInShell(tester, markup);
        final original = controller.activeTab;
        final text = find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('another topic'),
        );
        final paragraph = tester.renderObject<RenderParagraph>(text.first);
        final start = paragraph.text.toPlainText().indexOf('another topic');
        final box = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: start + 13),
            )
            .first;
        await tester.tapAt(
          paragraph.localToGlobal(box.toRect().center),
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await tester.pumpAndSettle();

        expect(controller.tabsForCurrentForum, hasLength(2));
        expect(controller.activeTab, original);
        final opened = controller.tabsForCurrentForum.last.currentContent;
        expect(opened.topicId, 42);
        expect(opened.postNumber, 8);
      });
    }

    testWidgets('middle-click opens a category hashtag in a background tab', (
      tester,
    ) async {
      final controller = await pumpCookedInShell(
        tester,
        '<p><a class="hashtag-cooked" data-type="category" data-slug="support" '
        'href="/c/support/12"><span>support</span></a></p>',
      );
      final original = controller.activeTab;

      await tester.tap(
        find.byType(HashtagPill),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();

      expect(controller.activeTab, original);
      expect(controller.tabsForCurrentForum, hasLength(2));
      expect(
        controller.tabsForCurrentForum.last.currentContent.feedPath,
        '/c/support/12.json',
      );
    });

    testWidgets('show the server click count beside a matching cooked link', (
      tester,
    ) async {
      const post = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '',
        linkCounts: [
          PostLinkCount(url: 'https://hotel.example/tour', clicks: 9),
        ],
      );

      await pumpCooked(
        tester,
        '<p>Take the <a href="https://hotel.example/tour">virtual tour</a>'
        ' today.</p>',
        post: post,
      );

      expect(renderedText('9'), findsOneWidget);
      expect(
        paragraphOf(tester, 'virtual tour'),
        contains('virtual tour\u{fffc}'),
      );
      expect(styleOf(tester, '9').fontSize, DiscourseTypography.xs);
      expect(styleOf(tester, '9').color, AppTheme.dark.discourse.whisper);
    });

    testWidgets('matches internal links before query parameters', (
      tester,
    ) async {
      const post = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '',
        linkCounts: [
          PostLinkCount(url: '/t/launch/1', clicks: 1250, internal: true),
        ],
      );

      await pumpCooked(
        tester,
        '<p><a href="/t/launch/1?u=sam">Launch topic</a></p>',
        post: post,
      );

      expect(renderedText('1.3k'), findsOneWidget);
    });

    testWidgets('omit counts from links core excludes from click tracking', (
      tester,
    ) async {
      const post = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '',
        linkCounts: [PostLinkCount(url: '/skip', clicks: 7)],
      );

      await pumpCooked(
        tester,
        '<p><a class="no-track-link" href="/skip">Skip me</a></p>',
        post: post,
      );

      expect(paragraphOf(tester, 'Skip me'), isNot(contains('7')));
    });

    Future<CustomWidgetBuilder> countBuilder(
      WidgetTester tester,
      List<PostLinkCount> counts,
    ) async {
      await pumpCooked(
        tester,
        '',
        post: Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '',
          linkCounts: counts,
        ),
      );
      return tester
          .widget<HtmlWidget>(find.byType(HtmlWidget))
          .customWidgetBuilder!;
    }

    testWidgets('use payload order across exact, query, and upload counts', (
      tester,
    ) async {
      const href = 'https://cdn.example/uploads/default/report.pdf?download=1';
      const records = [
        PostLinkCount(url: href, clicks: 1),
        PostLinkCount(
          url: 'https://cdn.example/uploads/default/report.pdf',
          clicks: 2,
          internal: true,
        ),
        PostLinkCount(
          url: '/uploads/default/report.pdf',
          clicks: 3,
          internal: true,
        ),
        PostLinkCount(
          url: '/uploads/default/report',
          clicks: 4,
          internal: true,
        ),
      ];
      for (final first in records) {
        for (final second in records) {
          if (identical(first, second)) continue;
          final builder = await countBuilder(tester, [
            first,
            second,
            const PostLinkCount(url: href, clicks: 0),
            const PostLinkCount(url: '/uploads/', clicks: -1, internal: true),
          ]);
          final anchor = html_parser
              .parseFragment('<a href="$href"> Report </a>')
              .querySelector('a')!;
          builder(anchor);
          builder(anchor);
          expect(
            anchor.attributes['data-clicks'],
            '${second.clicks}',
            reason: '${first.clicks} before ${second.clicks}',
          );
          expect(
            anchor.attributes['aria-label'],
            'Report link clicked ${second.clicks} ${second.clicks == 1 ? 'time' : 'times'}',
          );
          expect(
            anchor
                .querySelectorAll('.discourse-native-link-click-count')
                .map((badge) => badge.text),
            ['${second.clicks}'],
          );
        }
      }

      final builder = await countBuilder(tester, const [
        PostLinkCount(url: href, clicks: 8),
        PostLinkCount(url: href, clicks: 5),
        PostLinkCount(url: href, clicks: 0),
      ]);
      final anchor = dom.Element.tag('a')..attributes['href'] = href;
      builder(anchor);
      expect(anchor.attributes['aria-label'], 'link clicked 5 times');
    });

    testWidgets('keep literal URL and internal-only matching boundaries', (
      tester,
    ) async {
      final builder = await countBuilder(tester, const [
        PostLinkCount(url: '/t/internal/1', clicks: 8, internal: true),
        PostLinkCount(url: '/t/internal/1', clicks: 2, internal: true),
        PostLinkCount(url: '/t/internal/1', clicks: 10),
        PostLinkCount(url: '/t/external/2', clicks: 3),
        PostLinkCount(url: '/t/internal/1?first', clicks: 4, internal: true),
        PostLinkCount(
          url: '/uploads/default/file.png',
          clicks: 5,
          internal: true,
        ),
        PostLinkCount(url: '/uploads/default/file.png', clicks: 11),
        PostLinkCount(url: '/uploads/external.png', clicks: 6),
      ]);
      for (final (href, expected) in [
        ('/t/internal/1', '10'),
        ('/t/internal/1?first?second', '2'),
        ('/t/internal/1#reply', null),
        ('https://forum.example/t/internal/1?u=sam', null),
        ('/t/external/2', '3'),
        ('/t/external/2?u=sam', null),
        ('/T/internal/1', null),
        ('/uploads/default/file.png', '11'),
        ('https://cdn.example/proxy?url=/uploads/default/file.png', '5'),
        ('https://cdn.example/uploads/external.png', null),
        ('/uploads/external.png', '6'),
        ('/missing', null),
      ]) {
        final anchor = dom.Element.tag('a')..attributes['href'] = href;
        builder(anchor);
        expect(anchor.attributes['data-clicks'], expected, reason: href);
      }
    });

    testWidgets('preserve tracking exclusions and supplied click labels', (
      tester,
    ) async {
      final builder = await countBuilder(tester, const [
        PostLinkCount(url: '/counted', clicks: 7),
      ]);
      for (final (markup, expected) in [
        for (final name in [
          'lightbox',
          'no-track-link',
          'hashtag',
          'hashtag-cooked',
          'back',
        ])
          ('<a class="$name track-link" href="/counted">Link</a>', null),
        for (final name in ['elided', 'expanded-embed'])
          (
            '<div class="$name"><a class="track-link" href="/counted">Link</a></div>',
            null,
          ),
        for (final name in [
          'hashtag',
          'hashtag-cooked',
          'hashtag-icon-placeholder',
          'badge-category',
          'onebox-result',
          'onebox-body',
        ]) ...[
          ('<div class="$name"><a href="/counted">Link</a></div>', null),
          (
            '<div class="$name"><a class="track-link" href="/counted">Link</a></div>',
            '7',
          ),
        ],
        (
          '<aside class="quote"><a class="track-link" href="/counted">Link</a></aside>',
          null,
        ),
        ('<blockquote><a href="/counted">Link</a></blockquote>', '7'),
        ('<a>Link</a>', null),
      ]) {
        final anchor = html_parser.parseFragment(markup).querySelector('a')!;
        builder(anchor);
        expect(anchor.attributes['data-clicks'], expected, reason: markup);
      }
      final supplied = html_parser
          .parseFragment(
            '<a href="/counted" data-clicks="0" aria-label="Supplied label">Link</a>',
          )
          .querySelector('a')!;
      final before = supplied.outerHtml;
      builder(supplied);
      expect(supplied.outerHtml, before);
    });

    testWidgets('count only the best eligible link in each onebox', (
      tester,
    ) async {
      final builder = await countBuilder(tester, const [
        PostLinkCount(url: '/counted', clicks: 7),
      ]);
      for (final (markup, expected) in [
        (
          '<header><a href="/counted">Header</a></header>'
              '<article class="onebox-body"><h3><a href="/counted">Title</a></h3>'
              '<p><a href="/counted">Repeated</a></p></article>',
          ['Title'],
        ),
        ('<header><a href="/counted">Header</a></header>', ['Header']),
        (
          '<header><a href="/counted">Header</a></header>'
              '<article class="onebox-result"><h3><a href="/counted">Lower</a></h3>'
              '<h2><a href="/counted">Higher</a></h2></article>',
          ['Higher'],
        ),
        (
          '<header><a href="/other">Header</a></header>'
              '<article class="onebox-body"><h3><a href="/counted">Title</a></h3></article>',
          <String>[],
        ),
        (
          '<header><a href="/other">Header</a></header>'
              '<article class="onebox-body"><h3><a class="track-link" href="/counted">Title</a></h3></article>',
          ['Title'],
        ),
      ]) {
        final fragment = html_parser.parseFragment(
          '<aside class="onebox">$markup</aside>',
        );
        final decorated = <String>[];
        for (final anchor in fragment.querySelectorAll('a')) {
          final label = anchor.text;
          builder(anchor);
          if (anchor.attributes['data-clicks'] == '7') decorated.add(label);
        }
        expect(decorated, expected, reason: markup);
      }
    });

    testWidgets(
      'bound count-record reads across fresh matching and missing links',
      (tester) async {
        for (final size in [20, Post.maximumLinkCounts]) {
          var urlReads = 0;
          final counts = [
            for (var i = 0; i < size; i++)
              _CountingLinkCount(
                url: '/resource/$i',
                clicks: i + 1,
                internal: i.isEven,
                onUrlRead: () => urlReads += 1,
              ),
          ];
          final builder = await countBuilder(tester, counts);
          for (var pass = 0; pass < 3; pass++) {
            for (var i = 0; i < size; i++) {
              final suffix = i.isEven ? '?reader=$pass' : '';
              final anchor = dom.Element.tag('a')
                ..attributes['href'] = '/resource/$i$suffix';
              builder(anchor);
              expect(anchor.attributes['data-clicks'], '${i + 1}');
              final missing = dom.Element.tag('a')
                ..attributes['href'] = '/missing/$i?reader=$pass';
              builder(missing);
              expect(missing.attributes['data-clicks'], isNull);
            }
          }
          expect(
            urlReads,
            lessThanOrEqualTo(3 * size),
            reason: '$size records must not be rescanned for each anchor',
          );
        }
      },
    );

    testWidgets('refresh counts when the post or cooked HTML changes', (
      tester,
    ) async {
      const firstHtml = '<p><a href="/first">Read first</a></p>';
      const nextHtml = '<p><a href="/next">Read next</a></p>';
      Post post(int clicks) => Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: firstHtml,
        linkCounts: [
          PostLinkCount(url: '/first', clicks: clicks),
          const PostLinkCount(url: '/next', clicks: 12),
        ],
      );
      await pumpCooked(tester, firstHtml, post: post(7));
      expect(renderedText('7'), findsOneWidget);
      final updatedPost = post(9);
      await pumpCooked(tester, firstHtml, post: updatedPost);
      expect(renderedText('7'), findsNothing);
      expect(renderedText('9'), findsOneWidget);
      await pumpCooked(tester, nextHtml, post: updatedPost);
      expect(renderedText('9'), findsNothing);
      expect(renderedText('12'), findsOneWidget);
      await pumpCooked(tester, nextHtml);
      expect(renderedText('12'), findsNothing);
    });

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
    const sam = '<p>ask <a class="mention" href="/u/sam">@sam</a> about it</p>';

    testWidgets('are drawn as a pill rather than as a link', (tester) async {
      await pumpCooked(tester, sam);

      expect(find.byType(MentionPill), findsOneWidget);
      expect(find.text('@sam'), findsOneWidget);

      expect(paragraphOf(tester, 'about it'), contains('￼'));
      expect(paragraphOf(tester, 'about it'), isNot(contains('@sam')));
    });

    testWidgets('use the hand cursor in cooked posts', (tester) async {
      await pumpCooked(tester, sam);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('@sam')));
      await tester.pump();

      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    });

    testWidgets('keep the case the post was written in', (tester) async {
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
      expect(
        tester.widget<MentionPill>(find.byType(MentionPill)).href,
        '/g/staff',
      );
    });

    testWidgets('one the site could not resolve stays text', (tester) async {
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

    testWidgets('fit with a user status inside a narrow table cell', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpCookedInShell(
        tester,
        '',
        emoji: MockClient(
          (_) async => http.Response.bytes(
            onePixelPng,
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
        child: const CookedHtml(
          html:
              '<table style="width: 100%"><tbody><tr>'
              '<td style="width: 40px; max-width: 40px">By '
              '<a class="mention" href="/u/sam">@sam</a></td>'
              '<td>A second column that also needs room</td>'
              '</tr></tbody></table>',
          siteUrl: 'https://meta.discourse.org',
          mentionedUserStatuses: {
            'sam': UserStatusReference(
              userId: 42,
              status: UserStatus(description: 'At lunch', emoji: 'sandwich'),
            ),
          },
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(MentionPill), findsOneWidget);
      expect(find.byType(UserStatusMessage), findsOneWidget);
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
      expect(paragraphOf(tester, 'for more'), isNot(contains('bug')));
    });

    testWidgets('tapping a category pill opens its topic list', (tester) async {
      final controller = await pumpCookedInShell(
        tester,
        category,
        api: withCategories(const [
          TopicCategory(id: 5, name: 'Bug', color: '0088CC', slug: 'bug'),
        ]),
      );

      await tester.tap(find.byType(HashtagPill));
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'list-/c/bug/5.json');
      expect(controller.currentContent?.feedPath, '/c/bug/5.json');
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
      expect(find.text('Parent > Child'), findsOneWidget);
    });

    testWidgets('a category nobody has fetched still draws', (tester) async {
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
          href: '/voice/r/town-hall',
          styleType: 'icon',
          text: 'Town Hall',
        ),
        registry: PluginRegistry.validated(const [_RoomHashtagPlugin()]),
      );

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.label, 'Town Hall');
      expect(pill.href, '/voice/r/town-hall');
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
            href: '/voice/r/town-hall',
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
          href: '/voice/r/town-hall',
          styleType: 'icon',
          text: 'Town Hall',
        ),
        registry: PluginRegistry.empty,
      );

      final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
      expect(pill.label, 'Town Hall');
      expect(pill.href, '/voice/r/town-hall');
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
          href: '/voice/r/town-hall',
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
      // `data-icon` is whatever an admin picked, while this catalog carries
      // only the Lucide mappings the app supports.
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

    testWidgets('the placeholder SVG leaves nothing behind', (tester) async {
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

  testWidgets('headings use the same modular scale as the composer', (
    tester,
  ) async {
    await pumpCooked(
      tester,
      [
        for (var level = 1; level <= 6; level++)
          '<h$level>Heading $level</h$level>',
      ].join(),
    );

    final expected = [30.0, 24.0, 20.0, 18.0, 16.0, 14.0];
    for (var level = 1; level <= 6; level++) {
      final style = styleOf(tester, 'Heading $level');
      expect(style.fontSize, expected[level - 1], reason: 'heading $level');
      expect(
        style.height,
        closeTo(DiscourseTypography.headingLineHeight(level), 0.0001),
        reason: 'heading $level',
      );
    }
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
      expect(renderedText(':slight_smile:'), findsNothing);
    });

    testWidgets('render a custom SVG with the vector decoder', (tester) async {
      final svg = Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
                '<rect width="10" height="10" fill="red"/>'
                '</svg>'
            .codeUnits,
      );
      await pumpCookedInShell(
        tester,
        smile,
        emoji: MockClient(
          (_) async => http.Response.bytes(
            svg,
            200,
            headers: {'content-type': 'image/svg+xml'},
          ),
        ),
      );

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(renderedText(':slight_smile:'), findsNothing);
      expect(tester.takeException(), isNull);
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

    testWidgets('an only-emoji image inside a link stays compact', (
      tester,
    ) async {
      await pumpCookedInShell(
        tester,
        '<p><a href="https://meta.discourse.org/t/example">Result '
        '<img src="/images/emoji/twitter/smiley.png?v=15" '
        'title=":smiley:" class="emoji only-emoji" alt=":smiley:" '
        'loading="lazy" width="20" height="20"></a></p>',
        emoji: MockClient((_) async => http.Response.bytes(onePixelPng, 200)),
      );

      final emoji = tester.widget<EmojiImage>(find.byType(EmojiImage));
      expect(emoji.size, 20);
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
