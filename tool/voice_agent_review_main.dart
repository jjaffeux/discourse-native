import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'voice_review_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _AgentReviewApp());
}

class _AgentReviewApp extends StatefulWidget {
  const _AgentReviewApp();

  @override
  State<_AgentReviewApp> createState() => _AgentReviewAppState();
}

class _AgentReviewAppState extends State<_AgentReviewApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DToggle(
              pressed: _dark,
              onPressedChanged: (value) => setState(() => _dark = value),
              child: const Text('Dark theme'),
            ),
            const Expanded(child: VoiceReviewFixture(agentInvitations: true)),
          ],
        ),
      ),
    ),
  );
}
