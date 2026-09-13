import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final selectExamples = ComponentExamples(
  description: 'Displays a list of options for the user to pick from.',
  status: ComponentStatus.implemented,
  notes:
      'Source mapping: Base Nova SelectTrigger maps to a compact button-like '
      'DSelect trigger with the shared 24/28/32px button scale and matching '
      'text and icon metrics, input border, transparent/light background, dark input '
      'tint, exterior focus/invalid ring, disabled 50% opacity and selectable '
      'text disabled. SelectContent uses DPopover for live-theme overlay '
      'lifecycle, 4px side offset, collision handling, 144px minimum popup '
      'width, 8px radius, foreground/10 ring and shadow. Groups, labels, '
      'separators, disabled options, scrollable lists, RTL and Form validation '
      'are implemented. Focused closed triggers support native-style typeahead '
      'selection; open typeahead supports multi-word labels without treating '
      'Space as activation. Pointer/keyboard openings align the selected item with '
      'the trigger when there is enough viewport space; touch openings use '
      'ordinary edge placement. Legacy DropdownMenuItem callers route through '
      'the same rendering owner.',
  examples: [
    StyleguideExample(
      title: 'Size',
      description: 'The same small, regular and large scale as Button.',
      code:
          'DSelect<String>(size: DControlSize.small, entries: entries, onChanged: select)',
      builder: (_) => Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final size in DControlSize.values)
            DSelect<String>(
              size: size,
              width: 128,
              value: 'apple',
              entries: _fruitEntries,
              onChanged: (_) {},
            ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Default',
      description:
          'A controlled select with the documented fruit placeholder item.',
      states: const [
        'Controlled',
        'Placeholder',
        'Keyboard',
        'Closed typeahead',
      ],
      code: '''DSelect<String>(
  value: fruit,
  entries: const [
    DSelectOption(value: null, label: 'Select a fruit', child: Text('Select a fruit')),
    DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
  ],
  onChanged: (value) => setState(() => fruit = value),
)''',
      builder: (_) => const _FruitSelectDemo(),
    ),
    StyleguideExample(
      title: 'Align Item With Trigger',
      description:
          'Toggle selected-row overlap. When disabled, the popup aligns to the trigger edge.',
      states: const ['Aligned item', 'Edge aligned', 'Live toggle'],
      code: '''DSelect<String>(
  value: fruit,
  alignItemWithTrigger: alignItemWithTrigger,
  entries: fruitEntries,
  onChanged: (value) => setState(() => fruit = value),
)''',
      builder: (_) => const _AlignItemDemo(),
    ),
    StyleguideExample(
      title: 'Groups',
      description: 'Use labels and separators to organize related options.',
      states: const ['Group labels', 'Separator'],
      code: '''DSelect<String>(
  entries: const [
    DSelectGroup(label: Text('Fruits'), children: [
      DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
    ]),
    DSelectSeparator(),
    DSelectGroup(label: Text('Vegetables'), children: [
      DSelectOption(value: 'carrot', label: 'Carrot', child: Text('Carrot')),
    ]),
  ],
  onChanged: (value) => setState(() => value = value),
)''',
      builder: (_) => const _GroupedSelectDemo(),
    ),
    StyleguideExample(
      title: 'Scrollable',
      description:
          'Large lists keep the popup bounded and scroll to the selected item.',
      states: const ['Scrollable', 'Long list', 'Typeahead'],
      code: '''DSelect<String>(
  value: timezone,
  maxPopupHeight: 212,
  entries: timezoneEntries,
  onChanged: (value) => setState(() => timezone = value),
)''',
      builder: (_) => const _TimezoneSelectDemo(),
    ),
    StyleguideExample(
      title: 'Disabled',
      description: 'Disabled triggers and disabled items ignore activation.',
      states: const ['Disabled trigger', 'Disabled item'],
      code: '''DSelect<String>(
  value: 'apple',
  enabled: false,
  entries: fruitEntries,
  onChanged: (value) {},
)''',
      builder: (_) => const _DisabledSelectDemo(),
    ),
    StyleguideExample(
      title: 'Invalid and Form',
      description:
          'Flutter Form remains the validation/save/reset owner while Select paints the invalid trigger.',
      states: const ['Invalid', 'Required', 'Form'],
      code: '''DSelectField<String>(
  initialValue: fruit,
  decoration: const InputDecoration(labelText: 'Fruit', hintText: 'Select a fruit'),
  validator: (value) => value == null ? 'Please select a fruit.' : null,
  items: const [DropdownMenuItem(value: 'apple', child: Text('Apple'))],
  onChanged: (value) => setState(() => fruit = value),
)''',
      builder: (_) => const _SelectFormDemo(),
    ),
    StyleguideExample(
      title: 'RTL',
      description: 'Trigger, indicator and popup alignment follow direction.',
      states: const ['RTL', 'Arabic labels'],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DSelect<String>(value: language, entries: arabicEntries, onChanged: ...),
)''',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _RtlSelectDemo(),
      ),
    ),
    StyleguideExample(
      title: 'Multiple and custom value',
      description:
          'Multiple mode keeps the popup open while toggling values and can format the read-only selection.',
      states: const ['Multiple', 'Controlled', 'Custom value'],
      code: '''DMultiSelect<String>.controlled(
  value: languages,
  entries: const [
    DSelectOption(value: 'dart', label: 'Dart', child: Text('Dart')),
    DSelectOption(value: 'ruby', label: 'Ruby', child: Text('Ruby')),
  ],
  valueBuilder: (context, values, items) => Text(
    values.isEmpty ? 'Select languages' : items.map((item) => item.textValue).join(' · '),
  ),
  onChanged: (values) => setState(() => languages = values),
)''',
      builder: (_) => const _MultipleSelectDemo(),
    ),
    StyleguideExample(
      title: 'Button Group composition',
      description:
          'The trigger remains an independent control beside adjacent actions; the popup is outside joined geometry.',
      states: const ['Adjacent actions', 'Overlay outside group', 'Focus'],
      code: '''DButtonGroup(semanticLabel: 'Range navigation', children: [
  DButton(label: const Text('Back'), onPressed: previous),
  DSelect<String>(value: mode, entries: modes, onChanged: selectMode),
  DButton(label: const Text('Next'), onPressed: next),
])''',
      builder: (_) => const _ButtonGroupSelectDemo(),
    ),
  ],
);

const _fruitEntries = <DSelectEntry<String>>[
  DSelectOption(
    value: null,
    label: 'Select a fruit',
    child: Text('Select a fruit'),
  ),
  DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
  DSelectOption(value: 'banana', label: 'Banana', child: Text('Banana')),
  DSelectOption(
    value: 'blueberry',
    label: 'Blueberry',
    child: Text('Blueberry'),
  ),
  DSelectOption(value: 'grapes', label: 'Grapes', child: Text('Grapes')),
  DSelectOption(
    value: 'pineapple',
    label: 'Pineapple',
    child: Text('Pineapple'),
  ),
];

class _FruitSelectDemo extends StatefulWidget {
  const _FruitSelectDemo();

  @override
  State<_FruitSelectDemo> createState() => _FruitSelectDemoState();
}

class _FruitSelectDemoState extends State<_FruitSelectDemo> {
  String? _fruit;

  @override
  Widget build(BuildContext context) => Align(
    child: DSelect<String>(
      value: _fruit,
      entries: _fruitEntries,
      onChanged: (value) => setState(() => _fruit = value),
      semanticLabel: 'Fruit',
    ),
  );
}

class _AlignItemDemo extends StatefulWidget {
  const _AlignItemDemo();

  @override
  State<_AlignItemDemo> createState() => _AlignItemDemoState();
}

class _AlignItemDemoState extends State<_AlignItemDemo> {
  String? _fruit = 'banana';
  bool _align = true;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          value: _align,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) => setState(() => _align = value),
          title: const DLabel(child: Text('Align Item')),
          subtitle: const Text('Toggle to align the item with the trigger.'),
        ),
        DSelect<String>(
          value: _fruit,
          isExpanded: true,
          alignItemWithTrigger: _align,
          entries: _fruitEntries,
          onChanged: (value) => setState(() => _fruit = value),
          semanticLabel: 'Fruit',
        ),
      ],
    ),
  );
}

class _GroupedSelectDemo extends StatefulWidget {
  const _GroupedSelectDemo();

  @override
  State<_GroupedSelectDemo> createState() => _GroupedSelectDemoState();
}

class _GroupedSelectDemoState extends State<_GroupedSelectDemo> {
  String? _value;

  @override
  Widget build(BuildContext context) => Align(
    child: DSelect<String>(
      value: _value,
      semanticLabel: 'Food',
      entries: const [
        DSelectGroup(
          label: Text('Fruits'),
          children: [
            DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
            DSelectOption(
              value: 'banana',
              label: 'Banana',
              child: Text('Banana'),
            ),
            DSelectOption(
              value: 'blueberry',
              label: 'Blueberry',
              child: Text('Blueberry'),
            ),
          ],
        ),
        DSelectSeparator(),
        DSelectGroup(
          label: Text('Vegetables'),
          children: [
            DSelectOption(
              value: 'carrot',
              label: 'Carrot',
              child: Text('Carrot'),
            ),
            DSelectOption(
              value: 'broccoli',
              label: 'Broccoli',
              child: Text('Broccoli'),
            ),
            DSelectOption(
              value: 'spinach',
              label: 'Spinach',
              child: Text('Spinach'),
            ),
          ],
        ),
      ],
      onChanged: (value) => setState(() => _value = value),
    ),
  );
}

class _TimezoneSelectDemo extends StatefulWidget {
  const _TimezoneSelectDemo();

  @override
  State<_TimezoneSelectDemo> createState() => _TimezoneSelectDemoState();
}

class _TimezoneSelectDemoState extends State<_TimezoneSelectDemo> {
  String? _zone = 'cet';

  @override
  Widget build(BuildContext context) => Align(
    child: DSelect<String>(
      value: _zone,
      maxPopupHeight: 212,
      semanticLabel: 'Timezone',
      entries: const [
        DSelectOption(
          value: null,
          label: 'Select a timezone',
          child: Text('Select a timezone'),
        ),
        DSelectGroup(
          label: Text('North America'),
          children: [
            DSelectOption(
              value: 'est',
              label: 'Eastern Standard Time',
              child: Text('Eastern Standard Time'),
            ),
            DSelectOption(
              value: 'cst',
              label: 'Central Standard Time',
              child: Text('Central Standard Time'),
            ),
            DSelectOption(
              value: 'mst',
              label: 'Mountain Standard Time',
              child: Text('Mountain Standard Time'),
            ),
            DSelectOption(
              value: 'pst',
              label: 'Pacific Standard Time',
              child: Text('Pacific Standard Time'),
            ),
            DSelectOption(
              value: 'akst',
              label: 'Alaska Standard Time',
              child: Text('Alaska Standard Time'),
            ),
            DSelectOption(
              value: 'hst',
              label: 'Hawaii Standard Time',
              child: Text('Hawaii Standard Time'),
            ),
          ],
        ),
        DSelectGroup(
          label: Text('Europe & Africa'),
          children: [
            DSelectOption(
              value: 'gmt',
              label: 'Greenwich Mean Time',
              child: Text('Greenwich Mean Time'),
            ),
            DSelectOption(
              value: 'cet',
              label: 'Central European Time',
              child: Text('Central European Time'),
            ),
            DSelectOption(
              value: 'eet',
              label: 'Eastern European Time',
              child: Text('Eastern European Time'),
            ),
            DSelectOption(
              value: 'west',
              label: 'Western European Summer Time',
              child: Text('Western European Summer Time'),
            ),
            DSelectOption(
              value: 'cat',
              label: 'Central Africa Time',
              child: Text('Central Africa Time'),
            ),
            DSelectOption(
              value: 'eat',
              label: 'East Africa Time',
              child: Text('East Africa Time'),
            ),
          ],
        ),
        DSelectGroup(
          label: Text('Asia Pacific'),
          children: [
            DSelectOption(
              value: 'msk',
              label: 'Moscow Time',
              child: Text('Moscow Time'),
            ),
            DSelectOption(
              value: 'ist',
              label: 'India Standard Time',
              child: Text('India Standard Time'),
            ),
            DSelectOption(
              value: 'cst_china',
              label: 'China Standard Time',
              child: Text('China Standard Time'),
            ),
            DSelectOption(
              value: 'jst',
              label: 'Japan Standard Time',
              child: Text('Japan Standard Time'),
            ),
            DSelectOption(
              value: 'kst',
              label: 'Korea Standard Time',
              child: Text('Korea Standard Time'),
            ),
            DSelectOption(
              value: 'aest',
              label: 'Australian Eastern Standard Time',
              child: Text('Australian Eastern Standard Time'),
            ),
            DSelectOption(
              value: 'nzst',
              label: 'New Zealand Standard Time',
              child: Text('New Zealand Standard Time'),
            ),
          ],
        ),
      ],
      onChanged: (value) => setState(() => _zone = value),
    ),
  );
}

class _DisabledSelectDemo extends StatelessWidget {
  const _DisabledSelectDemo();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DSelect<String>(
          value: 'apple',
          isExpanded: true,
          enabled: false,
          semanticLabel: 'Disabled fruit',
          entries: _fruitEntries,
          onChanged: (value) {},
        ),
        const SizedBox(height: DSpacing.md),
        DSelect<String>(
          value: 'apple',
          isExpanded: true,
          semanticLabel: 'Fruit with disabled option',
          entries: const [
            DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
            DSelectOption(
              value: 'banana',
              label: 'Banana unavailable',
              enabled: false,
              child: Text('Banana unavailable'),
            ),
            DSelectOption(
              value: 'grapes',
              label: 'Grapes',
              child: Text('Grapes'),
            ),
          ],
          onChanged: (value) {},
        ),
      ],
    ),
  );
}

class _SelectFormDemo extends StatefulWidget {
  const _SelectFormDemo();

  @override
  State<_SelectFormDemo> createState() => _SelectFormDemoState();
}

class _SelectFormDemoState extends State<_SelectFormDemo> {
  final _form = GlobalKey<FormState>();
  String? _fruit;
  String _saved = 'Not saved';

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DSelectField<String>(
            initialValue: _fruit,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Fruit',
              hintText: 'Select a fruit',
            ),
            items: const [
              DropdownMenuItem(value: 'apple', child: Text('Apple')),
              DropdownMenuItem(value: 'banana', child: Text('Banana')),
              DropdownMenuItem(value: 'grapes', child: Text('Grapes')),
            ],
            validator: (value) =>
                value == null ? 'Please select a fruit.' : null,
            onChanged: (value) => setState(() => _fruit = value),
            onSaved: (value) => _saved = 'Saved: ${value ?? 'none'}',
          ),
          const SizedBox(height: DSpacing.md),
          Wrap(
            spacing: DSpacing.sm,
            children: [
              DButton(
                label: const Text('Save'),
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    _form.currentState!.save();
                    setState(() {});
                  }
                },
              ),
              DButton(
                label: const Text('Reset'),
                variant: DButtonVariant.outline,
                onPressed: () {
                  _form.currentState!.reset();
                  setState(() {
                    _fruit = null;
                    _saved = 'Not saved';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: DSpacing.sm),
          Semantics(liveRegion: true, child: Text(_saved)),
        ],
      ),
    ),
  );
}

class _RtlSelectDemo extends StatefulWidget {
  const _RtlSelectDemo();

  @override
  State<_RtlSelectDemo> createState() => _RtlSelectDemoState();
}

class _RtlSelectDemoState extends State<_RtlSelectDemo> {
  String? _language = 'ar';

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: DSelect<String>(
      value: _language,
      isExpanded: true,
      semanticLabel: 'اللغة',
      entries: const [
        DSelectOption(value: 'ar', label: 'العربية', child: Text('العربية')),
        DSelectOption(value: 'he', label: 'עברית', child: Text('עברית')),
        DSelectOption(value: 'fa', label: 'فارسی', child: Text('فارسی')),
      ],
      onChanged: (value) => setState(() => _language = value),
    ),
  );
}

class _ButtonGroupSelectDemo extends StatefulWidget {
  const _ButtonGroupSelectDemo();

  @override
  State<_ButtonGroupSelectDemo> createState() => _ButtonGroupSelectDemoState();
}

class _MultipleSelectDemo extends StatefulWidget {
  const _MultipleSelectDemo();

  @override
  State<_MultipleSelectDemo> createState() => _MultipleSelectDemoState();
}

class _MultipleSelectDemoState extends State<_MultipleSelectDemo> {
  List<String> _languages = const ['dart'];

  @override
  Widget build(BuildContext context) => Align(
    child: DMultiSelect<String>.controlled(
      value: _languages,
      semanticLabel: 'Languages',
      width: 224,
      entries: const [
        DSelectOption(value: 'dart', label: 'Dart', child: Text('Dart')),
        DSelectOption(value: 'ruby', label: 'Ruby', child: Text('Ruby')),
        DSelectOption(value: 'swift', label: 'Swift', child: Text('Swift')),
        DSelectOption(value: 'kotlin', label: 'Kotlin', child: Text('Kotlin')),
      ],
      valueBuilder: (context, values, items) => Text(
        values.isEmpty
            ? 'Select languages'
            : items.map((item) => item.textValue).join(' · '),
      ),
      onChanged: (values) => setState(() => _languages = values),
    ),
  );
}

class _ButtonGroupSelectDemoState extends State<_ButtonGroupSelectDemo> {
  String? _mode = 'week';
  int _actions = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DButtonGroup(
          semanticLabel: 'Range navigation',
          children: [
            DButton(
              label: const Text('Back'),
              variant: DButtonVariant.outline,
              onPressed: () => setState(() => _actions++),
            ),
            DSelect<String>(
              value: _mode,
              entries: const [
                DSelectOption(value: 'day', label: 'Day', child: Text('Day')),
                DSelectOption(
                  value: 'week',
                  label: 'Week',
                  child: Text('Week'),
                ),
                DSelectOption(
                  value: 'month',
                  label: 'Month',
                  child: Text('Month'),
                ),
              ],
              onChanged: (value) => setState(() => _mode = value),
              semanticLabel: 'Range',
            ),
            DButton(
              label: const Text('Next'),
              variant: DButtonVariant.outline,
              onPressed: () => setState(() => _actions++),
            ),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.md),
      Semantics(
        liveRegion: true,
        child: Text('Actions: $_actions, mode: $_mode'),
      ),
    ],
  );
}
