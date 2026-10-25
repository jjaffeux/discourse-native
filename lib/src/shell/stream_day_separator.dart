import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/calendar_day.dart';
import '../theme/app_theme.dart';

class StreamDaySeparator extends StatelessWidget {
  const StreamDaySeparator({
    super.key,
    required this.day,
    this.floating = false,
    this.showDivider = true,
    this.onTap,
  });

  static const double height = 48;

  final DateTime day;
  final bool floating;
  final bool showDivider;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = dayLabel(day, now: DateTime.now());
    final background = floating
        ? theme.shell.content
        : Color.alphaBlend(
            Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? .16 : .045,
            ),
            theme.shell.content,
          );
    final border = floating
        ? Color.lerp(theme.shell.content, theme.colorScheme.onSurface, .12)!
        : Colors.transparent;
    final foreground = Color.lerp(
      theme.shell.content,
      theme.colorScheme.onSurface,
      .50,
    )!;

    Widget date;
    if (onTap case final onTap?) {
      final actionLabel = context.l10n.goToStartOf((label).toString());
      final dateLabel = Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      );
      date = DButton(
        label: floating ? RepaintBoundary(child: dateLabel) : dateLabel,
        onPressed: onTap,
        semanticLabel: actionLabel,
        tooltip: actionLabel,
        variant: DButtonVariant.outline,
        density: floating
            ? DButtonDensity.floatingDate
            : DButtonDensity.standard,
        size: DButtonSize.chip,
        shape: DButtonShape.pill,
        backgroundColor: background,
        interactiveBackgroundColor: theme.shell.hover,
        foregroundColor: foreground,
        borderColor: border,
      );
    } else {
      date = DBadge(
        variant: DBadgeVariant.outline,
        backgroundColor: background,
        foregroundColor: foreground,
        borderColor: border,
        child: Text(label),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: !floating && !showDivider ? 28 : StreamDaySeparator.height,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DMarker(
          variant: !floating && showDivider
              ? DMarkerVariant.separator
              : DMarkerVariant.inline,
          axis: floating || !showDivider ? Axis.vertical : Axis.horizontal,
          borderColor: border,
          child: DMarkerContent(child: date),
        ),
      ),
    );
  }
}
