import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

const double shellHeaderHeight = 52;
const topicBottomBarPadding = EdgeInsets.all(8);

double topicBottomBarControlHeight(BuildContext context) {
  return math.max(
    context.isTouch ? DSpacing.touchTarget : 0,
    DControlStyle.scaledHeight(
      DControlSize.regular,
      MediaQuery.textScalerOf(context),
    ),
  );
}

double topicBottomBarHeight(BuildContext context) =>
    topicBottomBarControlHeight(context) + topicBottomBarPadding.vertical;

const double composerHeight = 280;
const double topicComposerHeight = 380;

const double composerSuggestionsWidth = 320;

const double composerSuggestionRowHeight = 44;
