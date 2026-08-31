import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const newTopicShortcut = SingleActivator(
  LogicalKeyboardKey.keyC,
  includeRepeats: false,
);

const topicReplyShortcut = SingleActivator(
  LogicalKeyboardKey.keyR,
  shift: true,
  includeRepeats: false,
);
