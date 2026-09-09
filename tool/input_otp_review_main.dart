// Local-only Input OTP inspection fixture. It performs no network or auth work.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/styleguide/examples/input_otp_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _InputOTPReview());
}

class _InputOTPReview extends StatefulWidget {
  const _InputOTPReview();
  @override
  State<_InputOTPReview> createState() => _InputOTPReviewState();
}

class _InputOTPReviewState extends State<_InputOTPReview> {
  StyleguideTheme _palette = StyleguideTheme.light;
  double _scale = 1;
  bool _rtl = false;
  bool _reducedMotion = false;
  double _width = 448;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _palette.resolve(AppTheme.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_scale),
        disableAnimations: _reducedMotion,
      ),
      child: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Input OTP — local review')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final palette in StyleguideTheme.values)
                    DButton(
                      label: Text(palette.label),
                      onPressed: () => setState(() => _palette = palette),
                    ),
                  DButton(
                    label: Text('${(_scale * 100).round()}% text'),
                    onPressed: () =>
                        setState(() => _scale = _scale == 1 ? 2 : 1),
                  ),
                  DButton(
                    label: Text(_rtl ? 'RTL' : 'LTR'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: Text(_reducedMotion ? 'Motion off' : 'Motion on'),
                    onPressed: () =>
                        setState(() => _reducedMotion = !_reducedMotion),
                  ),
                  DButton(
                    label: Text('${_width.round()}px'),
                    onPressed: () =>
                        setState(() => _width = _width == 448 ? 320 : 448),
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
              const SizedBox(height: 24),
              AnimatedContainer(
                duration: _reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                width: _width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final example in inputOTPExamples.examples) ...[
                      Text(
                        example.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      example.builder(context),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
