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
      'Use wrap: false for a nested tag row. Axis.vertical stacks painted rows; '
      'DControlExpanded reserves the remaining space in a non-wrapping row. '
      'Inside padded toolbars, reserveTouchTargets: false aligns the artwork '
      'to the padding while retaining targets. Unmarked children use layout bounds.',
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
    StyleguideExample(
      title: 'Aligned toolbar rows',
      description:
          'Shared edge alignment and visible row gaps with full touch targets.',
      states: const ['Rows', 'Expanded', 'Touch', 'RTL', 'Large text'],
      code: '''DControlWrap(direction: Axis.vertical, wrap: false,
  reserveTouchTargets: false, spacing: 10, children: [
    DControlWrap(wrap: false, reserveTouchTargets: false, children: [
      previousButton,
      DControlExpanded(child: Text('September 2026', textAlign: TextAlign.center)),
      nextButton,
    ]),
    nextRow,
])''',
      builder: (_) => const _AlignedRowsExample(),
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

class _AlignedRowsExample extends StatefulWidget {
  const _AlignedRowsExample();

  @override
  State<_AlignedRowsExample> createState() => _AlignedRowsExampleState();
}

class _AlignedRowsExampleState extends State<_AlignedRowsExample> {
  int _month = 9;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: DControlWrap(
      direction: Axis.vertical,
      wrap: false,
      reserveTouchTargets: false,
      spacing: 10,
      children: [
        DControlWrap(
          wrap: false,
          reserveTouchTargets: false,
          children: [
            DButton.iconOnly(
              size: DControlSize.chip,
              variant: DButtonVariant.outline,
              icon: const DIcon(DIcons.chevronLeft),
              tooltip: 'Previous month',
              onPressed: () => setState(() => _month--),
            ),
            DControlExpanded(
              child: Text('Month $_month', textAlign: TextAlign.center),
            ),
            DButton.iconOnly(
              size: DControlSize.chip,
              variant: DButtonVariant.outline,
              icon: const DIcon(DIcons.chevronRight),
              tooltip: 'Next month',
              onPressed: () => setState(() => _month++),
            ),
          ],
        ),
        DControlWrap(
          wrap: false,
          reserveTouchTargets: false,
          alignment: WrapAlignment.end,
          children: [
            DButton(
              size: DControlSize.chip,
              variant: DButtonVariant.outline,
              label: const Text('Today'),
              onPressed: () => setState(() => _month = 9),
            ),
          ],
        ),
      ],
    ),
  );
}
