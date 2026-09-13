import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_native_icons.dart';
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
      'when its target or account changes. Use variant to match an outlined '
      'button group or another action surface. Background, border and interactive '
      'background colors customize only the trigger. These examples save only local state.',
  examples: [
    StyleguideExample(
      title: 'Topic notifications',
      description: 'Choose a level from the labeled topic-footer button.',
      states: const ['Labeled', 'Outline', 'Selection', 'Keyboard'],
      code: '''DNotificationLevelMenu<int>(
  value: level,
  options: topicOptions,
  semanticLabel: 'Topic notifications',
  showLabel: true,
  variant: DButtonVariant.outline,
  onChanged: (value) => setState(() => level = value),
)

// Each option supplies a value, label, description, and icon:
const DNotificationLevelOption(
  value: 1,
  label: 'Normal',
  description: 'Mentions and replies only',
  icon: DIcon(DNativeIcons.bell),
)''',
      builder: (_) => const _NotificationExample(
        showLabel: true,
        variant: DButtonVariant.outline,
      ),
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
      title: 'Matching an action surface',
      description:
          'The trigger uses a custom surface with a subtle border. '
          'The dropdown retains its own colors.',
      states: const ['Custom fill', 'Custom border', 'Hover', 'Focus'],
      code: '''final tokens = DTokens.of(context);
DNotificationLevelMenu<int>(
  value: level, options: topicOptions,
  semanticLabel: 'Topic notifications', showLabel: true,
  variant: DButtonVariant.outline,
  backgroundColor: tokens.surface,
  borderColor: Color.lerp(tokens.surface, tokens.foreground, .12),
  interactiveBackgroundColor: Color.lerp(tokens.surface, tokens.foreground, .06),
  onChanged: (value) => setState(() => level = value),
)''',
      builder: (_) =>
          const _NotificationExample(showLabel: true, customColors: true),
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
    this.variant,
    this.customColors = false,
  });

  final bool showLabel;
  final bool category;
  final bool thread;
  final bool disabled;
  final int initialValue;
  final DButtonVariant? variant;
  final bool customColors;

  @override
  State<_NotificationExample> createState() => _NotificationExampleState();
}

class _NotificationExampleState extends State<_NotificationExample> {
  late int _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final watching = DNotificationLevelOption(
      value: 3,
      label: 'Watching',
      description: widget.category
          ? 'Every new post and unread count'
          : 'Every reply and unread count',
      icon: const DIcon(DNativeIcons.bellRing),
      emphasized: !widget.thread,
    );
    final tracking = DNotificationLevelOption(
      value: 2,
      label: 'Tracking',
      description: widget.thread
          ? 'Mentions and unread reply count'
          : 'Mentions, replies, and unread count',
      icon: const DIcon(DNativeIcons.bell),
      emphasized: !widget.thread,
    );
    final normal = DNotificationLevelOption(
      value: 1,
      label: 'Normal',
      description: widget.thread
          ? 'Mentions only'
          : 'Mentions and replies only',
      icon: const DIcon(DNativeIcons.bell),
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
                  icon: DIcon(DNativeIcons.bellRing),
                  emphasized: true,
                ),
              normal,
              const DNotificationLevelOption(
                value: 0,
                label: 'Muted',
                description: 'No notifications; hidden from Latest',
                icon: DIcon(DNativeIcons.bellOff),
              ),
            ],
      semanticLabel: widget.category
          ? 'Category notifications'
          : widget.thread
          ? 'Thread notifications'
          : 'Topic notifications',
      showLabel: widget.showLabel,
      variant: widget.customColors ? DButtonVariant.outline : widget.variant,
      backgroundColor: widget.customColors ? tokens.surface : null,
      borderColor: widget.customColors
          ? Color.lerp(tokens.surface, tokens.foreground, .12)
          : null,
      interactiveBackgroundColor: widget.customColors
          ? Color.lerp(tokens.surface, tokens.foreground, .06)
          : null,
      size: widget.thread ? DButtonSize.regular : DButtonSize.small,
      onChanged: widget.disabled
          ? null
          : (value) => setState(() => _value = value),
    );
  }
}
