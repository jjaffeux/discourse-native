import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

const _frameworks = [
  DComboboxOption(value: 'next', label: 'Next.js'),
  DComboboxOption(value: 'svelte', label: 'SvelteKit'),
  DComboboxOption(value: 'nuxt', label: 'Nuxt.js'),
  DComboboxOption(value: 'remix', label: 'Remix'),
  DComboboxOption(value: 'astro', label: 'Astro'),
];

const _timezoneGroups = [
  DComboboxOptionGroup(
    label: 'Americas',
    options: [
      DComboboxOption(value: 'new-york', label: '(GMT-5) New York'),
      DComboboxOption(value: 'los-angeles', label: '(GMT-8) Los Angeles'),
      DComboboxOption(value: 'chicago', label: '(GMT-6) Chicago'),
      DComboboxOption(value: 'toronto', label: '(GMT-5) Toronto'),
    ],
  ),
  DComboboxOptionGroup(
    label: 'Europe',
    options: [
      DComboboxOption(value: 'london', label: '(GMT+0) London'),
      DComboboxOption(value: 'paris', label: '(GMT+1) Paris'),
      DComboboxOption(value: 'berlin', label: '(GMT+1) Berlin'),
      DComboboxOption(value: 'rome', label: '(GMT+1) Rome'),
    ],
  ),
  DComboboxOptionGroup(
    label: 'Asia/Pacific',
    options: [
      DComboboxOption(value: 'tokyo', label: '(GMT+9) Tokyo'),
      DComboboxOption(value: 'shanghai', label: '(GMT+8) Shanghai'),
      DComboboxOption(value: 'singapore', label: '(GMT+8) Singapore'),
      DComboboxOption(value: 'sydney', label: '(GMT+11) Sydney'),
    ],
  ),
];

const _countries = [
  DComboboxOption(
    value: 'ar',
    label: 'Argentina',
    searchText: 'Argentina South America ar',
  ),
  DComboboxOption(
    value: 'au',
    label: 'Australia',
    searchText: 'Australia Oceania au',
  ),
  DComboboxOption(
    value: 'br',
    label: 'Brazil',
    searchText: 'Brazil South America br',
  ),
  DComboboxOption(
    value: 'ca',
    label: 'Canada',
    searchText: 'Canada North America ca',
  ),
  DComboboxOption(value: 'fr', label: 'France', searchText: 'France Europe fr'),
  DComboboxOption(value: 'jp', label: 'Japan', searchText: 'Japan Asia jp'),
];

final comboboxExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Autocomplete input with a filterable list of suggestions.',
  notes:
      'Source-prepared against the frozen Base UI/base-nova Combobox. '
      'The selection, query, highlight and open states have independent initial, '
      'controlled, callback and controller ownership. The generic component does '
      'not debounce or fetch; replace options from an application adapter for async '
      'results. Arrow keys move the active option, Enter selects, Escape dismisses, '
      'and Backspace removes the last chip from an empty multiple input. Popup '
      'positioning, collision, theme updates and dismissal compose DPopover. '
      'The reviewed implementation composes the accepted Popover, Input Group, '
      'Field and Item APIs and has passed official browser and native acceptance.',
  examples: [
    StyleguideExample(
      title: 'Composition',
      description:
          'The root composes an editable anchor, portal content, empty state and list.',
      states: const ['Input', 'Content', 'Empty', 'List', 'Item'],
      code: _basicCode,
      builder: (_) => const _BasicCombobox(),
    ),
    StyleguideExample(
      title: 'Simple',
      description: 'A single-line input and flat filtered collection.',
      code: _basicCode,
      builder: (_) => const _BasicCombobox(),
    ),
    StyleguideExample(
      title: 'With chips',
      description:
          'Multiple values render as removable, arrow-navigable chips around the editable input.',
      states: const [
        'Multiple',
        'Remove',
        'Backspace',
        'Arrow navigation',
        'Wrap',
      ],
      code: _multipleCode,
      builder: (_) => const _MultipleCombobox(),
    ),
    StyleguideExample(
      title: 'With groups and collection',
      description:
          'Groups retain accessible labels, filtered collections and separators.',
      code: _groupsCode,
      builder: (_) => const _GroupsCombobox(),
    ),
    StyleguideExample(
      title: 'Custom Items',
      description:
          'Search metadata and the row builder are independent from the selected label.',
      code: _customCode,
      builder: (_) => const _CustomItemsCombobox(),
    ),
    StyleguideExample(
      title: 'Multiple Selection',
      description:
          'The multiple constructor exposes a typed immutable list on every change.',
      code: _multipleCode,
      builder: (_) => const _MultipleCombobox(),
    ),
    StyleguideExample(
      title: 'Basic',
      description:
          'The exact basic frameworks composition from the frozen page.',
      code: _basicCode,
      builder: (_) => const _BasicCombobox(),
    ),
    StyleguideExample(
      title: 'Multiple',
      description:
          'Starts with Next.js selected and closes after each choice like the reference.',
      code: _multipleCode,
      builder: (_) => const _MultipleCombobox(),
    ),
    StyleguideExample(
      title: 'Clear Button',
      description:
          'A clear action replaces the trigger whenever the field has a value.',
      code: '''DCombobox<String>(
  initialValue: 'next',
  options: frameworks,
  anchor: const DComboboxInput<String>(showClear: true),
  content: content,
)''',
      builder: (_) => const _BasicCombobox(clear: true, initialValue: 'next'),
    ),
    StyleguideExample(
      title: 'Groups',
      description:
          'Timezone results are grouped and scroll inside a bounded popup.',
      code: _groupsCode,
      builder: (_) => const _GroupsCombobox(),
    ),
    StyleguideExample(
      title: 'Invalid',
      description:
          'Invalid is communicated semantically and with an exterior destructive ring.',
      states: const ['Invalid', 'Focus ring'],
      code: '''DCombobox<String>(
  options: frameworks,
  anchor: const DComboboxInput<String>(invalid: true),
  content: content,
)''',
      builder: (_) => const _BasicCombobox(invalid: true),
    ),
    StyleguideExample(
      title: 'Disabled',
      description: 'Disabled fields do not focus, edit, open or clear.',
      code: '''DCombobox<String>(
  enabled: false,
  options: frameworks,
  anchor: const DComboboxInput<String>(),
  content: content,
)''',
      builder: (_) => const _BasicCombobox(enabled: false),
    ),
    StyleguideExample(
      title: 'Auto Highlight',
      description:
          'The first enabled filtered result is automatically active for Enter.',
      code: '''DCombobox<String>(
  autoHighlight: true,
  options: frameworks,
  anchor: const DComboboxInput<String>(),
  content: content,
)''',
      builder: (_) => const _BasicCombobox(autoHighlight: true),
    ),
    StyleguideExample(
      title: 'Popup',
      description:
          'A button is the anchor and form control; the editable input moves inside the popup.',
      states: const ['Trigger', 'Input inside popup', 'Focus restoration'],
      code: _popupCode,
      builder: (_) => const _PopupCombobox(),
    ),
    StyleguideExample(
      title: 'Input Group',
      description:
          'A globe addon shares the compact input surface and the popup aligns past it.',
      code: '''DComboboxInput<String>(
  addons: const [
    DInputGroupAddon(child: DIcon(DIcons.globe, size: 16)),
  ],
  placeholder: 'Select a timezone',
)

DComboboxContent<String>(
  width: 240,
  alignOffset: -28,
)''',
      builder: (_) => const _GroupsCombobox(inputGroup: true),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic labels, chip flow, item padding and popup alignment follow directionality.',
      states: const ['Arabic', 'RTL', 'Multiple', 'Large text'],
      code: _rtlCode,
      builder: (_) => const _RtlCombobox(),
    ),
  ],
);

const _basicCode = '''DCombobox<String>(
  options: frameworks,
  anchor: const DComboboxInput<String>(placeholder: 'Select a framework'),
  content: const DComboboxContent(children: [
    DComboboxEmpty<String>(child: Text('No items found.')),
    DComboboxList<String>(),
  ]),
)''';

const _multipleCode = '''DCombobox<String>.multiple(
  initialValue: const ['next'],
  autoHighlight: true,
  options: frameworks,
  anchor: const DComboboxChips<String>(
    input: DComboboxChipsInput<String>(placeholder: 'Add framework'),
  ),
  content: const DComboboxContent(children: [
    DComboboxEmpty<String>(child: Text('No items found.')),
    DComboboxList<String>(),
  ]),
)''';

const _groupsCode = '''DCombobox<String>(
  options: const [],
  groups: timezoneGroups,
  anchor: const DComboboxInput<String>(placeholder: 'Select a timezone'),
  content: const DComboboxContent(children: [
    DComboboxEmpty<String>(child: Text('No timezones found.')),
    DComboboxList<String>(),
  ]),
)''';

const _customCode = '''DCombobox<String>(
  options: countries,
  anchor: const DComboboxInput<String>(placeholder: 'Search countries...'),
  content: DComboboxContent(children: [
    const DComboboxEmpty<String>(child: Text('No countries found.')),
    DComboboxList<String>(itemBuilder: (context, option) => DItem(
      size: DItemSize.xs,
      padding: EdgeInsets.zero,
      children: [DItemContent(children: [
        DItemTitle(child: Text(option.label)),
        DItemDescription(child: Text(option.searchText!)),
      ])],
    )),
  ]),
)''';

const _popupCode = '''DCombobox<String>(
  initialValue: 'ca',
  options: countries,
  anchor: DComboboxTrigger<String>(builder: (context, trigger) => DButton(
    label: DComboboxValue<String>(placeholder: 'Select country'),
    variant: DButtonVariant.outline,
    focusNode: trigger.focusNode,
    onPressed: trigger.toggle,
  )),
  content: const DComboboxContent(children: [
    Padding(padding: EdgeInsets.all(4), child:
      DComboboxInput<String>(registerAsAnchor: false, showTrigger: false)),
    DComboboxEmpty<String>(child: Text('No items found.')),
    DComboboxList<String>(),
  ]),
)''';

const _rtlCode = '''Directionality(
  textDirection: TextDirection.rtl,
  child: DCombobox<String>.multiple(
    initialValue: const ['technology'],
    options: categories,
    anchor: const DComboboxChips<String>(
      input: DComboboxChipsInput<String>(placeholder: 'أضف فئات'),
    ),
    content: const DComboboxContent(children: [DComboboxList<String>()]),
  ),
)''';

class _BasicCombobox extends StatelessWidget {
  const _BasicCombobox({
    this.clear = false,
    this.initialValue,
    this.invalid = false,
    this.enabled = true,
    this.autoHighlight = false,
  });

  final bool clear, invalid, enabled, autoHighlight;
  final String? initialValue;

  @override
  Widget build(BuildContext context) => DCombobox<String>(
    initialValue: initialValue,
    options: _frameworks,
    enabled: enabled,
    autoHighlight: autoHighlight,
    anchor: DComboboxInput<String>(
      placeholder: 'Select a framework',
      showClear: clear,
      invalid: invalid,
    ),
    content: const DComboboxContent(
      children: [
        DComboboxEmpty<String>(child: Text('No items found.')),
        DComboboxList<String>(),
      ],
    ),
  );
}

class _MultipleCombobox extends StatelessWidget {
  const _MultipleCombobox();

  @override
  Widget build(BuildContext context) => DCombobox<String>.multiple(
    initialValue: const ['next'],
    options: _frameworks,
    autoHighlight: true,
    anchor: const DComboboxChips<String>(
      input: DComboboxChipsInput<String>(placeholder: 'Add framework'),
    ),
    content: const DComboboxContent(
      children: [
        DComboboxEmpty<String>(child: Text('No items found.')),
        DComboboxList<String>(),
      ],
    ),
  );
}

class _GroupsCombobox extends StatelessWidget {
  const _GroupsCombobox({this.inputGroup = false});
  final bool inputGroup;

  @override
  Widget build(BuildContext context) => DCombobox<String>(
    options: const [],
    groups: _timezoneGroups,
    anchor: DComboboxInput<String>(
      placeholder: 'Select a timezone',
      addons: inputGroup
          ? const [DInputGroupAddon(child: DIcon(DIcons.globe, size: 16))]
          : const [],
    ),
    content: DComboboxContent(
      width: inputGroup ? 240 : 280,
      alignOffset: inputGroup ? -28 : 0,
      children: const [
        DComboboxEmpty<String>(child: Text('No timezones found.')),
        DComboboxList<String>(),
      ],
    ),
  );
}

class _CustomItemsCombobox extends StatelessWidget {
  const _CustomItemsCombobox();

  @override
  Widget build(BuildContext context) => DCombobox<String>(
    options: _countries,
    anchor: const DComboboxInput<String>(placeholder: 'Search countries...'),
    content: DComboboxContent(
      children: [
        const DComboboxEmpty<String>(child: Text('No countries found.')),
        DComboboxList<String>(
          itemBuilder: (context, option) => DItem(
            size: DItemSize.xs,
            padding: EdgeInsets.zero,
            children: [
              DItemContent(
                children: [
                  DItemTitle(child: Text(option.label)),
                  DItemDescription(
                    child: Text(
                      option.searchText!.split(' ').skip(1).join(' '),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PopupCombobox extends StatelessWidget {
  const _PopupCombobox();

  @override
  Widget build(BuildContext context) => DCombobox<String>(
    initialValue: 'ca',
    options: _countries,
    anchor: DComboboxTrigger<String>(
      builder: (context, trigger) => DButton(
        label: const DComboboxValue<String>(placeholder: 'Select country'),
        variant: DButtonVariant.outline,
        focusNode: trigger.focusNode,
        expanded: trigger.open,
        hasPopup: true,
        onPressed: trigger.toggle,
      ),
    ),
    content: const DComboboxContent(
      children: [
        Padding(
          padding: EdgeInsets.all(4),
          child: DComboboxInput<String>(
            placeholder: 'Search',
            registerAsAnchor: false,
            showTrigger: false,
          ),
        ),
        DComboboxEmpty<String>(child: Text('No items found.')),
        DComboboxList<String>(),
      ],
    ),
  );
}

class _RtlCombobox extends StatelessWidget {
  const _RtlCombobox();

  static const categories = [
    DComboboxOption(value: 'technology', label: 'التكنولوجيا'),
    DComboboxOption(value: 'design', label: 'التصميم'),
    DComboboxOption(value: 'business', label: 'الأعمال'),
    DComboboxOption(value: 'marketing', label: 'التسويق'),
    DComboboxOption(value: 'education', label: 'التعليم'),
    DComboboxOption(value: 'health', label: 'الصحة'),
  ];

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('الفئات'),
        const SizedBox(height: 8),
        DCombobox<String>.multiple(
          initialValue: const ['technology'],
          options: categories,
          autoHighlight: true,
          anchor: const DComboboxChips<String>(
            input: DComboboxChipsInput<String>(placeholder: 'أضف فئات'),
          ),
          content: const DComboboxContent(
            children: [
              DComboboxEmpty<String>(child: Text('لم يتم العثور على فئات.')),
              DComboboxList<String>(),
            ],
          ),
        ),
      ],
    ),
  );
}
