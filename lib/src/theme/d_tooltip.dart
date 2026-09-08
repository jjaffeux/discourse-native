import 'package:flutter/material.dart';

import '../ui/components/d_kbd.dart';

class DTooltip extends StatelessWidget {
  const DTooltip({
    super.key,
    required this.message,
    required this.child,
    this.shortcut,
    this.excludeFromSemantics = false,
  });

  static const BoxConstraints defaultConstraints = BoxConstraints(
    minHeight: 38,
    maxWidth: 400,
  );
  static const EdgeInsets defaultPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );
  static const EdgeInsets defaultMargin = EdgeInsets.all(8);
  static const double defaultVerticalOffset = 24;

  final String message;
  final Widget child;
  final DShortcut? shortcut;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    // Hidden panes keep their controls mounted but pause tooltip fade-outs.
    if (!TooltipVisibility.of(context) ||
        !TickerMode.valuesOf(context).enabled) {
      return child;
    }

    final tooltip = TooltipTheme.of(context);
    final verticalOffset = tooltip.verticalOffset ?? defaultVerticalOffset;
    final preferBelow = tooltip.preferBelow ?? true;

    return RawTooltip(
      semanticsTooltip:
          excludeFromSemantics || tooltip.excludeFromSemantics == true
          ? null
          : shortcut == null
          ? message
          : '$message, ${shortcut!.semanticLabel(Theme.of(context).platform)}',
      hoverDelay: tooltip.waitDuration ?? Duration.zero,
      touchDelay: tooltip.showDuration ?? const Duration(milliseconds: 1500),
      dismissDelay: tooltip.exitDuration ?? const Duration(milliseconds: 100),
      triggerMode: tooltip.triggerMode ?? TooltipTriggerMode.longPress,
      enableFeedback: tooltip.enableFeedback ?? true,
      ignorePointer: true,
      positionDelegate: (position) => positionDependentBox(
        size: position.overlaySize,
        childSize: position.tooltipSize,
        target: position.target,
        verticalOffset: verticalOffset,
        preferBelow: preferBelow,
      ),
      tooltipBuilder: (context, animation) => FadeTransition(
        opacity: animation,
        child: _TooltipSurface(message: message, shortcut: shortcut),
      ),
      child: child,
    );
  }
}

class _TooltipSurface extends StatelessWidget {
  const _TooltipSurface({required this.message, required this.shortcut});

  final String message;
  final DShortcut? shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltip = TooltipTheme.of(context);
    final textStyle =
        tooltip.textStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onInverseSurface,
        );
    final decoration =
        tooltip.decoration ??
        BoxDecoration(
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        );

    return ConstrainedBox(
      constraints: tooltip.constraints ?? DTooltip.defaultConstraints,
      child: DefaultTextStyle(
        style: textStyle ?? const TextStyle(),
        textAlign: tooltip.textAlign ?? TextAlign.start,
        child: Container(
          decoration: decoration,
          padding: tooltip.padding ?? DTooltip.defaultPadding,
          margin: tooltip.margin ?? DTooltip.defaultMargin,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(message),
              if (shortcut case final shortcut?)
                DKbdTheme(
                  foregroundColor:
                      textStyle?.color ?? theme.colorScheme.onInverseSurface,
                  backgroundColor:
                      (textStyle?.color ?? theme.colorScheme.onInverseSurface)
                          .withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.10
                                : 0.20,
                          ),
                  child: DShortcutKeycaps(shortcut: shortcut),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
