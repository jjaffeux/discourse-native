// Local-data review of the real Settings modal over forum-colored surfaces.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  final _shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  bool _dark = false;
  bool _rtl = false;

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: _shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: (_dark ? StyleguideTheme.plum : StyleguideTheme.forest)
          .resolve(AppTheme.light)
          .copyWith(platform: TargetPlatform.macOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: _dark ? Brightness.dark : Brightness.light,
        ),
        child: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: AppTextScaleRegion(
            controller: _shell.appSettings,
            child: child!,
          ),
        ),
      ),
      home: Builder(
        builder: (context) => ColoredBox(
          color: DTokens.of(context).background,
          child: Padding(
            padding: const EdgeInsets.all(DSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings · isolated review',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: DSpacing.lg),
                Wrap(
                  spacing: DSpacing.sm,
                  runSpacing: DSpacing.sm,
                  children: [
                    DButton(
                      label: const Text('Settings'),
                      onPressed: () => showAppSettingsModal(context),
                    ),
                    DButton(
                      label: const Text('Toggle dark'),
                      onPressed: () => setState(() {
                        _dark = !_dark;
                      }),
                    ),
                    DButton(
                      label: const Text('Toggle RTL'),
                      onPressed: () => setState(() {
                        _rtl = !_rtl;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
