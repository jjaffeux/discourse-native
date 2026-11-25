import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../../theme/tokens.dart';
import '../foundation/control_style.dart';
import '../foundation/phone_sheet.dart';
import 'd_badge.dart';
import 'd_item.dart';

/// A two-line header-menu row. Item owns activation, focus and its 8px surface.
/// A count sits beside the title and the timestamp sits beside the excerpt.
/// The row tint shows unread state even when there is no count.
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
    final muted = tokens.mutedForeground;
    final scaler = MediaQuery.textScalerOf(context);
    final reading = Theme.of(context).textTheme.bodyLarge;
    final phone = DControlStyle.isTouch(context);
    final sheet = DPhoneSheet.contains(context);
    final titleSize = phone
        ? DiscourseTypography.mobileRowTitle
        : DiscourseTypography.rowTitle;
    final excerptSize = phone
        ? DiscourseTypography.mobileRowPreview
        : DiscourseTypography.preview;
    final timeSize = phone
        ? DiscourseTypography.mobileRowMetadata
        : DiscourseTypography.xs;
    final largeText = scaler.scale(titleSize) / titleSize > 1.5;
    final showCount = unread && count > 0;
    const titleHeight = DiscourseTypography.lineHeightRowTitle;
    const excerptHeight = DiscourseTypography.lineHeightPreview;
    Widget line(Widget child, double size, double height) =>
        DefaultTextStyle.merge(
          style: TextStyle(
            fontFamily: reading?.fontFamily,
            fontFamilyFallback: reading?.fontFamilyFallback,
            fontSize: size,
            height: height,
            fontWeight: FontWeight.w400,
            color: muted,
          ),
          maxLines: largeText ? null : 1,
          overflow: largeText ? TextOverflow.clip : TextOverflow.ellipsis,
          child: child,
        );
    return DItem(
      size: DItemSize.xs,
      shape: DItemShape.menu,
      variant: unread ? DItemVariant.unread : DItemVariant.standard,
      padding: sheet
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10.5)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
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
                  spacing: sheet ? 13 : 10,
                  children: [
                    if (leading != null) Center(child: leading!),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 1,
                        children: [
                          line(title, titleSize, titleHeight),
                          if (description != null)
                            line(description!, excerptSize, excerptHeight),
                        ],
                      ),
                    ),
                    if (time != null || showCount)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (showCount)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    scaler.scale(titleSize) * titleHeight,
                              ),
                              child: Center(
                                widthFactor: 1,
                                child: DBadge(
                                  child: Text(count > 99 ? '99+' : '$count'),
                                ),
                              ),
                            ),
                          if (time != null) ...[
                            const Spacer(),
                            Text(
                              time!,
                              style: TextStyle(
                                fontSize: timeSize,
                                height:
                                    scaler.scale(excerptSize) /
                                    scaler.scale(timeSize) *
                                    excerptHeight,
                                color: muted,
                              ),
                            ),
                          ],
                        ],
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
