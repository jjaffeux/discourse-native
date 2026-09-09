// Offline native review of the actual Button Group styleguide and production
// navigation adoption. All state uses in-memory fakes; no account or network
// is used.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/content_navigation_controls.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/button_group_examples.dart';
import 'package:discourse_native/src/styleguide/examples/input_group_examples.dart';
import 'package:discourse_native/src/styleguide/examples/select_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_ButtonGroupReview(shell: shell));
}

class _ButtonGroupReview extends StatefulWidget {
  const _ButtonGroupReview({required this.shell});

  final ShellController shell;

  @override
  State<_ButtonGroupReview> createState() => _ButtonGroupReviewState();
}

class _ButtonGroupReviewState extends State<_ButtonGroupReview> {
  var _example = 0;
  var _palette = 0;
  var _rtl = false;
  var _scale = 1.0;
  var _width = 440.0;

  static const _palettes = [
    StyleguideTheme.light,
    StyleguideTheme.dark,
    StyleguideTheme.forest,
    StyleguideTheme.plum,
  ];

  @override
  void dispose() {
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final examples = [
      ...buttonGroupExamples.examples,
      selectExamples.examples.singleWhere(
        (example) => example.title == 'Button Group composition',
      ),
      inputGroupExamples.examples.singleWhere(
        (example) => example.title == 'Button actions',
      ),
    ];
    final example = examples[_example];
    return ShellScope(
      controller: widget.shell,
      child: MaterialApp(
        theme: _palettes[_palette].resolve(AppTheme.light),
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
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Button Group — exact-source review'),
            actions: const [ContentNavigationControls(), SizedBox(width: 12)],
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
                      label: const Text('Previous example'),
                      onPressed: _example == 0
                          ? null
                          : () => setState(() => _example--),
                    ),
                    DButton(
                      label: const Text('Next example'),
                      onPressed: _example == examples.length - 1
                          ? null
                          : () => setState(() => _example++),
                    ),
                    DButton(
                      label: Text('Theme: ${_palettes[_palette].label}'),
                      onPressed: () => setState(
                        () => _palette = (_palette + 1) % _palettes.length,
                      ),
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
                    DButton(
                      label: Text('Width: ${_width.toInt()}'),
                      onPressed: () =>
                          setState(() => _width = _width == 440 ? 320 : 440),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '${_example + 1}/${examples.length} — '
                  '${example.title}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(example.description),
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: _width,
                    child: Center(
                      child: Builder(
                        key: ValueKey(example.title),
                        builder: example.builder,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
