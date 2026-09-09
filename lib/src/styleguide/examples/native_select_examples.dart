import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

const _fruit = <DNativeSelectEntry<String>>[
  DNativeSelectOption(value: 'apple', label: 'Apple'),
  DNativeSelectOption(value: 'banana', label: 'Banana'),
  DNativeSelectOption(value: 'blueberry', label: 'Blueberry'),
  DNativeSelectOption(value: 'grapes', label: 'Grapes', enabled: false),
  DNativeSelectOption(value: 'pineapple', label: 'Pineapple'),
];

final nativeSelectExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A compact plain selection field with a Flutter-owned popup.',
  notes:
      'Independent source, browser, and macOS native review complete. '
      '32px standard / 28px small, 14px text with 20px leading, 16px Lucide chevron. '
      'The platform adaptation uses Flutter MenuAnchor/MenuItemButton on all targets, not '
      'an OS/AppKit/UIKit picker. Its popup provides scrolling, keyboard selection, '
      'Escape/outside dismissal and focus restoration. Type a prefix to choose; '
      'repeat a letter to cycle matching enabled choices. Options are plain text; '
      'use the separate Select for rich content. Popup environment changes update '
      'the open popup with current tokens, direction and text scale. '
      'The ordinary constructor owns state; .controlled displays only accepted '
      'parent values. Null onChanged disables editing; placeholderEnabled: false '
      'prevents clearing a required choice. Form reset requests the '
      'mount-time initialValue; controlled parents must accept that request. '
      'The inherited text scaler expands field height; long closed labels ellipsize '
      'and remain complete in the popup. Content width is the default; isExpanded '
      'fills a bounded width supplied by the caller.',
  examples: [
    StyleguideExample(
      title: 'Reference status',
      description:
          'Exact composition from the official Base UI Native Select page.',
      code: '''DNativeSelect<String>(
  placeholder: 'Select status',
  entries: const [
    DNativeSelectOption(value: 'todo', label: 'Todo'),
    DNativeSelectOption(value: 'in-progress', label: 'In Progress'),
    DNativeSelectOption(value: 'done', label: 'Done'),
    DNativeSelectOption(value: 'cancelled', label: 'Cancelled'),
  ],
  onChanged: (_) {},
)''',
      builder: (_) => DNativeSelect<String>(
        placeholder: 'Select status',
        entries: const [
          DNativeSelectOption(value: 'todo', label: 'Todo'),
          DNativeSelectOption(value: 'in-progress', label: 'In Progress'),
          DNativeSelectOption(value: 'done', label: 'Done'),
          DNativeSelectOption(value: 'cancelled', label: 'Cancelled'),
        ],
        onChanged: (_) {},
      ),
    ),
    StyleguideExample(
      title: 'Reference departments',
      description:
          'Exact composition from the official Base UI Native Select page.',
      code: '''DNativeSelect<String>(
  placeholder: 'Select department',
  entries: const [
    DNativeSelectOptGroup(label: 'Engineering', options: [
      DNativeSelectOption(value: 'frontend', label: 'Frontend'),
      DNativeSelectOption(value: 'backend', label: 'Backend'),
      DNativeSelectOption(value: 'devops', label: 'DevOps'),
    ]),
    DNativeSelectOptGroup(label: 'Sales', options: [
      DNativeSelectOption(value: 'sales-rep', label: 'Sales Rep'),
      DNativeSelectOption(value: 'account-manager', label: 'Account Manager'),
      DNativeSelectOption(value: 'sales-director', label: 'Sales Director'),
    ]),
    DNativeSelectOptGroup(label: 'Operations', options: [
      DNativeSelectOption(value: 'support', label: 'Customer Support'),
      DNativeSelectOption(value: 'product-manager', label: 'Product Manager'),
      DNativeSelectOption(value: 'ops-manager', label: 'Operations Manager'),
    ]),
  ],
  onChanged: (_) {},
)''',
      builder: (_) => DNativeSelect<String>(
        placeholder: 'Select department',
        entries: const [
          DNativeSelectOptGroup(
            label: 'Engineering',
            options: [
              DNativeSelectOption(value: 'frontend', label: 'Frontend'),
              DNativeSelectOption(value: 'backend', label: 'Backend'),
              DNativeSelectOption(value: 'devops', label: 'DevOps'),
            ],
          ),
          DNativeSelectOptGroup(
            label: 'Sales',
            options: [
              DNativeSelectOption(value: 'sales-rep', label: 'Sales Rep'),
              DNativeSelectOption(
                value: 'account-manager',
                label: 'Account Manager',
              ),
              DNativeSelectOption(
                value: 'sales-director',
                label: 'Sales Director',
              ),
            ],
          ),
          DNativeSelectOptGroup(
            label: 'Operations',
            options: [
              DNativeSelectOption(value: 'support', label: 'Customer Support'),
              DNativeSelectOption(
                value: 'product-manager',
                label: 'Product Manager',
              ),
              DNativeSelectOption(
                value: 'ops-manager',
                label: 'Operations Manager',
              ),
            ],
          ),
        ],
        onChanged: (_) {},
      ),
    ),
    StyleguideExample(
      title: 'Reference disabled',
      description:
          'Exact composition from the official Base UI Native Select page.',
      code: '''DNativeSelect<String>(
  placeholder: 'Select priority',
  entries: const [
    DNativeSelectOption(value: 'low', label: 'Low'),
    DNativeSelectOption(value: 'medium', label: 'Medium'),
    DNativeSelectOption(value: 'high', label: 'High'),
    DNativeSelectOption(value: 'critical', label: 'Critical'),
  ],
  onChanged: null,
)''',
      builder: (_) => const DNativeSelect<String>(
        placeholder: 'Select priority',
        entries: [
          DNativeSelectOption(value: 'low', label: 'Low'),
          DNativeSelectOption(value: 'medium', label: 'Medium'),
          DNativeSelectOption(value: 'high', label: 'High'),
          DNativeSelectOption(value: 'critical', label: 'Critical'),
        ],
        onChanged: null,
      ),
    ),
    StyleguideExample(
      title: 'Reference invalid',
      description:
          'Exact composition from the official Base UI Native Select page.',
      code: '''DNativeSelect<String>(
  placeholder: 'Select role',
  entries: const [
    DNativeSelectOption(value: 'admin', label: 'Admin'),
    DNativeSelectOption(value: 'editor', label: 'Editor'),
    DNativeSelectOption(value: 'viewer', label: 'Viewer'),
    DNativeSelectOption(value: 'guest', label: 'Guest'),
  ],
  onChanged: (_) {},
  invalid: true,
)''',
      builder: (_) => DNativeSelect<String>(
        placeholder: 'Select role',
        entries: const [
          DNativeSelectOption(value: 'admin', label: 'Admin'),
          DNativeSelectOption(value: 'editor', label: 'Editor'),
          DNativeSelectOption(value: 'viewer', label: 'Viewer'),
          DNativeSelectOption(value: 'guest', label: 'Guest'),
        ],
        onChanged: (_) {},
        invalid: true,
      ),
    ),
    StyleguideExample(
      title: 'Reference RTL',
      description:
          'Exact composition from the official Base UI Native Select page.',
      code:
          '''Directionality(textDirection: TextDirection.rtl, child: DNativeSelect<String>(
  placeholder: 'اختر الحالة',
  entries: const [
    DNativeSelectOption(value: 'todo', label: 'مهام'),
    DNativeSelectOption(value: 'in-progress', label: 'قيد التنفيذ'),
    DNativeSelectOption(value: 'done', label: 'منجز'),
    DNativeSelectOption(value: 'cancelled', label: 'ملغي'),
  ],
  onChanged: (_) {},
))''',
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DNativeSelect<String>(
          placeholder: 'اختر الحالة',
          entries: const [
            DNativeSelectOption(value: 'todo', label: 'مهام'),
            DNativeSelectOption(value: 'in-progress', label: 'قيد التنفيذ'),
            DNativeSelectOption(value: 'done', label: 'منجز'),
            DNativeSelectOption(value: 'cancelled', label: 'ملغي'),
          ],
          onChanged: (_) {},
        ),
      ),
    ),
    StyleguideExample(
      title: 'Simple',
      description:
          'Select a fruit; Grapes is disabled. The placeholder can be selected again.',
      states: const ['Default', 'Placeholder', 'Disabled option', 'Keyboard'],
      code: '''DNativeSelect<String>(
  placeholder: 'Select a fruit',
  entries: const [
    DNativeSelectOption(value: 'apple', label: 'Apple'),
    DNativeSelectOption(value: 'banana', label: 'Banana'),
    DNativeSelectOption(value: 'blueberry', label: 'Blueberry'),
    DNativeSelectOption(value: 'grapes', label: 'Grapes', enabled: false),
    DNativeSelectOption(value: 'pineapple', label: 'Pineapple'),
  ],
  onChanged: (value) {},
)''',
      builder: (_) => DNativeSelect<String>(
        placeholder: 'Select a fruit',
        entries: _fruit,
        onChanged: (_) {},
      ),
    ),
    StyleguideExample(
      title: 'Groups',
      description:
          'Fruit and vegetable optgroups; the seasonal group is disabled.',
      states: const ['Groups', 'Disabled group'],
      code: '''DNativeSelect<String>(
  placeholder: 'Select a food',
  entries: const [
    DNativeSelectOptGroup(label: 'Fruits', options: [
      DNativeSelectOption(value: 'apple', label: 'Apple'),
      DNativeSelectOption(value: 'banana', label: 'Banana'),
      DNativeSelectOption(value: 'blueberry', label: 'Blueberry'),
    ]),
    DNativeSelectOptGroup(label: 'Vegetables', options: [
      DNativeSelectOption(value: 'carrot', label: 'Carrot'),
      DNativeSelectOption(value: 'broccoli', label: 'Broccoli'),
      DNativeSelectOption(value: 'spinach', label: 'Spinach'),
    ]),
    DNativeSelectOptGroup(label: 'Seasonal', enabled: false, options: [
      DNativeSelectOption(value: 'pumpkin', label: 'Pumpkin'),
    ]),
  ],
  onChanged: (value) {},
)''',
      builder: (_) => DNativeSelect<String>(
        placeholder: 'Select a food',
        entries: const [
          DNativeSelectOptGroup(
            label: 'Fruits',
            options: [
              DNativeSelectOption(value: 'apple', label: 'Apple'),
              DNativeSelectOption(value: 'banana', label: 'Banana'),
              DNativeSelectOption(value: 'blueberry', label: 'Blueberry'),
            ],
          ),
          DNativeSelectOptGroup(
            label: 'Vegetables',
            options: [
              DNativeSelectOption(value: 'carrot', label: 'Carrot'),
              DNativeSelectOption(value: 'broccoli', label: 'Broccoli'),
              DNativeSelectOption(value: 'spinach', label: 'Spinach'),
            ],
          ),
          DNativeSelectOptGroup(
            label: 'Seasonal',
            enabled: false,
            options: [DNativeSelectOption(value: 'pumpkin', label: 'Pumpkin')],
          ),
        ],
        onChanged: (_) {},
      ),
    ),
    StyleguideExample(
      title: 'Sizes, disabled and invalid',
      description:
          'Both registry sizes, a disabled field and an invalid field. Large text expands both sizes.',
      states: const ['Small', 'Standard', 'Disabled', 'Invalid'],
      code: '''const fruit = <DNativeSelectEntry<String>>[
  DNativeSelectOption(value: 'apple', label: 'Apple'),
  DNativeSelectOption(value: 'banana', label: 'Banana'),
  DNativeSelectOption(value: 'blueberry', label: 'Blueberry'),
  DNativeSelectOption(value: 'grapes', label: 'Grapes', enabled: false),
  DNativeSelectOption(value: 'pineapple', label: 'Pineapple'),
];
Column(children: [
  DNativeSelect<String>(size: DNativeSelectSize.small,
    entries: fruit, onChanged: (value) {}),
  const SizedBox(height: 16),
  DNativeSelect<String>(entries: fruit, onChanged: (value) {}),
  const SizedBox(height: 16),
  DNativeSelect<String>(placeholder: 'Disabled',
    entries: fruit, onChanged: null),
  const SizedBox(height: 16),
  DNativeSelect<String>(placeholder: 'Error state', invalid: true,
    entries: fruit, onChanged: (value) {}),
])''',
      builder: (_) => Column(
        children: [
          DNativeSelect<String>(
            size: DNativeSelectSize.small,
            entries: _fruit,
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          DNativeSelect<String>(entries: _fruit, onChanged: (_) {}),
          const SizedBox(height: 16),
          const DNativeSelect<String>(
            placeholder: 'Disabled',
            entries: _fruit,
            onChanged: null,
          ),
          const SizedBox(height: 16),
          DNativeSelect<String>(
            placeholder: 'Error state',
            invalid: true,
            entries: _fruit,
            onChanged: (_) {},
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Country form',
      description:
          'Validate an empty country, select one, save and reset. All data stays in this preview.',
      states: const [
        'Label',
        'Description',
        'Required',
        'Validation',
        'Save',
        'Reset',
      ],
      code: '''class CountryForm extends StatefulWidget {
  const CountryForm({super.key});
  @override
  State<CountryForm> createState() => _CountryFormState();
}
class _CountryFormState extends State<CountryForm> {
  final form = GlobalKey<FormState>();
  String? saved;
  @override
  Widget build(BuildContext context) => Form(key: form, child: Column(children: [
    DNativeSelect<String>(label: 'Country', isRequired: true,
      placeholder: 'Select a country',
      description: 'Select your country of residence.',
      entries: const [
        DNativeSelectOption(value: 'us', label: 'United States'),
        DNativeSelectOption(value: 'uk', label: 'United Kingdom'),
        DNativeSelectOption(value: 'ca', label: 'Canada'),
        DNativeSelectOption(value: 'au', label: 'Australia'),
      ],
      onChanged: (_) {},
      validator: (value) => value == null ? 'Choose a country.' : null,
      onSaved: (value) => saved = value,
    ),
    DButton(label: const Text('Save'), onPressed: () {
      if (form.currentState!.validate()) setState(() => form.currentState!.save());
    }),
    DButton(label: const Text('Reset'), onPressed: () {
      form.currentState!.reset(); setState(() => saved = null);
    }),
    Text('Saved: \${saved ?? "none"}'),
  ]));
}''',
      builder: (_) => const _CountryForm(),
    ),
    StyleguideExample(
      title: 'Controlled selection',
      description:
          'The parent accepts changes. A separate action sets Banana; reset requests Apple.',
      states: const ['Controlled', 'External update', 'Reset'],
      code: '''class ControlledSelection extends StatefulWidget {
  const ControlledSelection({super.key});
  @override
  State<ControlledSelection> createState() => _ControlledSelectionState();
}
class _ControlledSelectionState extends State<ControlledSelection> {
  final form = GlobalKey<FormState>();
  String? value = 'apple';
  @override
  Widget build(BuildContext context) => Form(key: form, child: Column(children: [
    DNativeSelect<String>.controlled(
      value: value, initialValue: 'apple',
      entries: const [
        DNativeSelectOption(value: 'apple', label: 'Apple'),
        DNativeSelectOption(value: 'banana', label: 'Banana'),
        DNativeSelectOption(value: 'blueberry', label: 'Blueberry'),
        DNativeSelectOption(value: 'grapes', label: 'Grapes', enabled: false),
        DNativeSelectOption(value: 'pineapple', label: 'Pineapple'),
      ],
      onChanged: (next) => setState(() => value = next),
    ),
    const SizedBox(height: 16),
    Wrap(spacing: 8, children: [
      DButton(label: const Text('Set Banana'),
        onPressed: () => setState(() => value = 'banana')),
      DButton(label: const Text('Reset selection'),
        onPressed: () => form.currentState!.reset()),
    ]),
  ]));
}''',
      builder: (_) => const _Controlled(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic food groups with the chevron on the logical trailing edge.',
      states: const ['RTL', 'Groups', 'Text scaling'],
      code: '''Directionality(textDirection: TextDirection.rtl,
  child: DNativeSelect<String>(placeholder: 'اختر فاكهة',
    entries: const [
      DNativeSelectOptGroup(label: 'الفواكه', options: [
        DNativeSelectOption(value: 'apple', label: 'تفاح'),
        DNativeSelectOption(value: 'banana', label: 'موز'),
      ]),
    ], onChanged: (value) {},
  ),
)''',
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DNativeSelect<String>(
          placeholder: 'اختر فاكهة',
          entries: const [
            DNativeSelectOptGroup(
              label: 'الفواكه',
              options: [
                DNativeSelectOption(value: 'apple', label: 'تفاح'),
                DNativeSelectOption(value: 'banana', label: 'موز'),
              ],
            ),
          ],
          onChanged: (_) {},
        ),
      ),
    ),
  ],
);

class _CountryForm extends StatefulWidget {
  const _CountryForm();
  @override
  State<_CountryForm> createState() => _CountryFormState();
}

class _CountryFormState extends State<_CountryForm> {
  final _form = GlobalKey<FormState>();
  String? _saved;
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DNativeSelect<String>(
          label: 'Country',
          isRequired: true,
          placeholder: 'Select a country',
          description: 'Select your country of residence.',
          entries: const [
            DNativeSelectOption(value: 'us', label: 'United States'),
            DNativeSelectOption(value: 'uk', label: 'United Kingdom'),
            DNativeSelectOption(value: 'ca', label: 'Canada'),
            DNativeSelectOption(value: 'au', label: 'Australia'),
          ],
          onChanged: (_) {},
          validator: (value) => value == null ? 'Choose a country.' : null,
          onSaved: (value) => _saved = value,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            DButton(
              label: const Text('Save'),
              onPressed: () {
                if (_form.currentState!.validate()) {
                  setState(() => _form.currentState!.save());
                }
              },
            ),
            DButton(
              label: const Text('Reset'),
              onPressed: () {
                _form.currentState!.reset();
                setState(() => _saved = null);
              },
            ),
          ],
        ),
        Text('Saved: ${_saved ?? "none"}'),
      ],
    ),
  );
}

class _Controlled extends StatefulWidget {
  const _Controlled();
  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  final _form = GlobalKey<FormState>();
  String? _value = 'apple';
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      children: [
        DNativeSelect<String>.controlled(
          value: _value,
          initialValue: 'apple',
          entries: _fruit,
          onChanged: (next) => setState(() => _value = next),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            DButton(
              label: const Text('Set Banana'),
              onPressed: () => setState(() => _value = 'banana'),
            ),
            DButton(
              label: const Text('Reset selection'),
              onPressed: () => _form.currentState!.reset(),
            ),
          ],
        ),
      ],
    ),
  );
}
