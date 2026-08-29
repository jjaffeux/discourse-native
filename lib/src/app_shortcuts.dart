import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keyboard shortcuts owned by the application shell.
///
/// Keeping the activator beside the UI that describes it prevents displayed
/// key combinations from drifting away from the keys the shell accepts.
const topicReplyShortcut = SingleActivator(
  LogicalKeyboardKey.keyR,
  shift: true,
  includeRepeats: false,
);
