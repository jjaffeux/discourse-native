import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final radioGroupExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'Select one option from a group of choices.',
  notes:
      'Implementation awaiting rendered/native review. A 16px radio with an 8px dot, 1px border and 3px focus/invalid ring follows base-nova. '
      'Label rows use 12px gaps and 14px labels; pointer hit bounds are at least 40×32, touch bounds 48×48. '
      'Use DRadioGroup for local initialValue or DRadioGroup.controlled for parent-owned groupValue. '
      'Both integrate with Form validator/onSaved/reset. readOnly preserves focus and blocks selection; nullable item overrides inherit it. required announces the requirement while validator owns enforcement and error text. Tab enters once, arrows wrap and skip disabled items; Space selects. '
      'Label, description and card slots compose presentation without implementing the pending Field component. '
      'All samples use local state. The preview toolbar changes live theme, direction, scaling and motion.',
  examples: [
    StyleguideExample(
      title: 'Read-only and required',
      description:
          'Toggle the group policy live. Inherited stays read-only with the group, Editable always permits selection, and Locked always prevents it. Arrow keys still move focus. Parent updates and Form validation remain available.',
      states: const [
        'Read-only',
        'Required',
        'Item override',
        'Controlled',
        'Live props',
      ],
      code: """DRadioGroup<String>.controlled(
  groupValue: value,
  readOnly: readOnly,
  required: true,
  onChanged: (next) => setState(() => value = next),
  validator: (next) => next == null ? 'Choose an option.' : null,
  child: const Column(children: [
    DRadioGroupItem(value: 'a', label: Text('Inherited')),
    DRadioGroupItem(value: 'b', label: Text('Editable'), readOnly: false),
    DRadioGroupItem(value: 'c', label: Text('Locked'), readOnly: true),
  ]),
) // A parent may set value even when readOnly is true.""",
      builder: (_) => const _ReadOnlyPreview(),
    ),

    for (final mode in [
      'Default',
      'Description',
      'Choice Card',
      'Fieldset',
      'Disabled',
      'Invalid',
      'RTL',
    ])
      StyleguideExample(
        title: mode,
        description: switch (mode) {
          'Choice Card' => 'Click anywhere on a plan card to select it.',
          'Fieldset' =>
            'A labelled subscription group with descriptive context.',
          'Disabled' =>
            'The first choice is disabled; the other two remain selectable.',
          'Invalid' =>
            'Invalid radios display a ring and explanatory error text.',
          'RTL' => 'Arabic labels and descriptions follow logical direction.',
          _ =>
            'Choose Default, Comfortable or Compact using pointer or keyboard.',
        },
        states: [mode, 'Keyboard', 'Text scaling', 'Live theme'],
        code: _code(mode),
        builder: (_) => _Reference(mode: mode),
      ),
    StyleguideExample(
      title: 'Controlled form and dynamic options',
      description:
          'Validate an empty selection, choose a delivery method, save, then reset. The disabled option is skipped by arrow navigation.',
      states: const [
        'Controlled',
        'Form',
        'Reset',
        'Validation',
        'Disabled item',
      ],
      code: '''DRadioGroup<String>.controlled(
  groupValue: delivery,
  initialValue: null,
  onChanged: (value) => setState(() => delivery = value),
  validator: (value) => value == null ? 'Choose a delivery method.' : null,
  onSaved: (value) => setState(() => saved = value),
  child: const Column(children: [
    DRadioGroupItem(value: 'email', label: Text('Email')),
    DRadioGroupItem(value: 'sms', label: Text('SMS'), enabled: false),
    DRadioGroupItem(value: 'push', label: Text('Push notifications')),
  ]),
) // Place inside Form; use FormState.validate/save/reset.''',
      builder: (_) => const _FormPreview(),
    ),
  ],
);

String _code(String mode) {
  final sample = _Reference(mode: mode);
  final labels = sample.labels;
  final descriptions = sample.descriptions;
  final rows = <String>[];
  for (var i = 0; i < 3; i++) {
    if (i != 0) rows.add('    SizedBox(height: 8),');
    rows.add("    DRadioGroupItem<String>(value: '${sample.values[i]}',");
    if (mode == 'Disabled' && i == 0) rows.add('      enabled: false,');
    if (['Disabled', 'Invalid', 'Fieldset'].contains(mode)) {
      rows.add('      contentGap: 8, labelStyle: TextStyle(height: 1.375),');
    }
    rows.add("      label: Text('${labels[i].replaceAll(r'$', r'\$')}'),");
    if (sample.hasDescriptions) {
      rows.add("      description: Text('${descriptions[i]}'),");
    }
    if (mode == 'Choice Card') rows.add('      card: true,');
    rows.add('    ),');
  }
  return "${mode == 'Choice Card'
          ? 'ConstrainedBox(constraints: BoxConstraints(maxWidth: 384), child: '
          : ['Fieldset', 'Invalid'].contains(mode)
          ? 'ConstrainedBox(constraints: BoxConstraints(maxWidth: 320), child: '
          : 'IntrinsicWidth(child: '}${mode == 'RTL' ? 'Directionality(textDirection: TextDirection.rtl, child: ' : ''}DRadioGroup<String>(\n"
      "  initialValue: '${sample.initial}',\n"
      "  invalid: ${mode == 'Invalid'},\n"
      "${mode == 'Fieldset' ? "  label: Text('Subscription Plan'),\n  description: Text('Yearly and lifetime plans offer significant savings.'),\n" : ''}"
      "${mode == 'Invalid' ? "  label: Text('Notification Preferences'),\n  description: Text('Choose how you want to receive notifications.'),\n" : ''}"
      "  child: const Column(children: [\n${rows.join('\n')}\n  ]),\n)${mode == 'RTL' ? ')' : ''})";
}

class _Reference extends StatelessWidget {
  const _Reference({required this.mode});
  final String mode;
  List<String> get labels => (mode == 'Choice Card')
      ? ['Plus', 'Pro', 'Enterprise']
      : (mode == 'RTL')
      ? ['افتراضي', 'مريح', 'مضغوط']
      : (mode == 'Fieldset')
      ? [
          'Monthly (\$9.99/month)',
          'Yearly (\$99.99/year)',
          'Lifetime (\$299.99)',
        ]
      : (mode == 'Disabled')
      ? ['Disabled', 'Option 2', 'Option 3']
      : (mode == 'Invalid')
      ? ['Email only', 'SMS only', 'Both Email & SMS']
      : ['Default', 'Comfortable', 'Compact'];
  List<String> get descriptions => (mode == 'Choice Card')
      ? [
          'For individuals and small teams.',
          'For growing businesses.',
          'For large teams and enterprises.',
        ]
      : (mode == 'RTL')
      ? [
          'تباعد قياسي لمعظم حالات الاستخدام.',
          'مساحة أكبر بين العناصر.',
          'تباعد أدنى للتخطيطات الكثيفة.',
        ]
      : [
          'Standard spacing for most use cases.',
          'More space between elements.',
          'Minimal spacing for dense layouts.',
        ];
  List<String> get values => mode == 'Choice Card'
      ? ['plus', 'pro', 'enterprise']
      : ['default', 'comfortable', 'compact'];
  String get initial => mode == 'Choice Card'
      ? 'plus'
      : ['Default', 'Description', 'RTL', 'Disabled'].contains(mode)
      ? 'comfortable'
      : 'default';
  bool get hasDescriptions =>
      mode == 'Choice Card' || mode == 'RTL' || mode == 'Description';
  @override
  Widget build(BuildContext context) {
    final cards = mode == 'Choice Card';
    final rtl = mode == 'RTL';
    final fieldset = mode == 'Fieldset';
    final invalid = mode == 'Invalid';
    final example = Directionality(
      textDirection: rtl ? TextDirection.rtl : Directionality.of(context),
      child: DRadioGroup<String>(
        initialValue: initial,

        invalid: invalid,

        label: fieldset
            ? const Text('Subscription Plan', style: TextStyle(height: 20 / 14))
            : invalid
            ? const Text(
                'Notification Preferences',
                style: TextStyle(height: 20 / 14),
              )
            : null,
        description: fieldset
            ? const Text('Yearly and lifetime plans offer significant savings.')
            : invalid
            ? const Text('Choose how you want to receive notifications.')
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i != 0) const SizedBox(height: 8),
              DRadioGroupItem<String>(
                value: values[i],
                enabled: mode != 'Disabled' || i != 0,
                contentGap: ['Disabled', 'Invalid', 'Fieldset'].contains(mode)
                    ? 8
                    : null,
                labelStyle: ['Disabled', 'Invalid', 'Fieldset'].contains(mode)
                    ? const TextStyle(height: 1.375)
                    : null,
                label: Text(labels[i]),
                description: cards || rtl || mode == 'Description'
                    ? Text(descriptions[i])
                    : null,
                card: cards,
              ),
            ],
          ],
        ),
      ),
    );
    return Align(
      child: cards || fieldset || invalid
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cards ? 384 : 320),
              child: example,
            )
          : IntrinsicWidth(child: example),
    );
  }
}

class _FormPreview extends StatefulWidget {
  const _FormPreview();
  @override
  State<_FormPreview> createState() => _FormPreviewState();
}

class _FormPreviewState extends State<_FormPreview> {
  final _form = GlobalKey<FormState>();
  String? _value;
  String? _saved;
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DRadioGroup<String>.controlled(
          groupValue: _value,
          onChanged: (value) => setState(() => _value = value),
          validator: (value) =>
              value == null ? 'Choose a delivery method.' : null,
          onSaved: (value) => setState(() => _saved = value),
          child: const Column(
            children: [
              DRadioGroupItem(value: 'email', label: Text('Email')),
              DRadioGroupItem(value: 'sms', label: Text('SMS'), enabled: false),
              DRadioGroupItem(value: 'push', label: Text('Push notifications')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('Save'),
              onPressed: () {
                if (_form.currentState!.validate()) _form.currentState!.save();
              },
            ),
            DButton(
              label: const Text('Reset'),
              onPressed: () => _form.currentState!.reset(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Saved: ${_saved ?? 'none'}'),
      ],
    ),
  );
}

class _ReadOnlyPreview extends StatefulWidget {
  const _ReadOnlyPreview();
  @override
  State<_ReadOnlyPreview> createState() => _ReadOnlyPreviewState();
}

class _ReadOnlyPreviewState extends State<_ReadOnlyPreview> {
  final _form = GlobalKey<FormState>();
  bool _readOnly = true;
  String? _value = 'a';
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DRadioGroup<String>.controlled(
          groupValue: _value,
          readOnly: _readOnly,
          required: true,
          onChanged: (next) => setState(() => _value = next),
          validator: (next) => next == null ? 'Choose an option.' : null,
          child: const Column(
            children: [
              DRadioGroupItem(value: 'a', label: Text('Inherited')),
              DRadioGroupItem(
                value: 'b',
                label: Text('Editable'),
                readOnly: false,
              ),
              DRadioGroupItem(
                value: 'c',
                label: Text('Locked'),
                readOnly: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Group read-only: $_readOnly; value: ${_value ?? 'none'}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('Toggle read-only'),
              onPressed: () => setState(() => _readOnly = !_readOnly),
            ),
            DButton(
              label: const Text('Clear from parent'),
              onPressed: () => setState(() => _value = null),
            ),
            DButton(
              label: const Text('Validate'),
              onPressed: () => _form.currentState!.validate(),
            ),
          ],
        ),
      ],
    ),
  );
}
