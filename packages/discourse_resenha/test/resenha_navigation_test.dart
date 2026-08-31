import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_resenha/src/resenha_settings.dart';
import 'package:discourse_resenha/src/resenha_shell_service.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/finders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opening the current Resenha room twice needs only one Back', (
    tester,
  ) async {
    const siteUrl = 'https://voice.example';
    final host = await PluginHostHarness.open(
      transport: RecordingPluginTransport(),
      manifest: fullManifest,
      sites: const [PluginHostSite(url: siteUrl, apiKey: 'key')],
    );
    addTearDown(host.close);
    final destination = host.currentContent;
    const room = ContentRoute(
      id: 'resenha-room-7',
      title: 'Watercooler',
      icon: DIcons.microphoneLines,
    );

    final resenha = host.require(resenhaShellService);
    resenha.openRoom(siteUrl: siteUrl, route: room);
    resenha.openRoom(siteUrl: siteUrl, route: room);

    expect(host.contentStack, hasLength(2));
    expect(host.currentContent?.id, room.id);
    expect(host.popContent(), isTrue);
    expect(host.currentContent?.id, destination?.id);
  });

  testWidgets('a cooked room hashtag navigates through Resenha', (
    tester,
  ) async {
    const siteUrl = 'https://voice.example';
    final site = PluginHostSite(
      url: siteUrl,
      apiKey: 'key',
      user: const PluginHostUser(id: 1, username: 'reader'),
      config: SiteConfig(
        plugins: PluginData.none.withValue(
          resenhaSettingsDataKey,
          const ResenhaClientConfig(enabled: true),
        ),
      ),
    );
    final transport = RecordingPluginTransport(
      responses: {
        'GET /resenha/rooms.json': {
          'rooms': [_room],
          'can_create_room': false,
        },
      },
    );
    final host = await PluginHostHarness.open(
      transport: transport,
      manifest: fullManifest,
      sites: [site],
    );
    addTearDown(host.close);

    await tester.pumpWidget(
      host.scope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CookedHtml(html: _roomHashtag, siteUrl: siteUrl),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(HashtagPill), findsOneWidget);
    expect(find.dIcon(DIcons.microphoneLines), findsOneWidget);
    await tester.tap(find.text('Watercooler'));
    await tester.pumpAndSettle();

    expect(host.currentContent?.id, 'resenha-room-7');
    expect(host.currentContent?.title, 'Watercooler');
    expect(transport.reads.map((request) => request.path), [
      '/resenha/rooms.json',
    ]);
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

    const siteUrl = 'https://voice.example';
    final host = await PluginHostHarness.open(
      transport: RecordingPluginTransport(),
      sites: const [
        PluginHostSite(
          url: siteUrl,
          apiKey: 'key',
          user: PluginHostUser(id: 1, username: 'reader'),
        ),
      ],
    );
    addTearDown(host.close);

    await tester.pumpWidget(
      host.scope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CookedHtml(html: _roomHashtag, siteUrl: siteUrl),
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
