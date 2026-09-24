import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

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
                  fontSize: 13,
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
