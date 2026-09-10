// Offline native review of the production shell and registered Sidebar examples.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/sidebar_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';

const _site = 'https://sidebar-review.invalid';
final _sectionActions = ValueNotifier(0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This executable never reads or writes the user's saved settings.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  const user = DiscourseUser(id: 7, username: 'reader');
  final totals = chatNotificationTotals();
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: _site,
        title: 'Community with a long forum name',
        user: user,
        notificationTotals: totals,
      ),
      const DiscourseInstance(
        url: 'https://second-sidebar-review.invalid',
        title: 'Second community',
        user: user,
      ),
    ]),
    api: FakeDiscourseApi(
      user: user,
      totals: totals,
      feeds: const {'/latest.json': [], '/new.json': [], '/top.json': []},
      siteConfigs: {
        _site: SiteConfig(
          plugins: PluginData.none.withValue(
            chatSettingsDataKey,
            const ChatSettings(
              separateSidebarMode: ChatSeparateSidebarMode.always,
            ),
          ),
        ),
      },
      customSidebarSectionsBySite: {
        _site: [
          for (final (id, title) in [
            ('one-to-one', '1:1'),
            ('assignments', 'Assignments'),
            ('lead-calls', 'Teach Lead Calls'),
          ])
            SidebarSection(id: id, title: title, destinations: const []),
          SidebarSection(
            id: 'review-status',
            title: 'Voice status and categories',
            actionLabel: 'Create review room',
            onAction: () => _sectionActions.value++,
            destinations: [
              SidebarDestination(
                id: 'review-voice',
                label: 'Community watercooler',
                icon: DIcons.microphoneLines,
                trailingLabel: 'Live',
                badge: const SidebarBadge.count(1234),
                onTap: () {},
                onSecondaryTap: () {},
              ),
              const SidebarDestination(
                id: 'review-disabled',
                label: 'Unavailable room',
                icon: DIcons.microphoneLines,
                enabled: false,
                trailingLabel: 'Closed',
              ),
              SidebarDestination(
                id: 'review-category',
                label: 'Support category',
                icon: DIcons.folder,
                color: Colors.blue,
                parentColor: Colors.amber,
                onTap: () {},
              ),
              SidebarDestination(
                id: 'review-subcategory',
                label: 'Installation subcategory',
                icon: DIcons.folder,
                color: Colors.amber,
                indent: 1,
                onTap: () {},
              ),
            ],
          ),
          SidebarSection(
            id: 'review-lazy',
            title: '400 custom links',
            destinations: [
              for (var index = 0; index < 400; index++)
                SidebarDestination(
                  id: 'review-link-$index',
                  label: 'Custom destination $index',
                  icon: DIcons.link,
                  onTap: () {},
                ),
            ],
          ),
        ],
      },
      chatMessagesByKey: {
        for (var id = 1; id <= 100; id++)
          FakeDiscourseApi.chatMessagesKey(id): (
            messages: const [],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
      },
      chatChannelsBySite: {
        _site: ChatChannels(
          public: [
            for (var index = 0; index < 100; index++)
              ChatChannel(
                id: index + 1,
                title: index == 0
                    ? 'Announcements and community updates'
                    : 'Channel $index',
                kind: ChatChannelKind.category,
                membership: const ChatMembership(following: true),
                tracking: ChatTracking(mentionCount: index == 0 ? 1234 : 0),
              ),
          ],
        ),
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys[_site] = 'local-fixture'
      ..keys['https://second-sidebar-review.invalid'] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.pluginSession.require(chatControllerService).loadChannels(_site);
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_SidebarReview(shell: shell));
}

class _SidebarReview extends StatefulWidget {
  const _SidebarReview({required this.shell});
  final ShellController shell;
  @override
  State<_SidebarReview> createState() => _SidebarReviewState();
}

class _SidebarReviewState extends State<_SidebarReview> {
  bool _dark = false, _mobile = false, _rtl = false, _large = false;
  bool _customPalette = false;
  String _surface = 'Production';
  @override
  void dispose() {
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      theme:
          (_customPalette
                  ? (_dark ? StyleguideTheme.plum : StyleguideTheme.forest)
                        .resolve(AppTheme.light)
                  : (_dark ? AppTheme.dark : AppTheme.light))
              .copyWith(
                platform: _mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
              ),
      home: Scaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final surface in [
                    'Production',
                    'Lazy example',
                    'Styleguide',
                  ])
                    DButton(
                      label: Text(surface),
                      onPressed: () => setState(() => _surface = surface),
                    ),
                  DButton(
                    label: const Text('Light / Dark'),
                    onPressed: () => setState(() => _dark = !_dark),
                  ),
                  DButton(
                    label: const Text('Site palette'),
                    onPressed: () =>
                        setState(() => _customPalette = !_customPalette),
                  ),
                  DButton(
                    label: const Text('Desktop / Mobile'),
                    onPressed: () => setState(() => _mobile = !_mobile),
                  ),
                  DButton(
                    label: const Text('100 / 200%'),
                    onPressed: () => setState(() => _large = !_large),
                  ),
                  DButton(
                    label: const Text('LTR / RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _sectionActions,
                    builder: (context, count, _) =>
                        DBadge(child: Text('Section actions: $count')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _mobile ? 390 : double.infinity,
                  child: LayoutBuilder(
                    builder: (context, constraints) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        textScaler: TextScaler.linear(_large ? 2 : 1),
                      ),
                      child: Directionality(
                        textDirection: _rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: switch (_surface) {
                          'Lazy example' => Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: _mobile ? 342 : 300,
                              child: Builder(
                                builder: sidebarExamples.examples
                                    .singleWhere(
                                      (example) =>
                                          example.title == 'Lazy navigation',
                                    )
                                    .builder,
                              ),
                            ),
                          ),
                          'Styleguide' => const ComponentStyleguidePage(),
                          _ => const AdaptiveShell(),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
