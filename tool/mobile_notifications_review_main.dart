// Local data for inspecting the real notification menu and its Native tabs.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/styleguide/examples/tabs_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  const user = DiscourseUser(id: 7, username: 'reader');
  final notifications = [
    for (final (id, actor, title) in [
      (1, 'clickyclack99', "What's everyone's sourdough hydration?"),
      (2, 'verdant_vera', 'Mechanical keyboard switch tier list'),
      (3, 'sobercurious', 'Trip report: 10 days in Oaxaca'),
      (4, 'flourpower', 'Gear check: ultralight backpacking'),
      (5, 'readingpanda', "Who else is doing Dry January?"),
      (6, 'alice', 'Homemade ramen broth — how long is enough?'),
      (7, 'bob', 'Cold brew ratio megathread'),
      (8, 'carol', 'Share your community setup'),
    ])
      // ignore: invalid_use_of_visible_for_testing_member
      DiscourseNotification.test(
        id: id,
        typeId: const NotificationTypeId(2),
        read: id > 3,
        title: title,
        data: {'display_username': actor},
      ),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('review.invalid').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      notificationList: notifications,
      replyNotificationList: notifications.take(2).toList(),
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://review.invalid'] = 'fixture',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  runApp(ShellScope(controller: shell, child: const _Review()));
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  var _dark = true;
  var _width = 390.0;
  var _scale = 1.0;
  var _rtl = false;
  var _examples = false;

  @override
  Widget build(BuildContext context) {
    final theme = _dark
        ? AppTheme.fromPalette(
            forumThemePresets
                .singleWhere((p) => p.id == 'dracula')
                .resolve(Brightness.dark),
          )
        : AppTheme.light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(90, 12, 12, 12),
              child: Wrap(
                spacing: DSpacing.controlGap,
                children: [
                  DButton(
                    label: const Text('Light / dark'),
                    onPressed: () => setState(() => _dark = !_dark),
                  ),
                  DButton(
                    label: Text('Width ${_width.toInt()}'),
                    onPressed: () => setState(
                      () => _width = switch (_width) {
                        390 => 320,
                        320 => 900,
                        _ => 390,
                      },
                    ),
                  ),
                  DButton(
                    label: Text('Text ${(_scale * 100).toInt()}%'),
                    onPressed: () =>
                        setState(() => _scale = _scale == 1 ? 2 : 1),
                  ),
                  DButton(
                    label: const Text('LTR / RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: const Text('Menu / styleguide'),
                    onPressed: () => setState(() => _examples = !_examples),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _width,
                  child: LayoutBuilder(
                    builder: (context, constraints) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: constraints.biggest,
                        textScaler: TextScaler.linear(_scale),
                      ),
                      child: Directionality(
                        textDirection: _rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Navigator(
                          key: ValueKey(_examples),
                          onGenerateRoute: (_) => MaterialPageRoute<void>(
                            builder: (context) => Scaffold(
                              body: _examples
                                  ? Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: tabsExamples.examples
                                          .singleWhere(
                                            (e) => e.title == 'Outlined pills',
                                          )
                                          .builder(context),
                                    )
                                  : Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'The Commons',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                ),
                                              ),
                                              const UserMenuButton(),
                                            ],
                                          ),
                                        ),
                                        const DSeparator(),
                                        const Expanded(
                                          child: Center(
                                            child: Text('Community topics'),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
