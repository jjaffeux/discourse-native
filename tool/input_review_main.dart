// Local-data inspection of the actual migrated app fields; no account requests.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_sheet.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/input_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(
      results: {
        'forum.example': const DiscourseInstance(
          url: 'https://forum.example',
          title: 'Local fixture',
        ),
      },
    ),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(ShellScope(controller: controller, child: const _Review()));
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  StyleguideTheme _palette = StyleguideTheme.light;
  double _scale = 1;
  bool _rtl = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _palette.resolve(AppTheme.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_scale)),
      child: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Input review — isolated local data')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final palette in [
                    StyleguideTheme.light,
                    StyleguideTheme.dark,
                    StyleguideTheme.forest,
                    StyleguideTheme.plum,
                  ])
                    DButton(
                      label: Text(palette.label),
                      onPressed: () => setState(() => _palette = palette),
                    ),
                  DButton(
                    label: Text('${(_scale * 100).round()}% text'),
                    onPressed: () =>
                        setState(() => _scale = _scale == 1 ? 2 : 1),
                  ),
                  DButton(
                    label: const Text('RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: const Text('Styleguide'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ComponentStyleguidePage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    label: const Text('Real Add a Site'),
                    onPressed: () => showAddInstanceSheet(context),
                  ),
                  DButton(
                    label: const Text('Real Poll editor'),
                    onPressed: () => showPollComposerSheet(
                      context: context,
                      draft: PollComposerDraft.newPoll(
                        name: 'poll',
                        defaultPublic: false,
                      ),
                      maximumOptions: 20,
                      isStaff: true,
                      isPublished: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Reference specimen • 320 logical pixels wide'),
              const SizedBox(height: 16),
              SizedBox(
                width: 320,
                child: Column(
                  children: [
                    DInput(hintText: 'Enter text'),
                    const SizedBox(height: 20),
                    DInput(
                      labelText: 'Username',
                      hintText: 'Enter your username',
                      helperText: 'Choose a unique username for your account.',
                    ),
                    const SizedBox(height: 20),
                    DInput(
                      labelText: 'Email',
                      hintText: 'Email',
                      enabled: false,
                    ),
                    const SizedBox(height: 20),
                    DInput(
                      labelText: 'Invalid Input',
                      hintText: 'Error',
                      errorText: 'This field contains validation errors.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(width: 600, child: InputFormExample()),
            ],
          ),
        ),
      ),
    ),
  );
}
