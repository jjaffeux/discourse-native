import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final messageInboxMenuExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Switch between personal and group message inboxes.',
  notes:
      'DMessageInboxMenu composes DButton and a searchable DCombobox. '
      'Typed options provide names, descriptions, and icons. The caller owns '
      'selection, available groups, navigation, and account lifecycle. Change '
      'the widget key when its page or account changes. Long trigger names '
      'truncate, with the full name in the tooltip and accessible label; menu '
      'text wraps and long lists scroll. The selected inbox has a checkmark '
      'and selected semantics. Enter or Space opens and focuses search; typing '
      'filters inbox names, arrows navigate, and Enter selects. Escape dismisses '
      'without changing the inbox and restores button focus. Each opening '
      'starts with an empty search. The popup height is capped with scrolling. '
      'Touch uses the same combobox. These examples change only local state.',
  examples: [
    StyleguideExample(
      title: 'Personal and groups',
      description:
          'Search for a group, select it, then switch back to Personal.',
      states: const ['Search', 'Selection', 'Keyboard', 'Touch'],
      code: '''DMessageInboxMenu<String>(
  value: inbox,
  options: inboxOptions,
  onChanged: (value) => setState(() => inbox = value),
)

// Each option supplies a value, name, description, and icon:
const DMessageInboxOption(
  value: 'personal:',
  label: 'Personal',
  description: 'Private messages sent directly to you',
  icon: DIcon(DIcons.user),
)''',
      builder: (_) => const _InboxExample(),
    ),
    StyleguideExample(
      title: 'Group inbox',
      description: 'A selected group shows its name and group icon.',
      states: const ['Selected group'],
      code: '''DMessageInboxMenu<String>(
  value: 'group:dev-managers',
  options: inboxOptions,
  onChanged: selectInbox,
)''',
      builder: (_) => const _InboxExample(initialValue: 'group:dev-managers'),
    ),
    StyleguideExample(
      title: 'Personal only',
      description:
          'Personal remains available when there are no group inboxes.',
      states: const ['No groups'],
      code: '''DMessageInboxMenu<String>(
  value: 'personal:',
  options: [personalInbox],
  onChanged: selectInbox,
)''',
      builder: (_) => const _InboxExample(groups: []),
    ),
    StyleguideExample(
      title: 'Many groups',
      description:
          'Search for “safety” to find the last group, or scroll the list. '
          'Search for “missing” to see the empty state. Try larger text and RTL.',
      states: const [
        'Search',
        'No matches',
        'Scrolling',
        'Long names',
        'Text scaling',
        'RTL',
      ],
      code: '''ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 240),
  child: DMessageInboxMenu<String>(
    value: inbox,
    options: manyInboxOptions,
    onChanged: selectInbox,
  ),
)''',
      builder: (_) => const _InboxExample(
        initialValue: 'group:engineering-infrastructure-platform-team',
        groups: [
          ..._groups,
          'community',
          'customer-success',
          'design',
          'documentation',
          'engineering-infrastructure-platform-team',
          'marketing',
          'product',
          'support',
          'trust-and-safety',
        ],
      ),
    ),
    StyleguideExample(
      title: 'Disabled',
      description: 'A null callback keeps the current inbox visible and inert.',
      states: const ['Disabled'],
      code: '''DMessageInboxMenu<String>(
  value: inbox,
  options: inboxOptions,
  onChanged: null,
)''',
      builder: (_) => const _InboxExample(enabled: false),
    ),
  ],
);

const _groups = [
  'admins',
  'corporate-card',
  'dev-leads',
  'dev-managers',
  'emea-meetup-2023',
  'engineers-emea',
];

class _InboxExample extends StatefulWidget {
  const _InboxExample({
    this.initialValue = 'personal:',
    this.groups = _groups,
    this.enabled = true,
  });

  final String initialValue;
  final List<String> groups;
  final bool enabled;

  @override
  State<_InboxExample> createState() => _InboxExampleState();
}

class _InboxExampleState extends State<_InboxExample> {
  late String _value = widget.initialValue;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 240),
    child: DMessageInboxMenu<String>(
      value: _value,
      onChanged: widget.enabled
          ? (value) => setState(() => _value = value)
          : null,
      options: [
        const DMessageInboxOption(
          value: 'personal:',
          label: 'Personal',
          description: 'Private messages sent directly to you',
          icon: DIcon(DIcons.user),
        ),
        for (final group in widget.groups)
          DMessageInboxOption(
            value: 'group:$group',
            label: group,
            description: 'Private messages sent to @$group',
            icon: const DIcon(DIcons.users),
          ),
      ],
    ),
  );
}
