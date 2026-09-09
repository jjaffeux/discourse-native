import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_bubble.dart';

/// Logical placement of a conversation message.
enum DMessageAlign { start, end }

/// Native application rows may retain top-anchored avatars; the shadcn
/// reference uses [bottom].
enum DMessageAvatarAlignment { bottom, top }

/// Common delivery states for [DMessageStatus].
///
/// The caller remains responsible for delivery, retry work, and persistence.
enum DMessageDeliveryState { pending, delivered, read, failed, deleted }

class _DMessageScope extends InheritedWidget {
  const _DMessageScope({
    required this.align,
    required this.hasFooter,
    required super.child,
  });

  final DMessageAlign align;
  final bool hasFooter;

  static _DMessageScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DMessageScope>();
    assert(scope != null, 'DMessage parts require a DMessage ancestor.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DMessageScope oldWidget) =>
      align != oldWidget.align || hasFooter != oldWidget.hasFooter;
}

/// A presentational conversation row.
///
/// Direct children normally contain one [DMessageAvatar] and one
/// [DMessageContent]. The row does not merge descendant semantics, own message
/// identity, scroll state, network work, or actions. Set [liveRegion] only when
/// the entire row is itself a changing status; ordinary delivery updates should
/// use [DMessageStatus] or a live [DMessageFooter].
class DMessage extends StatelessWidget {
  const DMessage({
    super.key,
    required this.children,
    this.align = DMessageAlign.start,
    this.avatarAlignment = DMessageAvatarAlignment.bottom,
    this.spacing = DSpacing.sm,
    this.semanticLabel,
    this.liveRegion = false,
  });

  final List<Widget> children;
  final DMessageAlign align;
  final DMessageAvatarAlignment avatarAlignment;
  final double spacing;
  final String? semanticLabel;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final avatars = children.whereType<DMessageAvatar>().toList();
    final content = children.whereType<DMessageContent>().toList();
    final remaining = children
        .where((child) => child is! DMessageAvatar && child is! DMessageContent)
        .toList();
    final hasFooter = content.any((part) => part.hasFooter);

    final rowChildren = <Widget>[
      ...avatars,
      if (content.isNotEmpty)
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.sm,
            children: content,
          ),
        ),
      for (final child in remaining) Expanded(child: child),
    ];
    final laidOutChildren = align == DMessageAlign.end
        ? rowChildren.reversed.toList()
        : rowChildren;

    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      letterSpacing: 0,
    );
    Widget row = DefaultTextStyle(
      style: style,
      child: Row(
        crossAxisAlignment: avatarAlignment == DMessageAvatarAlignment.bottom
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        spacing: spacing,
        children: laidOutChildren,
      ),
    );
    if (semanticLabel != null || liveRegion) {
      row = Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticLabel,
        liveRegion: liveRegion,
        child: row,
      );
    }
    return _DMessageScope(align: align, hasFooter: hasFooter, child: row);
  }
}

/// Stacks consecutive message rows from one sender with an 8px gap.
class DMessageGroup extends StatelessWidget {
  const DMessageGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.sm,
    children: children,
  );
}

/// Reserves the reference 32px avatar column.
///
/// An empty slot keeps earlier grouped messages aligned. When the message has a
/// footer, the slot shifts upward by 32px so it remains anchored to the visible
/// message surface rather than the metadata row.
class DMessageAvatar extends StatelessWidget {
  const DMessageAvatar({
    super.key,
    this.child,
    this.footerOffset = 32,
    this.shiftForFooter = true,
    this.minimumExtent = 32,
  }) : assert(footerOffset >= 0),
       assert(minimumExtent >= 0);

  final Widget? child;
  final double footerOffset;
  final bool shiftForFooter;
  final double minimumExtent;

  @override
  Widget build(BuildContext context) {
    final scope = _DMessageScope.of(context);
    return Transform.translate(
      offset: Offset(0, scope.hasFooter && shiftForFooter ? -footerOffset : 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minimumExtent,
          minHeight: minimumExtent,
        ),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          alignment: Alignment.center,
          child: child ?? const SizedBox.square(dimension: 32),
        ),
      ),
    );
  }
}

/// Stacks a header, arbitrary rich message surfaces, and a footer.
///
/// [DBubble] has its own alignment API; use the same logical alignment as the
/// surrounding message for a bubble. Other content-sized children are aligned
/// automatically. Ghost bubbles remove the metadata inset, matching base-nova.
class DMessageContent extends StatelessWidget {
  const DMessageContent({
    super.key,
    required this.children,
    this.flushMetadata,
    this.spacing = 10,
    this.alignChildren = true,
  });

  final List<Widget> children;

  /// Overrides automatic removal of header/footer horizontal padding.
  final bool? flushMetadata;
  final double spacing;

  /// Disable only when an application adapter already owns child alignment.
  final bool alignChildren;

  bool get hasFooter => children.any((child) => child is DMessageFooter);

  bool get _containsGhostBubble => children.any((child) {
    if (child is DBubble) return child.variant == DBubbleVariant.ghost;
    if (child is DBubbleGroup) {
      return child.children.any(
        (bubble) => bubble is DBubble && bubble.variant == DBubbleVariant.ghost,
      );
    }
    return false;
  });

  @override
  Widget build(BuildContext context) {
    final scope = _DMessageScope.of(context);
    final flush = flushMetadata ?? _containsGhostBubble;
    final surfaceAlignment = scope.align == DMessageAlign.start
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd;

    return _DMessageContentScope(
      flushMetadata: flush,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: spacing,
        children: [
          for (final child in children)
            if (!alignChildren ||
                child is DMessageHeader ||
                child is DMessageFooter)
              child
            else
              Align(alignment: surfaceAlignment, child: child),
        ],
      ),
    );
  }
}

class _DMessageContentScope extends InheritedWidget {
  const _DMessageContentScope({
    required this.flushMetadata,
    required super.child,
  });

  final bool flushMetadata;

  static _DMessageContentScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DMessageContentScope>();
    assert(scope != null, 'Message metadata requires DMessageContent.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DMessageContentScope oldWidget) =>
      flushMetadata != oldWidget.flushMetadata;
}

/// Sender or context metadata above a message surface.
///
/// A header always follows logical start, including for end-aligned messages.
class DMessageHeader extends StatelessWidget {
  const DMessageHeader({
    super.key,
    required this.children,
    this.spacing = DSpacing.sm,
    this.runSpacing = DSpacing.xs,
    this.semanticLabel,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => _DMessageMetadata(
    alignment: WrapAlignment.start,
    semanticLabel: semanticLabel,
    spacing: spacing,
    runSpacing: runSpacing,
    children: children,
  );
}

/// Status, timestamp, or independently focusable actions below a message.
class DMessageFooter extends StatelessWidget {
  const DMessageFooter({
    super.key,
    required this.children,
    this.spacing = 0,
    this.runSpacing = DSpacing.xs,
    this.semanticLabel,
    this.liveRegion = false,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final String? semanticLabel;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final align = _DMessageScope.of(context).align;
    return _DMessageMetadata(
      alignment: align == DMessageAlign.start
          ? WrapAlignment.start
          : WrapAlignment.end,
      semanticLabel: semanticLabel,
      liveRegion: liveRegion,
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }
}

class _DMessageMetadata extends StatelessWidget {
  const _DMessageMetadata({
    required this.alignment,
    required this.children,
    required this.spacing,
    required this.runSpacing,
    this.semanticLabel,
    this.liveRegion = false,
  });

  final WrapAlignment alignment;
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final String? semanticLabel;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final flush = _DMessageContentScope.of(context).flushMetadata;
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: DiscourseTypography.xs,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: tokens.mutedForeground,
    );
    return Semantics(
      container: semanticLabel != null || liveRegion,
      explicitChildNodes: true,
      label: semanticLabel,
      liveRegion: liveRegion,
      child: Padding(
        padding: flush
            ? EdgeInsets.zero
            : const EdgeInsetsDirectional.symmetric(horizontal: 12),
        child: DefaultTextStyle(
          style: style,
          child: IconTheme.merge(
            data: IconThemeData(size: 16, color: tokens.mutedForeground),
            child: Wrap(
              alignment: alignment,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: spacing,
              runSpacing: runSpacing,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// A generic, localizable delivery-state label for use in a message footer.
class DMessageStatus extends StatelessWidget {
  const DMessageStatus({
    super.key,
    required this.state,
    this.label,
    this.liveRegion = true,
  });

  final DMessageDeliveryState state;
  final String? label;
  final bool liveRegion;

  String get _defaultLabel => switch (state) {
    DMessageDeliveryState.pending => 'Sending',
    DMessageDeliveryState.delivered => 'Delivered',
    DMessageDeliveryState.read => 'Read',
    DMessageDeliveryState.failed => 'Failed to send',
    DMessageDeliveryState.deleted => 'Message deleted',
  };

  @override
  Widget build(BuildContext context) {
    final value = label ?? _defaultLabel;
    final tokens = DTokens.of(context);
    return Semantics(
      label: value,
      liveRegion: liveRegion,
      excludeSemantics: true,
      child: Text(
        value,
        style: state == DMessageDeliveryState.failed
            ? TextStyle(color: tokens.destructive, fontWeight: FontWeight.w400)
            : const TextStyle(fontWeight: FontWeight.w400),
      ),
    );
  }
}
