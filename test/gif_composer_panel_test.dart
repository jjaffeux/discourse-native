import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _gif = GifResult(
  title: 'Happy dance',
  url: 'https://media.klipy.example/dance.webp',
  width: 320,
  height: 180,
);

SiteConfig _gifConfig({required bool enabled}) => SiteConfig(
  plugins: PluginData.none.withValue(
    gifsSettingsDataKey,
    GifsSettings(enabled: enabled),
  ),
);

final class _GatedSiteConfigApi extends FakeDiscourseApi {
  _GatedSiteConfigApi()
    : super(
        user: const DiscourseUser(id: 7, username: 'reader'),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: topicPayload(id: 7, title: 'GIFs', canCreatePost: true)},
      );

  final response = Completer<SiteConfig>();

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) => response.future;
}

Future<ShellController> _openComposer(FakeDiscourseApi api) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'gifs', title: 'GIFs'),
  );
  await shell.loadTopic(7, 'gifs');
  shell.openReply();
  return shell;
}

FakeDiscourseApi _api({required bool enabled}) => FakeDiscourseApi(
  user: const DiscourseUser(id: 7, username: 'reader'),
  feeds: const {'/latest.json': <Topic>[]},
  topics: {7: topicPayload(id: 7, title: 'GIFs', canCreatePost: true)},
  siteConfigs: {_site: _gifConfig(enabled: enabled)},
  gifSearchPages: {
    FakeDiscourseApi.gifSearchKey('dance'): GifSearchPage(
      results: const [_gif],
    ),
  },
);

Future<void> _pumpComposer(WidgetTester tester, ShellController shell) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
      home: ShellScope(
        controller: shell,
        child: Scaffold(body: ComposerPanel(composer: shell.visibleComposer!)),
      ),
    ),
  );
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _search(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search GIFs'));
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.byKey(const ValueKey('gif-picker-search')), findsOneWidget);

  await tester.enterText(
    find.byKey(const ValueKey('gif-picker-search')),
    'dance',
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
  expect(find.byKey(const ValueKey('gif-result-0')), findsOneWidget);
}

void main() {
  testWidgets('topic toolbar offers GIFs only when the site enables them', (
    tester,
  ) async {
    final disabled = await _openComposer(_api(enabled: false));
    addTearDown(disabled.dispose);
    await _pumpComposer(tester, disabled);
    expect(find.byTooltip('Search GIFs'), findsNothing);

    final enabled = await _openComposer(_api(enabled: true));
    addTearDown(enabled.dispose);
    await _pumpComposer(tester, enabled);
    expect(find.byTooltip('Search GIFs'), findsOneWidget);
  });

  testWidgets('an open topic composer gains GIFs when config arrives', (
    tester,
  ) async {
    final api = _GatedSiteConfigApi();
    final shell = await _openComposer(api);
    addTearDown(shell.dispose);
    await _pumpComposer(tester, shell);
    expect(find.byTooltip('Search GIFs'), findsNothing);

    api.response.complete(_gifConfig(enabled: true));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.byTooltip('Search GIFs'), findsOneWidget);
  });

  testWidgets('topic toolbar hides GIFs while an edit body is loading', (
    tester,
  ) async {
    final shell = await _openComposer(_api(enabled: true));
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    await _pumpComposer(tester, shell);
    expect(find.byTooltip('Search GIFs'), findsOneWidget);

    composer.beginLoadingBody();
    await tester.pump();
    expect(find.byTooltip('Search GIFs'), findsNothing);

    composer.loadedBody('Loaded body');
    await tester.pump();
    expect(find.byTooltip('Search GIFs'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('selected GIF is inserted at the captured topic selection', (
    tester,
  ) async {
    final api = _api(enabled: true);
    final shell = await _openComposer(api);
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: 'BeforeAfter',
      selection: TextSelection.collapsed(offset: 6),
    );
    await _pumpComposer(tester, shell);

    await _search(tester);
    await tester.tap(find.byKey(const ValueKey('gif-result-0')));
    await tester.pumpAndSettle();

    expect(
      composer.text.text,
      'Before\n\n![Happy dance|320x180]('
      'https://media.klipy.example/dance.webp)\n\nAfter',
    );
    expect(parseComposerImages(composer.text.text), hasLength(1));
    expect(api.gifSearchRequests.single.query, 'dance');
    expect(api.gifSearchRequests.single.fileDetail, 'webp');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a changed topic draft rejects the picker result', (
    tester,
  ) async {
    final shell = await _openComposer(_api(enabled: true));
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.text = 'Original draft';
    await _pumpComposer(tester, shell);

    await _search(tester);
    composer.text.text = 'Changed while open';
    await tester.tap(find.byKey(const ValueKey('gif-result-0')));
    await tester.pumpAndSettle();

    expect(composer.text.text, 'Changed while open');
    expect(
      find.text(
        'The composer changed while the GIF picker was open. Nothing was changed.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
  });
}
