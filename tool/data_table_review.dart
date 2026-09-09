import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/styleguide/examples/data_table_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Offline exact-widget fixture for the serialized Data Table native review.
/// It makes no account, store, clipboard, or network request.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _DataTableReviewApp());
}

class _DataTableReviewApp extends StatefulWidget {
  const _DataTableReviewApp();

  @override
  State<_DataTableReviewApp> createState() => _DataTableReviewAppState();
}

class _DataTableReviewAppState extends State<_DataTableReviewApp> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _largeText = false;
  bool _reducedMotion = false;
  bool _narrow = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme
        .resolve(AppTheme.light)
        .copyWith(platform: TargetPlatform.macOS),
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          size: Size(_narrow ? 360 : media.size.width, media.size.height),
          textScaler: TextScaler.linear(_largeText ? 2 : 1),
          disableAnimations: _reducedMotion,
        ),
        child: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      );
    },
    home: Scaffold(
      appBar: AppBar(title: const Text('Data Table review — local data')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in const [
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
                  _reducedMotion ? 'Reduced motion on' : 'Reduced motion off',
                ),
              ),
              DButton(
                size: DButtonSize.small,
                variant: DButtonVariant.outline,
                onPressed: () => setState(() => _narrow = !_narrow),
                label: Text(_narrow ? '360px viewport' : 'Wide viewport'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.topCenter,
            child: AnimatedContainer(
              duration: _reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              width: _narrow ? 360 : 900,
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  for (final example in dataTableExamples.examples) ...[
                    _ExampleCard(example: example),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.example});

  final StyleguideExample example;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: DTokens.of(context).border),
      borderRadius: BorderRadius.circular(DTokens.of(context).radius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(example.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(example.description),
          const SizedBox(height: 16),
          Builder(builder: example.builder),
        ],
      ),
    ),
  );
}
