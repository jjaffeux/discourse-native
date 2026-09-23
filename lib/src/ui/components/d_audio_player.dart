import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_card.dart';
import 'd_slider.dart';
import 'd_spinner.dart';

/// Controlled audio transport. The application owns playback and its lifetime.
class DAudioPlayer extends StatelessWidget {
  const DAudioPlayer({
    super.key,
    required this.title,
    required this.onPlayPause,
    this.playing = false,
    this.loading = false,
    this.failed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.onSeek,
    this.onRetry,
    this.onOpen,
  });

  final String title;
  final bool playing;
  final bool loading;
  final bool failed;
  final Duration position;
  final Duration duration;
  final VoidCallback? onPlayPause;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onRetry;
  final VoidCallback? onOpen;

  static String timeLabel(Duration value) {
    final seconds = value.inSeconds.clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => DCard(
    children: [
      DCardHeader(title: Text(title)),
      if (failed) const DCardContent(child: Text('Could not play this audio.')),
      if (!failed) ...[
        DCardContent(
          child: DSlider(
            value: position.inMilliseconds.toDouble().clamp(
              0,
              duration.inMilliseconds.toDouble().clamp(1, double.infinity),
            ),
            max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
            step: 1000,
            semanticLabel: 'Audio position',
            semanticFormatterCallback: (value) =>
                timeLabel(Duration(milliseconds: value.round())),
            onChanged: duration > Duration.zero && !loading && onSeek != null
                ? (value) => onSeek!(Duration(milliseconds: value.round()))
                : null,
          ),
        ),
        DCardContent(
          child: Text('${timeLabel(position)} / ${timeLabel(duration)}'),
        ),
      ],
      DCardContent(
        child: Wrap(
          spacing: DSpacing.controlGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (loading) const DSpinner(),
            if (!failed)
              DButton(
                label: Text(playing ? 'Pause audio' : 'Play audio'),
                onPressed: loading ? null : onPlayPause,
              ),
            if (failed && onRetry != null)
              DButton(label: const Text('Retry audio'), onPressed: onRetry),
            if (onOpen != null)
              DButton(
                variant: DButtonVariant.outline,
                label: const Text('Open audio'),
                onPressed: onOpen,
              ),
          ],
        ),
      ),
    ],
  );
}
