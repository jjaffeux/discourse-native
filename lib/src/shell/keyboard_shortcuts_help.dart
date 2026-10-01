import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import 'shell_sheet.dart';

Future<void> showKeyboardShortcuts(BuildContext context) async {
  if (DControlStyle.isTouch(context)) return;
  await showShellSheet<void>(
    context: context,
    title: appL10n.keyboardShortcuts,
    dialogOnDesktop: true,
    builder: (context) => SingleChildScrollView(
      key: const ValueKey('keyboard-shortcuts-help'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(appL10n.shiftJAndShiftKSelectTopicsWithoutOpeningThemJ),
          const SizedBox(height: 16),
          for (final command in ReadingCommand.values)
            _ShortcutRow(
              label: command.label,
              prefix: command.prefix,
              shortcuts: [
                for (final shortcut in command.shortcuts)
                  if (shortcut is! SingleActivator ||
                      shortcut.trigger != LogicalKeyboardKey.numpadEnter)
                    shortcut,
              ],
            ),
          const DSeparator(),
          _ShortcutRow(
            label: appL10n.backInCurrentTab,
            shortcuts: [contentBackShortcutForPlatform(defaultTargetPlatform)],
          ),
          _ShortcutRow(
            label: appL10n.forwardInCurrentTab,
            shortcuts: [
              contentForwardShortcutForPlatform(defaultTargetPlatform),
            ],
          ),
          _ShortcutRow(
            label: appL10n.refreshCurrentTab,
            shortcuts: [refreshTabShortcutForPlatform(defaultTargetPlatform)],
          ),
          _ShortcutRow(
            label: appL10n.newTopic,
            shortcuts: const [newTopicShortcut],
          ),
          _ShortcutRow(
            label: appL10n.replyToTopic,
            shortcuts: const [topicReplyShortcut],
          ),
          _ShortcutRow(
            label: appL10n.bookmarkTopic,
            shortcuts: const [topicBookmarkShortcut],
          ),
          _ShortcutRow(
            label: appL10n.submitComposer,
            shortcuts: [
              primaryShortcutForPlatform(
                defaultTargetPlatform,
                LogicalKeyboardKey.enter,
              ),
            ],
          ),
          _ShortcutRow(
            label: appL10n.closeComposer,
            shortcuts: const [SingleActivator(LogicalKeyboardKey.escape)],
          ),
          _ShortcutRow(
            label: appL10n.globalSearch,
            shortcuts: [searchShortcutForPlatform(defaultTargetPlatform)],
          ),
          _ShortcutRow(
            label: appL10n.contextualSearch,
            shortcuts: [
              searchShortcutForPlatform(
                defaultTargetPlatform,
                contextual: true,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.label,
    required this.shortcuts,
    this.prefix,
  });

  final String label;
  final List<ShortcutActivator> shortcuts;
  final SingleActivator? prefix;

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
                if (i > 0) Text(context.l10n.orAppsettingspage),
                if (shortcuts[i] case final SingleActivator shortcut)
                  DShortcutKeycaps(
                    shortcut: prefix == null
                        ? DShortcut(shortcut)
                        : DShortcut.sequence(prefix!, [shortcut]),
                  )
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
