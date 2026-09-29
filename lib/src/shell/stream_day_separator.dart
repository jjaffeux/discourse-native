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
    // Match the mockup's raised pill and subtle rule using the live forum
    // palette, including custom themes.
    final background = Color.lerp(
      theme.shell.content,
      theme.colorScheme.onSurface,
      .10,
    )!;
    final border = Color.lerp(
      theme.shell.content,
      theme.colorScheme.onSurface,
      .12,
    )!;
    final foreground = Color.lerp(
      theme.shell.content,
      theme.colorScheme.onSurface,
      .50,
    )!;

    Widget date;
    if (onTap case final onTap?) {
      final actionLabel = context.l10n.goToStartOf((label).toString());
      date = DButton(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onPressed: onTap,
        semanticLabel: actionLabel,
        tooltip: actionLabel,
        variant: DButtonVariant.outline,
        size: DButtonSize.chip,
        shape: DButtonShape.pill,
        backgroundColor: background,
        interactiveBackgroundColor: theme.shell.hover,
        foregroundColor: foreground,
        borderColor: border,
      );
    } else {
      date = Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
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
