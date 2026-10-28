import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../styleguide_example.dart';

final animatedEmojiExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Animated emoji artwork with a static fallback and reduced-motion support.',
  examples: [
    StyleguideExample(
      title: 'Animated and static artwork',
      description:
          'The second preview always follows the reduced-motion preference.',
      code: '''DAnimatedEmoji(
  url: staticUrl,
  animatedUrl: animatedUrl,
  alt: ':clap:',
)''',
      builder: (context) => Row(
        spacing: DSpacing.lg,
        children: [
          const _Emoji(),
          MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const _Emoji(),
          ),
        ],
      ),
    ),
  ],
);

final reactionOverlayExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Short-lived emoji bursts over a bounded call stage or floating preview.',
  examples: [
    StyleguideExample(
      title: 'Floating reactions',
      description:
          'Send a reaction to preview the kit-owned motion and sender label.',
      code: '''DReactionOverlay(entries: [
  DReactionOverlayEntry(id: id, label: username, artwork: emoji),
])''',
      builder: (_) => const _ReactionDemo(),
    ),
  ],
);

class _Emoji extends StatelessWidget {
  const _Emoji();

  @override
  Widget build(BuildContext context) => const DAnimatedEmoji(
    url: 'https://meta.discourse.org/images/emoji/twitter/clap.png',
    animatedUrl:
        'https://meta.discourse.org/images/emoji/noto_animated/clap.avif',
    alt: ':clap:',
  );
}

class _ReactionDemo extends StatefulWidget {
  const _ReactionDemo();

  @override
  State<_ReactionDemo> createState() => _ReactionDemoState();
}

class _ReactionDemoState extends State<_ReactionDemo> {
  final _entries = <DReactionOverlayEntry>[];
  final _timers = <Timer>[];
  int _nextId = 0;

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _react() {
    final id = ++_nextId;
    setState(
      () => _entries.add(
        DReactionOverlayEntry(id: id, label: 'sam', artwork: const _Emoji()),
      ),
    );
    _timers.add(
      Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _entries.removeWhere((entry) => entry.id == id));
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 320,
        height: 200,
        child: DReactionOverlay(entries: List.of(_entries)),
      ),
      DButton(label: const Text('Send reaction'), onPressed: _react),
    ],
  );
}
