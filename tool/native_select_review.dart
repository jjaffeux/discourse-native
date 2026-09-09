import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_preferences.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_status_editor.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

const _site = 'https://native-select.invalid';

/// Local-only native review entrypoint mounting the actual migrated owners.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This executable deliberately uses the package’s in-memory test backend.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  const user = DiscourseUser(
    id: 7,
    username: 'fixture',
    status: UserStatus(description: 'Reviewing Native Select', emoji: 'house'),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'native-select.invalid',
      ).copyWith(user: user, config: const SiteConfig(userStatusEnabled: true)),
    ]),
    api: FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': <Topic>[]},
      siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'fixture-only',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Review(shell: shell));
}

class _Review extends StatefulWidget {
  const _Review({required this.shell});
  final ShellController shell;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  bool _rtl = false;
  bool _large = false;
  bool _editable = true;
  UserPreferences _preferences = const UserPreferences(
    chatSeparateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
  );
  @override
  void dispose() {
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
        child: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Native Select Review 89bf — local data'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DButton(
                        label: const Text('Styleguide'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ComponentStyleguidePage(),
                          ),
                        ),
                      ),
                      DButton(
                        label: const Text('Actual status editor'),
                        onPressed: () =>
                            showUserStatusEditor(context, siteUrl: _site),
                      ),
                      DButton(
                        label: Text(_dark ? 'Light theme' : 'Dark theme'),
                        onPressed: () => setState(() => _dark = !_dark),
                      ),
                      DButton(
                        label: Text(_rtl ? 'LTR' : 'RTL'),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      DButton(
                        label: Text(_large ? '100% text' : '200% text'),
                        onPressed: () => setState(() => _large = !_large),
                      ),
                      DButton(
                        label: Text(
                          _editable
                              ? 'Disable chat editing'
                              : 'Enable chat editing',
                        ),
                        onPressed: () => setState(() => _editable = !_editable),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  chatUserPreferenceSection(
                    PluginUserPreferenceContext(
                      siteUrl: _site,
                      preferences: _preferences,
                      siteSettings: PluginData.none.withValue(
                        chatSettingsDataKey,
                        const ChatSettings(),
                      ),
                      currentUserData: PluginData.none.withValue(
                        chatCurrentUserDataKey,
                        const ChatCurrentUser(canChat: true),
                      ),
                      currentUserIsAdmin: false,
                      editable: _editable,
                      onEdit: (edit) =>
                          setState(() => _preferences = edit(_preferences)),
                    ),
                  )!.content,
                  const SizedBox(height: 16),
                  Text(
                    'Accepted chat preference: ${_preferences.chatSeparateSidebarMode.name}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
