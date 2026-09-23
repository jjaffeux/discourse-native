// Offline visual and interaction review of the production checklist composer.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _TodoReview());
}

class _TodoReview extends StatefulWidget {
  const _TodoReview();
  @override
  State<_TodoReview> createState() => _TodoReviewState();
}

class _TodoReviewState extends State<_TodoReview> {
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://todo-review.invalid',
      topicId: 1,
      slug: 'review',
      topicTitle: 'To-do list',
    ),
  );
  bool dark = true;
  bool narrow = false;

  @override
  void initState() {
    super.initState();
    composer.text.text =
        '- [x] Send the design\n'
        '- [ ] Review the implementation and verify the longer lines wrap beside the checkbox\n'
        '  Keep this continuation aligned with the task text.\n\n'
        '  Check the earlier database versions too.\n\n'
        '  ```sh\n  run-migration-checks\n  ```\n\n'
        '  - [ ] Check the nested task\n'
        '- [ ] ';
  }

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: narrow ? 360 : 680,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                  ],
                ),
                const SizedBox(height: 24),
                const Text('To-do list'),
                const SizedBox(height: 12),
                Expanded(
                  child: ComposerEditor(
                    composer: composer,
                    hintText: 'Type /todo',
                    textStyle: const TextStyle(fontSize: 16, height: 1.5),
                    hintStyle: null,
                  ),
                ),
                const DSeparator(),
                const SizedBox(height: 16),
                const Text('Saved post'),
                const SizedBox(height: 8),
                const CookedHtml(
                  html:
                      '<ul><li><span class="chcklst-box checked"></span> Send the design</li>'
                      '<li><p><span class="chcklst-box"></span> Review the implementation and verify the longer lines wrap beside the checkbox<br>'
                      'Keep this continuation aligned with the task text.</p>'
                      '<p>Check the earlier database versions too.</p>'
                      '<pre><code class="lang-sh">run-migration-checks</code></pre>'
                      '<ul><li><span class="chcklst-box"></span> Check the nested task</li></ul></li></ul>',
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
