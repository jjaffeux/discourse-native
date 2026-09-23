import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

// Offline fixture mounting the production block controls and slash menu.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://block-add.invalid',
      topicId: 1,
      slug: 'review',
      topicTitle: 'Block insertion',
    ),
  );
  void reset() {
    composer.text.value = const TextEditingValue(
      text: 'A paragraph with content.\n\n## Another block\n\n',
      selection: TextSelection.collapsed(offset: 0),
    );
    composer.history.reset();
  }

  reset();
  var dark = true;
  var narrow = false;
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    ShellScope(
      controller: shell,
      child: StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: narrow ? 360 : 720,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: DSpacing.controlGap,
                        children: [
                          DButton(
                            label: Text(dark ? 'Light' : 'Dark'),
                            onPressed: () => setState(() => dark = !dark),
                          ),
                          DButton(
                            label: Text(narrow ? 'Wide' : 'Narrow'),
                            onPressed: () => setState(() => narrow = !narrow),
                          ),
                          DButton(label: const Text('Reset'), onPressed: reset),
                          DButton(
                            label: const Text('Empty line drops'),
                            onPressed: () {
                              composer.text.value = const TextEditingValue(
                                text:
                                    '\n\nA movable paragraph.\n\n\n\n\n## Another block\n\n\n\n',
                                selection: TextSelection.collapsed(offset: 2),
                              );
                              composer.history.reset();
                              composer.focus.unfocus();
                            },
                          ),
                          DButton(
                            label: const Text('Empty draft'),
                            onPressed: () {
                              composer.text.clear();
                              composer.blocks.reset();
                              composer.history.reset();
                              composer.focus.unfocus();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Builder(
                          builder: (context) => ComposerEditor(
                            composer: composer,
                            hintText: 'Write a reply…',
                            hintStyle: Theme.of(context).textTheme.bodyLarge,
                            textStyle: Theme.of(context).textTheme.bodyLarge,
                            autofocus: false,
                          ),
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
  );
}
