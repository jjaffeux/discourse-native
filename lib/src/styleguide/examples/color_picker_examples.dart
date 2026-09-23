import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final colorPickerExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Live opaque color selection with a pointer plane and keyboard-accessible HSV sliders.',
  examples: [
    StyleguideExample(
      title: 'Presets and recent colors',
      description:
          'Choose a named text or background swatch. Recent choices and the selected color are controlled by the caller; Default clears the color.',
      code:
          'DColorPickerPresets(semanticLabel: "Text color", presets: colors, selected: selected, recentColors: recent, onChanged: pick, onReset: reset)',
      builder: (_) => const _PresetExample(),
    ),
    StyleguideExample(
      title: 'Inline palette',
      description:
          'Drag to choose hue and lightness. Focus the palette and use arrow keys; screen readers offer Lighter and Darker actions.',
      code:
          'DColorPicker.inline(value: color, semanticLabel: "Background color", onChanged: updateColor)',
      builder: (_) => const _Example(inline: true),
    ),
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
  const _Example({this.inline = false});
  final bool inline;
  @override
  State<_Example> createState() => _ExampleState();
}

class _PresetExample extends StatefulWidget {
  const _PresetExample();
  @override
  State<_PresetExample> createState() => _PresetExampleState();
}

class _PresetExampleState extends State<_PresetExample> {
  static const colors = [
    DColorPreset(color: Color(0xffd75c55), label: 'Red'),
    DColorPreset(color: Color(0xff58a47a), label: 'Green'),
    DColorPreset(color: Color(0xff4d94d5), label: 'Blue'),
    DColorPreset(
      color: Color(0xff244c39),
      label: 'Green background',
      appearance: DColorPresetAppearance.background,
    ),
  ];
  DColorPreset? selected;
  final recent = <DColorPreset>[];

  @override
  Widget build(BuildContext context) => DColorPickerPresets(
    semanticLabel: 'Text color',
    presets: colors,
    selected: selected,
    recentColors: recent,
    onReset: () => setState(() => selected = null),
    onChanged: (color) => setState(() {
      selected = color;
      recent.remove(color);
      recent.insert(0, color);
      if (recent.length > 3) recent.removeLast();
    }),
  );
}

class _ExampleState extends State<_Example> {
  Color color = const Color(0xff39845b);
  @override
  Widget build(BuildContext context) => widget.inline
      ? DColorPicker.inline(
          value: color,
          semanticLabel: "Background color",
          onChanged: (value) => setState(() => color = value),
        )
      : Row(
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
