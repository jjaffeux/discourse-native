import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final buttonGroupExamples = ComponentExamples(
  description:
      'A joined container for independent actions, fields, and passive text.',
  status: ComponentStatus.baseline,
  notes:
      'The frozen Base UI markdown hash is '
      '9118d89c3e715a7e77ec0454be6a276c24d114c8b3099505bb463487e9545eda. '
      'DButtonGroup reproduces the direct-child radius and leading-border rules, '
      'horizontal/vertical orientation, nested boundaries, group semantics, '
      'separators and rich passive text. Children retain independent Tab stops, '
      'callbacks, focus, disabled/invalid state, and screen-reader roles; use '
      'Toggle Group for mutually exclusive or toggled state. '
      'DButtonGroupExpanded is the explicit Flutter flex adaptation for a field '
      'inside a finite-width group. Menus below use MenuAnchor only as a local, '
      'request-free behavior fixture. Input Group, library Dropdown Menu, rich '
      'Select, and Popover examples are composition-ready but remain final review '
      'follow-ups until their owning components merge; Native Select is not used '
      'as a substitute. Group scoping applies only to the composed trigger and '
      'does not theme overlay descendants.',
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
          'Each direct nested group owns only its children. The outer group does '
          'not leak radius changes into a tooltip or menu overlay.',
      states: const ['Nested', 'Scoped edges', 'Tooltip trigger'],
      code: '''DButtonGroup(children: [
  DButtonGroup(children: [addButton]),
  DButtonGroup(children: [messageInput, voiceButton]),
])''',
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
      title: 'Input and text',
      description:
          'The editable field takes the remaining finite width. Rich group text '
          'is passive, and validation remains owned by DInput.',
      states: const ['Input', 'Expanded field', 'Rich text', 'Invalid'],
      code: '''SizedBox(width: 360, child: DButtonGroup(
  mainAxisSize: MainAxisSize.max,
  children: [
    DButtonGroupText(child: Text('Search')),
    DButtonGroupExpanded(child: DInput(invalid: invalid)),
    DButton.iconOnly(icon: Icon(Icons.search), tooltip: 'Search', onPressed: search),
  ],
))''',
      builder: (_) => const _InputGroup(),
    ),
    StyleguideExample(
      title: 'Input Group composition',
      description:
          'The public DInputGroup owns the nested field and voice action surface '
          'while Button Group owns the outside join.',
      states: const ['Input Group API', 'Voice state', 'State retention'],
      code: '''
DButtonGroup(children: [
  DButton.iconOnly(icon: Icon(Icons.add), tooltip: 'Add attachment', onPressed: add),
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
])''',
      builder: (_) => const _VoiceFixture(),
    ),
    StyleguideExample(
      title: 'Dropdown menu',
      description:
          'A keyboard-operable local MenuAnchor validates the split trigger. '
          'Final review swaps in the library Dropdown Menu without changing '
          'DButtonGroup.',
      states: const ['Split trigger', 'Keyboard menu', 'Destructive item'],
      code: '''DButtonGroup(children: [
  DButton(label: Text('Follow'), onPressed: follow),
  MenuAnchor(builder: (_, menu, __) => DButton.iconOnly(
    hasPopup: true, expanded: menu.isOpen, tooltip: 'More follow actions',
    icon: Icon(Icons.keyboard_arrow_down), onPressed: menu.open),
    menuChildren: followActions),
])''',
      builder: (_) => const _MenuFixture(),
    ),
    StyleguideExample(
      title: 'Rich Select composition handoff',
      description:
          'The joined currency trigger, amount field and send action are ready '
          'for the rich Select owner. Native Select is deliberately not used as '
          'a substitute; the local menu only exercises state and geometry.',
      states: const [
        'Pending rich Select owner',
        'Controlled value',
        'Numeric input',
      ],
      code:
          '''// Replace currencyMenu with DSelect when the rich Select owner merges.
DButtonGroup(children: [currencyMenu, amountInput, sendButton])''',
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
  ],
);

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
    width: 360,
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
                child: DInput(hintText: 'Send a message...'),
              ),
              DButton.iconOnly(
                variant: DButtonVariant.outline,
                icon: const Icon(Icons.graphic_eq),
                tooltip: 'Voice mode',
                onPressed: () {},
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

class _InputGroup extends StatefulWidget {
  const _InputGroup();
  @override
  State<_InputGroup> createState() => _InputGroupState();
}

class _InputGroupState extends State<_InputGroup> {
  bool _invalid = false;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    child: DButtonGroup(
      mainAxisSize: MainAxisSize.max,
      semanticLabel: 'Search controls',
      children: [
        const DButtonGroupText(
          semanticLabel: 'Search query',
          child: Icon(Icons.manage_search),
        ),
        DButtonGroupExpanded(
          child: DInput(
            hintText: 'Search...',
            invalid: _invalid,
            onSubmitted: (value) => setState(() => _invalid = value.isEmpty),
          ),
        ),
        DButton.iconOnly(
          variant: DButtonVariant.outline,
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => setState(() => _invalid = !_invalid),
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
        DButton.iconOnly(
          variant: DButtonVariant.outline,
          icon: const Icon(Icons.add),
          tooltip: 'Add attachment',
          onPressed: () {},
        ),
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
                  tooltip: _voice ? 'Disable voice mode' : 'Enable voice mode',
                  onPressed: () => setState(() => _voice = !_voice),
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
      MenuAnchor(
        menuChildren: [
          MenuItemButton(
            onPressed: () {},
            child: const Text('Mute conversation'),
          ),
          MenuItemButton(onPressed: () {}, child: const Text('Mark as read')),
          MenuItemButton(
            onPressed: () {},
            child: const Text('Report conversation'),
          ),
          MenuItemButton(
            onPressed: () {},
            child: const Text('Delete conversation'),
          ),
        ],
        builder: (context, menu, child) => DButton.iconOnly(
          variant: DButtonVariant.outline,
          hasPopup: true,
          expanded: menu.isOpen,
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: 'More follow actions',
          onPressed: menu.isOpen ? menu.close : menu.open,
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
  String _currency = r'$';
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: DButtonGroup(
      mainAxisSize: MainAxisSize.max,
      semanticLabel: 'Payment',
      children: [
        MenuAnchor(
          menuChildren: [
            for (final currency in const [r'$', '€', '£'])
              MenuItemButton(
                onPressed: () => setState(() => _currency = currency),
                child: Text(currency),
              ),
          ],
          builder: (context, menu, child) => DButton(
            variant: DButtonVariant.outline,
            hasPopup: true,
            expanded: menu.isOpen,
            label: Text(_currency),
            onPressed: menu.isOpen ? menu.close : menu.open,
          ),
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
