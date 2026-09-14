// Local-only review fixture: registered examples and the production composer.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/toggle_group_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

const _target = ComposerTarget(
  siteUrl: 'https://toggle-group.invalid',
  topicId: 7,
  slug: 'local-review',
  topicTitle: 'Local Toggle Group review',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This executable must never read or write the user's real app preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  final composer = ComposerController(
    _target,
    resolveUploadUrls: (_) async => const {},
  );
  composer.text.value = const TextEditingValue(
    text:
        '[grid]\n'
        '![One|640x480](upload://one)\n'
        '![Two|640x480](upload://two)\n'
        '[/grid]',
    selection: TextSelection.collapsed(offset: 0),
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(ToggleGroupReviewApp(shell: shell, composer: composer));
}

class ToggleGroupReviewApp extends StatefulWidget {
  const ToggleGroupReviewApp({
    super.key,
    required this.shell,
    required this.composer,
  });

  final ShellController shell;
  final ComposerController composer;

  @override
  State<ToggleGroupReviewApp> createState() => _ToggleGroupReviewAppState();
}

class _ToggleGroupReviewAppState extends State<ToggleGroupReviewApp> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _largeText = false;
  bool _reducedMotion = false;
  bool _showComposer = false;
  int _example = 0;

  @override
  void dispose() {
    widget.composer.dispose();
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme.resolve(AppTheme.light);
    final example = toggleGroupExamples.examples[_example];
    return ShellScope(
      controller: widget.shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_largeText ? 2 : 1),
            disableAnimations: _reducedMotion,
          ),
          child: Directionality(
            textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Toggle Group — local native review'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in [
                    StyleguideTheme.light,
                    StyleguideTheme.dark,
                    StyleguideTheme.forest,
                    StyleguideTheme.plum,
                  ])
                    DButton(
                      size: DButtonSize.small,
                      variant: _theme == choice
                          ? DButtonVariant.primary
                          : DButtonVariant.outline,
                      onPressed: () => setState(() => _theme = choice),
                      label: Text(choice.label),
                    ),
                  DButton(
                    size: DButtonSize.small,
                    variant: DButtonVariant.outline,
                    onPressed: () => setState(() => _rtl = !_rtl),
                    label: Text(_rtl ? 'RTL on' : 'RTL off'),
                  ),
                  DButton(
                    size: DButtonSize.small,
                    variant: DButtonVariant.outline,
                    onPressed: () => setState(() => _largeText = !_largeText),
                    label: Text(_largeText ? '200% text' : '100% text'),
                  ),
                  DButton(
                    size: DButtonSize.small,
                    variant: DButtonVariant.outline,
                    onPressed: () =>
                        setState(() => _reducedMotion = !_reducedMotion),
                    label: Text(
                      _reducedMotion
                          ? 'Reduced motion on'
                          : 'Reduced motion off',
                    ),
                  ),
                  DButton(
                    size: DButtonSize.small,
                    variant: DButtonVariant.outline,
                    onPressed: () =>
                        setState(() => _showComposer = !_showComposer),
                    label: Text(
                      _showComposer ? 'Show examples' : 'Show real composer',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_showComposer)
                _ComposerReview(composer: widget.composer)
              else ...[
                Row(
                  children: [
                    DButton(
                      size: DButtonSize.small,
                      variant: DButtonVariant.outline,
                      onPressed: _example == 0
                          ? null
                          : () => setState(() => _example--),
                      label: const Text('Previous example'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_example + 1}/${toggleGroupExamples.examples.length}: '
                        '${example.title}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DButton(
                      size: DButtonSize.small,
                      variant: DButtonVariant.outline,
                      onPressed:
                          _example == toggleGroupExamples.examples.length - 1
                          ? null
                          : () => setState(() => _example++),
                      label: const Text('Next example'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ExampleCard(example: example),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.example});

  final StyleguideExample example;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(example.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(example.description),
          const SizedBox(height: 20),
          Center(child: Builder(builder: example.builder)),
        ],
      ),
    ),
  );
}

class _ComposerReview extends StatelessWidget {
  const _ComposerReview({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Actual production ComposerPanel — in-memory gallery data',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Select the gallery preview, then switch Grid/Carousel. The production '
        'controller owns the markup, selection identity, callback and focus.',
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 620,
        child: ComposerPanel(
          composer: composer,
          height: 620,
          pickImages: _cancelImagePick,
          readClipboardFiles: _cancelImagePick,
        ),
      ),
    ],
  );
}

Future<List<ComposerUploadFile>> _cancelImagePick() async => const [];
