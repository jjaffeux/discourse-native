import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

const double shellHeaderHeight = 52;
const topicBottomBarPadding = EdgeInsets.all(8);

double topicBottomBarControlHeight(BuildContext context) {
  final fontSize = DButton.fontSizeFor(DButtonSize.small);
  final textScale = MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
  return math.max(
    context.isTouch ? DSpacing.touchTarget : 0,
    DButton.visualDimensionFor(DButtonSize.small) * math.max(1, textScale),
  );
}

double topicBottomBarHeight(BuildContext context) =>
    topicBottomBarControlHeight(context) + topicBottomBarPadding.vertical;

const double composerHeight = 280;
const double topicComposerHeight = 380;

const double composerSuggestionsWidth = 320;

const double composerSuggestionRowHeight = 44;
