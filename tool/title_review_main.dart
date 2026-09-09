import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

/// Local-data fixture for the production title editor and documentation shell.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _TitleReview());
}

class _TitleReview extends StatefulWidget {
  const _TitleReview();

  @override
  State<_TitleReview> createState() => _TitleReviewState();
}

class _TitleReviewState extends State<_TitleReview> {
  final _shell = ShellController(
    instanceStore: FakeInstanceStore([instance('review.example')]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  bool _dark = false;
  bool _large = false;
  bool _failSave = false;
  String _title = 'A clearer topic title';
  String _result = 'No save attempted';

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
      theme: _dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            label: Text(_dark ? 'Light theme' : 'Dark theme'),
                            onPressed: () => setState(() => _dark = !_dark),
                          ),
                          DButton(
                            label: Text(_large ? '100% text' : '200% text'),
                            onPressed: () => setState(() => _large = !_large),
                          ),
                          DButton(
                            label: Text(
                              _failSave ? 'Allow save' : 'Simulate save error',
                            ),
                            onPressed: () =>
                                setState(() => _failSave = !_failSave),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Click the title to edit. Escape cancels; Enter saves.',
                      ),
                      const SizedBox(height: 24),
                      InlineTopicTitleEditor(
                        title: _title,
                        siteUrl: 'https://review.example',
                        showEditingFrame: true,
                        style: Theme.of(context).textTheme.titleLarge,
                        onSave: (value) async {
                          setState(() {
                            _result = _failSave
                                ? 'Save rejected; edit retained'
                                : 'Saved: $value';
                            if (!_failSave) _title = value;
                          });
                          return _failSave ? 'Simulated save error' : null;
                        },
                      ),
                      const SizedBox(height: 32),
                      Text(_result),
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
