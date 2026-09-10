// Local-only fixture for the production Quiet dock composer. All account,
// post and draft data is in memory, and preferences have an isolated prefix.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/plugins/poll/poll_data.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

const _site = 'https://quiet-dock-review.invalid';
const _topic = Topic(
  id: 7,
  title: 'Making the first contribution feel easier',
  slug: 'first-contribution',
);
const _post = Post(
  id: 12,
  postNumber: 8,
  username: 'maya',
  cooked: '<p>A small invitation can make the first reply feel easier.</p>',
  raw: 'A small invitation can make the first reply feel easier.',
  canEdit: true,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('quiet_dock_review.');
  final draftGate = const bool.fromEnvironment('QUIET_DOCK_BLOCK_DRAFTS')
      ? Completer<void>()
      : null;
  final user = DiscourseUser(
    id: 7,
    username: 'reviewer',
    canCreateTopic: true,
    whisperer: true,
    plugins: PluginData.none.withValue(
      pollCurrentUserDataKey,
      const PollCurrentUser(canCreatePoll: true),
    ),
  );
  final shell = ShellController(
    plugins: PluginInstaller.install(bundledPluginManifest),
    instanceStore: FakeInstanceStore([
      instance(
        'quiet-dock-review.invalid',
        title: 'Quiet dock review',
      ).copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      draftGate: draftGate,
      siteConfigs: {
        _site: SiteConfig(
          plugins: PluginData.none.withValue(
            localDatesSettingsDataKey,
            const LocalDatesSettings(enabled: true),
          ),
        ),
      },
      feeds: const {
        '/latest.json': [_topic],
      },
      creatableFeedPaths: const {'/latest.json'},
      topics: {
        7: topicPayload(
          id: 7,
          title: _topic.title,
          posts: [_post],
          canCreatePost: true,
        ),
      },
      postsById: const {12: _post},
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.openNewTopicFromSidebar();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Review(shell: shell, draftGate: draftGate));
}

class _Review extends StatefulWidget {
  const _Review({required this.shell, this.draftGate});
  final ShellController shell;
  final Completer<void>? draftGate;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  ThemeMode _theme = ThemeMode.light;

  Future<void> _mode(String mode) async {
    final shell = widget.shell;
    // Switching a fixture intentionally starts a new in-memory sample.
    shell.closeComposer();
    if (mode == 'New topic') {
      await shell.openNewTopicFromSidebar();
    } else {
      shell.openTopic(_topic);
      for (
        var attempt = 0;
        attempt < 50 && shell.currentTopic == null;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (mode == 'Edit') {
        shell.openEdit(_post);
      } else {
        shell.openReply(
          replyToPostNumber: 8,
          replyToUsername: 'maya',
          replyingToWhisper: mode == 'Whisper target',
        );
        if (mode == 'Whisper') shell.visibleComposer?.setWhisper(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _theme,
      builder: (context, child) => DToaster(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final mode in [
                    'New topic',
                    'Reply',
                    'Whisper',
                    'Whisper target',
                    'Edit',
                  ])
                    DButton(
                      label: Text(mode),
                      onPressed: () => unawaited(_mode(mode)),
                    ),
                  DButton(
                    label: const Text('Light / dark'),
                    onPressed: () => setState(
                      () => _theme = _theme == ThemeMode.light
                          ? ThemeMode.dark
                          : ThemeMode.light,
                    ),
                  ),
                  if (widget.draftGate case final gate?)
                    DButton(
                      label: const Text('Finish server save'),
                      onPressed: gate.isCompleted
                          ? null
                          : () => setState(gate.complete),
                    ),
                ],
              ),
            ),
            const Expanded(child: AdaptiveShell()),
          ],
        ),
      ),
    ),
  );
}
