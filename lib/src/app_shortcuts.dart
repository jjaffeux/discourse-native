import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const forumSwitchShortcutKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

SingleActivator primaryShortcutForPlatform(
  TargetPlatform platform,
  LogicalKeyboardKey trigger, {
  bool includeRepeats = true,
  bool shift = false,
}) {
  final macOS = platform == TargetPlatform.macOS;
  return SingleActivator(
    trigger,
    meta: macOS,
    control: !macOS,
    shift: shift,
    includeRepeats: includeRepeats,
  );
}

SingleActivator searchShortcutForPlatform(
  TargetPlatform platform, {
  bool contextual = false,
}) => primaryShortcutForPlatform(
  platform,
  LogicalKeyboardKey.keyF,
  shift: contextual,
  includeRepeats: false,
);

SingleActivator newDirectMessageShortcutForPlatform(TargetPlatform platform) =>
    primaryShortcutForPlatform(
      platform,
      LogicalKeyboardKey.keyK,
      includeRepeats: false,
    );

const newTopicShortcut = SingleActivator(
  LogicalKeyboardKey.keyC,
  includeRepeats: false,
);

const topicReplyShortcut = SingleActivator(
  LogicalKeyboardKey.keyR,
  shift: true,
  includeRepeats: false,
);

SingleActivator contentBackShortcutForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.macOS
    ? const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true)
    : const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true);

SingleActivator contentForwardShortcutForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.macOS
    ? const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true)
    : const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true);

SingleActivator refreshTabShortcutForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.macOS
    ? const SingleActivator(
        LogicalKeyboardKey.keyR,
        meta: true,
        includeRepeats: false,
      )
    : const SingleActivator(LogicalKeyboardKey.f5, includeRepeats: false);

enum ReadingCommand {
  openNextTopic('Open next topic', [
    SingleActivator(LogicalKeyboardKey.keyJ, includeRepeats: false),
  ], prefix: SingleActivator(LogicalKeyboardKey.keyG, includeRepeats: false)),
  openPreviousTopic('Open previous topic', [
    SingleActivator(LogicalKeyboardKey.keyK, includeRepeats: false),
  ], prefix: SingleActivator(LogicalKeyboardKey.keyG, includeRepeats: false)),
  nextTopic('Next topic in the list', [
    SingleActivator(LogicalKeyboardKey.keyJ, shift: true),
  ]),
  previousTopic('Previous topic in the list', [
    SingleActivator(LogicalKeyboardKey.keyK, shift: true),
  ]),
  openTopic('Open highlighted topic', [
    SingleActivator(LogicalKeyboardKey.keyO, includeRepeats: false),
    SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false),
    SingleActivator(LogicalKeyboardKey.numpadEnter, includeRepeats: false),
  ]),
  nextPost('Next post or topic', [SingleActivator(LogicalKeyboardKey.keyJ)]),
  previousPost('Previous post or topic', [
    SingleActivator(LogicalKeyboardKey.keyK),
  ]),
  replyToPost('Reply to selected post', [
    SingleActivator(LogicalKeyboardKey.keyR, includeRepeats: false),
  ]),
  back('Back', [
    SingleActivator(LogicalKeyboardKey.keyU, includeRepeats: false),
  ]),
  help('Keyboard shortcuts', [CharacterActivator('?', includeRepeats: false)]);

  const ReadingCommand(this.label, this.shortcuts, {this.prefix});

  final String label;
  final List<ShortcutActivator> shortcuts;
  final SingleActivator? prefix;

  bool accepts(KeyEvent event) => shortcuts.any(
    (shortcut) => shortcut.accepts(event, HardwareKeyboard.instance),
  );
}
