// Local-only fixture mounting the production docked composer.
// API calls and drafts are in memory; preferences use an isolated prefix.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('composer_docking_review.');
  const user = DiscourseUser(id: 7, username: 'reviewer', canCreateTopic: true);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'first-review.invalid',
        title: 'First review site',
      ).copyWith(user: user),
      instance(
        'second-review.invalid',
        title: 'Second review site',
      ).copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://first-review.invalid'] = 'local-fixture'
      ..keys['https://second-review.invalid'] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.openNewTopicFromSidebar();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        builder: (context, child) => DToaster(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      DButton(
                        label: const Text('First draft'),
                        onPressed: () {
                          shell.selectInstance(0);
                          unawaited(shell.openNewTopicFromSidebar());
                        },
                      ),
                      DButton(
                        label: const Text('Second draft'),
                        onPressed: () {
                          shell.selectInstance(1);
                          unawaited(shell.openNewTopicFromSidebar());
                        },
                      ),
                    ],
                  ),
                ),
                const Expanded(child: AdaptiveShell()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
