import 'package:discourse_native/l10n/strings.dart';
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

const newTopicShortcut = SingleActivator(
  LogicalKeyboardKey.keyC,
  includeRepeats: false,
);

const topicReplyShortcut = SingleActivator(
  LogicalKeyboardKey.keyR,
  shift: true,
  includeRepeats: false,
);

const topicBookmarkShortcut = SingleActivator(
  LogicalKeyboardKey.keyB,
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
  openNextTopic([
    SingleActivator(LogicalKeyboardKey.keyJ, includeRepeats: false),
  ], prefix: SingleActivator(LogicalKeyboardKey.keyG, includeRepeats: false)),
  openPreviousTopic([
    SingleActivator(LogicalKeyboardKey.keyK, includeRepeats: false),
  ], prefix: SingleActivator(LogicalKeyboardKey.keyG, includeRepeats: false)),
  nextTopic([SingleActivator(LogicalKeyboardKey.keyJ, shift: true)]),
  previousTopic([SingleActivator(LogicalKeyboardKey.keyK, shift: true)]),
  openTopic([
    SingleActivator(LogicalKeyboardKey.keyO, includeRepeats: false),
    SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false),
    SingleActivator(LogicalKeyboardKey.numpadEnter, includeRepeats: false),
  ]),
  nextPost([SingleActivator(LogicalKeyboardKey.keyJ)]),
  previousPost([SingleActivator(LogicalKeyboardKey.keyK)]),
  replyToPost([
    SingleActivator(LogicalKeyboardKey.keyR, includeRepeats: false),
  ]),
  back([SingleActivator(LogicalKeyboardKey.keyU, includeRepeats: false)]),
  help([CharacterActivator('?', includeRepeats: false)]);

  const ReadingCommand(this.shortcuts, {this.prefix});

  String get label => switch (this) {
    openNextTopic => appL10n.openNextTopic,
    openPreviousTopic => appL10n.openPreviousTopic,
    nextTopic => appL10n.nextTopicInTheList,
    previousTopic => appL10n.previousTopicInTheList,
    openTopic => appL10n.openHighlightedTopic,
    nextPost => appL10n.nextPostOrTopic,
    previousPost => appL10n.previousPostOrTopic,
    replyToPost => appL10n.replyToSelectedPost,
    back => appL10n.back,
    help => appL10n.keyboardShortcuts,
  };
  final List<ShortcutActivator> shortcuts;
  final SingleActivator? prefix;

  bool accepts(KeyEvent event) => shortcuts.any(
    (shortcut) => shortcut.accepts(event, HardwareKeyboard.instance),
  );
}
