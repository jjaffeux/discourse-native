// Offline review fixture using the production mobile Chat panel and account actions.
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/chat_shell.dart';
import '../test/support/fakes.dart';

const mobileChatReviewSite = 'https://chat-review.invalid';

Future<ShellController> mobileChatReviewShell() async {
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    hidePresence: false,
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
    ),
  );
  final config = SiteConfig(
    userStatusEnabled: true,
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(
        chatEnabled: true,
        publicChannelsEnabled: true,
        threadsEnabled: true,
      ),
    ),
  );
  final names = [
    'general',
    'flourpower',
    'baking',
    'plants',
    'verdant_vera',
    'keyboards',
    'travel',
    'books',
    'hiking',
  ];
  final counts = [0, 3, 4, 2, 0, 8, 7, 2, 0];
  final colors = [
    0xffa0a0ad,
    0xffe8a135,
    0xffdfb567,
    0xff80bad8,
    0xff20af63,
    0xff91d4b6,
    0xffcaa0dc,
    0xffeab58b,
    0xff94d8cf,
  ];
  final channels = [
    for (var i = 0; i < names.length; i++)
      ChatChannel(
        id: i + 1,
        title: names[i],
        kind: i == 1 || i == 4
            ? ChatChannelKind.directMessage
            : ChatChannelKind.category,
        categoryColor: Color(colors[i]),
        users: i == 1 || i == 4
            ? [ChatUser(id: i + 10, username: names[i])]
            : const [],
        membership: const ChatMembership(following: true),
        tracking: ChatTracking(unreadCount: counts[i]),
        lastMessageId: (i + 1) * 10,
        lastMessageAt: DateTime.now().subtract(Duration(minutes: i * 3)),
        lastMessageUserId: i == 4 ? 14 : 7,
        lastMessagePreview: 'Will follow up in the morning.',
      ),
  ];
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('chat-review.invalid').copyWith(user: user, config: config),
    ]),
    api: FakeDiscourseApi(
      user: user,
      doNotDisturbUntil: DateTime.now().add(const Duration(minutes: 30)),
      siteConfigs: {mobileChatReviewSite: config},
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        mobileChatReviewSite: ChatChannels(
          public: channels
              .where((channel) => !channel.isDirectMessage)
              .toList(),
          direct: channels.where((channel) => channel.isDirectMessage).toList(),
          hasThreads: true,
        ),
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys[mobileChatReviewSite] = 'fixture-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    forumTabs: FakeForumTabStore(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.chat.loadChannels(mobileChatReviewSite);
  return shell;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = await mobileChatReviewShell();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(MobileChatReview(shell: shell));
}

class MobileChatReview extends StatefulWidget {
  const MobileChatReview({super.key, required this.shell});
  final ShellController shell;
  @override
  State<MobileChatReview> createState() => _MobileChatReviewState();
}

class _MobileChatReviewState extends State<MobileChatReview> {
  bool dark = true;
  bool narrow = false;
  bool largeText = false;
  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme:
          (dark
                  ? AppTheme.fromPalette(
                      forumThemePresets
                          .firstWhere((theme) => theme.id == 'dracula')
                          .resolve(Brightness.dark),
                    )
                  : AppTheme.light)
              .copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => DFocusHighlight(
        child: DToaster(
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(largeText ? 1.5 : 1)),
            child: child!,
          ),
        ),
      ),
      home: Builder(
        builder: (context) => ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: DSpacing.controlGap,
                  children: [
                    DButton(
                      label: Text(dark ? 'Light' : 'Dracula'),
                      onPressed: () => setState(() => dark = !dark),
                    ),
                    DButton(
                      label: Text(narrow ? '390 px' : '320 px'),
                      onPressed: () => setState(() => narrow = !narrow),
                    ),
                    DButton(
                      label: Text(largeText ? 'Normal text' : 'Large text'),
                      onPressed: () => setState(() => largeText = !largeText),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: narrow ? 320 : 390,
                    child: DPageSurface(
                      child: PluginUiScope.own(
                        chatPluginId,
                        const ChatMobileSidebar(siteUrl: mobileChatReviewSite),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
