import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A tooltip that can show a real keyboard shortcut alongside its message.
///
/// Flutter's Material tooltip accepts rich inline widgets, but represents them
/// as placeholder characters in its semantic label. [RawTooltip] lets the
/// visual keycaps stay widgets while assistive technology still receives the
/// original, useful tooltip message.
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
  final SingleActivator? shortcut;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    if (!TooltipVisibility.of(context)) return child;

    final tooltip = TooltipTheme.of(context);
    final verticalOffset = tooltip.verticalOffset ?? defaultVerticalOffset;
    final preferBelow = tooltip.preferBelow ?? true;

    return RawTooltip(
      semanticsTooltip:
          excludeFromSemantics || tooltip.excludeFromSemantics == true
          ? null
          : message,
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
  final SingleActivator? shortcut;

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
                _ShortcutKeycaps(shortcut: shortcut),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutKeycaps extends StatelessWidget {
  const _ShortcutKeycaps({required this.shortcut});

  final SingleActivator shortcut;

  @override
  Widget build(BuildContext context) {
    final keys = _shortcutKeys(shortcut, Theme.of(context).platform);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < keys.length; index++) ...[
          if (index > 0) const SizedBox(width: 4),
          DKbd(
            keys[index].visualLabel,
            semanticLabel: keys[index].semanticLabel,
          ),
        ],
      ],
    );
  }
}

/// The keyboard-key treatment used inside shortcut tooltips.
class DKbd extends StatelessWidget {
  const DKbd(this.label, {super.key, this.semanticLabel});

  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        DefaultTextStyle.of(context).style.color ?? colors.onSurface;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.08),
          border: Border.all(color: foreground.withValues(alpha: 0.20)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontFamily: 'JetBrains Mono',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

typedef _ShortcutKey = ({String visualLabel, String semanticLabel});

List<_ShortcutKey> _shortcutKeys(
  SingleActivator shortcut,
  TargetPlatform platform,
) {
  final macOS = platform == TargetPlatform.macOS;
  return [
    if (shortcut.control)
      (visualLabel: macOS ? '⌃' : 'Ctrl', semanticLabel: 'Control'),
    if (shortcut.alt) (visualLabel: macOS ? '⌥' : 'Alt', semanticLabel: 'Alt'),
    if (shortcut.shift)
      (visualLabel: macOS ? '⇧' : 'Shift', semanticLabel: 'Shift'),
    if (shortcut.meta)
      (
        visualLabel: macOS ? '⌘' : 'Meta',
        semanticLabel: macOS ? 'Command' : 'Meta',
      ),
    (
      visualLabel: _logicalKeyLabel(shortcut.trigger),
      semanticLabel: _logicalKeyLabel(shortcut.trigger),
    ),
  ];
}

String _logicalKeyLabel(LogicalKeyboardKey key) {
  final namedLabel = switch (key) {
    LogicalKeyboardKey.enter => 'Enter',
    LogicalKeyboardKey.escape => 'Esc',
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.tab => 'Tab',
    LogicalKeyboardKey.backspace => 'Backspace',
    LogicalKeyboardKey.delete => 'Delete',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowRight => '→',
    _ => null,
  };
  if (namedLabel != null) return namedLabel;
  if (key.keyLabel.isNotEmpty) return key.keyLabel.toUpperCase();
  return key.debugName ?? 'Key';
}
