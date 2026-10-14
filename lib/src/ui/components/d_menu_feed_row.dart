import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_badge.dart';
import 'd_item.dart';
import 'd_notification_dot.dart';

/// A two-line header-menu row. Item owns activation, focus and its 8px surface.
/// The trailing time and unread marker share a column; read rows keep its width.
class DMenuFeedRow extends StatelessWidget {
  const DMenuFeedRow({
    super.key,
    required this.title,
    required this.onPressed,
    required this.unread,
    this.description,
    this.leading,
    this.time,
    this.count = 0,
    this.semanticLabel,
  });

  final Widget title;
  final Widget? description;
  final Widget? leading;
  final String? time;
  final int count;
  final bool unread;
  final VoidCallback onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final muted = Color.lerp(tokens.colors.surface, tokens.foreground, .50)!;
    final scaler = MediaQuery.textScalerOf(context);
    final largeText = scaler.scale(13) > 19.5;
    final titleHeight = scaler.scale(13) * 1.35;
    final subjectHeight = scaler.scale(12.5) * 1.4;
    // Flutter rounds each paragraph's line box up. Balance that extra leading
    // across the insets so the two-line row retains the reference's 52.05px.
    final verticalInset = description != null && !largeText
        ? 8 -
              (titleHeight.ceilToDouble() -
                      titleHeight +
                      subjectHeight.ceilToDouble() -
                      subjectHeight) /
                  2
        : 8.0;
    Widget line(Widget child, double size, double height, Color color) =>
        DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: size,
            height: height,
            fontWeight: FontWeight.w400,
            color: color,
          ),
          maxLines: largeText ? null : 1,
          overflow: largeText ? TextOverflow.clip : TextOverflow.ellipsis,
          child: child,
        );
    return DItem(
      size: DItemSize.xs,
      shape: DItemShape.menu,
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: verticalInset),
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      children: [
        DItemContent(
          children: [
            ExcludeSemantics(
              excluding: semanticLabel != null,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    if (leading != null) Center(child: leading!),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 1,
                        children: [
                          line(title, 13, 1.35, muted),
                          if (description != null)
                            line(
                              description!,
                              12.5,
                              1.4,
                              unread
                                  ? Color.lerp(
                                      tokens.colors.surface,
                                      tokens.foreground,
                                      .90,
                                    )!
                                  : muted,
                            ),
                        ],
                      ),
                    ),
                    if (time != null || unread)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (time != null)
                              Text(
                                time!,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                  color: Color.lerp(
                                    tokens.colors.surface,
                                    tokens.foreground,
                                    .4,
                                  ),
                                ),
                              ),
                            if (unread) ...[
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: count > 0
                                    ? DBadge(
                                        child: Text(
                                          count > 99 ? '99+' : '$count',
                                        ),
                                      )
                                    : const DNotificationDot(),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
