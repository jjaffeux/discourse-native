// Local-data review only. No accounts, network clients, or platform plugins.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/styleguide/examples/select_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const SelectReviewApp());
}

class SelectReviewApp extends StatefulWidget {
  const SelectReviewApp({super.key});

  @override
  State<SelectReviewApp> createState() => _SelectReviewAppState();
}

class _SelectReviewAppState extends State<SelectReviewApp> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _largeText = false;
  bool _reducedMotion = false;
  bool _narrow = false;

  @override
  Widget build(BuildContext context) {
    final theme = _theme
        .resolve(AppTheme.light)
        .copyWith(platform: TargetPlatform.macOS);
    return MaterialApp(
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
        appBar: AppBar(title: const Text('Select review — local data')),
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
                    _reducedMotion ? 'Reduced motion on' : 'Reduced motion off',
                  ),
                ),
                DButton(
                  size: DButtonSize.small,
                  variant: DButtonVariant.outline,
                  onPressed: () => setState(() => _narrow = !_narrow),
                  label: Text(_narrow ? '216px viewport' : 'Wide viewport'),
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
                width: _narrow ? 216 : 640,
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    for (final example in selectExamples.examples) ...[
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
          Center(child: Builder(builder: example.builder)),
        ],
      ),
    ),
  );
}
