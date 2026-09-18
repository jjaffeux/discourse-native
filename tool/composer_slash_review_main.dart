// Offline native review of the production Chat composer and slash commands.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/chat_shell.dart';
import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const site = 'https://slash-review.invalid';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: site,
        title: 'Slash commands',
        apiVersion: 4,
        config: SiteConfig(
          plugins: PluginData.none.withValue(
            localDatesSettingsDataKey,
            const LocalDatesSettings(enabled: true),
          ),
        ),
      ),
    ]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator()..keys[site] = 'offline-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  shell.chatRecords.put(
    site,
    const ChatChannel(
      id: 9,
      title: 'design',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
    ),
  );
  var dark = true;
  var narrow = false;
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    ShellScope(
      controller: shell,
      child: PluginUiScope.own(
        chatPluginId,
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 8,
                      children: [
                        DButton(
                          label: Text(dark ? 'Light' : 'Dark'),
                          onPressed: () => setState(() => dark = !dark),
                        ),
                        DButton(
                          label: Text(narrow ? 'Wide' : 'Narrow'),
                          onPressed: () => setState(() => narrow = !narrow),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Center(
                    child: SizedBox(
                      width: narrow ? 360 : 680,
                      child: const ChatComposer(siteUrl: site, channelId: 9),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
