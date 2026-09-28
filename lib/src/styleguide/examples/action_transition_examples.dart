import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final actionTransitionExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Quick, gentle entrances and exits for contextual actions.',
  notes:
      'Actions rise, fade and scale from 72% to full size over 240ms, and leave '
      'in 160ms. Use a stable key for each action and null for an empty slot. '
      'Outgoing actions immediately leave hit testing, focus and semantics. '
      'A fixed slot keeps neighboring controls still. Reduced motion switches '
      'immediately, including when enabled during a transition.',
  examples: [
    for (final reducedMotion in [false, true])
      StyleguideExample(
        title: reducedMotion ? 'Reduced motion' : 'Contextual action',
        description:
            'Show, replace and hide the trailing action. Try changing it again '
            'before the animation finishes.',
        code: 'SizedBox(width: 64, child: DActionTransition(child: action))',
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                reducedMotion || MediaQuery.disableAnimationsOf(context),
          ),
          child: const _ActionExample(),
        ),
      ),
  ],
);

class _ActionExample extends StatefulWidget {
  const _ActionExample();

  @override
  State<_ActionExample> createState() => _ActionExampleState();
}

class _ActionExampleState extends State<_ActionExample> {
  String? _action = 'New topic';
  String _feedback = 'Choose an action';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: DSpacing.md,
    children: [
      Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.controlGap,
        children: [
          for (final action in ['New topic', 'Reply', null])
            DButton(
              label: Text(action == null ? 'Hide action' : 'Show $action'),
              onPressed: () => setState(() => _action = action),
            ),
        ],
      ),
      SizedBox(
        width: 220,
        child: Row(
          spacing: DSpacing.controlGap,
          children: [
            Expanded(
              child: DMobileDockItem(
                icon: const DIcon(DIcons.house),
                label: 'Start',
                onPressed: () => setState(() => _action = null),
              ),
            ),
            Expanded(
              child: DMobileDockItem(
                icon: const DIcon(DIcons.layerGroup),
                label: 'Topics',
                selected: true,
                onPressed: () => setState(() => _action = 'New topic'),
              ),
            ),
            SizedBox(
              width: 64,
              child: DActionTransition(
                child: _action == null
                    ? null
                    : DButton.iconOnly(
                        key: ValueKey(_action),
                        tooltip: _action!,
                        icon: DIcon(
                          _action == 'Reply' ? DIcons.reply : DIcons.plus,
                        ),
                        shape: DButtonShape.pill,
                        density: DButtonDensity.mobileDockAction,
                        onPressed: () => setState(() => _feedback = _action!),
                      ),
              ),
            ),
          ],
        ),
      ),
      Text(_feedback),
    ],
  );
}
