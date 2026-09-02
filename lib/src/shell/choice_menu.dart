import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'curved_animation_builder.dart';
import 'platform.dart';
import 'shell_sheet.dart';

@immutable
final class ChoiceMenuOption<T> {
  const ChoiceMenuOption({
    required this.value,
    required this.title,
    required this.description,
    this.icon,
  });

  final T value;
  final String title;
  final String description;
  final DIconData? icon;
}

typedef ChoiceMenuAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback? openMenu);

class ChoiceMenuAnchor<T> extends StatefulWidget {
  const ChoiceMenuAnchor({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.builder,
    this.enabled = true,
    this.showPopoverTitle = true,
  });

  final String title;
  final T value;
  final List<ChoiceMenuOption<T>> options;
  final ValueChanged<T> onSelected;
  final ChoiceMenuAnchorBuilder builder;
  final bool enabled;

  final bool showPopoverTitle;

  @override
  State<ChoiceMenuAnchor<T>> createState() => _ChoiceMenuAnchorState<T>();
}

class _ChoiceMenuAnchorState<T> extends State<ChoiceMenuAnchor<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _showing = false;

  Future<void> _show() async {
    final anchorContext = _anchorKey.currentContext;
    if (_showing || !widget.enabled || anchorContext == null) return;
    _showing = true;
    try {
      final selected = await showChoiceMenu<T>(
        context: context,
        anchorContext: anchorContext,
        title: widget.title,
        value: widget.value,
        options: widget.options,
        showPopoverTitle: widget.showPopoverTitle,
      );
      if (!mounted || selected == null || selected == widget.value) return;
      widget.onSelected(selected);
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: _anchorKey,
    child: widget.builder(context, widget.enabled ? _show : null),
  );
}

Future<T?> showChoiceMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required String title,
  required T value,
  required List<ChoiceMenuOption<T>> options,
  bool showPopoverTitle = true,
}) {
  if (options.isEmpty) return Future<T?>.value();

  if (context.isTouch) {
    return showShellSheet<T>(
      context: context,
      title: title,
      padding: const EdgeInsets.all(8),
      builder: (sheetContext) => _ChoiceRows<T>(
        value: value,
        options: options,
        touch: true,
        onSelected: (choice) => Navigator.of(sheetContext).pop(choice),
      ),
    );
  }

  final navigator = Navigator.of(context);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  final anchor = anchorRect(
    anchor: anchorContext.findRenderObject() as RenderBox?,
    overlay: overlay,
  );
  final media = MediaQuery.of(context);
  final disableAnimations = media.disableAnimations;
  final alignment = _transitionAlignment(
    anchor: anchor,
    viewport: media.size,
    optionCount: options.length,
    showTitle: showPopoverTitle,
  );

  return navigator.push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Dismiss $title',
      barrierColor: Colors.transparent,
      transitionDuration: disableAnimations
          ? Duration.zero
          : discourseMenuOpenDuration,
      reverseTransitionDuration: disableAnimations
          ? Duration.zero
          : discourseMenuCloseDuration,
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          _ChoiceMenuPopup<T>(
            title: title,
            value: value,
            options: options,
            anchor: anchor,
            animation: animation,
            transitionAlignment: alignment,
            showTitle: showPopoverTitle,
          ),
    ),
  );
}

Alignment _transitionAlignment({
  required Rect? anchor,
  required Size viewport,
  required int optionCount,
  required bool showTitle,
}) {
  if (anchor == null) return Alignment.center;
  final right = anchor.center.dx > viewport.width / 2;
  final estimatedHeight = (showTitle ? 45.0 : 0) + optionCount * 62.0;
  final roomBelow = viewport.height - anchor.bottom - 12;
  final above = roomBelow < estimatedHeight && anchor.top > roomBelow;
  return Alignment(right ? 1 : -1, above ? 1 : -1);
}

class _ChoiceMenuPopup<T> extends StatelessWidget {
  const _ChoiceMenuPopup({
    required this.title,
    required this.value,
    required this.options,
    required this.anchor,
    required this.animation,
    required this.transitionAlignment,
    required this.showTitle,
  });

  static const double width = 336;

  final String title;
  final T value;
  final List<ChoiceMenuOption<T>> options;
  final Rect? anchor;
  final Animation<double> animation;
  final Alignment transitionAlignment;
  final bool showTitle;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: AnchoredLayout(anchor: anchor, maxWidth: width),
    child: _ChoiceMenuTransition(
      animation: animation,
      alignment: transitionAlignment,
      child: _ChoiceMenuSurface<T>(
        title: title,
        value: value,
        options: options,
        onSelected: Navigator.of(context).pop,
        showTitle: showTitle,
      ),
    ),
  );
}

class _ChoiceMenuTransition extends StatelessWidget {
  const _ChoiceMenuTransition({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CurvedAnimationBuilder(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
      builder: (context, curved) => FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, alignment.y < 0 ? -0.025 : 0.025),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            alignment: alignment,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ChoiceMenuSurface<T> extends StatelessWidget {
  const _ChoiceMenuSurface({
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.showTitle,
  });

  final String title;
  final T value;
  final List<ChoiceMenuOption<T>> options;
  final ValueChanged<T> onSelected;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.extension<ShellColors>();
    final floating = shell?.floating ?? theme.colorScheme.surfaceContainer;
    final divider = shell?.divider ?? theme.colorScheme.outlineVariant;
    const radius = BorderRadius.all(Radius.circular(12));
    return Material(
      key: const ValueKey('choice-menu-surface'),
      color: floating,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: _ChoiceMenuPopup.width,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          border: Border.all(color: divider),
          borderRadius: radius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Divider(height: 1, color: divider),
            ],
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: _ChoiceRows<T>(
                  value: value,
                  options: options,
                  onSelected: onSelected,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceRows<T> extends StatefulWidget {
  const _ChoiceRows({
    required this.value,
    required this.options,
    required this.onSelected,
    this.touch = false,
  });

  final T value;
  final List<ChoiceMenuOption<T>> options;
  final ValueChanged<T> onSelected;
  final bool touch;

  @override
  State<_ChoiceRows<T>> createState() => _ChoiceRowsState<T>();
}

class _ChoiceRowsState<T> extends State<_ChoiceRows<T>> {
  late List<FocusNode> _focusNodes;
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNodes = _nodes();
    final selected = widget.options.indexWhere(
      (option) => option.value == widget.value,
    );
    _focusedIndex = selected < 0 ? 0 : selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.touch) _focusNodes[_focusedIndex].requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _ChoiceRows<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length == widget.options.length) return;
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes = _nodes();
    _focusedIndex = _focusedIndex.clamp(0, _focusNodes.length - 1);
  }

  List<FocusNode> _nodes() => [
    for (final option in widget.options)
      FocusNode(debugLabel: 'choice ${option.title}'),
  ];

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _move(int delta) {
    _focusedIndex = (_focusedIndex + delta) % _focusNodes.length;
    _focusNodes[_focusedIndex].requestFocus();
  }

  void _focusAt(int index) {
    _focusedIndex = index;
    _focusNodes[index].requestFocus();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
      const SingleActivator(LogicalKeyboardKey.home): () => _focusAt(0),
      const SingleActivator(LogicalKeyboardKey.end): () =>
          _focusAt(_focusNodes.length - 1),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    },
    child: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Semantics(
        role: SemanticsRole.menu,
        label: 'Choices',
        explicitChildNodes: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < widget.options.length; index++) ...[
              if (index > 0) const SizedBox(height: 4),
              _ChoiceRow<T>(
                option: widget.options[index],
                selected: widget.options[index].value == widget.value,
                focusNode: _focusNodes[index],
                touch: widget.touch,
                onFocused: () => _focusedIndex = index,
                onSelected: widget.onSelected,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ChoiceRow<T> extends StatefulWidget {
  const _ChoiceRow({
    required this.option,
    required this.selected,
    required this.focusNode,
    required this.touch,
    required this.onFocused,
    required this.onSelected,
  });

  final ChoiceMenuOption<T> option;
  final bool selected;
  final FocusNode focusNode;
  final bool touch;
  final VoidCallback onFocused;
  final ValueChanged<T> onSelected;

  @override
  State<_ChoiceRow<T>> createState() => _ChoiceRowState<T>();
}

class _ChoiceRowState<T> extends State<_ChoiceRow<T>> {
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  void _setFocused(bool focused) {
    if (_focused != focused) setState(() => _focused = focused);
    if (focused) widget.onFocused();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.extension<ShellColors>();
    final surface = shell?.floating ?? theme.colorScheme.surfaceContainer;
    final selectedColor = Color.alphaBlend(
      theme.colorScheme.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.16 : 0.09,
      ),
      surface,
    );
    final hoverColor = Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06,
      ),
      surface,
    );
    final selectedHoverColor = Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.08 : 0.05,
      ),
      selectedColor,
    );
    final interactive = _hovered || _focused;
    final background = widget.selected
        ? (interactive ? selectedHoverColor : selectedColor)
        : (interactive ? hoverColor : Colors.transparent);
    final iconColor = widget.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 90);
    final radius = BorderRadius.circular(8);
    return Semantics(
      key: ValueKey(('choice-menu-option', widget.option.value)),
      role: SemanticsRole.menuItemRadio,
      checked: widget.selected,
      button: true,
      label: widget.option.title,
      hint: widget.option.description,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          key: ValueKey(('choice-menu-option-background', widget.option.value)),
          duration: duration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              focusNode: widget.focusNode,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: radius,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              onHover: _setHovered,
              onFocusChange: _setFocused,
              onTap: () => widget.onSelected(widget.option.value),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.touch ? 64 : 58),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.touch ? 12 : 10,
                    vertical: widget.touch ? 10 : 8,
                  ),
                  child: Row(
                    children: [
                      if (widget.option.icon case final icon?) ...[
                        SizedBox.square(
                          dimension: 24,
                          child: Center(
                            child: DIcon(icon, size: 20, color: iconColor),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.option.title,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.option.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox.square(
                        dimension: 20,
                        child: widget.selected
                            ? DIcon(
                                DIcons.check,
                                size: 16,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
