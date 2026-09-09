// Local-only review fixture: actual production Preferences and Voice editor.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_editor.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/field_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

const _site = DiscourseInstance(
  url: 'https://field.example',
  title: 'Field fixture',
  user: DiscourseUser(id: 7, username: 'reader', timezone: 'Etc/UTC'),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This executable is a test fixture; never read or write real preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final shell = ShellController(
    instanceStore: FakeInstanceStore([_site]),
    api: FakeDiscourseApi(
      user: _site.user,
      userPreferences: const UserPreferences(
        username: 'reader',
        timezone: 'Etc/UTC',
        canEdit: true,
        canChangeTrackingPreferences: true,
      ),
    ),
    authenticator: FakeAuthenticator()..keys[_site.url] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_FieldReview(shell: shell));
}

class _FieldReview extends StatefulWidget {
  const _FieldReview({required this.shell});
  final ShellController shell;
  @override
  State<_FieldReview> createState() => _FieldReviewState();
}

class _FieldReviewState extends State<_FieldReview> {
  bool _dark = false;
  bool _rtl = false;
  double _scale = 1;
  String? _draft;
  @override
  void dispose() {
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentAlignmentScope(
    controller: widget.shell.appSettings,
    child: ShellScope(
      controller: widget.shell,
      child: MaterialApp(
        theme: _dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_scale),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Field — local production review'),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DButton(
                        label: const Text('Styleguide'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ComponentStyleguidePage(),
                          ),
                        ),
                      ),
                      DButton(
                        label: const Text('Actual Preferences'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const Scaffold(
                              body: PreferencesPage(siteUrl: _siteUrl),
                            ),
                          ),
                        ),
                      ),
                      DButton(
                        label: const Text('Actual Voice editor'),
                        onPressed: () async {
                          final draft = await showDialog<VoiceRoomDraft>(
                            context: context,
                            builder: (_) => const VoiceRoomEditorDialog(),
                          );
                          if (mounted && draft != null) {
                            setState(
                              () => _draft =
                                  'Local draft: ${draft.name}; public=${draft.isPublic}',
                            );
                          }
                        },
                      ),
                      DButton(
                        label: const Text('Light / dark'),
                        onPressed: () => setState(() => _dark = !_dark),
                      ),
                      DButton(
                        label: const Text('LTR / RTL'),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      DButton(
                        label: const Text('100% / 200%'),
                        onPressed: () =>
                            setState(() => _scale = _scale == 1 ? 2 : 1),
                      ),
                    ],
                  ),
                  if (_draft != null) Text(_draft!),
                  const SizedBox(height: 24),
                  const SizedBox(width: 448, child: FieldChoiceExample()),
                  const SizedBox(height: 24),
                  const SizedBox(width: 448, child: FieldResponsiveExample()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _siteUrl = 'https://field.example';
