import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../styleguide_example.dart';

final audioPlayerExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Native audio transport controls with accessible seeking.',
  notes:
      'This example uses local state. Play and Pause change the control state; '
      'the slider changes the displayed position. Real media playback is in the Onebox gallery.',
  examples: [
    StyleguideExample(
      title: 'Playback',
      description: 'Play, pause and seek through local sample state.',
      code:
          'DAudioPlayer(title: title, playing: playing, position: position, duration: duration, onPlayPause: toggle, onSeek: seek)',
      builder: (_) => const _AudioExample(),
    ),
    StyleguideExample(
      title: 'Loading',
      description: 'Playback stays disabled while the source initializes.',
      code: 'DAudioPlayer(title: title, loading: true, onPlayPause: null)',
      builder: (_) => const DAudioPlayer(
        title: 'Loading recording',
        loading: true,
        onPlayPause: null,
      ),
    ),
    StyleguideExample(
      title: 'Unavailable',
      description: 'Retry recovers the local example.',
      code:
          'DAudioPlayer(title: title, failed: true, onRetry: retry, onPlayPause: null)',
      builder: (_) => const _AudioExample(initialFailure: true),
    ),
  ],
);

class _AudioExample extends StatefulWidget {
  const _AudioExample({this.initialFailure = false});
  final bool initialFailure;
  @override
  State<_AudioExample> createState() => _AudioExampleState();
}

class _AudioExampleState extends State<_AudioExample> {
  bool _playing = false;
  late bool _failed = widget.initialFailure;
  Duration _position = const Duration(seconds: 30);
  @override
  Widget build(BuildContext context) => DAudioPlayer(
    title: 'Community recording',
    playing: _playing,
    failed: _failed,
    position: _position,
    duration: const Duration(minutes: 3),
    onPlayPause: () => setState(() => _playing = !_playing),
    onSeek: (position) => setState(() => _position = position),
    onRetry: () => setState(() => _failed = false),
  );
}
