import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final imagePreviewExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Image previews with a fading metadata bar and hover shadow.',
  notes:
      'Approved application component based on Discourse lightbox.scss. '
      'Hover fades metadata to 90% opacity in 500ms; leaving takes 200ms. '
      'Keyboard focus also reveals metadata. Touch shows a compact expand hint. '
      'Reduced motion removes transitions. Narrow previews truncate filenames '
      'and omit details before falling back to the expand icon. The caller '
      'owns image loading, sizing, and gallery navigation.',
  examples: [
    for (final compact in [false, true])
      StyleguideExample(
        title: compact ? 'Chat image' : 'Post image',
        description:
            'Hover or Tab to the image, then click or press Enter to open it. '
            'Try the theme, direction, text size, and reduced-motion controls.',
        states: const ['Hover', 'Keyboard', 'Touch', 'RTL', 'Reduced motion'],
        code: '''DImagePreview(
  semanticLabel: 'Open image: community.png',
  filename: 'community.png',
  details: '1024×512 128 KB',
  onPressed: openImage,
  child: image,
)''',
        builder: (_) => _PreviewExample(width: compact ? 240 : 480),
      ),
    StyleguideExample(
      title: 'Narrow and disabled',
      description:
          'Tiny previews keep their image dimensions and avoid overflow.',
      states: const ['Narrow', 'Disabled', 'Long filename'],
      code: '''DImagePreview(
  semanticLabel: 'Unavailable image',
  onPressed: null,
  child: image,
)''',
      builder: (_) => const Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _PreviewExample(width: 90),
          _PreviewExample(width: 240, enabled: false),
        ],
      ),
    ),
  ],
);

class _PreviewExample extends StatelessWidget {
  const _PreviewExample({required this.width, this.enabled = true});
  final double width;
  final bool enabled;

  Widget _image() => Image.asset(
    'packages/discourse_native/src/styleguide/assets/discourse.png',
    fit: BoxFit.cover,
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DAspectRatio(
      ratio: 2,
      child: DImagePreview(
        semanticLabel: 'Open image: community-gathering.png',
        filename: 'community-gathering.png',
        details: '1024×512 128 KB',
        onPressed: enabled
            ? () => showDDialog<void>(
                context: context,
                builder: (_, controller) => DDialogContent(
                  children: [
                    const DDialogHeader(
                      children: [
                        DDialogTitle(child: Text('community-gathering.png')),
                      ],
                    ),
                    DAspectRatio(ratio: 2, child: _image()),
                  ],
                ),
              )
            : null,
        child: _image(),
      ),
    ),
  );
}
