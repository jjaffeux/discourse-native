import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/color_picker_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

// Offline fixture mounting the production selection menu with color support.
class _ColorShell extends ShellController {
  _ColorShell()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
  @override
  bool supportsComposerColors(String siteUrl) => true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = _ColorShell();
  await shell.load();
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://selection.invalid',
      topicId: 1,
      slug: 'review',
      topicTitle: 'Selection formatting',
    ),
  );
  void reset() {
    composer.text.value = const TextEditingValue(
      text:
          'Select text to format it.\n\nTry bold, italic, underline, links and inline code.\n\n'
          'E = mc<sup>2</sup> and H<sub>2</sub>O\n\n'
          'Press <kbd>Ctrl</kbd> + <kbd>**Shift**</kbd> + <kbd>K</kbd>.',
      selection: TextSelection(baseOffset: 0, extentOffset: 11),
    );
    composer.history.reset();
    composer.focus.requestFocus();
  }

  reset();
  var dark = true;
  var narrow = false;
  var styleguide = false;
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
                            label: Text(styleguide ? 'Composer' : 'Styleguide'),
                            onPressed: () =>
                                setState(() => styleguide = !styleguide),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Builder(
                          builder: (context) => styleguide
                              ? colorPickerExamples.examples.first.builder(
                                  context,
                                )
                              : ComposerEditor(
                                  composer: composer,
                                  hintText: 'Write a reply…',
                                  hintStyle: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge,
                                  textStyle: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge,
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
