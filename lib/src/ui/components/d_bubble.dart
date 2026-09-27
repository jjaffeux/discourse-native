import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_spinner.dart';

enum DBubbleVariant {
  primary,

  /// Muted accent fill with the conversation's 12px corners and 13.5px text.
  accent,

  /// Raised neutral fill with the same geometry as [accent].
  neutral,
  secondary,
  muted,
  tinted,
  outline,
  ghost,
  destructive,
}

enum DBubbleAlign { start, end }

enum DBubbleReactionSide { top, bottom }

/// The native semantic role for an interactive [DBubbleContent].
enum DBubbleContentAction { button, link }

@immutable
class _DBubbleScope extends InheritedWidget {
  const _DBubbleScope({
    required this.variant,
    required this.align,
    required super.child,
    this.quote = false,
  });

  final DBubbleVariant variant;
  final DBubbleAlign align;
  final bool quote;

  static _DBubbleScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DBubbleScope>();
    assert(scope != null, 'DBubble parts require a DBubble ancestor.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DBubbleScope oldWidget) =>
      variant != oldWidget.variant ||
      align != oldWidget.align ||
      quote != oldWidget.quote;
}

/// A content-sized conversational surface aligned within its available row.
///
/// Direct [DBubbleReactions] children are positioned over the content edge and
/// do not consume layout space, matching the reference composition. Conversation
/// roles, author names and timestamps belong to the surrounding Message owner.
class DBubble extends StatelessWidget {
  const DBubble({
    super.key,
    required this.children,
    this.variant = DBubbleVariant.primary,
    this.align = DBubbleAlign.start,
    this.maximumWidthFactor = .8,
  }) : assert(maximumWidthFactor > 0 && maximumWidthFactor <= 1);

  final List<Widget> children;
  final DBubbleVariant variant;
  final DBubbleAlign align;

  /// The non-ghost width limit relative to the available conversation width.
  final double maximumWidthFactor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = <Widget>[];
      final reactions = <DBubbleReactions>[];
      for (final child in children) {
        if (child is DBubbleReactions) {
          reactions.add(child);
        } else {
          content.add(child);
        }
      }

      final finiteWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final maxWidth = variant == DBubbleVariant.ghost
          ? finiteWidth
          : finiteWidth * maximumWidthFactor;
      final alignment = switch (align) {
        DBubbleAlign.start => AlignmentDirectional.centerStart,
        DBubbleAlign.end => AlignmentDirectional.centerEnd,
      };

      return Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: _DBubbleScope(
            variant: variant,
            align: align,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: align == DBubbleAlign.start
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  spacing: DSpacing.xs,
                  children: content,
                ),
                for (final reaction in reactions)
                  PositionedDirectional(
                    top: reaction.side == DBubbleReactionSide.top ? 0 : null,
                    bottom: reaction.side == DBubbleReactionSide.bottom
                        ? 0
                        : null,
                    start: reaction.align == DBubbleAlign.start ? 12 : null,
                    end: reaction.align == DBubbleAlign.end ? 12 : null,
                    child: FractionalTranslation(
                      translation: Offset(
                        0,
                        reaction.side == DBubbleReactionSide.top
                            ? (reaction.interactive ? -.45 : -.75)
                            : (reaction.interactive ? .45 : .75),
                      ),
                      child: reaction,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Groups consecutive bubbles from one sender with the reference 8px gap.
class DBubbleGroup extends StatelessWidget {
  const DBubbleGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.sm,
    children: children,
  );
}

@immutable
class _ContentStyle {
  const _ContentStyle({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

/// The framed content inside a [DBubble].
///
/// Set [action] to expose a real button or link. [focusNode] is borrowed and
/// never disposed; an omitted node is owned internally. [busy] is controlled
/// by the caller and blocks activation without owning asynchronous work.
/// Presentational content participates in any surrounding SelectionArea;
/// interactive content disables text selection so pointer activation is clear.
class DBubbleContent extends StatefulWidget {
  const DBubbleContent({
    super.key,
    required this.child,
    this.compact = false,
    this.borderRadius,
    this.trailingAction,
    this.quote,
    this.action,
    this.onPressed,
    this.disabled = false,
    this.busy = false,
    this.busyLabel = 'Working',
    this.selected = false,
    this.invalid = false,
    this.errorLabel,
    this.semanticLabel,
    this.semanticHint,
    this.focusNode,
    this.autofocus = false,
  }) : assert(action != null || onPressed == null),
       assert(!busy || action != null),
       assert(!selected || action != null),
       assert(action == null || (trailingAction == null && quote == null));

  final Widget child;

  /// An independently interactive control at the top trailing corner. Reserve
  /// its slot with a hidden control when revealing actions on hover or focus.
  /// Whole-surface actions must not contain another action.
  final Widget? trailingAction;

  /// An inset reply reference above the body, normally a [DBubbleQuote].
  final Widget? quote;

  /// Uses 4px vertical padding instead of 8px for compact conversations.
  /// Horizontal padding remains 12px; ghost bubbles remain unpadded.
  final bool compact;

  /// Overrides the surface corners. Directional radii follow the text direction.
  /// Defaults to the variant's usual shape.
  final BorderRadiusGeometry? borderRadius;
  final DBubbleContentAction? action;
  final VoidCallback? onPressed;
  final bool disabled;
  final bool busy;
  final String busyLabel;
  final bool selected;
  final bool invalid;
  final String? errorLabel;
  final String? semanticLabel;
  final String? semanticHint;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<DBubbleContent> createState() => _DBubbleContentState();
}

class _DBubbleContentState extends State<DBubbleContent> {
  FocusNode? _ownedFocus;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownedFocus ??= FocusNode(debugLabel: 'DBubbleContent action'));

  bool get _enabled =>
      widget.action != null &&
      widget.onPressed != null &&
      !widget.disabled &&
      !widget.busy;

  @override
  void didUpdateWidget(DBubbleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode &&
        oldWidget.focusNode == null) {
      _ownedFocus?.dispose();
      _ownedFocus = null;
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  _ContentStyle _style(BuildContext context, bool interactive) {
    final scope = _DBubbleScope.of(context);
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = interactive && (_hovered || _pressed);
    Color mix(Color base, Color foreground, double amount) =>
        Color.lerp(base, foreground, amount)!;
    final secondary = mix(tokens.muted, tokens.foreground, .01);

    var style = switch (scope.variant) {
      DBubbleVariant.neutral => _ContentStyle(
        background: mix(
          tokens.background,
          tokens.foreground,
          active ? .14 : .10,
        ),
        foreground: tokens.foreground,
        border: mix(tokens.background, tokens.foreground, .12),
      ),
      DBubbleVariant.accent => _ContentStyle(
        background: active
            ? tokens.buttonTheme.primary.hover
            : tokens.buttonTheme.primary.background,
        foreground: tokens.buttonTheme.primary.foreground,
        border: Colors.transparent,
      ),
      DBubbleVariant.primary => _ContentStyle(
        background: active
            ? tokens.primary.withValues(alpha: tokens.primary.a * .8)
            : tokens.primary,
        foreground: tokens.primaryForeground,
        border: Colors.transparent,
      ),
      DBubbleVariant.secondary => _ContentStyle(
        background: active ? mix(secondary, tokens.foreground, .05) : secondary,
        foreground: tokens.foreground,
        border: Colors.transparent,
      ),
      DBubbleVariant.muted => _ContentStyle(
        background: active
            ? mix(tokens.muted, tokens.foreground, .05)
            : tokens.muted,
        foreground: tokens.foreground,
        border: Colors.transparent,
      ),
      DBubbleVariant.tinted => _ContentStyle(
        background: mix(
          tokens.background,
          tokens.primary,
          active ? (dark ? .30 : .18) : (dark ? .24 : .12),
        ),
        foreground: tokens.foreground,
        border: Colors.transparent,
      ),
      DBubbleVariant.outline => _ContentStyle(
        background: active
            ? (dark
                  ? tokens.colors.outlineVariant.withValues(
                      alpha: tokens.colors.outlineVariant.a * .3,
                    )
                  : tokens.muted)
            : tokens.background,
        foreground: tokens.foreground,
        border: tokens.border,
      ),
      DBubbleVariant.ghost => _ContentStyle(
        background: active
            ? tokens.muted.withValues(alpha: tokens.muted.a * (dark ? .5 : 1))
            : Colors.transparent,
        foreground: tokens.foreground,
        border: Colors.transparent,
      ),
      DBubbleVariant.destructive => _ContentStyle(
        background: tokens.destructive.withValues(
          alpha:
              tokens.destructive.a *
              (active ? (dark ? .3 : .2) : (dark ? .2 : .1)),
        ),
        foreground: tokens.destructive,
        border: Colors.transparent,
      ),
    };
    if (scope.quote) {
      style = _ContentStyle(
        background: mix(
          tokens.background,
          tokens.foreground,
          active ? .08 : .035,
        ),
        foreground: tokens.foreground,
        border: tokens.primary,
      );
    }
    if (widget.invalid) {
      style = _ContentStyle(
        background: style.background,
        foreground: style.foreground,
        border: tokens.destructive,
      );
    }
    return style;
  }

  Widget _surface(BuildContext context, {required bool interactive}) {
    final scope = _DBubbleScope.of(context);
    final style = _style(context, interactive);
    final ghost = scope.variant == DBubbleVariant.ghost;
    final conversation =
        scope.quote ||
        scope.variant == DBubbleVariant.accent ||
        scope.variant == DBubbleVariant.neutral;
    final radius =
        widget.borderRadius?.resolve(Directionality.of(context)) ??
        (ghost ? BorderRadius.zero : BorderRadius.circular(DRadius.bubble));
    final status = widget.busy
        ? DSpinner(size: 14, semanticLabel: null, color: style.foreground)
        : widget.invalid
        ? Icon(Icons.error_outline, size: 14, color: style.foreground)
        : widget.selected
        ? Icon(Icons.check, size: 14, color: style.foreground)
        : null;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: style.foreground,
      fontSize: conversation
          ? DiscourseTypography.compact
          : DiscourseTypography.sm,
      height: conversation ? 1.5 : 1.625,
    );

    return AnimatedContainer(
      duration: DMotion.duration(context, DMotion.change),
      curve: Curves.easeOut,
      // Corner controls may own popovers whose accessibility subtree must
      // remain visible beyond the bubble's rounded surface.
      clipBehavior: widget.trailingAction == null ? Clip.antiAlias : Clip.none,
      padding: ghost
          ? EdgeInsets.zero
          : widget.compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
          : DInsets.bubble,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: radius,
        border: scope.quote
            ? BorderDirectional(
                start: BorderSide(color: style.border, width: 3),
              )
            : Border.all(color: style.border),
      ),
      child: DefaultTextStyle.merge(
        style: textStyle,
        child: IconTheme.merge(
          data: IconThemeData(color: style.foreground, size: 16),
          child: _contents(context, status),
        ),
      ),
    );
  }

  Widget _contents(BuildContext context, Widget? status) {
    if (widget.trailingAction == null && widget.quote == null) {
      if (status == null) return widget.child;
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DSpacing.sm,
        children: [
          Flexible(child: widget.child),
          status,
        ],
      );
    }
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DSpacing.sm,
      children: [?widget.quote, widget.child],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Give the corner action its own line when scaled content needs the full
        // bubble width, keeping quotes and attachments readable in narrow panes.
        if (constraints.maxWidth <
            MediaQuery.textScalerOf(context).scale(160)) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.xs,
            children: [
              if (widget.trailingAction case final action?)
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              body,
              ?status,
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DSpacing.xs,
          children: [
            Flexible(child: body),
            ?status,
            ?widget.trailingAction,
          ],
        );
      },
    );
  }

  void _activate() {
    if (!_enabled) return;
    _focus.requestFocus();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.action == null) return _surface(context, interactive: false);

    final scope = _DBubbleScope.of(context);
    final tokens = DTokens.of(context);
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
      if (widget.action == DBubbleContentAction.button)
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
      if (widget.action == DBubbleContentAction.link)
        const SingleActivator(LogicalKeyboardKey.space):
            const DoNothingIntent(),
    };
    final semanticValue = [
      if (widget.busy) widget.busyLabel,
      if (widget.invalid && widget.errorLabel != null) widget.errorLabel!,
    ].join('. ');

    return Semantics(
      container: true,
      button: widget.action == DBubbleContentAction.button,
      link: widget.action == DBubbleContentAction.link,
      enabled: _enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      value: semanticValue.isEmpty ? null : semanticValue,
      liveRegion: widget.busy || widget.invalid,
      onTap: _enabled ? _activate : null,
      child: FocusableActionDetector(
        focusNode: _focus,
        autofocus: widget.autofocus,
        enabled: true,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: shortcuts,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
          DoNothingIntent: DoNothingAction(),
        },
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _enabled ? _activate : null,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            alignment: AlignmentDirectional.centerStart,
            child: CustomPaint(
              foregroundPainter: _BubbleFocusPainter(
                visible: _focused,
                color: tokens.focusRing,
                radius: scope.variant == DBubbleVariant.ghost
                    ? 0
                    : scope.quote ||
                          scope.variant == DBubbleVariant.accent ||
                          scope.variant == DBubbleVariant.neutral
                    ? 12
                    : tokens.radius * 1.4,
              ),
              child: SelectionContainer.disabled(
                child: ExcludeSemantics(
                  excluding: widget.semanticLabel != null,
                  child: Opacity(
                    opacity: _enabled || widget.busy ? 1 : .5,
                    child: _surface(context, interactive: true),
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

/// A quoted reply inside [DBubbleContent.quote]. Author and excerpt are
/// caller-owned widgets; navigation and source-message lookup stay with the app.
/// The surface reuses Bubble's link focus, touch target and disabled behavior.
class DBubbleQuote extends StatelessWidget {
  const DBubbleQuote({
    super.key,
    required this.author,
    required this.child,
    this.onPressed,
    this.semanticLabel,
  });

  final Widget author;
  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => _DBubbleScope(
    variant: DBubbleVariant.muted,
    align: DBubbleAlign.start,
    quote: true,
    child: DBubbleContent(
      action: onPressed == null ? null : DBubbleContentAction.link,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DSpacing.xs,
        children: [
          DefaultTextStyle.merge(
            style: TextStyle(
              color: DTokens.of(context).primary,
              fontWeight: FontWeight.w600,
            ),
            child: author,
          ),
          child,
        ],
      ),
    ),
  );
}

class _BubbleFocusPainter extends CustomPainter {
  const _BubbleFocusPainter({
    required this.visible,
    required this.color,
    required this.radius,
  });

  final bool visible;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final rect = (Offset.zero & size).inflate(3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + 3)),
      Paint()
        ..color = color.withValues(alpha: color.a * .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(1),
        Radius.circular(radius + 1),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BubbleFocusPainter oldDelegate) =>
      visible != oldDelegate.visible ||
      color != oldDelegate.color ||
      radius != oldDelegate.radius;
}

/// An overlapped reaction or quick-action row.
///
/// For static emoji, provide [semanticLabel] to expose one descriptive image
/// and suppress ambiguous glyph announcements. Omit it for interactive child
/// buttons so each control keeps its own accessible label and state.
class DBubbleReactions extends StatelessWidget {
  const DBubbleReactions({
    super.key,
    required this.children,
    this.side = DBubbleReactionSide.bottom,
    this.align = DBubbleAlign.end,
    this.semanticLabel,
    this.interactive = false,
  });

  final List<Widget> children;
  final DBubbleReactionSide side;
  final DBubbleAlign align;
  final String? semanticLabel;

  /// Removes the static emoji inset when children provide their own button
  /// surfaces, matching the reference's `has(button)` composition. Interactive
  /// rows retain slightly more overlap with the bubble so Flutter's bounded
  /// hit testing includes their center; the artwork remains edge-anchored.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final content = CustomPaint(
      foregroundPainter: _ExteriorRingPainter(color: tokens.background),
      child: Container(
        padding: interactive
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: tokens.muted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: tokens.foreground,
            fontSize: DiscourseTypography.sm,
            height: 20 / DiscourseTypography.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: children,
          ),
        ),
      ),
    );
    if (semanticLabel == null) return content;
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: content,
    );
  }
}

class _ExteriorRingPainter extends CustomPainter {
  const _ExteriorRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(1.5),
        const Radius.circular(1000),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ExteriorRingPainter oldDelegate) =>
      color != oldDelegate.color;
}
