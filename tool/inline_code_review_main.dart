import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/styleguide/examples/typography_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final palette in StyleguideTheme.values.where(
                  (value) => value != StyleguideTheme.current,
                ))
                  SizedBox(
                    width: 510,
                    child: Theme(
                      data: palette.resolve(AppTheme.light),
                      child: Builder(
                        builder: (context) => DCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 12,
                              children: [
                                DText(
                                  palette.label,
                                  variant: DTextVariant.large,
                                ),
                                typographyExamples.examples.first.builder(
                                  context,
                                ),
                                const DText('Authored message'),
                                const DBubble(
                                  variant: DBubbleVariant.neutral,
                                  maximumWidthFactor: 1,
                                  children: [
                                    DBubbleContent(
                                      child: CookedHtml(
                                        html:
                                            "<p>so if we're running <code>pg_restore -j 4 ...</code> "
                                            'it would use 4×4GB not 4 * '
                                            '<code>max_parallel_maintenance_workers</code> * 4GB</p>',
                                        textStyle: TextStyle(
                                          fontFamily: 'JetBrains Mono',
                                        ),
                                        compactParagraphs: true,
                                        contentSized: true,
                                      ),
                                    ),
                                  ],
                                ),
                                const CookedHtml(
                                  html:
                                      '<p>Linked: '
                                      '<a href="https://example.com"><code>pg_restore</code></a>.</p>',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
