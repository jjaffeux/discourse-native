import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';
import 'toggle_reference_icons.dart';

final toggleGroupExamples = ComponentExamples(
  description:
      'A shared single- or multiple-selection state for two-state buttons.',
  status: ComponentStatus.implemented,
  notes:
      'Accepted after independent rendered and native review. The frozen 2026-05-17 behavior uses 8px default spacing; spacing 0 joins edges, collapses inner outline borders and uses 8px horizontal padding. DToggle remains the visual and activation owner. Values may be parent-controlled, borrowed from a DToggleGroupController, or internally owned. Arrow keys follow orientation and RTL, Home/End move to edges, disabled items are skipped, and loopFocus controls wrapping. The documented 64px font-weight tiles compose the accepted DField label and description around the group without transferring control ownership.',
  examples: [
    StyleguideExample(
      title: 'Default and composition',
      description:
          'The lead multiple-selection outline group uses the documented ToggleGroup → ToggleGroupItem composition.',
      states: const ['Multiple', 'Outline', 'Icons', 'Default spacing 8px'],
      code: '''DToggleGroup<String>(
  multiple: true,
  variant: DToggleVariant.outline,
  items: const [
    DToggleGroupItem.iconOnly(value: 'bold', semanticLabel: 'Toggle bold', icon: ToggleReferenceIcon(ToggleReferenceIcon.bold)),
    DToggleGroupItem.iconOnly(value: 'italic', semanticLabel: 'Toggle italic', icon: ToggleReferenceIcon(ToggleReferenceIcon.italic)),
    DToggleGroupItem.iconOnly(value: 'strikethrough', semanticLabel: 'Toggle strikethrough', icon: ToggleReferenceIcon(ToggleReferenceIcon.underline)),
  ],
)''',
      builder: (_) => const _FormattingGroup(),
    ),
    StyleguideExample(
      title: 'Outline',
      description:
          'A single-select text group starts with All selected and permits deselection like Base UI.',
      states: const ['Single', 'Outline', 'Text', 'Deselectable'],
      code:
          "DToggleGroup<String>(initialValues: const ['all'], variant: DToggleVariant.outline, items: const [DToggleGroupItem(value: 'all', child: Text('All')), DToggleGroupItem(value: 'missed', child: Text('Missed'))])",
      builder: (_) => const _SimpleGroup(
        labels: ['All', 'Missed'],
        initial: ['All'],
        outline: true,
      ),
    ),
    StyleguideExample(
      title: 'Size',
      description:
          'Small and default groups retain the accepted 28px and 32px Toggle artwork.',
      states: const ['Small 28px', 'Default 32px', 'Outline'],
      code:
          "DToggleGroup<String>(size: DToggleSize.small, initialValues: const ['Top'], variant: DToggleVariant.outline, items: items)",
      builder: (_) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SimpleGroup(
            labels: ['Top', 'Bottom', 'Left', 'Right'],
            initial: ['Top'],
            outline: true,
            size: DToggleSize.small,
          ),
          SizedBox(height: 16),
          _SimpleGroup(
            labels: ['Top', 'Bottom', 'Left', 'Right'],
            initial: ['Top'],
            outline: true,
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Spacing',
      description:
          'Compare the frozen 8px default with connected spacing 0 and a 4px vertical group.',
      states: const ['Default 8px', 'Connected 0px', 'Vertical 4px'],
      code:
          "DToggleGroup<String>(spacing: 0, variant: DToggleVariant.outline, initialValues: const ['Top'], items: items)",
      builder: (_) => const Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          _SimpleGroup(
            labels: ['Top', 'Bottom', 'Left', 'Right'],
            initial: ['Top'],
            outline: true,
            size: DToggleSize.small,
          ),
          _SimpleGroup(
            labels: ['Top', 'Bottom', 'Left', 'Right'],
            initial: ['Top'],
            outline: true,
            size: DToggleSize.small,
            spacing: 0,
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Vertical',
      description:
          'Multiple formatting choices stack vertically with 4px spacing and vertical arrow focus.',
      states: const ['Vertical', 'Multiple', '4px gap', 'Arrow keys'],
      code:
          "DToggleGroup<String>(multiple: true, orientation: Axis.vertical, spacing: 1, initialValues: const ['bold', 'italic'], items: formattingItems)",
      builder: (_) => const _FormattingGroup(vertical: true),
    ),
    StyleguideExample(
      title: 'Disabled',
      description:
          'A disabled group preserves selection semantics but blocks pointer, keyboard and semantic activation.',
      states: const ['Disabled group', 'Pressed state retained'],
      code:
          "DToggleGroup<String>(enabled: false, initialValues: const ['bold'], items: formattingItems)",
      builder: (_) => const _FormattingGroup(enabled: false),
    ),
    StyleguideExample(
      title: 'Custom font weight',
      description:
          'The documented controlled 64px tile composition previews and describes the selected font weight.',
      states: const [
        'Controlled',
        '64px tiles',
        'Custom radius',
        'Field composition',
      ],
      code: '''DField(
  children: [
    const DFieldLabel(child: Text('Font Weight')),
    DToggleGroup<String>(
      values: [fontWeight],
      onChanged: (values) => setState(() => fontWeight = values.single),
      allowEmptySelection: false,
      variant: DToggleVariant.outline,
      spacing: 2,
      size: DToggleSize.large,
      items: weights.map((weight) => DToggleGroupItem(
        value: weight,
        semanticLabel: weight,
        visualStyle: const DToggleVisualStyle(
        ),
        child: WeightTile(weight),
      )).toList(),
    ),
    DFieldDescription(child: WeightDescription(fontWeight)),
  ],
)''',
      builder: (_) => const _FontWeightGroup(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic text follows reading order; Left/Right arrows move visually in RTL.',
      states: const ['RTL', 'Arabic', 'Single', 'Outline'],
      code:
          "Directionality(textDirection: TextDirection.rtl, child: DToggleGroup<String>(variant: DToggleVariant.outline, initialValues: const ['قائمة'], items: arabicItems))",
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _SimpleGroup(
          labels: ['قائمة', 'شبكة', 'بطاقات'],
          initial: ['قائمة'],
          outline: true,
        ),
      ),
    ),
    StyleguideExample(
      title: 'Ownership and dynamic items',
      description:
          'Exercise a borrowed controller, required selection, disabled-item focus skipping, looping and item removal.',
      states: const [
        'Borrowed controller',
        'Required choice',
        'Dynamic items',
        'Disabled item',
        'Home/End',
      ],
      code:
          "DToggleGroup<String>(controller: controller, allowEmptySelection: false, items: dynamicItems, onChanged: observe)",
      builder: (_) => const _DynamicGroup(),
    ),
  ],
);

List<DToggleGroupItem<String>> _formattingItems() => const [
  DToggleGroupItem.iconOnly(
    value: 'bold',
    semanticLabel: 'Toggle bold',
    icon: ToggleReferenceIcon(ToggleReferenceIcon.bold),
  ),
  DToggleGroupItem.iconOnly(
    value: 'italic',
    semanticLabel: 'Toggle italic',
    icon: ToggleReferenceIcon(ToggleReferenceIcon.italic),
  ),
  DToggleGroupItem.iconOnly(
    value: 'strikethrough',
    semanticLabel: 'Toggle strikethrough',
    icon: ToggleReferenceIcon(ToggleReferenceIcon.underline),
  ),
];

class _FormattingGroup extends StatelessWidget {
  const _FormattingGroup({this.vertical = false, this.enabled = true});
  final bool vertical;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DToggleGroup<String>(
    multiple: true,
    initialValues: vertical ? const ['bold', 'italic'] : const [],
    orientation: vertical ? Axis.vertical : Axis.horizontal,
    spacing: vertical ? 1 : 8,
    enabled: enabled,
    variant: vertical ? DToggleVariant.standard : DToggleVariant.outline,
    semanticLabel: 'Text formatting',
    items: _formattingItems(),
  );
}

class _SimpleGroup extends StatelessWidget {
  const _SimpleGroup({
    required this.labels,
    required this.initial,
    this.outline = false,
    this.size = DToggleSize.regular,
    this.spacing = 2,
  });

  final List<String> labels;
  final List<String> initial;
  final bool outline;
  final DToggleSize size;
  final double spacing;

  @override
  Widget build(BuildContext context) => DToggleGroup<String>(
    initialValues: initial,
    variant: outline ? DToggleVariant.outline : DToggleVariant.standard,
    size: size,
    spacing: spacing,
    semanticLabel: 'View options',
    items: [
      for (final label in labels)
        DToggleGroupItem(
          value: label,
          semanticLabel: 'Toggle $label',
          child: Text(label),
        ),
    ],
  );
}

class _FontWeightGroup extends StatefulWidget {
  const _FontWeightGroup();

  @override
  State<_FontWeightGroup> createState() => _FontWeightGroupState();
}

class _FontWeightGroupState extends State<_FontWeightGroup> {
  String _weight = 'normal';
  static const _weights = ['light', 'normal', 'medium', 'bold'];

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DField(
      children: [
        const DFieldLabel(child: Text('Font Weight')),
        DToggleGroup<String>(
          values: [_weight],
          onChanged: (values) {
            if (values.isNotEmpty) setState(() => _weight = values.single);
          },
          allowEmptySelection: false,
          variant: DToggleVariant.outline,
          size: DToggleSize.large,
          semanticLabel: 'Font weight',
          items: [
            for (final weight in _weights)
              DToggleGroupItem(
                value: weight,
                semanticLabel: weight,
                visualStyle: DToggleVisualStyle(
                  borderRadius: BorderRadius.circular(tokens.radius * 1.4),
                ),
                child: _WeightTile(weight),
              ),
          ],
        ),
        DFieldDescription(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Use '),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.muted,
                  borderRadius: BorderRadius.circular(tokens.radius * .8),
                ),
                child: Text(
                  'font-$_weight',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const Text(' to set the font weight.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeightTile extends StatelessWidget {
  const _WeightTile(this.weight);
  final String weight;

  FontWeight get _fontWeight => switch (weight) {
    'light' => FontWeight.w300,
    'normal' => FontWeight.w400,
    'medium' => FontWeight.w500,
    _ => FontWeight.w700,
  };

  @override
  Widget build(BuildContext context) => Text(
    '${weight[0].toUpperCase()}${weight.substring(1)}',
    style: TextStyle(fontWeight: _fontWeight),
  );
}

class _DynamicGroup extends StatefulWidget {
  const _DynamicGroup();

  @override
  State<_DynamicGroup> createState() => _DynamicGroupState();
}

class _DynamicGroupState extends State<_DynamicGroup> {
  late final DToggleGroupController<String> _controller =
      DToggleGroupController(values: const ['list']);
  bool _showCards = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DToggleGroup<String>(
        controller: _controller,
        onChanged: (_) => setState(() {}),
        allowEmptySelection: false,
        loopFocus: true,
        variant: DToggleVariant.outline,
        semanticLabel: 'Layout',
        items: [
          const DToggleGroupItem(value: 'list', child: Text('List')),
          const DToggleGroupItem(
            value: 'grid',
            enabled: false,
            child: Text('Grid'),
          ),
          if (_showCards)
            const DToggleGroupItem(value: 'cards', child: Text('Cards')),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            size: DButtonSize.small,
            variant: DButtonVariant.secondary,
            onPressed: () => _controller.setValues(const ['cards']),
            label: const Text('Select externally'),
          ),
          DButton(
            size: DButtonSize.small,
            variant: DButtonVariant.secondary,
            onPressed: () => setState(() => _showCards = !_showCards),
            label: Text(_showCards ? 'Remove Cards' : 'Restore Cards'),
          ),
        ],
      ),
    ],
  );
}
