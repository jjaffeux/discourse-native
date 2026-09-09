import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/plugins/voice/voice_join.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Local-data review target. No shell, account store, API client or voice join.
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
  StyleguideTheme theme = StyleguideTheme.light;
  double scale = 1;
  bool rtl = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    theme: theme.resolve(AppTheme.light),
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final choice in [
                    StyleguideTheme.light,
                    StyleguideTheme.dark,
                    StyleguideTheme.forest,
                    StyleguideTheme.plum,
                  ])
                    DButton(
                      label: Text(choice.name),
                      onPressed: () => setState(() => theme = choice),
                    ),
                  DButton(
                    label: Text(scale == 1 ? '200%' : '100%'),
                    onPressed: () => setState(() => scale = scale == 1 ? 2 : 1),
                  ),
                  DButton(
                    label: Text(rtl ? 'LTR' : 'RTL'),
                    onPressed: () => setState(() => rtl = !rtl),
                  ),
                ],
              ),
              Expanded(
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: const _FixtureHome(),
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

class _FixtureHome extends StatelessWidget {
  const _FixtureHome();
  @override
  Widget build(BuildContext context) => Center(
    child: Wrap(
      spacing: 12,
      children: [
        DButton(
          label: const Text('Styleguide'),
          onPressed: () => showComponentStyleguide(context),
        ),
        DButton(
          label: const Text('Legal confirmation'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _LegalFixture(),
                ),
              ),
            ),
          ),
        ),
        DButton(
          label: const Text('Voice privacy'),
          onPressed: () => showDialog<VoiceMeshPrivacyDecision>(
            context: context,
            builder: (_) => const VoiceMeshPrivacyDialog(),
          ),
        ),
      ],
    ),
  );
}

class _LegalFixture extends StatefulWidget {
  @override
  State<_LegalFixture> createState() => _LegalFixtureState();
}

class _LegalFixtureState extends State<_LegalFixture> {
  int attempts = 0;
  @override
  Widget build(BuildContext context) => PostFlagEditor(
    siteUrl: 'https://checkbox.example.test',
    targetUsername: 'sample',
    flagTypes: const [
      PostFlagType(
        id: 8,
        nameKey: 'illegal',
        name: 'Illegal',
        description: '<p>This may break the law.</p>',
        requireMessage: true,
        appliesTo: ['Post'],
      ),
    ],
    minimumMessageLength: 5,
    save: (type, {message}) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return ++attempts == 1
          ? 'Local fixture error. Your confirmation is retained; retry.'
          : null;
    },
    onComplete: () => Navigator.of(context).pop(),
  );
}
