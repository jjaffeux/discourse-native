import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ListNavigationTab extends StatefulWidget {
  const ListNavigationTab({
    super.key,
    required this.controlKey,
    required this.label,
    required this.textStyle,
    required this.selected,
    required this.onTap,
    this.count = 0,
    this.showCountBadge = false,
    this.showCount = true,
    this.underline = false,
    this.segmented = false,
  });

  final Key controlKey;
  final String label;
  final TextStyle? textStyle;
  final int count;
  final bool showCountBadge;
  final bool showCount;
  final bool underline;
  final bool segmented;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<ListNavigationTab> createState() => _ListNavigationTabState();
}

class _ListNavigationTabState extends State<ListNavigationTab> {
  final WidgetStatesController _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel =
        widget.showCount &&
            widget.count > 0 &&
            !widget.showCountBadge &&
            !widget.segmented
        ? '${widget.label} (${widget.count})'
        : widget.label;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.count > 0
          ? '${widget.label}, ${widget.count}'
          : widget.label,
      child: ExcludeSemantics(
        child: InkWell(
          key: widget.controlKey,
          statesController: _states,
          onTap: widget.onTap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          borderRadius: BorderRadius.circular(
            widget.underline
                ? 0
                : widget.segmented
                ? 4
                : 6,
          ),
          child: ValueListenableBuilder<Set<WidgetState>>(
            valueListenable: _states,
            builder: (context, states, _) {
              final focused = states.contains(WidgetState.focused);
              final emphasized =
                  states.contains(WidgetState.hovered) ||
                  focused ||
                  states.contains(WidgetState.pressed);
              final highlighted =
                  widget.selected || (widget.underline && emphasized);
              final labelWidget = TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: highlighted
                      ? widget.underline || widget.segmented
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                duration: duration,
                curve: Curves.easeOut,
                builder: (context, color, _) => Text(
                  displayLabel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: (widget.textStyle ?? theme.textTheme.labelLarge)
                      ?.copyWith(
                        color: color,
                        fontWeight: widget.selected
                            ? widget.underline || widget.segmented
                                  ? FontWeight.w600
                                  : FontWeight.w500
                            : FontWeight.w400,
                      ),
                ),
              );
              return AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                alignment: Alignment.center,
                margin: EdgeInsets.symmetric(
                  vertical: widget.underline || widget.segmented ? 0 : 9,
                ),
                padding: widget.underline
                    ? const EdgeInsets.only(top: 3, bottom: 10)
                    : EdgeInsets.symmetric(
                        horizontal: widget.segmented ? 4 : 10,
                      ),
                decoration: BoxDecoration(
                  color: widget.underline
                      ? Colors.transparent
                      : widget.selected && widget.segmented
                      ? theme.shell.content
                      : widget.selected
                      ? theme.shell.selected
                      : emphasized
                      ? theme.shell.hover
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    widget.underline
                        ? 0
                        : widget.segmented
                        ? 4
                        : 6,
                  ),
                  boxShadow: widget.selected && widget.segmented
                      ? const [
                          BoxShadow(
                            color: Color(0x11000000),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ]
                      : null,
                  border: widget.underline
                      ? Border(
                          bottom: BorderSide(
                            width: 2,
                            color: widget.selected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                          ),
                        )
                      : null,
                ),
                foregroundDecoration: widget.underline && focused
                    ? BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: widget.segmented
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          labelWidget,
                          if (widget.count > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${widget.count}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      )
                    : widget.showCount &&
                          widget.showCountBadge &&
                          widget.count > 0
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          labelWidget,
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.shell.hover,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${widget.count}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : labelWidget,
              );
            },
          ),
        ),
      ),
    );
  }
}
