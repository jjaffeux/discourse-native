import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';

const _site = 'https://notification-capsule-review.invalid';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // All stores and transports are local fixtures, including app preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  const user = DiscourseUser(id: 7, username: 'reader', name: 'Reader');
  final totals = chatNotificationTotals(unreadNotifications: 128);
  final shell = ShellController(
    plugins: installedPlugins,
    initialRootMode: ShellRootMode.forum,
    instanceStore: FakeInstanceStore([
      instance(
        'notification-capsule-review.invalid',
      ).copyWith(user: user, notificationTotals: totals),
    ]),
    api: FakeDiscourseApi(
      user: user,
      totals: totals,
      feeds: const {'/latest.json': [], '/new.json': []},
      chatChannelsBySite: {
        _site: const ChatChannels(
          public: [
            ChatChannel(
              id: 9,
              title: 'Community discussion',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
              tracking: ChatTracking(unreadCount: 4, mentionCount: 128),
            ),
          ],
          direct: [],
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.pluginSession.require(chatControllerService).loadChannels(_site);
  runApp(_Review(shell: shell));
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review({required this.shell});
  final ShellController shell;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool dark = true,
      narrow = false,
      rtl = false,
      styleguide = false,
      custom = false,
      largeText = false;

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
          (custom
                  ? StyleguideTheme.forest.resolve(AppTheme.light)
                  : dark
                  ? AppTheme.dark
                  : AppTheme.light)
              .copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(90, 12, 12, 12),
              child: Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  DButton(
                    label: const Text('App / Styleguide'),
                    onPressed: () => setState(() => styleguide = !styleguide),
                  ),
                  DButton(
                    label: const Text('Light / Dark'),
                    onPressed: () => setState(() {
                      dark = !dark;
                      custom = false;
                    }),
                  ),
                  DButton(
                    label: const Text('Site palette'),
                    onPressed: () => setState(() => custom = !custom),
                  ),
                  DButton(
                    label: const Text('Wide / Narrow'),
                    onPressed: () => setState(() => narrow = !narrow),
                  ),
                  DButton(
                    label: const Text('100% / 200%'),
                    onPressed: () => setState(() => largeText = !largeText),
                  ),
                  DButton(
                    label: const Text('LTR / RTL'),
                    onPressed: () => setState(() => rtl = !rtl),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: narrow ? 390 : double.infinity,
                  child: LayoutBuilder(
                    builder: (context, constraints) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: constraints.biggest,
                        textScaler: TextScaler.linear(largeText ? 2 : 1),
                      ),
                      child: Directionality(
                        textDirection: rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: styleguide
                            ? const ComponentStyleguidePage()
                            : const AdaptiveShell(),
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
