import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';

// Exercise mobile startup in AOT, including on an Apple Silicon Mac:
// flutter run --release -d macos -t tool/mobile_startup_smoke_main.dart
// Widget tests alone cannot detect release compiler null-load regressions.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    exit(1);
  };
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
    ),
  );
  final site = instance(
    'mobile-startup.invalid',
  ).copyWith(user: user, config: config);
  final shell = ShellController(
    plugins: PluginInstaller.install(bundledWidgetTestManifest),
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(user: user, siteConfigs: {site.url: config}),
    authenticator: FakeAuthenticator()..keys[site.url] = 'fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  runApp(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: const MobileForumRoot(content: Text('Mobile startup smoke')),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  stdout.writeln('PASS: topics startup with an available chat panel');
  shell.selectMobilePanel('chat');
  await WidgetsBinding.instance.endOfFrame;
  stdout.writeln('PASS: chat panel root');
  shell.selectMobileDestination(MobileTab.topics, site.defaultDestination);
  await WidgetsBinding.instance.endOfFrame;
  stdout.writeln('PASS: return to topics');
  runApp(const SizedBox.shrink());
  await WidgetsBinding.instance.endOfFrame;
  shell.dispose();
  await shell.plugins.close();
  exit(0);
}
