import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final colorPickerExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Live opaque color selection with a pointer plane and keyboard-accessible HSV sliders.',
  examples: [
    StyleguideExample(
      title: 'Live color',
      description:
          'Drag the plane or adjust the HSV sliders. Escape closes the picker.',
      code:
          'DColorPicker(value: color, semanticLabel: "Choose color", onChanged: updateColor)',
      builder: (_) => const _Example(),
    ),
    StyleguideExample(
      title: 'Disabled',
      description: 'A disabled swatch does not open.',
      code:
          'DColorPicker(value: Colors.blue, semanticLabel: "Choose color", onChanged: null)',
      builder: (_) => const DColorPicker(
        value: Colors.blue,
        semanticLabel: 'Choose color',
        onChanged: null,
      ),
    ),
  ],
);

class _Example extends StatefulWidget {
  const _Example();
  @override
  State<_Example> createState() => _ExampleState();
}

class _ExampleState extends State<_Example> {
  Color color = const Color(0xff39845b);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DColorPicker(
        value: color,
        semanticLabel: 'Choose color',
        onChanged: (value) => setState(() => color = value),
      ),
      Text(
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      ),
    ],
  );
}
