import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/styleguide/examples/message_scroller_examples.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/styleguide/styleguide_theme.dart';
import 'src/theme/app_theme.dart';

/// Offline exact-source fixture for independent Message Scroller review.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _MessageScrollerReview());
}

class _MessageScrollerReview extends StatefulWidget {
  const _MessageScrollerReview();

  @override
  State<_MessageScrollerReview> createState() => _MessageScrollerReviewState();
}

class _MessageScrollerReviewState extends State<_MessageScrollerReview> {
  var _dark = false;
  var _narrow = false;
  var _large = false;
  var _rtl = false;
  var _reduced = false;
  var _plum = false;
  var _example = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _plum
        ? StyleguideTheme.plum.resolve(AppTheme.light)
        : _dark
        ? AppTheme.dark
        : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Message Scroller Review 0ff5')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DButton(
                  label: const Text('Open styleguide'),
                  onPressed: () => showComponentStyleguide(context),
                ),
                DButton(
                  label: const Text('Light / dark'),
                  onPressed: () => setState(() => _dark = !_dark),
                ),
                DButton(
                  label: const Text('Plum palette'),
                  onPressed: () => setState(() => _plum = !_plum),
                ),
                DButton(
                  label: const Text('360px'),
                  onPressed: () => setState(() => _narrow = !_narrow),
                ),
                DButton(
                  label: const Text('200% text'),
                  onPressed: () => setState(() => _large = !_large),
                ),
                DButton(
                  label: const Text('RTL'),
                  onPressed: () => setState(() => _rtl = !_rtl),
                ),
                DButton(
                  label: const Text('Reduced motion'),
                  onPressed: () => setState(() => _reduced = !_reduced),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButton<int>(
              value: _example,
              items: [
                for (
                  var index = 0;
                  index < messageScrollerExamples.examples.length;
                  index++
                )
                  DropdownMenuItem(
                    value: index,
                    child: Text(messageScrollerExamples.examples[index].title),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _example = value);
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: _narrow ? 360 : 720,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(_large ? 2 : 1),
                    disableAnimations: _reduced,
                  ),
                  child: Directionality(
                    textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Builder(
                      builder:
                          messageScrollerExamples.examples[_example].builder,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
