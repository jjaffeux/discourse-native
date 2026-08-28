import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_resenha/src/resenha_settings.dart';
import 'package:discourse_resenha/src/resenha_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/finders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opening the current Resenha room twice needs only one Back', (
    tester,
  ) async {
    final site = instance('voice.example');
    final authenticator = FakeAuthenticator()..keys[site.url] = 'key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    addTearDown(shell.dispose);
    await shell.load();
    final destination = shell.currentContent;
    const room = ContentRoute(
      id: 'resenha-room-7',
      title: 'Watercooler',
      icon: DIcons.microphoneLines,
    );

    final resenha = shell.pluginSession.require(resenhaShellService);
    resenha.openRoom(siteUrl: site.url, route: room);
    resenha.openRoom(siteUrl: site.url, route: room);

    expect(shell.contentStack, hasLength(2));
    expect(shell.currentContent?.id, room.id);
    expect(shell.handleBack(canReturnToSidebar: false), isTrue);
    expect(shell.currentContent?.id, destination?.id);
  });

  testWidgets('a cooked room hashtag navigates through Resenha', (
    tester,
  ) async {
    final site = instance('voice.example').copyWith(
      user: const DiscourseUser(id: 1, username: 'reader'),
      config: SiteConfig(
        plugins: PluginData.none.withValue(
          resenhaSettingsDataKey,
          const ResenhaClientConfig(enabled: true),
        ),
      ),
    );
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      pluginResponses: {
        'GET /resenha/rooms.json': {
          'rooms': [_room],
          'can_create_room': false,
        },
      },
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator()..keys[site.url] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    addTearDown(shell.dispose);
    await shell.load();

    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CookedHtml(
              html: _roomHashtag,
              siteUrl: site.url,
              registry: installedPlugins.registry,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(HashtagPill), findsOneWidget);
    expect(find.dIcon(DIcons.microphoneLines), findsOneWidget);
    await tester.tap(find.text('Watercooler'));
    await tester.pumpAndSettle();

    expect(shell.currentContent?.id, 'resenha-room-7');
    expect(shell.currentContent?.title, 'Watercooler');
    expect(api.pluginReadPaths, contains('/resenha/rooms.json'));
  });

  testWidgets('a cooked room without Resenha falls back to its safe link', (
    tester,
  ) async {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final launched = <String>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

    final site = instance(
      'voice.example',
    ).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));
    final shell = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator()..keys[site.url] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();

    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CookedHtml(html: _roomHashtag, siteUrl: site.url),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Watercooler'));
    await tester.pumpAndSettle();

    expect(launched, ['https://voice.example/resenha/r/watercooler']);
  });
}

const Map<String, Object?> _room = {
  'id': 7,
  'name': 'Watercooler',
  'slug': 'watercooler',
  'public': true,
  'ephemeral': false,
  'room_type': 'open',
  'active_participants': <Object?>[],
};

const String _roomHashtag =
    '<p><a class="hashtag-cooked" href="/resenha/r/watercooler" '
    'data-type="room" data-id="7" data-style-type="icon">'
    '<span>Watercooler</span></a></p>';
