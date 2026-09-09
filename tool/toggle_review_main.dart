// Local-data review only. No real accounts, network clients or media devices.
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_view.dart';
import 'package:discourse_native/src/styleguide/examples/toggle_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const ToggleReviewApp());
}

class ToggleReviewApp extends StatefulWidget {
  const ToggleReviewApp({super.key});

  @override
  State<ToggleReviewApp> createState() => _ToggleReviewAppState();
}

class _ToggleReviewAppState extends State<ToggleReviewApp> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _largeText = false;

  @override
  Widget build(BuildContext context) {
    final theme = _theme.resolve(AppTheme.light);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_largeText ? 2 : 1),
          disableAnimations: false,
        ),
        child: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Toggle review — local data')),
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
              ],
            ),
            const SizedBox(height: 20),
            const _VoiceControlsReview(),
            const SizedBox(height: 20),
            for (final example in toggleExamples.examples) ...[
              _ExampleCard(example: example),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceControlsReview extends StatefulWidget {
  const _VoiceControlsReview();

  @override
  State<_VoiceControlsReview> createState() => _VoiceControlsReviewState();
}

class _VoiceControlsReviewState extends State<_VoiceControlsReview> {
  bool _muted = false;
  bool _deafened = false;
  bool _camera = false;
  bool _sharing = false;
  bool _raised = false;
  bool _recording = false;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actual Voice toolbar adapters',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Controlled production controls; state remains owned here as it '
            'is by VoiceController.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VoiceToolbarControl(
                label: _muted ? 'Unmute' : 'Mute',
                icon: _muted ? DIcons.microphoneSlash : DIcons.microphoneLines,
                selected: _muted,
                onPressed: () => setState(() => _muted = !_muted),
              ),
              VoiceToolbarControl(
                label: _deafened ? 'Listen' : 'Deafen',
                icon: DIcons.earListen,
                selected: _deafened,
                onPressed: () => setState(() => _deafened = !_deafened),
              ),
              VoiceToolbarControl(
                label: _camera ? 'Camera off' : 'Camera on',
                icon: _camera ? DIcons.videoSlash : DIcons.video,
                selected: _camera,
                onPressed: () => setState(() => _camera = !_camera),
              ),
              VoiceToolbarControl(
                label: _sharing ? 'Stop sharing' : 'Share screen',
                icon: DIcons.display,
                selected: _sharing,
                onPressed: () => setState(() => _sharing = !_sharing),
              ),
              VoiceToolbarControl(
                label: _raised ? 'Lower hand' : 'Raise hand',
                icon: DIcons.hand,
                selected: _raised,
                onPressed: () => setState(() => _raised = !_raised),
              ),
              VoiceToolbarControl(
                label: _recording ? 'Stop recording' : 'Start recording',
                icon: DIcons.circle,
                selected: _recording,
                onPressed: () => setState(() => _recording = !_recording),
              ),
              VoiceToolbarControl(
                label: 'Media settings',
                icon: DIcons.gear,
                selected: null,
                onPressed: () {},
              ),
            ],
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
