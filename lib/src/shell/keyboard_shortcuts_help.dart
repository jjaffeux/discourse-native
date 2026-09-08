import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import 'shell_sheet.dart';

Future<void> showKeyboardShortcuts(BuildContext context) async {
  await showShellSheet<void>(
    context: context,
    title: 'Keyboard shortcuts',
    dialogOnDesktop: true,
    builder: (context) => SingleChildScrollView(
      key: const ValueKey('keyboard-shortcuts-help'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Shift+J and Shift+K select topics without opening them. '
            'J and K move through posts in the open topic. '
            'When no topic is open, J and K select topics in the list. '
            'Navigation shortcuts pause while you type or use a menu.',
          ),
          const SizedBox(height: 16),
          for (final command in ReadingCommand.values)
            _ShortcutRow(
              label: command.label,
              shortcuts: [
                for (final shortcut in command.shortcuts)
                  if (shortcut is! SingleActivator ||
                      shortcut.trigger != LogicalKeyboardKey.numpadEnter)
                    shortcut,
              ],
            ),
          const DSeparator(),
          _ShortcutRow(
            label: 'Back in current tab',
            shortcuts: [contentBackShortcutForPlatform(defaultTargetPlatform)],
          ),
          _ShortcutRow(
            label: 'Forward in current tab',
            shortcuts: [
              contentForwardShortcutForPlatform(defaultTargetPlatform),
            ],
          ),
          _ShortcutRow(
            label: 'Refresh current tab',
            shortcuts: [refreshTabShortcutForPlatform(defaultTargetPlatform)],
          ),
          const _ShortcutRow(label: 'New topic', shortcuts: [newTopicShortcut]),
          const _ShortcutRow(
            label: 'Reply to topic',
            shortcuts: [topicReplyShortcut],
          ),
          _ShortcutRow(
            label: 'Submit composer',
            shortcuts: [
              primaryShortcutForPlatform(
                defaultTargetPlatform,
                LogicalKeyboardKey.enter,
              ),
            ],
          ),
          const _ShortcutRow(
            label: 'Close composer',
            shortcuts: [SingleActivator(LogicalKeyboardKey.escape)],
          ),
          _ShortcutRow(
            label: 'Search',
            shortcuts: [
              primaryShortcutForPlatform(
                defaultTargetPlatform,
                LogicalKeyboardKey.keyF,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.shortcuts});

  final String label;
  final List<ShortcutActivator> shortcuts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: Text(label)),
        const SizedBox(width: 16),
        Flexible(
          flex: 2,
          child: DKbdGroup(
            spacing: DSpacing.sm,
            children: [
              for (var i = 0; i < shortcuts.length; i++) ...[
                if (i > 0) const Text('or'),
                if (shortcuts[i] case final SingleActivator shortcut)
                  DShortcutKeycaps(shortcut: DShortcut(shortcut))
                else if (shortcuts[i] case final CharacterActivator shortcut)
                  DKbd(shortcut.character),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
