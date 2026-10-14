import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Runs the production mobile sidebar with an account-free in-memory fixture.
/// Run with `flutter run -d <simulator>` and this file as the target.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  runApp(const _Review());
}

const _site = 'https://meta.discourse.org';

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  final _capture = GlobalKey();
  late final Widget _app;

  @override
  void initState() {
    super.initState();
    const user = DiscourseUser(id: 7, username: 'reader');
    final config = SiteConfig(
      plugins: PluginData.none
          .withValue(
            chatSettingsDataKey,
            const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
          )
          .withValue(
            voiceSettingsDataKey,
            const VoiceClientConfig(enabled: true),
          ),
    );
    _app = DiscourseApp(
      store: FakeInstanceStore([
        instance(
          'meta.discourse.org',
          title: 'Discourse Meta',
        ).copyWith(user: user, config: config),
        instance('team.discourse.org', title: 'Discourse Team'),
        instance('community.example.org', title: 'Community'),
      ]),
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      notificationOpenUrls: const Stream.empty(),
      pluginManifest: PluginManifest([
        ChatModule(apiFactory: (transport) => transport as ChatApi),
        const VoiceModule.withoutDiagnostics(),
      ]),
      api: FakeDiscourseApi(
        user: user,
        totals: chatNotificationTotals(),
        siteConfigs: {_site: config},
        feeds: const {'/latest.json': []},
        customSidebarSectionsBySite: const {
          _site: [
            SidebarSection(
              id: 'custom-1',
              title: 'Team links',
              destinations: [
                SidebarDestination(
                  id: 'handbook',
                  label: 'Handbook',
                  icon: DIcons.link,
                  url: '/about',
                ),
              ],
            ),
          ],
        },
        chatChannelsBySite: const {
          _site: ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'General',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
              ),
            ],
            direct: [
              ChatChannel(
                id: 10,
                title: 'sam',
                kind: ChatChannelKind.directMessage,
                users: [ChatUser(id: 2, username: 'sam')],
                membership: ChatMembership(following: true),
              ),
            ],
          ),
        },
        pluginResponses: {
          'GET /voice/rooms.json': {
            'rooms': [
              for (final (id, name) in [
                (7, 'Watercooler'),
                (8, 'Breakroom'),
                (9, 'Kitchen'),
              ])
                {
                  'id': id,
                  'name': name,
                  'slug': name.toLowerCase(),
                  'room_type': 'conference',
                  'active_participants': <Object>[],
                },
            ],
            'can_create_room': true,
          },
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_review()));
  }

  Element? _elementWhere(bool Function(Widget) predicate) {
    Element? result;
    void visit(Element element) {
      if (result != null) return;
      if (predicate(element.widget)) {
        result = element;
        return;
      }
      element.visitChildElements(visit);
    }

    visit(_capture.currentContext! as Element);
    return result;
  }

  Future<void> _review() async {
    ShellController? shell;
    for (var attempt = 0; attempt < 80; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final root = _elementWhere((widget) => widget is MobileForumRoot);
      if (root == null) continue;
      shell = ShellScope.read(root);
      if (shell.currentInstance?.isConnected == true) break;
    }
    if (shell == null) {
      debugPrint('MOBILE_SIDEBAR_REVIEW_FAILED');
      return;
    }
    await shell.pluginSession
        .require(voiceControllerService)
        .ensureLoaded(_site);
    await shell.forumSettings.setThemes(
      _site,
      ForumThemePreferences.preset('dracula'),
    );
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(
        font: ForumFont.lato,
        interfaceFont: ForumFont.lato,
      ),
    );
    shell.toggleMobileSidebar();
    for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
      await shell.forumSettings.setThemeMode(_site, mode);
      for (final state in ['forum', 'chat', 'shortcuts']) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final tabs =
            _elementWhere(
                  (widget) =>
                      widget.key == const ValueKey('sidebar-panel-tabs'),
                )!.widget
                as DTabs<String>;
        tabs.onChanged!(state);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await WidgetsBinding.instance.endOfFrame;
        final boundary =
            _capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        boundary.markNeedsPaint();
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final path =
            '${Directory.systemTemp.path}/native-mobile-sidebar-${mode.name}-$state.png';
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        debugPrint('MOBILE_SIDEBAR_CAPTURE $path');
      }
    }
    debugPrint('MOBILE_SIDEBAR_REVIEW_COMPLETE');
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _capture, child: _app);
}
