// Offline review fixture. It uses only local sample data and real components.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/styleguide/examples/breadcrumb_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const BreadcrumbReviewApp());
}

class BreadcrumbReviewApp extends StatefulWidget {
  const BreadcrumbReviewApp({super.key});

  @override
  State<BreadcrumbReviewApp> createState() => _BreadcrumbReviewAppState();
}

class _BreadcrumbReviewAppState extends State<BreadcrumbReviewApp> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _largeText = false;
  bool _reducedMotion = false;
  bool _narrow = false;

  void _scheduleThemeChange() {
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _theme = _theme == StyleguideTheme.dark
            ? StyleguideTheme.light
            : StyleguideTheme.dark;
      });
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme.resolve(AppTheme.light),
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
      appBar: AppBar(title: const Text('Breadcrumb review — local data')),
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
                  _reducedMotion ? 'Reduced motion' : 'Motion enabled',
                ),
              ),
              DButton(
                size: DButtonSize.small,
                variant: DButtonVariant.outline,
                onPressed: () => setState(() => _narrow = !_narrow),
                label: Text(_narrow ? '240px viewport' : 'Full width'),
              ),
              DButton(
                size: DButtonSize.small,
                variant: DButtonVariant.outline,
                onPressed: _scheduleThemeChange,
                label: const Text('Toggle theme in 2s'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.topCenter,
            child: SizedBox(
              width: _narrow ? 240 : null,
              child: Column(
                spacing: 16,
                children: [
                  for (final example in breadcrumbExamples.examples)
                    _ExampleCard(example: example),
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
      color: DTokens.of(context).surface,
      border: Border.all(color: DTokens.of(context).border),
      borderRadius: DTokens.of(context).borderRadius,
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(example.title, style: Theme.of(context).textTheme.titleMedium),
          Text(example.description),
          Center(child: Builder(builder: example.builder)),
        ],
      ),
    ),
  );
}
