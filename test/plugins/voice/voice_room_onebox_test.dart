import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_onebox.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const _site = 'https://voice.example';
const _registry = PluginRegistry([VoicePlugin()]);
const _card =
    '''<aside class="onebox live-room-onebox">
<article class="onebox-body live-room-onebox__body">
<h3 class="live-room-onebox__title"><a href="$_site/live/r/watercooler"><svg class="d-icon-microphone-lines"></svg><span>Watercooler</span></a></h3>
<div class="live-room-onebox__type">Open room</div>
<div class="live-room-onebox__description"><p>Share <strong>ideas</strong>.</p></div>
<div class="live-room-onebox__presence">99 stale people here now</div>
</article></aside>''';

Map<String, dynamic> _room({int participants = 0}) => {
  'id': 7,
  'name': 'Watercooler',
  'slug': 'watercooler',
  'public': true,
  'room_type': 'open',
  'active_participants': [
    for (var i = 0; i < participants; i++)
      {'id': i + 1, 'username': 'person$i', 'role': 'participant'},
  ],
};

VoiceRoomOneboxData? _parse(String source, {String site = _site}) =>
    VoiceRoomOneboxData.read(
      html.parseFragment(source).querySelector('aside')!,
      site,
    );

void main() {
  test('reads the upstream card and scopes presence to the serving forum', () {
    final data = _parse(_card)!;
    expect(data.name, 'Watercooler');
    expect(data.type, 'Open room');
    expect(data.descriptionHtml, '<p>Share <strong>ideas</strong>.</p>');
    expect(data.localSlug, 'watercooler');
    expect(
      _parse(_card.replaceAll('$_site/live/', '/voice/'))!.localSlug,
      'watercooler',
    );
    expect(
      _parse(
        _card.replaceAll('$_site/live/', '$_site/forum/live/'),
        site: '$_site/forum',
      )!.localSlug,
      'watercooler',
    );
    expect(
      _parse(_card.replaceAll(_site, 'https://another.example'))!.localSlug,
      isNull,
    );
    expect(
      _parse(_card.replaceAll('/live/r/', '/unrelated/live/r/'))!.localSlug,
      isNull,
    );
    expect(
      _parse(
        _card.replaceAll('$_site/live/r/watercooler', 'javascript:alert(1)'),
      ),
      isNull,
    );
  });

  test('inline room and stage oneboxes keep their wrapping link text', () {
    const plugin = VoicePlugin();
    for (final (kind, icon) in [
      ('room', DIcons.microphoneLines),
      ('stage', DIcons.earListen),
    ]) {
      final element = html
          .parseFragment(
            '<a class="inline-onebox live-inline-onebox-$kind" href="/live/r/watercooler">Watercooler</a>',
          )
          .querySelector('a')!;
      final prefix = plugin.cookedInlinePrefix(element)!;
      expect((prefix.child as DIcon).icon, icon);
      expect(prefix.excludeLinkSemantics, isTrue);
    }
    expect(
      plugin.cookedInlinePrefix(
        html
            .parseFragment(
              '<a class="inline-onebox" href="/t/topic/1">A topic</a>',
            )
            .querySelector('a')!,
      ),
      isNull,
    );
  });

  testWidgets(
    'card follows current viewer presence, clears it on removal, and opens the native room',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /live/rooms.json': {
            'rooms': [_room(participants: 1)],
            'can_create_room': false,
          },
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        manifest: const PluginManifest([chatModule, voiceModule]),
        sites: [
          PluginHostSite(
            url: _site,
            apiKey: 'key',
            user: const PluginHostUser(id: 1, username: 'reader'),
            config: SiteConfig.fromSettings(const {
              'live_enabled': true,
            }, extensions: _registry),
          ),
        ],
      );
      addTearDown(host.close);
      final controller = host.require(voiceControllerService);
      final tracker = RecordingPluginLiveChannels();
      controller.attachTracker(_site, tracker);
      await controller.ensureLoaded(_site);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: CookedHtml(
                  html: _card,
                  siteUrl: _site,
                  buildAsync: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DCard), findsOneWidget);
      expect(find.text('1 person here now'), findsOneWidget);
      expect(find.textContaining('99 stale'), findsNothing);
      expect(find.byType(DAvatar), findsOneWidget);

      tracker.deliver('/live/rooms', {
        'type': 'updated',
        'room': _room(participants: 7),
      }, messageId: 2);
      await tester.pump();
      expect(find.text('7 people here now'), findsOneWidget);
      expect(find.byType(DAvatar), findsNWidgets(5));

      await tester.tap(find.text('Watercooler'));
      await tester.pumpAndSettle();
      expect(host.currentContent?.id, 'voice-room-7');

      tracker.deliver('/live/rooms', {
        'type': 'destroyed',
        'room': _room(),
      }, messageId: 3);
      await tester.pump();
      expect(find.text('7 people here now'), findsNothing);
      expect(find.byType(DAvatar), findsNothing);
    },
  );

  testWidgets('external cards never borrow local room presence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: VoiceRoomOnebox(
            data: _parse(_card.replaceAll(_site, 'https://another.example'))!,
            siteUrl: _site,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Watercooler'), findsOneWidget);
    expect(find.textContaining('here now'), findsNothing);
  });
}
