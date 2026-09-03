import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class DShortcut {
  const DShortcut(this._first) : _following = const [];

  const DShortcut.sequence(this._first, List<SingleActivator> following)
    : _following = following;

  final SingleActivator _first;
  final List<SingleActivator> _following;

  int get length => _following.length + 1;

  SingleActivator operator [](int index) {
    if (index == 0) return _first;
    return _following[index - 1];
  }
}

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
  final DShortcut? shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltip = TooltipTheme.of(context);
    final textStyle =
        tooltip.textStyle ??
        theme.textTheme.bodySmall?.copyWith(
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
                DShortcutKeycaps(shortcut: shortcut),
            ],
          ),
        ),
      ),
    );
  }
}

class DShortcutKeycaps extends StatefulWidget {
  const DShortcutKeycaps({super.key, required this.shortcut});

  final DShortcut shortcut;

  @override
  State<DShortcutKeycaps> createState() => _ShortcutKeycapsState();
}

class _ShortcutKeycapsState extends State<DShortcutKeycaps> {
  int _completedSteps = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(DShortcutKeycaps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shortcut != widget.shortcut) _completedSteps = 0;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    var completedSteps = _completedSteps;

    if (event is KeyDownEvent && !_isModifierKey(event.logicalKey)) {
      final shortcut = widget.shortcut;
      final expected = completedSteps < shortcut.length
          ? shortcut[completedSteps]
          : null;
      if (expected?.accepts(event, HardwareKeyboard.instance) == true) {
        completedSteps++;
      } else if (shortcut[0].accepts(event, HardwareKeyboard.instance)) {
        // The first trigger also starts a fresh attempt while a partial or
        // completed sequence is still painted.
        completedSteps = 1;
      } else {
        completedSteps = 0;
      }
    } else if (event is KeyUpEvent &&
        completedSteps == widget.shortcut.length &&
        event.logicalKey == widget.shortcut[completedSteps - 1].trigger) {
      completedSteps = 0;
    }

    if (mounted) {
      setState(() => _completedSteps = completedSteps);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shortcut = widget.shortcut;
    final platform = Theme.of(context).platform;
    final keyboard = HardwareKeyboard.instance;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var stepIndex = 0; stepIndex < shortcut.length; stepIndex++) ...[
          if (stepIndex > 0) const SizedBox(width: 8),
          Builder(
            builder: (context) {
              final keys = _shortcutKeys(shortcut[stepIndex], platform);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var keyIndex = 0;
                    keyIndex < keys.length;
                    keyIndex++
                  ) ...[
                    if (keyIndex > 0) const SizedBox(width: 4),
                    DKbd(
                      keys[keyIndex].visualLabel,
                      key: ValueKey('shortcut-key-$stepIndex-$keyIndex'),
                      semanticLabel: keys[keyIndex].semanticLabel,
                      highlighted:
                          stepIndex < _completedSteps ||
                          (stepIndex == _completedSteps &&
                              _isPressed(keys[keyIndex], keyboard)),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class DKbd extends StatelessWidget {
  const DKbd(
    this.label, {
    super.key,
    this.semanticLabel,
    this.highlighted = false,
  });

  final String label;
  final String? semanticLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        DefaultTextStyle.of(context).style.color ?? colors.onSurface;
    final keyForeground = highlighted ? colors.onPrimary : foreground;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: highlighted
              ? colors.primary
              : foreground.withValues(alpha: 0.08),
          border: Border.all(
            color: highlighted
                ? colors.primary
                : foreground.withValues(alpha: 0.20),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          style: TextStyle(
            color: keyForeground,
            fontFamily: 'JetBrains Mono',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

enum _ShortcutKeyRole { control, alt, shift, meta, trigger }

typedef _ShortcutKey = ({
  String visualLabel,
  String semanticLabel,
  _ShortcutKeyRole role,
  LogicalKeyboardKey? trigger,
});

List<_ShortcutKey> _shortcutKeys(
  SingleActivator shortcut,
  TargetPlatform platform,
) {
  final macOS = platform == TargetPlatform.macOS;
  return [
    if (shortcut.control)
      (
        visualLabel: macOS ? '⌃' : 'Ctrl',
        semanticLabel: 'Control',
        role: _ShortcutKeyRole.control,
        trigger: null,
      ),
    if (shortcut.alt)
      (
        visualLabel: macOS ? '⌥' : 'Alt',
        semanticLabel: 'Alt',
        role: _ShortcutKeyRole.alt,
        trigger: null,
      ),
    if (shortcut.shift)
      (
        visualLabel: macOS ? '⇧' : 'Shift',
        semanticLabel: 'Shift',
        role: _ShortcutKeyRole.shift,
        trigger: null,
      ),
    if (shortcut.meta)
      (
        visualLabel: macOS ? '⌘' : 'Meta',
        semanticLabel: macOS ? 'Command' : 'Meta',
        role: _ShortcutKeyRole.meta,
        trigger: null,
      ),
    (
      visualLabel: _logicalKeyLabel(shortcut.trigger),
      semanticLabel: _logicalKeyLabel(shortcut.trigger),
      role: _ShortcutKeyRole.trigger,
      trigger: shortcut.trigger,
    ),
  ];
}

bool _isPressed(_ShortcutKey key, HardwareKeyboard keyboard) =>
    switch (key.role) {
      _ShortcutKeyRole.control => keyboard.isControlPressed,
      _ShortcutKeyRole.alt => keyboard.isAltPressed,
      _ShortcutKeyRole.shift => keyboard.isShiftPressed,
      _ShortcutKeyRole.meta => keyboard.isMetaPressed,
      _ShortcutKeyRole.trigger => keyboard.isLogicalKeyPressed(key.trigger!),
    };

bool _isModifierKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.controlLeft ||
    key == LogicalKeyboardKey.controlRight ||
    key == LogicalKeyboardKey.altLeft ||
    key == LogicalKeyboardKey.altRight ||
    key == LogicalKeyboardKey.shiftLeft ||
    key == LogicalKeyboardKey.shiftRight ||
    key == LogicalKeyboardKey.metaLeft ||
    key == LogicalKeyboardKey.metaRight;

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
