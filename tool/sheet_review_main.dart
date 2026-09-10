import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'voice_review_fixture.dart';

const _room = VoiceRoom(
  id: 7,
  name: 'Local fixture',
  slug: 'fixture',
  isPublic: true,
  ephemeral: false,
  type: VoiceRoomType.open,
  participants: [
    VoiceParticipant(id: 1, username: 'fixture', role: VoiceRole.moderator),
  ],
  canManage: true,
  creatorId: 1,
  videoAllowed: true,
  chatAvailable: true,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _SheetReviewApp());
}

class _SheetReviewApp extends StatefulWidget {
  const _SheetReviewApp();

  @override
  State<_SheetReviewApp> createState() => _SheetReviewAppState();
}

class _SheetReviewAppState extends State<_SheetReviewApp> {
  bool _dark = false;
  bool _rtl = false;
  bool _reduceMotion = false;
  double _scale = 1;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_scale),
        disableAnimations: _reduceMotion,
      ),
      child: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Sheet — local production review')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    label: const Text('Sheet styleguide'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ComponentStyleguidePage(),
                      ),
                    ),
                  ),
                  DButton(
                    label: const Text('Light / dark'),
                    onPressed: () => setState(() => _dark = !_dark),
                  ),
                  DButton(
                    label: const Text('LTR / RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: const Text('100% / 200%'),
                    onPressed: () =>
                        setState(() => _scale = _scale == 1 ? 2 : 1),
                  ),
                  DButton(
                    label: const Text('Reduced motion'),
                    onPressed: () =>
                        setState(() => _reduceMotion = !_reduceMotion),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Expanded(child: VoiceReviewFixture(room: _room)),
            ],
          ),
        ),
      ),
    ),
  );
}
