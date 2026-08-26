import 'package:flutter/material.dart';

import '../foundation/calendar_day.dart';
import '../theme/app_theme.dart';

/// The date boundary shared by topic and chat streams.
class StreamDaySeparator extends StatefulWidget {
  const StreamDaySeparator({
    super.key,
    required this.day,
    this.floating = false,
    this.onTap,
  });

  static const double height = 44;

  final DateTime day;
  final bool floating;

  /// Topics return to the first post of the day. Chat dates are informative,
  /// so they retain the same hover treatment without presenting as buttons.
  final VoidCallback? onTap;

  @override
  State<StreamDaySeparator> createState() => _StreamDaySeparatorState();
}

class _StreamDaySeparatorState extends State<StreamDaySeparator> {
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = dayLabel(widget.day, now: DateTime.now());
    // Core's pinned date uses primary-50 against a primary-200 border. The
    // matching Material roles preserve that contrast for each site palette.
    final idleBackground = widget.floating
        ? theme.colorScheme.surfaceContainerLow
        : theme.shell.content;
    final background = _hovered || _focused
        ? theme.shell.hover
        : idleBackground;

    Widget date = MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: widget.floating
                ? theme.colorScheme.surfaceContainerHigh
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: widget.floating
              ? const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    if (widget.onTap case final onTap?) {
      final actionLabel = 'Go to start of $label';
      date = Semantics(
        button: true,
        label: actionLabel,
        onTap: onTap,
        excludeSemantics: true,
        child: Tooltip(
          message: actionLabel,
          excludeFromSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onTap,
              onFocusChange: _setFocused,
              child: date,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: StreamDaySeparator.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!widget.floating)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, color: theme.shell.divider),
            ),
          date,
        ],
      ),
    );
  }
}
