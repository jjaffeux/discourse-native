import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final imageThumbnailExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A square image that picks what a gallery shows.',
  notes:
      'Drawn 52 by 52 with 6px corners. An unselected thumbnail recedes to '
      '45% opacity in 150ms; the selected one gains a 2px outline 2px outside '
      'its bounds. Reduced motion removes the transition. The caller owns '
      'decoding the image small and the selection.',
  examples: [
    StyleguideExample(
      title: 'Gallery strip',
      description:
          'Press a thumbnail or Tab to one and press Enter to select it.',
      states: const ['Selected', 'Keyboard', 'Reduced motion'],
      code: '''DImageThumbnail(
  semanticLabel: 'Go to image 2 of 3',
  selected: index == 1,
  onPressed: () => select(1),
  child: image,
)''',
      builder: (_) => const _StripExample(),
    ),
  ],
);

class _StripExample extends StatefulWidget {
  const _StripExample();

  @override
  State<_StripExample> createState() => _StripExampleState();
}

class _StripExampleState extends State<_StripExample> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(DImageThumbnail.outlineExtent),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        for (var index = 0; index < 3; index++)
          DImageThumbnail(
            semanticLabel: 'Go to image ${index + 1} of 3',
            selected: index == _selected,
            onPressed: () => setState(() => _selected = index),
            child: Image.asset(
              'packages/discourse_native/src/styleguide/assets/discourse.png',
              fit: BoxFit.cover,
            ),
          ),
      ],
    ),
  );
}
