import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import 'anchored_layout.dart';

@immutable
final class CommandMenuOption<T> {
  const CommandMenuOption({
    required this.value,
    required this.label,
    required this.icon,
    this.key,
    this.dividerBefore = false,
    this.destructive = false,
  });

  final T value;
  final String label;
  final DIconData icon;
  final Key? key;
  final bool dividerBefore;
  final bool destructive;
}

typedef CommandMenuAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback? openMenu);

class CommandMenuAnchor<T> extends StatefulWidget {
  const CommandMenuAnchor({
    super.key,
    required this.title,
    required this.options,
    required this.onSelected,
    required this.builder,
    this.enabled = true,
  });

  final String title;
  final List<CommandMenuOption<T>> options;
  final ValueChanged<T> onSelected;
  final CommandMenuAnchorBuilder builder;
  final bool enabled;

  @override
  State<CommandMenuAnchor<T>> createState() => _CommandMenuAnchorState<T>();
}

class _CommandMenuAnchorState<T> extends State<CommandMenuAnchor<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _showing = false;

  Future<void> _show() async {
    final anchorContext = _anchorKey.currentContext;
    if (_showing || !widget.enabled || anchorContext == null) return;
    _showing = true;
    try {
      final selected = await showCommandMenu<T>(
        context: context,
        anchorContext: anchorContext,
        title: widget.title,
        options: widget.options,
      );
      if (mounted && selected != null) widget.onSelected(selected);
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: _anchorKey,
    child: widget.builder(
      context,
      widget.enabled && widget.options.isNotEmpty ? _show : null,
    ),
  );
}

Future<T?> showCommandMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required String title,
  required List<CommandMenuOption<T>> options,
}) {
  if (options.isEmpty) return Future<T?>.value();

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
    options: options,
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
          CustomSingleChildLayout(
            delegate: AnchoredLayout(
              anchor: anchor,
              maxWidth: _CommandMenuSurface.maxWidth,
              gap: 4,
              margin: 10,
            ),
            child: _CommandMenuTransition(
              animation: animation,
              alignment: alignment,
              child: _CommandMenuSurface<T>(
                title: title,
                options: options,
                onSelected: Navigator.of(routeContext).pop,
              ),
            ),
          ),
    ),
  );
}

Alignment _transitionAlignment<T>({
  required Rect? anchor,
  required Size viewport,
  required List<CommandMenuOption<T>> options,
}) {
  if (anchor == null) return Alignment.center;
  final right = anchor.center.dx > viewport.width / 2;
  final dividerCount = options.where((option) => option.dividerBefore).length;
  final estimatedHeight = options.length * 40.0 + dividerCount + 12;
  final roomBelow = viewport.height - anchor.bottom - 10;
  final above = roomBelow < estimatedHeight && anchor.top > roomBelow;
  return Alignment(right ? 1 : -1, above ? 1 : -1);
}

class _CommandMenuTransition extends StatelessWidget {
  const _CommandMenuTransition({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        alignment: alignment,
        child: child,
      ),
    );
  }
}

class _CommandMenuSurface<T> extends StatelessWidget {
  const _CommandMenuSurface({
    required this.title,
    required this.options,
    required this.onSelected,
  });

  static const double maxWidth = 380;

  final String title;
  final List<CommandMenuOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.extension<ShellColors>();
    final floating = shell?.floating ?? theme.colorScheme.surfaceContainer;
    final divider = shell?.divider ?? theme.colorScheme.outlineVariant;
    const radius = BorderRadius.all(Radius.circular(12));
    return Material(
      key: const ValueKey('command-menu-surface'),
      color: floating,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 180,
          maxWidth: maxWidth,
          maxHeight: 440,
        ),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(6),
            child: _CommandMenuRows<T>(
              title: title,
              options: options,
              onSelected: onSelected,
              dividerColor: divider,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandMenuRows<T> extends StatefulWidget {
  const _CommandMenuRows({
    required this.title,
    required this.options,
    required this.onSelected,
    required this.dividerColor,
  });

  final String title;
  final List<CommandMenuOption<T>> options;
  final ValueChanged<T> onSelected;
  final Color dividerColor;

  @override
  State<_CommandMenuRows<T>> createState() => _CommandMenuRowsState<T>();
}

class _CommandMenuRowsState<T> extends State<_CommandMenuRows<T>> {
  late final List<FocusNode> _focusNodes = [
    for (final option in widget.options)
      FocusNode(debugLabel: 'command ${option.label}'),
  ];
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
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
          label: widget.title,
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < widget.options.length; index++) ...[
                if (widget.options[index].dividerBefore)
                  Divider(height: 1, color: widget.dividerColor),
                MenuItemButton(
                  key: widget.options[index].key,
                  focusNode: _focusNodes[index],
                  onFocusChange: (focused) {
                    if (focused) _focusedIndex = index;
                  },
                  onPressed: () =>
                      widget.onSelected(widget.options[index].value),
                  leadingIcon: DIcon(widget.options[index].icon, size: 16),
                  child: Text(
                    widget.options[index].label,
                    style: widget.options[index].destructive
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
