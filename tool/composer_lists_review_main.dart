// Offline visual and interaction review of the production list composer.
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
  runApp(const _ListsReview());
}

class _ListsReview extends StatefulWidget {
  const _ListsReview();
  @override
  State<_ListsReview> createState() => _ListsReviewState();
}

class _ListsReviewState extends State<_ListsReview> {
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://lists-review.invalid',
      topicId: 1,
      slug: 'review',
      topicTitle: 'Lists',
    ),
  );
  bool dark = true;
  bool narrow = false;

  @override
  void initState() {
    super.initState();
    composer.text.text =
        '- First bullet\n'
        '- Another bullet with **bold** text\n'
        '  - A nested bullet\n'
        '- [ ] A to-do in the same list\n\n'
        '1. First numbered item\n'
        '1. Second item with a longer line that wraps in a narrow composer\n'
        '1. ';
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
                      label: const Text('Clear'),
                      onPressed: () {
                        composer.text.clear();
                        composer.requestFocus();
                      },
                    ),
                    DButton(
                      label: Text(narrow ? 'Wide' : 'Narrow'),
                      onPressed: () => setState(() => narrow = !narrow),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Bulleted and numbered lists'),
                const SizedBox(height: 12),
                Expanded(
                  child: ComposerEditor(
                    composer: composer,
                    hintText: 'Type /bullet or /number',
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
                      '<ul><li>First bullet</li><li>Another bullet with <strong>bold</strong> text<ul><li>A nested bullet</li></ul></li></ul>'
                      '<ol><li>First numbered item</li><li>Second numbered item</li></ol>',
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
