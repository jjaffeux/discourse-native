import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_marker.dart';
import 'd_scroll_area.dart';

/// The externally owned lifecycle represented by an attachment.
enum DAttachmentState { idle, uploading, processing, error, done }

/// Base-nova's default, small, and extra-small attachment geometries.
enum DAttachmentSize { regular, small, extraSmall }

enum DAttachmentOrientation { horizontal, vertical }

enum DAttachmentMediaVariant { icon, image }

/// A composed file or image attachment.
///
/// The caller owns file data, network work, progress, errors, and state changes.
/// Direct children are the documented [DAttachmentMedia],
/// [DAttachmentContent], [DAttachmentActions], and [DAttachmentTrigger] parts.
/// A trigger is layered behind independently focusable actions.
class DAttachment extends StatefulWidget {
  const DAttachment({
    super.key,
    required this.children,
    this.state = DAttachmentState.done,
    this.size = DAttachmentSize.regular,
    this.orientation = DAttachmentOrientation.horizontal,
    this.width,
    this.constraints,
    this.semanticLabel,
    this.liveRegion = false,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
  });

  final List<Widget> children;
  final DAttachmentState state;
  final DAttachmentSize size;
  final DAttachmentOrientation orientation;
  final double? width;
  final BoxConstraints? constraints;
  final String? semanticLabel;
  final bool liveRegion;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  @override
  State<DAttachment> createState() => _DAttachmentState();
}

class _DAttachmentState extends State<DAttachment> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final trigger = widget.children.whereType<DAttachmentTrigger>().firstOrNull;
    final actions = widget.children.whereType<DAttachmentActions>().toList();
    final visual = widget.children
        .where(
          (child) =>
              child is! DAttachmentTrigger && child is! DAttachmentActions,
        )
        .toList();
    final padding = _rootPadding(visual);
    final radius =
        widget.borderRadius ??
        BorderRadius.circular(
          tokens.radius * (widget.size == DAttachmentSize.extraSmall ? 1 : 1.4),
        );
    final error = widget.state == DAttachmentState.error;
    final borderColor =
        widget.borderColor ??
        (error
            ? tokens.destructive.withValues(alpha: tokens.destructive.a * .3)
            : tokens.border);
    final background =
        widget.backgroundColor ??
        (trigger != null && _hovered
            ? Color.alphaBlend(
                tokens.muted.withValues(alpha: tokens.muted.a * .5),
                tokens.surface,
              )
            : tokens.surface);
    Widget inScope(Widget child) => _DAttachmentScope(
      state: widget.state,
      size: widget.size,
      orientation: widget.orientation,
      child: child,
    );

    Widget card = Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        if (trigger != null) Positioned.fill(child: trigger),
        IgnorePointer(
          child: inScope(
            Padding(padding: padding, child: _layout(visual, actions)),
          ),
        ),
        if (actions.isNotEmpty)
          if (widget.orientation == DAttachmentOrientation.vertical)
            PositionedDirectional(
              top: 12,
              end: 12,
              child: inScope(actions.first),
            )
          else
            PositionedDirectional(
              top: 0,
              bottom: 0,
              end: padding.right,
              child: Center(child: inScope(actions.first)),
            ),
      ],
    );
    card = Container(
      width: widget.width,
      constraints:
          widget.constraints ??
          (widget.orientation == DAttachmentOrientation.horizontal
              ? const BoxConstraints(minWidth: 160)
              : const BoxConstraints.tightFor(width: 96)),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        // Keep the border's layout inset while the idle state's dashed stroke
        // is painted separately below.
        border: Border.all(
          color: widget.state == DAttachmentState.idle
              ? Colors.transparent
              : borderColor,
        ),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: tokens.focusRing.withValues(
                  alpha: tokens.focusRing.a * .5,
                ),
                width: 3,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            )
          : null,
      child: card,
    );
    if (widget.state == DAttachmentState.idle) {
      card = CustomPaint(
        foregroundPainter: _DashedAttachmentBorder(
          color: borderColor,
          radius: radius,
        ),
        child: card,
      );
    }
    card = MouseRegion(
      cursor: trigger?.enabled == true
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: trigger == null ? null : (_) => setState(() => _hovered = true),
      onExit: trigger == null ? null : (_) => setState(() => _hovered = false),
      child: Focus(
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: card,
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      liveRegion: widget.liveRegion,
      child: card,
    );
  }

  EdgeInsets _rootPadding(List<Widget> visual) {
    // The reference applies its size padding to Attachment itself through
    // `:has()` selectors. Media's all-sided padding wins over Content's
    // horizontal padding when both documented parts are present.
    if (visual.any((child) => child is DAttachmentMedia)) {
      return EdgeInsets.all(switch (widget.size) {
        DAttachmentSize.regular => 8,
        DAttachmentSize.small => 6,
        DAttachmentSize.extraSmall => 4,
      });
    }
    if (visual.any((child) => child is DAttachmentContent)) {
      return switch (widget.size) {
        DAttachmentSize.regular => const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        DAttachmentSize.small => const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        DAttachmentSize.extraSmall => const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 4,
        ),
      };
    }
    return EdgeInsets.zero;
  }

  Widget _layout(List<Widget> visual, List<DAttachmentActions> actions) {
    final gap = switch (widget.size) {
      DAttachmentSize.regular => 8.0,
      DAttachmentSize.small => 10.0,
      DAttachmentSize.extraSmall => 6.0,
    };
    if (widget.orientation == DAttachmentOrientation.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(visual, gap, Axis.vertical),
      );
    }
    final children = <Widget>[];
    for (final child in visual) {
      if (children.isNotEmpty) children.add(SizedBox(width: gap));
      children.add(
        child is DAttachmentContent ? Flexible(child: child) : child,
      );
    }
    if (actions.isNotEmpty) {
      if (children.isNotEmpty) children.add(SizedBox(width: gap));
      final touch = switch (Theme.of(context).platform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };
      final actionWidth = touch
          ? actions.first.touchVisualWidth
          : actions.first.horizontalVisualWidth;
      children.add(SizedBox(width: actionWidth));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  static List<Widget> _spaced(List<Widget> children, double gap, Axis axis) {
    final result = <Widget>[];
    for (final child in children) {
      if (result.isNotEmpty) {
        result.add(
          axis == Axis.horizontal
              ? SizedBox(width: gap)
              : SizedBox(height: gap),
        );
      }
      result.add(child);
    }
    return result;
  }
}

class _DAttachmentScope extends InheritedWidget {
  const _DAttachmentScope({
    required this.state,
    required this.size,
    required this.orientation,
    required super.child,
  });

  final DAttachmentState state;
  final DAttachmentSize size;
  final DAttachmentOrientation orientation;

  static _DAttachmentScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DAttachmentScope>();
    assert(
      scope != null,
      'Attachment parts must be descendants of DAttachment.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(_DAttachmentScope oldWidget) =>
      state != oldWidget.state ||
      size != oldWidget.size ||
      orientation != oldWidget.orientation;
}

/// Icon or square image artwork. The surrounding attachment owns geometry.
class DAttachmentMedia extends StatelessWidget {
  const DAttachmentMedia({
    super.key,
    required this.child,
    this.variant = DAttachmentMediaVariant.icon,
    this.semanticLabel,
    this.backgroundColor,
  });

  final Widget child;
  final DAttachmentMediaVariant variant;
  final String? semanticLabel;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scope = _DAttachmentScope.of(context);
    final tokens = DTokens.of(context);
    final extent = switch ((scope.orientation, scope.size)) {
      (DAttachmentOrientation.vertical, _) => 96.0,
      (_, DAttachmentSize.regular) => 40.0,
      (_, DAttachmentSize.small) => 32.0,
      (_, DAttachmentSize.extraSmall) => 28.0,
    };
    final iconSize = switch ((scope.orientation, scope.size)) {
      (_, DAttachmentSize.extraSmall) => 14.0,
      (DAttachmentOrientation.vertical, _) => 24.0,
      _ => 16.0,
    };
    final padding = switch (scope.size) {
      DAttachmentSize.regular => 8.0,
      DAttachmentSize.small => 6.0,
      DAttachmentSize.extraSmall => 4.0,
    };
    final error = scope.state == DAttachmentState.error;
    final radius = BorderRadius.circular(
      tokens.radius * (scope.size == DAttachmentSize.extraSmall ? .8 : 1),
    );
    Widget content = variant == DAttachmentMediaVariant.image
        ? SizedBox.expand(child: child)
        : Padding(
            padding: EdgeInsets.all(padding),
            child: Center(
              child: SizedBox.square(
                dimension: iconSize,
                child: FittedBox(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      size: iconSize,
                      color: error ? tokens.destructive : tokens.foreground,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          );
    Widget artwork = scope.orientation == DAttachmentOrientation.vertical
        ? AspectRatio(aspectRatio: 1, child: content)
        : SizedBox.square(dimension: extent, child: content);
    if (variant == DAttachmentMediaVariant.image &&
        scope.state != DAttachmentState.done &&
        scope.state != DAttachmentState.idle) {
      artwork = Opacity(opacity: .6, child: artwork);
    }
    artwork = ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color:
            backgroundColor ??
            (error
                ? tokens.destructive.withValues(
                    alpha: tokens.destructive.a * .1,
                  )
                : tokens.muted),
        child: artwork,
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: artwork)
        : Semantics(image: true, label: semanticLabel, child: artwork);
  }
}

class DAttachmentContent extends StatelessWidget {
  const DAttachmentContent({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scope = _DAttachmentScope.of(context);
    return Padding(
      padding: scope.orientation == DAttachmentOrientation.vertical
          ? const EdgeInsets.symmetric(horizontal: 4)
          : EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class DAttachmentTitle extends StatelessWidget {
  const DAttachmentTitle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _DAttachmentScope.of(context);
    final fontSize = scope.size == DAttachmentSize.regular
        ? DiscourseTypography.sm
        : DiscourseTypography.xs;
    return DefaultTextStyle.merge(
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        height: (scope.size == DAttachmentSize.regular ? 17.5 : 15) / fontSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: DTokens.of(context).foreground,
      ),
      child: DMarkerContent(
        shimmer:
            scope.state == DAttachmentState.uploading ||
            scope.state == DAttachmentState.processing,
        child: child,
      ),
    );
  }
}

class DAttachmentDescription extends StatelessWidget {
  const DAttachmentDescription({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _DAttachmentScope.of(context);
    final tokens = DTokens.of(context);
    final color = scope.state == DAttachmentState.error
        ? tokens.destructive.withValues(alpha: tokens.destructive.a * .8)
        : tokens.mutedForeground;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: DefaultTextStyle.merge(
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: DiscourseTypography.xs,
          height: 16 / DiscourseTypography.xs,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: color,
        ),
        child: child,
      ),
    );
  }
}

class DAttachmentActions extends StatelessWidget {
  const DAttachmentActions({super.key, required this.children});
  final List<DAttachmentAction> children;

  double get horizontalVisualWidth => math.max(
    DButton.visualDimensionFor(DButtonSize.extraSmall),
    children.fold(
      0,
      (width, action) => width + DButton.visualDimensionFor(action.size),
    ),
  );

  double get touchVisualWidth => children.fold(
    0,
    (width, action) =>
        width +
        math.max(DSpacing.touchTarget, DButton.visualDimensionFor(action.size)),
  );

  @override
  Widget build(BuildContext context) {
    final scope = _DAttachmentScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0 && scope.orientation == DAttachmentOrientation.vertical)
            const SizedBox(width: 4),
          children[index],
        ],
      ],
    );
  }
}

/// The default icon-only ghost button used by attachment actions.
///
/// [focusNode] is borrowed. The caller owns callback work and loading state.
class DAttachmentAction extends StatelessWidget {
  const DAttachmentAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.loading = false,
    this.variant = DButtonVariant.ghost,
    this.size = DButtonSize.extraSmall,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool loading;
  final DButtonVariant variant;
  final DButtonSize size;

  @override
  Widget build(BuildContext context) {
    return DButton.iconOnly(
      icon: icon,
      tooltip: tooltip,
      semanticLabel: semanticLabel ?? tooltip,
      onPressed: onPressed,
      focusNode: focusNode,
      autofocus: autofocus,
      loading: loading,
      variant: variant,
      size: size,
    );
  }
}

/// A transparent full-card button or link layered behind attachment actions.
///
/// [focusNode] is borrowed. Use [isLink] when activation performs navigation.
class DAttachmentTrigger extends StatefulWidget {
  const DAttachmentTrigger({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
    this.isLink = false,
    this.focusNode,
    this.autofocus = false,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool isLink;
  final FocusNode? focusNode;
  final bool autofocus;

  bool get enabled => onPressed != null;

  @override
  State<DAttachmentTrigger> createState() => _DAttachmentTriggerState();
}

class _DAttachmentTriggerState extends State<DAttachmentTrigger> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _ownedFocusNode = widget.focusNode == null
        ? FocusNode(debugLabel: 'Attachment trigger')
        : null;
    _focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(DAttachmentTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    (oldWidget.focusNode ?? _ownedFocusNode)?.removeListener(_focusChanged);
    _ownedFocusNode?.dispose();
    _ownedFocusNode = widget.focusNode == null
        ? FocusNode(debugLabel: 'Attachment trigger')
        : null;
    _focusNode.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_focusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: widget.semanticLabel,
    button: !widget.isLink,
    link: widget.isLink,
    enabled: widget.enabled,
    focusable: widget.enabled,
    focused: _focusNode.hasFocus,
    onFocus: widget.enabled ? _focusNode.requestFocus : null,
    onTap: widget.onPressed,
    child: InkWell(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onTap: widget.onPressed,
      mouseCursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: const SizedBox.expand(),
    ),
  );
}

/// Horizontally scrollable, edge-faded attachment row.
///
/// Supplied [controller] and [focusNode] are borrowed. Omitted resources are
/// owned and disposed by the group. Set [semanticLabel] for a presentational
/// group so the scroll viewport is announced and keyboard reachable.
class DAttachmentGroup extends StatefulWidget {
  const DAttachmentGroup({
    super.key,
    required this.children,
    this.controller,
    this.focusNode,
    this.semanticLabel,
    this.snapExtent = 268,
    this.gap = 12,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  }) : assert(snapExtent > 0),
       assert(gap >= 0);

  final List<Widget> children;
  final ScrollController? controller;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final double snapExtent;
  final double gap;
  final EdgeInsetsGeometry padding;

  @override
  State<DAttachmentGroup> createState() => _DAttachmentGroupState();
}

class _DAttachmentGroupState extends State<DAttachmentGroup> {
  ScrollController? _ownedController;
  FocusNode? _ownedFocusNode;

  ScrollController get _controller =>
      widget.controller ?? (_ownedController ??= ScrollController());
  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'Attachment group'));

  @override
  void didUpdateWidget(DAttachmentGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == null && widget.controller != null) {
      _ownedController?.dispose();
      _ownedController = null;
    }
    if (oldWidget.focusNode == null && widget.focusNode != null) {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget group = DScrollArea(
      axes: DScrollAxes.horizontal,
      controller: _controller,
      thumbVisibility: false,
      padding: widget.padding,
      physics: _AttachmentSnapScrollPhysics(
        extent: widget.snapExtent,
        parent: const ClampingScrollPhysics(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < widget.children.length; index++) ...[
            if (index > 0) SizedBox(width: widget.gap),
            widget.children[index],
          ],
        ],
      ),
    );
    group = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0, .04, .96, 1],
      ).createShader(bounds),
      child: group,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: Focus(
        focusNode: widget.semanticLabel == null ? null : _focusNode,
        canRequestFocus: widget.semanticLabel != null,
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent || !_controller.hasClients) {
            return KeyEventResult.ignored;
          }
          final position = _controller.position;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final key = event.logicalKey;
          final double delta;
          if (key == LogicalKeyboardKey.arrowRight) {
            delta = rtl ? -40 : 40;
          } else if (key == LogicalKeyboardKey.arrowLeft) {
            delta = rtl ? 40 : -40;
          } else if (key == LogicalKeyboardKey.home) {
            delta = position.minScrollExtent - position.pixels;
          } else if (key == LogicalKeyboardKey.end) {
            delta = position.maxScrollExtent - position.pixels;
          } else {
            return KeyEventResult.ignored;
          }
          _controller.jumpTo(
            (position.pixels + delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
          return KeyEventResult.handled;
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: group,
        ),
      ),
    );
  }
}

class _AttachmentSnapScrollPhysics extends ScrollPhysics {
  const _AttachmentSnapScrollPhysics({required this.extent, super.parent});
  final double extent;

  @override
  _AttachmentSnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _AttachmentSnapScrollPhysics(
        extent: extent,
        parent: buildParent(ancestor),
      );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var page = position.pixels / extent;
    if (velocity < -tolerance.velocity) {
      page -= .5;
    } else if (velocity > tolerance.velocity) {
      page += .5;
    }
    final target = (page.round() * extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

class _DashedAttachmentBorder extends CustomPainter {
  const _DashedAttachmentBorder({required this.color, required this.radius});
  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(radius.toRRect(Offset.zero & size).deflate(.5));
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 4, metric.length)),
          paint,
        );
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedAttachmentBorder oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
