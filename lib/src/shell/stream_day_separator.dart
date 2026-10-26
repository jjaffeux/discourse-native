import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/calendar_day.dart';
import '../theme/app_theme.dart';

/// The pill shared by day separators and the topic progress trigger, which sit
/// over the same post stream. Floating pills stand on the content color behind
/// a hairline; inline ones are a faint well without one.
final class StreamChip {
  factory StreamChip.of(BuildContext context, {required bool floating}) {
    final theme = Theme.of(context);
    return StreamChip._(
      floating: floating,
      background: floating
          ? theme.shell.content
          : Color.alphaBlend(
              Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? .16 : .045,
              ),
              theme.shell.content,
            ),
      border: floating
          ? Color.lerp(theme.shell.content, theme.colorScheme.onSurface, .12)!
          : Colors.transparent,
      foreground: Color.lerp(
        theme.shell.content,
        theme.colorScheme.onSurface,
        .50,
      )!,
      hover: theme.shell.hover,
    );
  }

  const StreamChip._({
    required this.floating,
    required this.background,
    required this.border,
    required this.foreground,
    required this.hover,
  });

  final bool floating;
  final Color background;
  final Color border;
  final Color foreground;
  final Color hover;

  DButton button({
    Key? key,
    required Widget label,
    required VoidCallback onPressed,
    String? tooltip,
    String? semanticLabel,
    FocusNode? focusNode,
    bool expanded = false,
    bool hasPopup = false,
  }) => DButton(
    key: key,
    label: DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: FontWeight.w600),
      child: label,
    ),
    onPressed: onPressed,
    focusNode: focusNode,
    expanded: expanded,
    hasPopup: hasPopup,
    semanticLabel: semanticLabel,
    tooltip: tooltip,
    variant: DButtonVariant.outline,
    density: floating ? DButtonDensity.floatingDate : DButtonDensity.standard,
    size: DButtonSize.chip,
    shape: DButtonShape.pill,
    backgroundColor: background,
    interactiveBackgroundColor: hover,
    foregroundColor: foreground,
    borderColor: border,
  );
}

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
    final label = dayLabel(day, now: DateTime.now());
    final chip = StreamChip.of(context, floating: floating);

    Widget date;
    if (onTap case final onTap?) {
      final actionLabel = context.l10n.goToStartOf((label).toString());
      final dateLabel = Text(label);
      date = chip.button(
        label: floating ? RepaintBoundary(child: dateLabel) : dateLabel,
        onPressed: onTap,
        semanticLabel: actionLabel,
        tooltip: actionLabel,
      );
    } else {
      date = DBadge(
        variant: DBadgeVariant.outline,
        backgroundColor: chip.background,
        foregroundColor: chip.foreground,
        borderColor: chip.border,
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
          borderColor: chip.border,
          child: DMarkerContent(child: date),
        ),
      ),
    );
  }
}
