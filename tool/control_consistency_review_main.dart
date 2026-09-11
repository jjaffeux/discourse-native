import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/topic_taxonomy_button.dart';
import 'package:discourse_native/src/styleguide/examples/button_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Mounts the control comparison and production taxonomy triggers with local data.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  StyleguideTheme _palette = StyleguideTheme.dark;
  bool _narrow = false;
  bool _large = false;
  bool _rtl = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _palette.resolve(AppTheme.light),
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DText('Control consistency', variant: DTextVariant.h2),
              const SizedBox(height: DSpacing.lg),
              Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  for (final palette in StyleguideTheme.values.where(
                    (palette) => palette != StyleguideTheme.current,
                  ))
                    DButton(
                      label: Text(palette.label),
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(() => _palette = palette),
                    ),
                  DButton(
                    label: Text(_narrow ? 'Width: 320' : 'Width: 640'),
                    onPressed: () => setState(() => _narrow = !_narrow),
                  ),
                  DButton(
                    label: Text(_large ? 'Text: 200%' : 'Text: 100%'),
                    onPressed: () => setState(() => _large = !_large),
                  ),
                  DButton(
                    label: Text(_rtl ? 'RTL' : 'LTR'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                ],
              ),
              const SizedBox(height: DSpacing.xl),
              Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  for (final label in ['Discourse', 'Bugs', 'Tags'])
                    TopicTaxonomyButton(
                      label: label,
                      semanticLabel: label,
                      maximumWidth: 240,
                      onPressed: () {},
                    ),
                ],
              ),
              const SizedBox(height: DSpacing.xl),
              Center(
                child: SizedBox(
                  width: _narrow ? 320 : 640,
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
                      child: Directionality(
                        textDirection: _rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Builder(
                          builder: buttonExamples.examples
                              .singleWhere(
                                (example) =>
                                    example.title == 'Control consistency',
                              )
                              .builder,
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
  );
}
