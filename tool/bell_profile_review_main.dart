import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('bell_profile_review.');
  const user = DiscourseUser(
    id: 7,
    username: 'joffrey',
    name: 'Joffrey',
    canInviteToForum: true,
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      totals: const NotificationTotals(unreadNotifications: 3),
      notificationList: [
        for (var id = 1; id <= 3; id++)
          // Local fixture data for the production menu.
          // ignore: invalid_use_of_visible_for_testing_member
          DiscourseNotification.test(
            id: id,
            typeId: NotificationTypeId(CoreNotificationTypes.replied.wireId),
            topicId: id,
            title: [
              'A calmer reading experience',
              'Small improvements to the composer',
              'Share your community’s setup',
            ][id - 1],
            data: const {'display_username': 'sam'},
          ),
      ],
    ),
    authenticator: FakeAuthenticator()..keys['https://meta.example'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  await controller.accountActivity.refresh(controller.currentInstance!);
  runApp(ShellScope(controller: controller, child: const _Review()));
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(90, 12, 12, 12),
              child: Row(
                children: [
                  DButton(
                    label: const Text('Toggle theme'),
                    onPressed: () => setState(() => dark = !dark),
                  ),
                  const Spacer(),
                  const UserMenuButton(size: 26),
                ],
              ),
            ),
            const DSeparator(),
            const Expanded(
              child: Center(
                child: Text('Discourse Meta · Account menu review'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
