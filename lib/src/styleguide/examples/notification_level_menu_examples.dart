import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final notificationLevelMenuExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A notification button with a descriptive selection dropdown.',
  notes:
      'DNotificationLevelMenu composes DButton and DDropdownMenu radio items. '
      'It accepts typed values, descriptions, and icon widgets; saving and '
      'account ownership stay with the caller. The selected level has a '
      'checkmark and checked semantics. Both trigger styles announce the current '
      'level. Enter or Space opens the menu; arrows, Home, End, and typeahead '
      'navigate; Escape dismisses and returns focus. Touch uses the same '
      'dropdown with scrolling and collision handling. Change the widget key '
      'when its target or account changes. These examples save only local state.',
  examples: [
    StyleguideExample(
      title: 'Topic notifications',
      description: 'Choose a level from the labeled topic-footer button.',
      states: const ['Labeled', 'Selection', 'Keyboard'],
      code: '''DNotificationLevelMenu<int>(
  value: level,
  options: topicOptions,
  semanticLabel: 'Topic notifications',
  showLabel: true,
  onChanged: (value) => setState(() => level = value),
)

// Each option supplies a value, label, description, and icon:
const DNotificationLevelOption(
  value: 1,
  label: 'Normal',
  description: 'Mentions and replies only',
  icon: DIcon(DIcons.farBell),
)''',
      builder: (_) => const _NotificationExample(showLabel: true),
    ),
    StyleguideExample(
      title: 'Icon trigger',
      description: 'The toolbar bell highlights Watching and Tracking.',
      states: const ['Icon only', 'Emphasized', 'Tooltip'],
      code: '''DNotificationLevelMenu<int>(
  value: level, options: topicOptions,
  semanticLabel: 'Topic notifications',
  onChanged: (value) => setState(() => level = value),
)
// Use emphasized: true on active subscription options.''',
      builder: (_) => const _NotificationExample(initialValue: 3),
    ),
    StyleguideExample(
      title: 'Category notifications',
      description: 'Category choices also include Watching First Post.',
      states: const ['Five levels', 'Icon only'],
      code: '''DNotificationLevelMenu<int>(
  value: level, options: categoryOptions,
  semanticLabel: 'Category notifications',
  onChanged: (value) => setState(() => level = value),
)''',
      builder: (_) => const _NotificationExample(category: true),
    ),
    StyleguideExample(
      title: 'Thread notifications',
      description: 'Chat threads offer Normal, Tracking, and Watching.',
      states: const ['Three levels', 'Icon only'],
      code: '''DNotificationLevelMenu<int>(
  value: level, options: threadOptions,
  semanticLabel: 'Thread notifications', size: DButtonSize.regular,
  onChanged: (value) => setState(() => level = value),
)''',
      builder: (_) => const _NotificationExample(thread: true),
    ),
    StyleguideExample(
      title: 'Disabled',
      description:
          'Both triggers remain readable while editing is unavailable.',
      states: const ['Disabled', 'Labeled', 'Icon only'],
      code: '''DNotificationLevelMenu<int>(
  value: level, options: topicOptions,
  semanticLabel: 'Topic notifications',
  showLabel: true, onChanged: null,
)''',
      builder: (_) => const Wrap(
        spacing: DSpacing.md,
        runSpacing: DSpacing.md,
        children: [
          _NotificationExample(disabled: true, showLabel: true),
          _NotificationExample(disabled: true),
        ],
      ),
    ),
  ],
);

class _NotificationExample extends StatefulWidget {
  const _NotificationExample({
    this.showLabel = false,
    this.category = false,
    this.thread = false,
    this.disabled = false,
    this.initialValue = 1,
  });

  final bool showLabel;
  final bool category;
  final bool thread;
  final bool disabled;
  final int initialValue;

  @override
  State<_NotificationExample> createState() => _NotificationExampleState();
}

class _NotificationExampleState extends State<_NotificationExample> {
  late int _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    final watching = DNotificationLevelOption(
      value: 3,
      label: 'Watching',
      description: widget.category
          ? 'Every new post and unread count'
          : 'Every reply and unread count',
      icon: const DIcon(DIcons.discourseBellExclamation),
      emphasized: !widget.thread,
    );
    final tracking = DNotificationLevelOption(
      value: 2,
      label: 'Tracking',
      description: widget.thread
          ? 'Mentions and unread reply count'
          : 'Mentions, replies, and unread count',
      icon: const DIcon(DIcons.bell),
      emphasized: !widget.thread,
    );
    final normal = DNotificationLevelOption(
      value: 1,
      label: 'Normal',
      description: widget.thread
          ? 'Mentions only'
          : 'Mentions and replies only',
      icon: const DIcon(DIcons.farBell),
    );
    return DNotificationLevelMenu<int>(
      value: _value,
      options: widget.thread
          ? [normal, tracking, watching]
          : [
              watching,
              tracking,
              if (widget.category)
                const DNotificationLevelOption(
                  value: 4,
                  label: 'Watching First Post',
                  description: 'New topics only',
                  icon: DIcon(DIcons.discourseBellExclamation),
                  emphasized: true,
                ),
              normal,
              const DNotificationLevelOption(
                value: 0,
                label: 'Muted',
                description: 'No notifications; hidden from Latest',
                icon: DIcon(DIcons.discourseBellSlash),
              ),
            ],
      semanticLabel: widget.category
          ? 'Category notifications'
          : widget.thread
          ? 'Thread notifications'
          : 'Topic notifications',
      showLabel: widget.showLabel,
      size: widget.thread ? DButtonSize.regular : DButtonSize.small,
      onChanged: widget.disabled
          ? null
          : (value) => setState(() => _value = value),
    );
  }
}
