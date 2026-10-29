import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/composer/components/details.dart';
import 'package:discourse_native/src/shell/composer/components/link.dart';
import 'package:discourse_native/src/shell/composer/components/quote.dart';
import 'package:discourse_native/src/shell/composer/components/table.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_text.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://meta.example';
const _output = String.fromEnvironment('EMOJI_PARITY_OUTPUT');
const _names = [
  'cat',
  'cat_face',
  'dog',
  'dog_face',
  'waving_hand',
  'cheese_wedge',
  'sparkles',
  'rocket',
  'tada',
  'world_map',
  'saluting_face',
];
const _prose =
    ':cat: :cat_face: :dog: :dog_face: :hello:t4: :cheese: '
    ':not_an_emoji: word:cat: é:dog: `:cat:`';
const _rich = '''# Heading :rocket:

Paragraph :cat: :cat_face: :dog: :dog_face: :wave:t4: :cheese_wedge:
Unknown :not_an_emoji: · word:cat: · é:dog: · `:cat:`

- List :sparkles:

> Quote :waving_hand:

[quote="sailor, post:1, topic:1"]
Quoted :waving_hand: and `:dog:`
[/quote]

[Label :rocket:](https://example.test)

| Table :cat: | Header |
| --- | --- |
| Cell :dog: | :not_an_emoji: |

[details="Details :cheese:"]
Body :saluting_face: and `:cat:`
[/details]

[spoiler]Secret :world_map:[/spoiler]

```text
:cat: word:dog:
```
''';

void main() {
  testWidgets(
    'titles, excerpts, chat and cooked block surfaces preserve shortcode rules',
    (tester) async {
      await _fonts(tester);
      await tester.binding.setSurfaceSize(const Size(760, 1250));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = await _shell(tester);
      final cooking = OfflineCookingService();
      addTearDown(cooking.dispose);
      final result = await tester.runAsync(
        () => cooking.cook(
          CookingRequest(
            raw: _rich,
            configuration: CookingConfiguration(
              modules: [
                CookingModule.spoiler,
                CookingModule(
                  id: 'details',
                  owner: 'cooking',
                  version: '1',
                  profiles: const ['post'],
                ),
              ],
            ),
            snapshot: CookingSnapshot(
              siteId: _site,
              accountId: 'fixture',
              baseUrl: _site,
              siteSettings: const {
                'enable_emoji': true,
                'emoji_set': 'twitter',
              },
            ),
          ),
        ),
      );
      expect(result!.failure, isNull);
      final document = html.parseFragment(result.html);
      // These expectations come from the server cooking contract, independently
      // of Native's presentation matcher. Native must consume its img markup.
      for (final selector in ['h1', 'li', 'blockquote', 'th', 'td', 'a']) {
        expect(
          document.querySelector('$selector img.emoji'),
          isNotNull,
          reason: '$selector: \n${result.html}',
        );
      }
      expect(document.querySelector('code')!.text, ':cat:');
      expect(document.text, contains(':not_an_emoji:'));
      expect(document.text, contains('word:cat:'));
      expect(document.text, contains('é:dog:'));
      final key = GlobalKey();
      shell.chatRecords.put(
        _site,
        const ChatChannel(id: 9, title: 'Crew', kind: ChatChannelKind.category),
      );
      shell.chatRecords.put(
        _site,
        const ChatMessage(
          id: 7,
          channelId: 9,
          raw: _prose,
          cooked:
              '<p>Crew <img class="emoji" src="/images/emoji/twitter/waving_hand/4.png" alt=":waving_hand:t4:"> '
              ':not_an_emoji: word:cat: é:dog: <code>:cat:</code></p>',
          author: ChatMessageAuthor(id: 22, username: 'sailor', name: 'Sailor'),
        ),
      );
      for (final dark in [false, true]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _app(
            shell,
            dark: dark,
            capture: key,
            children: [
              const Text('Emoji parity · Native Flutter fixture'),
              TopicListRow(
                siteUrl: _site,
                topic: const Topic(
                  id: 1,
                  slug: 'crew',
                  title: 'Animals :cat: :cat_face: :dog: :dog_face:',
                  excerpt: _prose,
                ),
                onTap: () {},
              ),
              PluginUiScope.own(
                chatPluginId,
                const ChatMessageTile(
                  siteUrl: _site,
                  messageId: 7,
                  chained: false,
                ),
              ),
              CookedHtml(html: result.html, siteUrl: _site, buildAsync: false),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(TopicListRow);
        final rowArt = _images(tester, row);
        expect(
          rowArt.map((image) => image.url).join(' '),
          contains('/cat.png'),
        );
        expect(
          rowArt.map((image) => image.url).join(' '),
          contains('/cat_face.png'),
        );
        expect(
          rowArt.map((image) => image.url).join(' '),
          contains('/cheese_wedge.png'),
        );
        expect(
          _images(tester, find.byType(ChatMessageTile)).single.url,
          contains('/waving_hand/4.png'),
        );
        // Details and spoilers own their own controls and rendering state.
        expect(find.byType(DAccordion<int>), findsOneWidget);
        expect(find.byType(DSpoiler), findsOneWidget);
        await tester.tap(find.byType(DAccordionTrigger));
        await tester.pumpAndSettle();
        final spoilerAction = find
            .descendant(
              of: find.byType(DSpoiler),
              matching: find.byType(GestureDetector),
            )
            .first;
        Actions.invoke(tester.element(spoilerAction), const ActivateIntent());
        await tester.pumpAndSettle();
        final bodyImages = _images(
          tester,
          find.byWidgetPredicate(
            (widget) => widget is CookedHtml && widget.html == result.html,
          ),
        );
        expect(
          bodyImages.map((image) => image.url).join(' '),
          contains('/saluting_face.png'),
        );
        expect(
          bodyImages.map((image) => image.url).join(' '),
          contains('/world_map.png'),
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, key, 'readers-${dark ? 'dark' : 'light'}');
      }
    },
  );

  testWidgets(
    'rich composer renders emoji in nested controls without changing source',
    (tester) async {
      await _fonts(tester);
      await tester.binding.setSurfaceSize(const Size(760, 1250));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = await _shell(tester);
      final composer = _composer(shell, _rich);
      addTearDown(composer.dispose);
      final key = GlobalKey();
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          _app(
            shell,
            dark: dark,
            capture: key,
            children: [
              const Text('Rich composer · Native Flutter fixture'),
              SizedBox(
                height: 1140,
                child: ComposerEditor(
                  composer: composer,
                  hintText: 'Reply',
                  textStyle: const TextStyle(fontSize: 16, height: 1.5),
                  hintStyle: null,
                  autofocus: false,
                  showSelectionToolbar: false,
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(composer.text.text, _rich);
        for (final type in [
          ComposerLinkPill,
          ComposerTableEditor,
          ComposerDetailsEditor,
          ComposerQuotePreview,
        ]) {
          final component = find.byType(type);
          expect(component, findsOneWidget);
          expect(_images(tester, component), isNotEmpty, reason: '$type');
        }
        final urls = _images(
          tester,
          find.byType(ComposerEditor),
        ).map((image) => image.url).join(' ');
        expect(urls, contains('/waving_hand/4.png'));
        expect(urls, contains('/cheese_wedge.png'));
        expect(urls, isNot(contains('/not_an_emoji')));
        expect(tester.takeException(), isNull);
        await _capture(tester, key, 'composer-${dark ? 'dark' : 'light'}');
      }
    },
  );

  testWidgets('replacing an account scope rejects the old catalog redraw', (
    tester,
  ) async {
    _media();
    final oldApi = _EmojiApi()
      ..catalogGate = Completer<SiteEmojiCatalog>()
      ..aliases = const {
        'new_alias': ['cat'],
      };
    ShellController shell(_EmojiApi api) => ShellController(
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    final oldShell = shell(oldApi);
    final newShell = shell(
      _EmojiApi()
        ..aliases = const {
          'new_alias': ['dog'],
        },
    );
    addTearDown(oldShell.dispose);
    addTearDown(newShell.dispose);
    Widget content(ShellController owner) => _app(
      owner,
      children: [SiteEmojiText.plain('Hi :new_alias:', siteUrl: _site)],
    );
    await tester.pumpWidget(content(oldShell));
    await tester.pump();
    await tester.pumpWidget(content(newShell));
    await tester.pumpAndSettle();
    expect(
      _images(tester, find.byType(SiteEmojiText)).single.url,
      contains('/dog.png'),
    );
    oldApi.catalogGate!.complete(
      SiteEmojiCatalog(
        groups: [
          SiteEmojiGroup(
            id: 'old',
            emojis: const [SiteEmoji(name: 'cat', url: '/old-cat.png')],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _images(tester, find.byType(SiteEmojiText)).single.url,
      contains('/dog.png'),
    );
  });

  testWidgets(
    'catalog and alias arrival redraw only emoji consumers and reject retired responses',
    (tester) async {
      final api = _EmojiApi()..catalogGate = Completer<SiteEmojiCatalog>();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      _media();
      final composer = _composer(shell, ':new_alias: :cat: :not_an_emoji:');
      addTearDown(composer.dispose);
      var broadChanges = 0;
      shell.addListener(() => broadChanges++);
      await tester.pumpWidget(
        _app(
          shell,
          children: [
            SiteEmojiText.plain(':new_alias: :cat:', siteUrl: _site),
            DInput(borderless: true, controller: composer.text, maxLines: null),
          ],
        ),
      );
      expect(find.byType(EmojiImage), findsNothing);
      api.catalogGate!.complete(
        SiteEmojiCatalog(
          groups: [
            SiteEmojiGroup(
              id: 'animals',
              emojis: const [
                SiteEmoji(name: 'cat', url: '/images/emoji/twitter/cat.png'),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(_images(tester, find.byType(DInput)).map((image) => image.url), [
        contains('/cat.png'),
      ]);
      api.aliases = const {
        'new_alias': ['cat'],
      };
      await shell.refreshEmojiSearchAliases(_site);
      await tester.pumpAndSettle();
      expect(_images(tester, find.byType(DInput)), hasLength(2));
      expect(broadChanges, 0);
      final pendingGate = Completer<SiteEmojiCatalog>();
      api.catalogGate = pendingGate;
      final pending = shell.refreshEmojiCatalog(_site);
      await tester.pump();
      shell.lifecycle.invalidate(_site);
      // Disconnect retires the owning presentation cache in production. The
      // public lifecycle invalidation must also reject this outstanding result.
      pendingGate.complete(
        SiteEmojiCatalog(
          groups: [
            SiteEmojiGroup(
              id: 'old',
              emojis: const [SiteEmoji(name: 'not_an_emoji', url: '/old.png')],
            ),
          ],
        ),
      );
      expect(await pending, isNull);
      expect(shell.emojiNameFor(_site, 'not_an_emoji'), isNull);
    },
  );
}

ComposerController _composer(ShellController shell, String source) =>
    ComposerController(
        const ReplyComposerTarget(
          siteUrl: _site,
          topicId: 1,
          slug: 'crew',
          topicTitle: 'Crew',
          privateMessageTopic: false,
        ),
        resolveEmoji: (name) {
          final canonical = shell.emojiNameFor(_site, name);
          return canonical == null ? null : shell.emojiUrlFor(_site, canonical);
        },
        emojiChanges: shell.emojiChangesFor(_site),
      )
      ..text.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );

Future<ShellController> _shell(WidgetTester tester) async {
  _media();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.example')]),
    api: _EmojiApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.ensureEmojiCatalog(_site);
  await shell.ensureEmojiSearchAliases(_site);
  return shell;
}

void _media() {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );
  installTestMediaPipeline(
    client: MockClient((request) async {
      if (_output.isNotEmpty) {
        final name = request.url.path
            .split('/images/emoji/twitter/')
            .last
            .replaceAll('/', '-');
        final asset = File('$_output/emoji-assets/$name');
        if (asset.existsSync()) {
          return http.Response.bytes(asset.readAsBytesSync(), 200);
        }
      }
      return request.url.path.contains('/images/emoji/')
          ? http.Response.bytes(bytes, 200)
          : http.Response('', 404);
    }),
  );
}

class _EmojiApi extends FakeDiscourseApi {
  Completer<SiteEmojiCatalog>? catalogGate;
  Map<String, List<String>> aliases = const {
    'waving_hand': ['hello'],
    'cheese': ['cheese_wedge'],
  };
  @override
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async =>
      catalogGate?.future ??
      SiteEmojiCatalog(
        groups: [
          SiteEmojiGroup(
            id: 'all',
            emojis: [
              for (final name in _names)
                SiteEmoji(
                  name: name,
                  url: '/images/emoji/twitter/$name.png',
                  tonable: name == 'waving_hand',
                ),
            ],
          ),
        ],
      );
  @override
  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => aliases;
}

Widget _app(
  ShellController shell, {
  List<Widget> children = const [],
  bool dark = false,
  GlobalKey? capture,
}) => ShellScope(
  controller: shell,
  child: MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: RepaintBoundary(
      key: capture,
      child: DPageSurface(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    ),
  ),
);

List<EmojiImage> _images(WidgetTester tester, Finder parent) => tester
    .widgetList<EmojiImage>(
      find.descendant(of: parent, matching: find.byType(EmojiImage)),
    )
    .toList();

Future<void> _fonts(WidgetTester tester) async {
  if (_output.isEmpty) return;
  await tester.runAsync(() async {
    final font = File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync();
    for (final family in [
      '.AppleSystemUIFont',
      'Roboto',
      'SF Pro Text',
      'SF Pro Display',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
    final mono = File(
      'assets/fonts/JetBrainsMono-Regular.ttf',
    ).readAsBytesSync();
    await (FontLoader(
      'JetBrains Mono',
    )..addFont(Future.value(ByteData.sublistView(mono)))).load();
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_output.isEmpty) return;
  await tester.runAsync(() async {
    final images = find.descendant(
      of: find.byType(EmojiImage),
      matching: find.byType(Image),
    );
    await Future.wait([
      for (final element in images.evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
