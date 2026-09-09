import 'package:flutter/material.dart';

import '../../discourse_ui.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import 'anchored_layout.dart';
import 'popup_transition.dart';

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
            child: PopupTransition(
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
          child: _CommandMenuRows<T>(
            title: title,
            options: options,
            onSelected: onSelected,
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
  });

  final String title;
  final List<CommandMenuOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  State<_CommandMenuRows<T>> createState() => _CommandMenuRowsState<T>();
}

class _CommandMenuRowsState<T> extends State<_CommandMenuRows<T>> {
  late final DCommandController<T> _controller = DCommandController<T>(
    initialValue: widget.options.first.value,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstRow());
  }

  void _focusFirstRow() {
    if (!mounted) return;
    final scope = FocusScope.of(context);
    scope.nextFocus();
  }

  List<Widget> _children() {
    final children = <Widget>[];
    var group = <DCommandItem<T>>[];
    void flush() {
      if (group.isEmpty) return;
      children.add(DCommandGroup<T>(items: group));
      group = [];
    }

    for (final option in widget.options) {
      if (option.dividerBefore) {
        flush();
        children.add(DCommandSeparator<T>());
      }
      group.add(
        DCommandItem<T>(
          key: option.key,
          value: option.value,
          searchValue: option.label,
          leading: DIcon(option.icon, size: 16),
          destructive: option.destructive,
          child: Text(option.label),
        ),
      );
    }
    flush();
    return children;
  }

  @override
  Widget build(BuildContext context) {
    return DCommand<T>(
      controller: _controller,
      semanticLabel: widget.title,
      shouldFilter: false,
      loop: true,
      onEscape: Navigator.of(context).maybePop,
      onSelected: widget.onSelected,
      child: DCommandList<T>(maxHeight: 428, children: _children()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
