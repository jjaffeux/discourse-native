import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final controlWrapExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Consistent visible gaps between Native controls and rows.',
  notes:
      'DControlWrap measures button and badge artwork, including nested groups. '
      'It preserves their larger touch targets and spaces the painted edges. '
      'Overlapping targets prioritize a painted control, then the closest edge. '
      'Keyboard order and semantics stay with the original controls. '
      'Use wrap: false for a nested tag row. Unmarked children use their layout bounds.',
  examples: [
    StyleguideExample(
      title: 'Compact controls',
      description:
          'Resize the window or change text scale and direction to inspect the gaps.',
      states: const ['Wrap', 'Touch', 'RTL', 'Large text', 'Keyboard'],
      code: '''DControlWrap(children: [
  DBadge.action(size: DBadgeSize.control, child: Text('# design'), onPressed: openTag),
  DBadge.action(size: DBadgeSize.control, child: Text('+1'), onPressed: openTags),
  DButtonGroup(children: [bookmarkButton, notificationButton]),
])''',
      builder: (_) => const _ControlWrapExample(),
    ),
  ],
);

class _ControlWrapExample extends StatefulWidget {
  const _ControlWrapExample();

  @override
  State<_ControlWrapExample> createState() => _ControlWrapExampleState();
}

class _ControlWrapExampleState extends State<_ControlWrapExample> {
  String _selected = 'Choose a control';

  void _choose(String value) => setState(() => _selected = value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: DSpacing.lg,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 290),
        child: DControlWrap(
          children: [
            DButton(
              label: const Text('Design'),
              variant: DButtonVariant.outline,
              size: DButtonSize.filter,
              onPressed: () => _choose('Design'),
            ),
            DControlWrap(
              wrap: false,
              children: [
                for (final label in ['# design', '+1'])
                  DBadge.action(
                    size: DBadgeSize.control,
                    child: Text(label),
                    onPressed: () => _choose(label),
                  ),
              ],
            ),
            DButtonGroup(
              children: [
                DButton.iconOnly(
                  icon: const DIcon(DIcons.bookmark),
                  tooltip: 'Bookmark',
                  variant: DButtonVariant.outline,
                  size: DButtonSize.filter,
                  onPressed: () => _choose('Bookmark'),
                ),
                DButton.iconOnly(
                  icon: const DIcon(DIcons.bell),
                  tooltip: 'Notifications',
                  variant: DButtonVariant.outline,
                  size: DButtonSize.filter,
                  onPressed: () => _choose('Notifications'),
                ),
              ],
            ),
          ],
        ),
      ),
      Text(_selected),
    ],
  );
}
