import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';
import 'radio_group_example_sources.dart';

final radioGroupExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Select one option from a group of choices.',
  notes:
      'A 16px radio with an 8px dot, 1px border and 3px focus/invalid ring follows base-nova. '
      'Label rows use 12px gaps and 14px labels; desktop rows follow intrinsic content height; touch bounds are at least 48×48. '
      'Use DRadioGroup for local initialValue or DRadioGroup.controlled for parent-owned groupValue. '
      'Both integrate with Form validator/onSaved/reset. readOnly preserves focus and blocks selection; nullable item overrides inherit it. required announces the requirement while validator owns enforcement and error text. Tab enters once, arrows wrap and skip disabled items; Space selects and Enter is inert, as on the reference span. The pointer cursor stays the default arrow; only a disabled item shows the forbidden cursor. The root is a grid with 8px gaps, supplied here by the caller\'s Column spacing or the Field composition. '
      'The frozen Default example composes DLabel; Description, Choice Card, Fieldset, Disabled, Invalid and RTL compose the accepted DField family while each DRadioGroupItem remains the sole radio, focus and selection owner. '
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
      code: _code('Read-only and required'),
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
          'Invalid' => 'Invalid radios display error-colored labels and rings.',
          'RTL' =>
            'Choose English, Arabic or Hebrew: labels, descriptions and the indicator side follow that language\'s direction while the selector stays LTR. The selection survives the switch.',
          _ =>
            'Choose Default, Comfortable or Compact using pointer or keyboard.',
        },
        states: [
          mode,
          if (mode == 'RTL') ...['Arabic default', 'Hebrew', 'English'],
          'Keyboard',
          'Text scaling',
          'Live theme',
        ],
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
      code: _code('Controlled form and dynamic options'),
      builder: (_) => const _FormPreview(),
    ),
  ],
);

String _code(String mode) {
  final (source, example) = switch (mode) {
    'Read-only and required' => ('readOnly', 'const _ReadOnlyPreview()'),
    'Controlled form and dynamic options' => ('form', 'const _FormPreview()'),
    _ => ('reference', "_Reference(mode: '$mode')"),
  };
  return "import 'package:discourse_native/discourse_ui.dart';\n"
      "import 'package:flutter/material.dart';\n\n"
      'void main() => runApp(MaterialApp(home: Scaffold(body: SingleChildScrollView('
      'padding: const EdgeInsets.all(24), child: $example))));\n\n'
      '${radioGroupExampleSources[source]}';
}

class _Reference extends StatefulWidget {
  const _Reference({required this.mode});
  final String mode;

  @override
  State<_Reference> createState() => _ReferenceState();
}

class _ReferenceState extends State<_Reference> {
  final _focusNodes = <String, FocusNode>{};

  // The reference RTL example reads useTranslation(translations, 'ar'): one
  // record per language with its direction and strings.
  static const _translations =
      <String, ({TextDirection dir, List<String> labels, List<String> notes})>{
        'en': (
          dir: TextDirection.ltr,
          labels: ['Default', 'Comfortable', 'Compact'],
          notes: [
            'Standard spacing for most use cases.',
            'More space between elements.',
            'Minimal spacing for dense layouts.',
          ],
        ),
        'ar': (
          dir: TextDirection.rtl,
          labels: ['افتراضي', 'مريح', 'مضغوط'],
          notes: [
            'تباعد قياسي لمعظم حالات الاستخدام.',
            'مساحة أكبر بين العناصر.',
            'تباعد أدنى للتخطيطات الكثيفة.',
          ],
        ),
        'he': (
          dir: TextDirection.rtl,
          labels: ['ברירת מחדל', 'נוח', 'קומפקטי'],
          notes: [
            'ריווח סטנדרטי לרוב מקרי השימוש.',
            'יותר מקום בין האלמנטים.',
            'ריווח מינימלי לפריסות צפופות.',
          ],
        ),
      };
  String _language = 'ar';

  String get mode => widget.mode;
  List<String> get labels => (mode == 'Choice Card')
      ? ['Plus', 'Pro', 'Enterprise']
      : (mode == 'RTL')
      ? _translations[_language]!.labels
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
      ? _translations[_language]!.notes
      : [
          'Standard spacing for most use cases.',
          'More space between elements.',
          'Minimal spacing for dense layouts.',
        ];
  List<String> get values => switch (mode) {
    'Choice Card' => ['plus', 'pro', 'enterprise'],
    'Fieldset' => ['monthly', 'yearly', 'lifetime'],
    'Disabled' => ['option1', 'option2', 'option3'],
    'Invalid' => ['email', 'sms', 'both'],
    _ => ['default', 'comfortable', 'compact'],
  };
  String get initial => switch (mode) {
    'Default' || 'Description' || 'RTL' => 'comfortable',
    'Disabled' => 'option2',
    _ => values.first,
  };
  late String _value = initial;

  @override
  void didUpdateWidget(covariant _Reference oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _value = initial;
  }

  FocusNode _focus(String value) =>
      _focusNodes.putIfAbsent(value, FocusNode.new);

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(String value, {bool enabled = true}) {
    // Labels activate the native radio; they do not become another value owner.
    if (enabled) {
      Actions.maybeInvoke(_focus(value).context!, const ActivateIntent());
    }
  }

  Widget _item({
    required int index,
    bool description = false,
    bool invalid = false,
    bool enabled = true,
  }) {
    final value = values[index];
    final label = labels[index];
    final help = description ? descriptions[index] : null;
    return DField(
      orientation: DFieldOrientation.horizontal,
      invalid: invalid,
      enabled: enabled,
      children: [
        DFieldControl(
          label: label,
          description: help,
          expand: false,
          alignIndicatorToContent: description,
          child: DRadioGroupItem<String>(
            value: value,
            semanticLabel: '',
            enabled: enabled,
            focusNode: _focus(value),
          ),
        ),
        if (description)
          DFieldContent(
            children: [
              DFieldLabel(
                excludeSemantics: true,
                focusNode: _focus(value),
                onPressed: () => _select(value, enabled: enabled),
                child: Text(label),
              ),
              DFieldDescription(child: Text(help!)),
            ],
          )
        else
          DFieldLabel(
            excludeSemantics: true,
            enabled: enabled,
            focusNode: _focus(value),
            onPressed: enabled ? () => _select(value) : null,
            style: const TextStyle(fontWeight: FontWeight.w400),
            child: Text(label),
          ),
      ],
    );
  }

  Widget _items({
    bool description = false,
    bool invalid = false,
    bool firstDisabled = false,
  }) => _spaced([
    for (var i = 0; i < 3; i++)
      _item(
        index: i,
        description: description,
        invalid: invalid,
        enabled: !firstDisabled || i != 0,
      ),
  ]);

  Widget _spaced(List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        children[i],
      ],
    ],
  );

  Widget _group(Widget child, {bool invalid = false}) =>
      DRadioGroup<String>.controlled(
        groupValue: _value,
        invalid: invalid,
        onChanged: (next) => setState(() => _value = next!),
        child: child,
      );

  Widget _choiceCards() => _group(
    _spaced([
      for (var i = 0; i < 3; i++)
        DFieldLabel.choice(
          selected: _value == values[i],
          focusNode: _focus(values[i]),
          onPressed: () => _select(values[i]),
          child: DField(
            orientation: DFieldOrientation.horizontal,
            children: [
              DFieldContent(
                children: [
                  DFieldTitle(excludeSemantics: true, child: Text(labels[i])),
                  DFieldDescription(child: Text(descriptions[i])),
                ],
              ),
              DFieldControl(
                label: labels[i],
                description: descriptions[i],
                expand: false,
                alignIndicatorToContent: true,
                child: DRadioGroupItem<String>(
                  value: values[i],
                  semanticLabel: '',
                  focusNode: _focus(values[i]),
                ),
              ),
            ],
          ),
        ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final cards = mode == 'Choice Card';
    final rtl = mode == 'RTL';
    final fieldset = mode == 'Fieldset';
    final invalid = mode == 'Invalid';
    final example = Directionality(
      textDirection: rtl
          ? _translations[_language]!.dir
          : Directionality.of(context),
      child: switch (mode) {
        'Default' => _group(
          _spaced([
            for (var i = 0; i < 3; i++)
              DRadioGroupItem<String>(
                value: values[i],
                focusNode: _focus(values[i]),
                label: DLabel(child: Text(labels[i])),
              ),
          ]),
        ),
        'Description' || 'RTL' => _group(_items(description: true)),
        'Choice Card' => _choiceCards(),
        'Fieldset' => DFieldSet(
          semanticLabel: 'Subscription Plan',
          spacing: 12,
          children: [
            const DFieldContent(
              children: [
                DFieldLegend(
                  variant: DFieldLegendVariant.label,
                  child: Text('Subscription Plan'),
                ),
                DFieldDescription(
                  child: Text(
                    'Yearly and lifetime plans offer significant savings.',
                  ),
                ),
              ],
            ),
            _group(_items()),
          ],
        ),
        'Disabled' => _group(_items(firstDisabled: true)),
        'Invalid' => DFieldSet(
          semanticLabel: 'Notification Preferences',
          spacing: 12,
          children: [
            const DFieldContent(
              children: [
                DFieldLegend(
                  variant: DFieldLegendVariant.label,
                  child: Text('Notification Preferences'),
                ),
                DFieldDescription(
                  child: Text('Choose how you want to receive notifications.'),
                ),
              ],
            ),
            _group(_items(invalid: true), invalid: true),
          ],
        ),
        _ => const SizedBox.shrink(),
      },
    );
    if (rtl) {
      // The selector's popup measures itself with a LayoutBuilder, so only
      // the group takes the reference's intrinsic w-fit width.
      return Align(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // The reference selector keeps dir="ltr" on its trigger and
            // popup; the chosen language owns the group's direction.
            DDirection(
              textDirection: TextDirection.ltr,
              child: DSelect<String>(
                value: _language,
                size: DSelectSize.small,
                width: 144,
                semanticLabel: 'Language',
                entries: const [
                  DSelectOption(
                    value: 'en',
                    label: 'English',
                    child: Text('English'),
                  ),
                  DSelectOption(
                    value: 'ar',
                    label: 'Arabic (العربية)',
                    child: Text('Arabic (العربية)'),
                  ),
                  DSelectOption(
                    value: 'he',
                    label: 'Hebrew (עברית)',
                    child: Text('Hebrew (עברית)'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            IntrinsicWidth(child: example),
          ],
        ),
      );
    }
    return Align(
      child: cards || fieldset || invalid
          ? SizedBox(width: cards ? 384 : 320, child: example)
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
            spacing: 8,
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
            spacing: 8,
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
