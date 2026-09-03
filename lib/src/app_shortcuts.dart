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
}) {
  final macOS = platform == TargetPlatform.macOS;
  return SingleActivator(
    trigger,
    meta: macOS,
    control: !macOS,
    includeRepeats: includeRepeats,
  );
}

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
