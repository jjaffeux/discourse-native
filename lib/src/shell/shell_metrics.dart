import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

// Measured from the desktop mockup. Gutters belong to the workspace layout.
const double workspacePanelGap = 12;
const double workspaceEdgeInset = 6;

const double shellHeaderHeight = 52;
const double readerHeaderHeight = 44;

const double workspaceTabStripHeight = 38;
const workspaceTabsPadding = EdgeInsets.fromLTRB(8, 8, 8, 4);

/// Grows with the forum tab label role so scaled tab labels keep their inset.
double workspaceTabStripHeightFor(BuildContext context) {
  final style = Theme.of(context).textTheme.labelLarge!;
  final fontSize = style.fontSize!;
  final growth =
      (MediaQuery.textScalerOf(context).scale(fontSize) - fontSize) *
      style.height!;
  return workspaceTabStripHeight + math.max(0, growth);
}

const topicBottomBarPadding = EdgeInsets.all(8);

double topicBottomBarControlHeight(BuildContext context) {
  return math.max(
    context.isTouch ? DSpacing.touchTarget : 0,
    DControlStyle.scaledHeight(
      DControlSize.regular,
      MediaQuery.textScalerOf(context),
      context: context,
    ),
  );
}

double topicBottomBarHeight(BuildContext context) =>
    topicBottomBarControlHeight(context) + topicBottomBarPadding.vertical;

const double composerHeight = 280;
const double topicComposerHeight = 380;

const double composerSuggestionsWidth = 320;

const double composerSuggestionRowHeight = 44;
