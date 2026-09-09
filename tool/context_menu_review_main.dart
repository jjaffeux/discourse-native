// Native review fixture using the production rail and in-memory forum data.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/context_menu_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('alpha-review.invalid', title: 'Alpha'),
      instance('beta-review.invalid', title: 'Beta'),
      instance('gamma-review.invalid', title: 'Gamma'),
    ]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_ContextMenuReview(controller: controller));
}

class _ContextMenuReview extends StatefulWidget {
  const _ContextMenuReview({required this.controller});

  final ShellController controller;

  @override
  State<_ContextMenuReview> createState() => _ContextMenuReviewState();
}

class _ContextMenuReviewState extends State<_ContextMenuReview> {
  bool _dark = false;
  bool _forest = false;
  bool _rtl = false;
  bool _touch = false;
  bool _largeText = false;
  bool _reducedMotion = false;
  String _example = 'Sides';

  ThemeData get _theme {
    final base = _dark ? AppTheme.dark : AppTheme.light;
    return (_forest ? StyleguideTheme.forest.resolve(base) : base).copyWith(
      platform: _touch ? TargetPlatform.iOS : TargetPlatform.macOS,
    );
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.controller,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_largeText ? 2 : 1),
          disableAnimations: _reducedMotion,
        ),
        child: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: DToaster(child: child ?? const SizedBox.shrink()),
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Context Menu review')),
          body: Row(
            children: [
              const SizedBox(width: 64, child: InstanceRail()),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 24,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          DButton(
                            label: Text(_dark ? 'Light' : 'Dark'),
                            onPressed: () => setState(() => _dark = !_dark),
                          ),
                          DButton(
                            label: Text(_forest ? 'Default palette' : 'Forest'),
                            onPressed: () => setState(() => _forest = !_forest),
                          ),
                          DButton(
                            label: Text(_rtl ? 'LTR' : 'RTL'),
                            onPressed: () => setState(() => _rtl = !_rtl),
                          ),
                          DButton(
                            label: Text(
                              _touch ? 'Desktop actions' : 'Touch actions',
                            ),
                            onPressed: () => setState(() => _touch = !_touch),
                          ),
                          DButton(
                            label: Text(_largeText ? '100%' : '200%'),
                            onPressed: () =>
                                setState(() => _largeText = !_largeText),
                          ),
                          DButton(
                            label: Text(
                              _reducedMotion ? 'Motion on' : 'Reduced motion',
                            ),
                            onPressed: () => setState(
                              () => _reducedMotion = !_reducedMotion,
                            ),
                          ),
                          DButton(
                            label: const Text('Full styleguide'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ComponentStyleguidePage(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) => Text(
                          'Forum order: ${widget.controller.instances.map((site) => site.title).join(', ')}',
                        ),
                      ),
                      const Text(
                        'The left rail is the production InstanceRail. '
                        'Context actions modify only these in-memory forums.',
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final example in contextMenuExamples.examples)
                            DButton(
                              label: Text(example.title),
                              onPressed: () =>
                                  setState(() => _example = example.title),
                            ),
                        ],
                      ),
                      Text('Example: $_example'),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: KeyedSubtree(
                          key: ValueKey(_example),
                          child: Builder(
                            builder: contextMenuExamples.examples
                                .firstWhere((item) => item.title == _example)
                                .builder,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }
}
