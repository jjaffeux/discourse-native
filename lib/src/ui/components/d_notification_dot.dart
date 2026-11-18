import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

/// Sizes for inline indicators.
enum DNotificationDotSize {
  /// A 7px dot for secondary unread activity in a compact row.
  compact,

  /// An 8px dot for ordinary unread activity.
  standard,
}

/// An unread or new-activity indicator, without a count or interaction.
///
/// Use the default constructor beside text. [DNotificationDot.overlay] adds a
/// 2px surface-colored ring within a 12px footprint when overlapping artwork.
/// Positioning and visibility belong to the caller; neither form scales with
/// text or intercepts pointer input. Use [semanticLabel] for a standalone state,
/// or omit it when the enclosing button/row already announces the unread state.
class DNotificationDot extends StatelessWidget {
  const DNotificationDot({
    super.key,
    this.color,
    this.semanticLabel,
    this.size = DNotificationDotSize.standard,
  }) : ringColor = null,
       _overlay = false;

  const DNotificationDot.overlay({
    super.key,
    this.color,
    this.ringColor,
    this.semanticLabel,
  }) : size = DNotificationDotSize.standard,
       _overlay = true;

  /// Defaults to the current theme's primary color.
  final Color? color;

  /// The surrounding surface; overlay dots default to the theme background.
  final Color? ringColor;

  final String? semanticLabel;
  final DNotificationDotSize size;
  final bool _overlay;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dot = SizedBox.square(
      dimension: _overlay ? 12 : (size == DNotificationDotSize.compact ? 7 : 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? tokens.primary,
          shape: BoxShape.circle,
          border: _overlay
              ? Border.all(color: ringColor ?? tokens.background, width: 2)
              : null,
        ),
      ),
    );
    final visual = IgnorePointer(child: dot);
    return semanticLabel == null
        ? ExcludeSemantics(child: visual)
        : Semantics(container: true, label: semanticLabel, child: visual);
  }
}
