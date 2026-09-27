import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/discourse_typography.dart';

/// The reference form recipe: an icon heading above an outlined field group.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget icon;
  final Widget child;

  /// Sits at the heading's end, for what the section applies to.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 9,
    children: [
      Row(
        spacing: 8,
        children: [
          IconTheme.merge(
            data: IconThemeData(
              size: 12,
              color: DTokens.of(context).mutedForeground,
            ),
            child: icon,
          ),
          Expanded(
            child: Semantics(
              headingLevel: 2,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: DiscourseTypography.control,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: DTokens.of(context).foreground,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
      DCard(
        spacing: 16,
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        children: [DCardContent(child: child)],
      ),
    ],
  );
}

/// A pair of radio choice cards: side by side when each has room for its
/// description, stacked otherwise, and the same height when side by side.
class SettingsChoiceCards extends StatelessWidget {
  const SettingsChoiceCards({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >=
          540 * MediaQuery.textScalerOf(context).scale(14) / 14;
      return wide
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DSpacing.md,
                children: [for (final card in children) Expanded(child: card)],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DSpacing.sm,
              children: children,
            );
    },
  );
}
