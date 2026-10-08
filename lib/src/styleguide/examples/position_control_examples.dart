import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final positionControlExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A position selector that unfolds leftward at the trigger.',
  examples: [
    StyleguideExample(
      title: 'Unfolding position selector',
      description:
          'The thumb moves to a chosen position, then folds. Outside press and Escape dismiss; reduced motion removes transitions.',
      states: const ['Selection', 'Keyboard', 'Reduced motion'],
      code:
          'DPositionControl(value: value, label: "Position", icon: icon, items: items, onChanged: select)',
      builder: (_) => const _Example(),
    ),
  ],
);

class _Example extends StatefulWidget {
  const _Example();
  @override
  State<_Example> createState() => _ExampleState();
}

class _ExampleState extends State<_Example> {
  int _value = 0;
  @override
  Widget build(BuildContext context) => DPositionControl<int>(
    value: _value,
    label: 'Position',
    icon: const DIcon(DIcons.expand),
    onChanged: (value) => setState(() => _value = value),
    items: [
      for (final (value, label, icon) in [
        (0, 'Left', DIcons.arrowLeft),
        (1, 'Bottom', DIcons.minus),
        (2, 'Full screen', DIcons.expand),
      ])
        DToggleGroupItem.iconOnly(
          value: value,
          semanticLabel: label,
          tooltip: label,
          icon: DIcon(icon),
        ),
    ],
  );
}
