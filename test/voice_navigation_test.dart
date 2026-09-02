import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

const _voiceManifest = PluginManifest([chatModule, voiceModule]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opening the current Voice room twice needs only one Back', (
    tester,
  ) async {
    const siteUrl = 'https://voice.example';
    final host = await PluginHostHarness.open(
      transport: RecordingPluginTransport(),
      manifest: _voiceManifest,
      sites: const [PluginHostSite(url: siteUrl, apiKey: 'key')],
    );
    addTearDown(host.close);
    final destination = host.currentContent;
    const room = ContentRoute(
      id: 'voice-room-7',
      title: 'Watercooler',
      icon: DIcons.microphoneLines,
    );

    final voice = host.require(voiceShellService);
    voice.openRoom(siteUrl: siteUrl, route: room);
    voice.openRoom(siteUrl: siteUrl, route: room);

    expect(host.contentStack, hasLength(2));
    expect(host.currentContent?.id, room.id);
    expect(host.popContent(), isTrue);
    expect(host.currentContent?.id, destination?.id);
  });

  testWidgets('a cooked room hashtag navigates through Voice', (tester) async {
    const siteUrl = 'https://voice.example';
    final site = PluginHostSite(
      url: siteUrl,
      apiKey: 'key',
      user: const PluginHostUser(id: 1, username: 'reader'),
      config: SiteConfig(
        plugins: PluginData.none.withValue(
          voiceSettingsDataKey,
          const VoiceClientConfig(enabled: true),
        ),
      ),
    );
    final transport = RecordingPluginTransport(
      responses: {
        'GET /voice/rooms.json': {
          'rooms': [_room],
          'can_create_room': false,
        },
      },
    );
    final host = await PluginHostHarness.open(
      transport: transport,
      manifest: _voiceManifest,
      sites: [site],
    );
    addTearDown(host.close);

    await tester.pumpWidget(
      host.scope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
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

    expect(host.currentContent?.id, 'voice-room-7');
    expect(host.currentContent?.title, 'Watercooler');
    expect(transport.reads.map((request) => request.path), [
      '/voice/rooms.json',
    ]);
  });

  testWidgets('an invitation link opens its Voice room', (tester) async {
    const siteUrl = 'https://voice.example';
    final site = PluginHostSite(
      url: siteUrl,
      apiKey: 'key',
      user: const PluginHostUser(id: 1, username: 'reader'),
      config: SiteConfig(
        plugins: PluginData.none.withValue(
          voiceSettingsDataKey,
          const VoiceClientConfig(enabled: true),
        ),
      ),
    );
    final transport = RecordingPluginTransport(
      responses: {
        'GET /voice/rooms.json': {
          'rooms': [_room],
          'can_create_room': false,
        },
      },
    );
    final host = await PluginHostHarness.open(
      transport: transport,
      manifest: _voiceManifest,
      sites: [site],
    );
    addTearDown(host.close);

    final voice = host.require(voiceShellService);
    expect(
      await voice.openPluginUrl('/voice/r/watercooler/invited-by/Inviter'),
      isTrue,
    );

    expect(host.currentContent?.id, 'voice-room-7');
    expect(host.currentContent?.title, 'Watercooler');
  });

  testWidgets('a cooked room without Voice falls back to its safe link', (
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
          home: const Scaffold(
            body: CookedHtml(html: _roomHashtag, siteUrl: siteUrl),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Watercooler'));
    await tester.pumpAndSettle();

    expect(launched, ['https://voice.example/voice/r/watercooler']);
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
    '<p><a class="hashtag-cooked" href="/voice/r/watercooler" '
    'data-type="room" data-id="7" data-style-type="icon">'
    '<span>Watercooler</span></a></p>';
