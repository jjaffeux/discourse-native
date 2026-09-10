import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';
import 'button_reference_icons.dart';

final buttonGroupExamples = ComponentExamples(
  topLevelExampleIndex: 11,
  description:
      'A joined container for independent actions, fields, and passive text.',
  status: ComponentStatus.implemented,
  notes:
      'The frozen Base UI markdown hash is '
      '9118d89c3e715a7e77ec0454be6a276c24d114c8b3099505bb463487e9545eda. '
      'DButtonGroup reproduces the direct-child radius and leading-border rules, '
      'horizontal/vertical orientation, nested boundaries, group semantics, '
      'separators and rich passive text. Children retain independent Tab stops, '
      'callbacks, focus, disabled/invalid state, and screen-reader roles; use '
      'Toggle Group for mutually exclusive or toggled state. '
      'DButtonGroupExpanded is the explicit Flutter flex adaptation for a field '
      'inside a finite-width group. Field, Input Group, Dropdown Menu, Select, '
      'and Popover use their public component APIs. Group scoping applies only '
      'to composed controls and never themes detached overlay descendants.',
  examples: [
    StyleguideExample(
      title: 'Composition and independent actions',
      description:
          'Archive, report and snooze are separate actions. Tab visits each one; '
          'this is intentionally not a Toggle Group or toolbar.',
      states: const ['Group semantics', 'Independent actions', 'Disabled'],
      code: '''DButtonGroup(
  semanticLabel: 'Message actions',
  children: [
    DButton(variant: DButtonVariant.outline, onPressed: archive,
      label: const Text('Archive')),
    DButton(variant: DButtonVariant.outline, onPressed: report,
      label: const Text('Report')),
    DButton(variant: DButtonVariant.outline, onPressed: null,
      label: const Text('Snooze')),
  ],
)''',
      builder: (_) => const _ActionGroup(),
    ),
    StyleguideExample(
      title: 'Orientation',
      description:
          'The vertical group keeps one outside radius and horizontal joins. '
          'Icon actions expose their own labels and 48px touch targets.',
      states: const ['Vertical', 'Icon only', 'Keyboard', 'Touch'],
      code: '''DButtonGroup(
  orientation: DButtonGroupOrientation.vertical,
  semanticLabel: 'Zoom controls',
  children: [
    DButton.iconOnly(icon: Icon(Icons.add), tooltip: 'Zoom in', onPressed: zoomIn),
    DButton.iconOnly(icon: Icon(Icons.remove), tooltip: 'Zoom out', onPressed: zoomOut),
  ],
)''',
      builder: (_) => const _OrientationGroup(),
    ),
    StyleguideExample(
      title: 'Sizes',
      description:
          'Small, default and large groups combine text and icon sizes without '
          'inflating desktop artwork.',
      states: const ['Small', 'Default', 'Large', 'Mixed icon size'],
      code: '''DButtonGroup(children: [
  DButton(size: DButtonSize.small, label: Text('Small'), onPressed: action),
  DButton.iconOnly(size: DButtonSize.small, icon: Icon(Icons.add),
    tooltip: 'Add', onPressed: action),
])''',
      builder: (_) => const _SizeGroups(),
    ),
    StyleguideExample(
      title: 'Nested groups',
      description:
          'The outer group spaces its nested groups by 8px. Each nested group '
          'owns its children, so the attachment button and the composer keep '
          'their complete rounded outlines.',
      states: const ['Nested', '8px gap', 'Input Group', 'Tooltip trigger'],
      code: '''SizedBox(
  width: 252,
  child: DButtonGroup(
    mainAxisSize: MainAxisSize.max,
    children: [
      DButtonGroup(children: [addButton]),
      DButtonGroupExpanded(
        child: DButtonGroup(
          mainAxisSize: MainAxisSize.max,
          children: [
            DButtonGroupExpanded(
              child: DInputGroup(children: [
                DInputGroupInput(hintText: 'Send a message...'),
                DInputGroupAddon(
                  alignment: DInputGroupAddonAlignment.inlineEnd,
                  child: DInputGroupButton.icon(
                    icon: Icon(Icons.graphic_eq),
                    tooltip: 'Voice mode',
                    onPressed: enableVoice,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    ],
  ),
)''',
      builder: (_) => const _NestedGroup(),
    ),
    StyleguideExample(
      title: 'Separator and split action',
      description:
          'Secondary controls use an explicit vertical separator. Each side has '
          'its own activation and semantics.',
      states: const ['Secondary', 'Separator', 'Split'],
      code: '''DButtonGroup(children: [
  DButton(variant: DButtonVariant.secondary, label: Text('Create'), onPressed: create),
  DButtonGroupSeparator(),
  DButton.iconOnly(variant: DButtonVariant.secondary, icon: Icon(Icons.add),
    tooltip: 'Create another', onPressed: createAnother),
])''',
      builder: (_) => const _SplitGroup(),
    ),
    StyleguideExample(
      title: 'Input',
      description:
          'The documented composition contains only the editable input and its '
          'trailing outline action, joined at one shared seam.',
      states: const ['Input', 'Expanded input', 'Icon action'],
      code: '''SizedBox(
  width: 229,
  child: DButtonGroup(
    mainAxisSize: MainAxisSize.max,
    children: [
      DButtonGroupExpanded(child: DInput(hintText: 'Search...')),
      DButton.iconOnly(
        variant: DButtonVariant.outline,
        icon: Icon(Icons.search),
        tooltip: 'Search',
        onPressed: search,
      ),
    ],
  ),
)''',
      builder: (_) => const _InputFixture(),
    ),
    StyleguideExample(
      title: 'Input Group composition',
      description:
          'Two nested groups preserve the attachment and composer as complete '
          'rounded surfaces with an 8px gap. The public DInputGroup owns the '
          'field and voice action surface.',
      states: const [
        'Nested groups',
        '8px gap',
        'Input Group API',
        'Voice state',
        'State retention',
      ],
      code: '''
DButtonGroup(children: [
  DButtonGroup(children: [
    DButton.iconOnly(icon: Icon(Icons.add), tooltip: 'Add attachment', onPressed: add),
  ]),
  DButtonGroupExpanded(
    child: DButtonGroup(mainAxisSize: MainAxisSize.max, children: [
      DButtonGroupExpanded(
        child: DInputGroup(children: [
          DInputGroupInput(hintText: 'Send a message...'),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupButton.icon(
              icon: Icon(Icons.graphic_eq),
              tooltip: 'Enable voice mode',
              onPressed: toggleVoice,
            ),
          ),
        ]),
      ),
    ]),
  ),
])''',
      builder: (_) => const _VoiceFixture(),
    ),
    StyleguideExample(
      title: 'Dropdown menu',
      description:
          'The public Dropdown Menu owns keyboard navigation, dismissal and '
          'focus restoration while its DButton trigger keeps the joined edge.',
      states: const ['Split trigger', 'Keyboard menu', 'Destructive item'],
      code: '''DButtonGroup(children: [
  DButton(label: Text('Follow'), onPressed: follow),
  DDropdownMenu(
    content: DDropdownMenuContent(children: followActions),
    child: DDropdownMenuTrigger(builder: (_, state) => DButton.iconOnly(
      hasPopup: true, expanded: state.open, focusNode: state.focusNode,
      tooltip: 'More follow actions', icon: Icon(Icons.keyboard_arrow_down),
      onPressed: state.toggle)),
  ),
])''',
      builder: (_) => const _MenuFixture(),
    ),
    StyleguideExample(
      title: 'Select composition',
      description:
          'The public Select is the sole joined currency trigger. Its popup '
          'keeps independent overlay geometry while amount editing is retained.',
      states: const ['Rich Select', 'Controlled value', 'Numeric input'],
      code: '''DButtonGroup(children: [
  DSelect(value: currency, entries: currencies, onChanged: setCurrency),
  DButtonGroupExpanded(child: DInput(keyboardType: TextInputType.number)),
  DButton.iconOnly(icon: Icon(Icons.arrow_forward), tooltip: 'Send payment',
    onPressed: send),
])''',
      builder: (_) => const _CurrencyFixture(),
    ),
    StyleguideExample(
      title: 'Popover composition',
      description:
          'The Copilot split trigger opens the library Popover without network '
          'work. Popup content stays outside the joined control geometry.',
      states: const ['Popover', 'Anchored content', 'Focus restoration'],
      code: '''DButtonGroup(children: [
  DButton(label: Text('Copilot'), onPressed: startCopilot),
  DPopover(
    child: DPopoverTrigger(builder: (_, state) =>
      DButton.iconOnly(
        hasPopup: true,
        expanded: state.open,
        tooltip: 'Open Copilot task form',
        icon: Icon(Icons.keyboard_arrow_down),
        onPressed: state.toggle,
      ),
    ),
    content: DPopoverContent(child: taskForm),
  ),
])''',
      builder: (_) => const _PopoverFixture(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Directional child order and logical outside corners mirror while '
          'Arabic labels, callbacks and menu alignment remain intact.',
      states: const ['RTL', 'Directional corners', 'Arabic'],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DButtonGroup(semanticLabel: 'إجراءات الرسالة', children: actions),
)''',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _ActionGroup(arabic: true),
      ),
    ),
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical responsive nested action groups with a complete More Options menu.',
      states: const [
        'Nested groups',
        'Responsive',
        'Dropdown',
        'Radio submenu',
      ],
      code: '''DButtonGroup(children: [
  if (wide)
    DButtonGroup(children: [
      DButton.iconOnly(
        tooltip: 'Go Back',
        icon: ButtonReferenceIcon(ButtonReferenceIcon.arrowLeft),
        variant: DButtonVariant.outline,
        onPressed: goBack,
      ),
    ]),
  DButtonGroup(children: [
    DButton(label: Text('Archive'), variant: DButtonVariant.outline, onPressed: archive),
    DButton(label: Text('Report'), variant: DButtonVariant.outline, onPressed: report),
  ]),
  DButtonGroup(children: [
    DButton(label: Text('Snooze'), variant: DButtonVariant.outline, onPressed: snooze),
    moreOptionsMenu,
  ]),
])''',
      builder: (_) => const _ButtonGroupReferenceDemo(),
    ),
  ],
);

class _ButtonGroupReferenceDemo extends StatefulWidget {
  const _ButtonGroupReferenceDemo();

  @override
  State<_ButtonGroupReferenceDemo> createState() =>
      _ButtonGroupReferenceDemoState();
}

class _ButtonGroupReferenceDemoState extends State<_ButtonGroupReferenceDemo> {
  String _label = 'personal';
  String _status = '';

  void _select(String value) => setState(() => _status = value);

  DDropdownMenuItem _item(
    String label,
    String icon, {
    bool destructive = false,
  }) => DDropdownMenuItem(
    leading: ButtonReferenceIcon(icon),
    variant: destructive
        ? DDropdownMenuItemVariant.destructive
        : DDropdownMenuItemVariant.standard,
    onPressed: () => _select(label),
    child: Text(label),
  );

  Widget _moreMenu() => DDropdownMenu(
    content: DDropdownMenuContent(
      width: 160,
      align: DPopoverAlign.end,
      children: [
        DDropdownMenuGroup(
          children: [
            _item('Mark as Read', ButtonReferenceIcon.mailCheck),
            _item('Archive', ButtonReferenceIcon.archive),
          ],
        ),
        const DDropdownMenuSeparator(),
        DDropdownMenuGroup(
          children: [
            _item('Snooze', ButtonReferenceIcon.clock),
            _item('Add to Calendar', ButtonReferenceIcon.calendarPlus),
            _item('Add to List', ButtonReferenceIcon.listFilter),
            DDropdownMenuSub(
              leading: const ButtonReferenceIcon(ButtonReferenceIcon.tag),
              trigger: const Text('Label As...'),
              children: [
                DDropdownMenuRadioGroup<String>(
                  value: _label,
                  onChanged: (value) => setState(() => _label = value),
                  children: const [
                    DDropdownMenuRadioItem(
                      value: 'personal',
                      child: Text('Personal'),
                    ),
                    DDropdownMenuRadioItem(value: 'work', child: Text('Work')),
                    DDropdownMenuRadioItem(
                      value: 'other',
                      child: Text('Other'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const DDropdownMenuSeparator(),
        DDropdownMenuGroup(
          children: [
            _item('Trash', ButtonReferenceIcon.trash2, destructive: true),
          ],
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, menu) => DButton.iconOnly(
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.ellipsis),
        tooltip: 'More Options',
        variant: DButtonVariant.outline,
        hasPopup: true,
        expanded: menu.open,
        focusNode: menu.focusNode,
        onPressed: menu.toggle,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DButtonGroup(
            children: [
              if (constraints.maxWidth >= 640)
                DButtonGroup(
                  children: [
                    DButton.iconOnly(
                      icon: const ButtonReferenceIcon(
                        ButtonReferenceIcon.arrowLeft,
                      ),
                      tooltip: 'Go Back',
                      variant: DButtonVariant.outline,
                      onPressed: () => _select('Go Back'),
                    ),
                  ],
                ),
              DButtonGroup(
                children: [
                  DButton(
                    label: const Text('Archive'),
                    variant: DButtonVariant.outline,
                    onPressed: () => _select('Archive'),
                  ),
                  DButton(
                    label: const Text('Report'),
                    variant: DButtonVariant.outline,
                    onPressed: () => _select('Report'),
                  ),
                ],
              ),
              DButtonGroup(
                children: [
                  DButton(
                    label: const Text('Snooze'),
                    variant: DButtonVariant.outline,
                    onPressed: () => _select('Snooze'),
                  ),
                  _moreMenu(),
                ],
              ),
            ],
          ),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: DSpacing.md),
          Semantics(liveRegion: true, child: Text(_status)),
        ],
      ],
    ),
  );
}

class _ActionGroup extends StatefulWidget {
  const _ActionGroup({this.arabic = false});
  final bool arabic;
  @override
  State<_ActionGroup> createState() => _ActionGroupState();
}

class _ActionGroupState extends State<_ActionGroup> {
  String _last = 'No action yet';
  void _set(String value) => setState(() => _last = value);
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DButtonGroup(
          semanticLabel: widget.arabic ? 'إجراءات الرسالة' : 'Message actions',
          children: [
            DButton(
              variant: DButtonVariant.outline,
              label: Text(widget.arabic ? 'أرشفة' : 'Archive'),
              onPressed: () => _set(widget.arabic ? 'تمت الأرشفة' : 'Archived'),
            ),
            DButton(
              variant: DButtonVariant.outline,
              label: Text(widget.arabic ? 'تقرير' : 'Report'),
              onPressed: () => _set(widget.arabic ? 'تم التقرير' : 'Reported'),
            ),
            DButton(
              variant: DButtonVariant.outline,
              label: Text(widget.arabic ? 'تأجيل' : 'Snooze'),
              onPressed: null,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(_last),
    ],
  );
}

class _OrientationGroup extends StatelessWidget {
  const _OrientationGroup();
  @override
  Widget build(BuildContext context) => DButtonGroup(
    orientation: DButtonGroupOrientation.vertical,
    semanticLabel: 'Zoom controls',
    children: [
      DButton.iconOnly(
        variant: DButtonVariant.outline,
        icon: const Icon(Icons.add),
        tooltip: 'Zoom in',
        onPressed: () {},
      ),
      DButton.iconOnly(
        variant: DButtonVariant.outline,
        icon: const Icon(Icons.remove),
        tooltip: 'Zoom out',
        onPressed: () {},
      ),
    ],
  );
}

class _SizeGroups extends StatelessWidget {
  const _SizeGroups();
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in const [
          ('Small', DButtonSize.small),
          ('Default', DButtonSize.regular),
          ('Large', DButtonSize.large),
        ]) ...[
          DButtonGroup(
            children: [
              for (final label in [entry.$1, 'Button', 'Group'])
                DButton(
                  variant: DButtonVariant.outline,
                  size: entry.$2,
                  label: Text(label),
                  onPressed: () {},
                ),
              DButton.iconOnly(
                variant: DButtonVariant.outline,
                size: entry.$2,
                icon: const Icon(Icons.add),
                tooltip: 'Add ${entry.$1.toLowerCase()}',
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}

class _NestedGroup extends StatelessWidget {
  const _NestedGroup();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 252,
    child: DButtonGroup(
      mainAxisSize: MainAxisSize.max,
      semanticLabel: 'Message composer actions',
      children: [
        DButtonGroup(
          children: [
            DButton.iconOnly(
              variant: DButtonVariant.outline,
              icon: const Icon(Icons.add),
              tooltip: 'Add attachment',
              onPressed: () {},
            ),
          ],
        ),
        DButtonGroupExpanded(
          child: DButtonGroup(
            mainAxisSize: MainAxisSize.max,
            children: [
              DButtonGroupExpanded(
                child: DInputGroup(
                  semanticLabel: 'Message composer',
                  children: [
                    DInputGroupInput(hintText: 'Send a message...'),
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DInputGroupButton.icon(
                        icon: const Icon(Icons.graphic_eq),
                        tooltip: 'Voice mode',
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SplitGroup extends StatelessWidget {
  const _SplitGroup();
  @override
  Widget build(BuildContext context) => DButtonGroup(
    semanticLabel: 'Create actions',
    children: [
      DButton(
        variant: DButtonVariant.secondary,
        label: const Text('Create'),
        onPressed: () {},
      ),
      const DButtonGroupSeparator(),
      DButton.iconOnly(
        variant: DButtonVariant.secondary,
        icon: const Icon(Icons.add),
        tooltip: 'Create another',
        onPressed: () {},
      ),
    ],
  );
}

class _InputFixture extends StatelessWidget {
  const _InputFixture();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 229,
    child: DButtonGroup(
      mainAxisSize: MainAxisSize.max,
      semanticLabel: 'Search controls',
      children: [
        DButtonGroupExpanded(
          child: DInput(semanticLabel: 'Search', hintText: 'Search...'),
        ),
        DButton.iconOnly(
          variant: DButtonVariant.outline,
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () {},
        ),
      ],
    ),
  );
}

class _VoiceFixture extends StatefulWidget {
  const _VoiceFixture();
  @override
  State<_VoiceFixture> createState() => _VoiceFixtureState();
}

class _VoiceFixtureState extends State<_VoiceFixture> {
  bool _voice = false;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    child: DButtonGroup(
      mainAxisSize: MainAxisSize.max,
      children: [
        DButtonGroup(
          children: [
            DButton.iconOnly(
              variant: DButtonVariant.outline,
              icon: const Icon(Icons.add),
              tooltip: 'Add attachment',
              onPressed: () {},
            ),
          ],
        ),
        DButtonGroupExpanded(
          child: DButtonGroup(
            mainAxisSize: MainAxisSize.max,
            children: [
              DButtonGroupExpanded(
                child: DInputGroup(
                  semanticLabel: 'Message composer',
                  children: [
                    DInputGroupInput(
                      hintText: _voice
                          ? 'Record and send audio...'
                          : 'Send a message...',
                      enabled: !_voice,
                    ),
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DInputGroupButton.icon(
                        variant: _voice
                            ? DButtonVariant.secondary
                            : DButtonVariant.ghost,
                        icon: const Icon(Icons.graphic_eq),
                        tooltip: _voice
                            ? 'Disable voice mode'
                            : 'Enable voice mode',
                        onPressed: () => setState(() => _voice = !_voice),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MenuFixture extends StatelessWidget {
  const _MenuFixture();
  @override
  Widget build(BuildContext context) => DButtonGroup(
    semanticLabel: 'Follow actions',
    children: [
      DButton(
        variant: DButtonVariant.outline,
        label: const Text('Follow'),
        onPressed: () {},
      ),
      DDropdownMenu(
        content: DDropdownMenuContent(
          semanticLabel: 'More follow actions',
          children: [
            DDropdownMenuItem(
              onPressed: () {},
              child: const Text('Mute conversation'),
            ),
            DDropdownMenuItem(
              onPressed: () {},
              child: const Text('Mark as read'),
            ),
            DDropdownMenuItem(
              onPressed: () {},
              child: const Text('Report conversation'),
            ),
            DDropdownMenuItem(
              variant: DDropdownMenuItemVariant.destructive,
              onPressed: () {},
              child: const Text('Delete conversation'),
            ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton.iconOnly(
            variant: DButtonVariant.outline,
            hasPopup: true,
            expanded: state.open,
            focusNode: state.focusNode,
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'More follow actions',
            onPressed: state.toggle,
          ),
        ),
      ),
    ],
  );
}

class _CurrencyFixture extends StatefulWidget {
  const _CurrencyFixture();
  @override
  State<_CurrencyFixture> createState() => _CurrencyFixtureState();
}

class _CurrencyFixtureState extends State<_CurrencyFixture> {
  String _currency = 'usd';
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: DButtonGroup(
      mainAxisSize: MainAxisSize.max,
      semanticLabel: 'Payment',
      children: [
        DSelect<String>(
          value: _currency,
          width: 76,
          semanticLabel: 'Currency',
          entries: const [
            DSelectOption(value: 'usd', label: r'$', child: Text(r'$')),
            DSelectOption(value: 'eur', label: '€', child: Text('€')),
            DSelectOption(value: 'gbp', label: '£', child: Text('£')),
          ],
          onChanged: (currency) {
            if (currency != null) setState(() => _currency = currency);
          },
        ),
        DButtonGroupExpanded(
          child: DInput(
            hintText: '10.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        DButton.iconOnly(
          variant: DButtonVariant.outline,
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'Send payment',
          onPressed: () {},
        ),
      ],
    ),
  );
}

class _PopoverFixture extends StatelessWidget {
  const _PopoverFixture();
  @override
  Widget build(BuildContext context) => DButtonGroup(
    semanticLabel: 'Copilot actions',
    children: [
      DButton(
        variant: DButtonVariant.outline,
        icon: const Icon(Icons.smart_toy_outlined),
        label: const Text('Copilot'),
        onPressed: () {},
      ),
      DPopover(
        content: const DPopoverContent(
          semanticLabel: 'Copilot task form',
          child: DPopoverHeader(
            children: [
              DPopoverTitle(child: Text('Start a new task with Copilot')),
              DPopoverDescription(
                child: Text('Describe your task in natural language.'),
              ),
            ],
          ),
        ),
        child: DPopoverTrigger(
          builder: (context, state) => DButton.iconOnly(
            variant: DButtonVariant.outline,
            hasPopup: true,
            expanded: state.open,
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'Open Copilot task form',
            focusNode: state.focusNode,
            onPressed: state.toggle,
          ),
        ),
      ),
    ],
  );
}
