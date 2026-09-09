import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// How a breadcrumb list responds when its path is wider than the viewport.
enum DBreadcrumbOverflow { wrap, scroll }

/// Wraps a typed route destination around the link surface.
///
/// The returned widget may add routing metadata or secondary-click behavior,
/// but [child] remains the sole focus, activation, and link-semantics owner.
typedef DBreadcrumbRouteAdapter<T> =
    Widget Function(BuildContext context, T destination, Widget child);

/// The navigation landmark for a path to the current resource.
class DBreadcrumb extends StatelessWidget {
  const DBreadcrumb({
    super.key,
    required this.child,
    this.semanticLabel = 'Breadcrumb',
    this.textDirection,
  });

  final Widget child;
  final String semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    Widget result = Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: child,
    );
    if (textDirection != null) {
      result = Directionality(textDirection: textDirection!, child: result);
    }
    return result;
  }
}

/// An ordered visual list of breadcrumb items and separators.
///
/// [DBreadcrumbOverflow.wrap] matches the reference. Use [scroll] when a real
/// application path must remain on one line; focused links scroll into view.
class DBreadcrumbList extends StatelessWidget {
  const DBreadcrumbList({
    super.key,
    required this.children,
    this.overflow = DBreadcrumbOverflow.wrap,
    this.spacing = 6,
    this.runSpacing = 6,
    this.alignment = WrapAlignment.start,
  });

  final List<Widget> children;
  final DBreadcrumbOverflow overflow;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: DTokens.of(context).mutedForeground,
      fontSize: DiscourseTypography.sm,
      height: DiscourseTypography.lineHeightSmall,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );

    final content = switch (overflow) {
      DBreadcrumbOverflow.wrap => Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
      DBreadcrumbOverflow.scroll => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: spacing,
          children: children,
        ),
      ),
    };

    return DefaultTextStyle.merge(style: style, child: content);
  }
}

/// Groups the content that represents one level of the path.
class DBreadcrumbItem extends StatelessWidget {
  const DBreadcrumbItem({super.key, required this.child, this.spacing = 4})
    : children = null;

  const DBreadcrumbItem.children({
    super.key,
    required List<Widget> this.children,
    this.spacing = 4,
  }) : child = null;

  final Widget? child;
  final List<Widget>? children;
  final double spacing;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: spacing,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children ?? [child!],
  );
}

/// A focusable breadcrumb link with caller-owned navigation.
///
/// Use [DBreadcrumbLink.route] for typed route values. A null callback keeps
/// the link visible but disabled. Borrowed [focusNode]s are never disposed.
class DBreadcrumbLink extends StatefulWidget {
  const DBreadcrumbLink({
    super.key,
    required this.child,
    required this.onPressed,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Creates a link whose destination and callback retain their route type.
  static Widget route<T>({
    Key? key,
    required Widget child,
    required T destination,
    required ValueChanged<T>? onNavigate,
    DBreadcrumbRouteAdapter<T>? adapter,
    String? semanticLabel,
    FocusNode? focusNode,
    bool autofocus = false,
  }) => _DBreadcrumbRouteLink<T>(
    key: key,
    destination: destination,
    onNavigate: onNavigate,
    adapter: adapter,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    autofocus: autofocus,
    child: child,
  );

  @override
  State<DBreadcrumbLink> createState() => _DBreadcrumbLinkState();
}

class _DBreadcrumbLinkState extends State<DBreadcrumbLink> {
  FocusNode? _ownedFocusNode;
  bool _hovered = false;
  bool _focused = false;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'Breadcrumb link'));

  bool get _enabled => widget.onPressed != null;

  void _activate() {
    if (!_enabled) return;
    widget.onPressed!.call();
  }

  void _ensureVisible(bool focused) {
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.context != null) {
        Scrollable.ensureVisible(
          _focusNode.context!,
          alignment: 0.5,
          duration: DMotion.duration(context, DMotion.exit),
        );
      }
    });
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final enabled = _enabled;
    final duration = DMotion.duration(
      context,
      const Duration(milliseconds: 150),
    );
    final interactiveColor = enabled && (_hovered || _focused)
        ? tokens.foreground
        : tokens.mutedForeground;
    final color = enabled
        ? interactiveColor
        : tokens.mutedForeground.withValues(
            alpha: tokens.mutedForeground.a * .5,
          );
    final platform = Theme.of(context).platform;
    final touch =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;

    Widget result = Semantics(
      button: false,
      link: true,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? _activate : null,
      child: ExcludeSemantics(
        excluding: widget.semanticLabel != null,
        child: FocusableActionDetector(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          enabled: enabled,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onFocusChange: _ensureVisible,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: enabled ? _activate : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: touch ? 48 : 0),
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radius * .6),
                  border: _focused
                      ? Border.all(color: tokens.focusRing, width: 1)
                      : null,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: Curves.easeOut,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: color,
                      fontSize: DiscourseTypography.sm,
                      height: DiscourseTypography.lineHeightSmall,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(color: color, size: 14),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return result;
  }
}

class _DBreadcrumbRouteLink<T> extends StatelessWidget {
  const _DBreadcrumbRouteLink({
    super.key,
    required this.destination,
    required this.onNavigate,
    required this.child,
    this.adapter,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  });

  final T destination;
  final ValueChanged<T>? onNavigate;
  final Widget child;
  final DBreadcrumbRouteAdapter<T>? adapter;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    Widget result = DBreadcrumbLink(
      onPressed: onNavigate == null ? null : () => onNavigate!(destination),
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      autofocus: autofocus,
      child: child,
    );
    final adapter = this.adapter;
    if (adapter != null) result = adapter(context, destination, result);
    return result;
  }
}

/// The non-interactive current page in the path.
class DBreadcrumbPage extends StatelessWidget {
  const DBreadcrumbPage({super.key, required this.child, this.semanticLabel});

  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    enabled: false,
    selected: true,
    label: semanticLabel,
    child: ExcludeSemantics(
      excluding: semanticLabel != null,
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: DTokens.of(context).foreground,
          fontSize: DiscourseTypography.sm,
          height: DiscourseTypography.lineHeightSmall,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: DTokens.of(context).foreground, size: 14),
          child: child,
        ),
      ),
    ),
  );
}

/// A decorative logical separator between breadcrumb items.
class DBreadcrumbSeparator extends StatelessWidget {
  const DBreadcrumbSeparator({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 14,
        child: Center(
          child: IconTheme.merge(
            data: IconThemeData(color: color, size: 14),
            child:
                child ??
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: const DIcon(DIcons.chevronRight, size: 14),
                ),
          ),
        ),
      ),
    );
  }
}

/// A decorative indicator for omitted breadcrumb levels.
///
/// Wrap it in a labeled button or menu trigger when it is interactive.
class DBreadcrumbEllipsis extends StatelessWidget {
  const DBreadcrumbEllipsis({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 20,
      child: Center(
        child: IconTheme.merge(
          data: IconThemeData(
            color: DefaultTextStyle.of(context).style.color,
            size: 16,
          ),
          child: const DIcon(DIcons.ellipsis, size: 16),
        ),
      ),
    ),
  );
}
