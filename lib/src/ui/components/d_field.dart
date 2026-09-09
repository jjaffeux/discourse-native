import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_label.dart';
import 'd_separator.dart';
import 'd_typography.dart';

/// Layout only: the enclosed native control or FormField owns its value.
enum DFieldOrientation { vertical, horizontal, responsive }

enum DFieldLegendVariant { legend, label }

/// Choice groups use the reference's tighter checkbox/radio spacing.
enum DFieldGroupVariant { standard, choice }

TextStyle _textStyle(
  BuildContext context, {
  double size = 14,
  double height = 1.5,
  FontWeight weight = FontWeight.w400,
  Color? color,
}) => DText.styleOf(context, DTextVariant.small).copyWith(
  fontSize: size,
  height: height,
  fontWeight: weight,
  letterSpacing: 0,
  color: color ?? DTokens.of(context).foreground,
);

/// A semantic group. A legend names this group, not each individual control.
/// Disabled groups prevent pointer/focus interaction; callers should also pass
/// the enabled state to controls so their own disabled visuals stay accurate.
class DFieldSet extends StatelessWidget {
  const DFieldSet({
    super.key,
    required this.children,
    this.enabled = true,
    this.semanticLabel,
    this.spacing,
  });
  final List<Widget> children;
  final bool enabled;
  final String? semanticLabel;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final inherited = _FieldScope.maybeOf(context);
    final legend = children.whereType<DFieldLegend>().firstOrNull;
    final legendChild = legend?.child;
    final groupLabel =
        semanticLabel ??
        (legendChild is Text
            ? legendChild.semanticsLabel ??
                  legendChild.data ??
                  legendChild.textSpan?.toPlainText()
            : null);
    final active = enabled && (inherited?.enabled ?? true);
    final gap =
        spacing ??
        (children.any(
              (child) =>
                  child is DFieldGroup &&
                  child.variant == DFieldGroupVariant.choice,
            )
            ? 12.0
            : 16.0);
    return _FieldScope(
      enabled: active,
      invalid: false,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: groupLabel,
        enabled: active ? null : false,
        child: ExcludeFocus(
          excluding: !active,
          child: IgnorePointer(
            ignoring: !active,
            child: _column(children, gap),
          ),
        ),
      ),
    );
  }
}

class DFieldLegend extends StatelessWidget {
  const DFieldLegend({
    super.key,
    required this.child,
    this.variant = DFieldLegendVariant.legend,
  });
  final Widget child;
  final DFieldLegendVariant variant;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: DefaultTextStyle(
      style: _textStyle(
        context,
        size: variant == DFieldLegendVariant.legend
            ? DiscourseTypography.base
            : DiscourseTypography.sm,
        weight: FontWeight.w500,
        height: variant == DFieldLegendVariant.legend ? 1.5 : 20 / 14,
      ),
      child: child,
    ),
  );
}

/// Stacks fields and establishes the container width for responsive fields.
/// Nested groups use 16px, choice groups 12px, otherwise 20px.
class DFieldGroup extends StatelessWidget {
  const DFieldGroup({
    super.key,
    required this.children,
    this.variant = DFieldGroupVariant.standard,
    this.spacing,
  });
  final List<Widget> children;
  final DFieldGroupVariant variant;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final nested =
        context.dependOnInheritedWidgetOfExactType<_GroupScope>() != null;
    return LayoutBuilder(
      builder: (context, constraints) => _GroupScope(
        width: constraints.maxWidth,
        child: _column(
          children,
          spacing ??
              (variant == DFieldGroupVariant.choice
                  ? 12
                  : nested
                  ? 16
                  : 20),
        ),
      ),
    );
  }
}

/// Composes a label, control, description and error without owning form state.
///
/// Use [DFieldControl] around the single control to give it an accessible name,
/// description and invalid state. Associate [DFieldLabel] with that control's
/// borrowed focus node (editors) or activation callback (choices). A plain
/// adjacent label alone cannot create a native accessibility relationship.
///
/// Horizontal fields flex content/labels and expanding controls; compact
/// controls use `DFieldControl(expand: false)`. Responsive fields switch at
/// 448px of the nearest FieldGroup (their own width outside a group). A single
/// Flex preserves editing/focus state when orientation changes.
class DField extends StatelessWidget {
  const DField({
    super.key,
    required this.children,
    this.orientation = DFieldOrientation.vertical,
    this.invalid = false,
    this.enabled = true,
    this.responsiveBreakpoint = 448,
  });
  final List<Widget> children;
  final DFieldOrientation orientation;
  final bool invalid;
  final bool enabled;
  final double responsiveBreakpoint;

  @override
  Widget build(BuildContext context) {
    final active = enabled && (_FieldScope.maybeOf(context)?.enabled ?? true);
    final children = this.children.where(_visible).toList();
    final groupWidth = context
        .dependOnInheritedWidgetOfExactType<_GroupScope>()
        ?.width;
    return _FieldScope(
      enabled: active,
      invalid: invalid,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: invalid ? DTokens.of(context).destructive : null,
        ),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: ExcludeFocus(
            excluding: !active,
            child: IgnorePointer(
              ignoring: !active,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal =
                      orientation == DFieldOrientation.horizontal ||
                      (orientation == DFieldOrientation.responsive &&
                          (groupWidth ?? constraints.maxWidth) >=
                              responsiveBreakpoint);
                  final hasContent = children.any(
                    (child) => child is DFieldContent,
                  );
                  return Flex(
                    direction: horizontal ? Axis.horizontal : Axis.vertical,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: horizontal
                        ? hasContent
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center
                        : CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0)
                          SizedBox(
                            width: horizontal ? 8 : 0,
                            height: horizontal ? 0 : _gap(children, i, 8),
                          ),
                        Flexible(
                          flex: horizontal && _expands(children[i]) ? 1 : 0,
                          fit: FlexFit.loose,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top:
                                  horizontal &&
                                      hasContent &&
                                      children[i] is DFieldControl &&
                                      (children[i] as DFieldControl)
                                          .alignIndicatorToContent
                                  ? 1
                                  : 0,
                            ),
                            child: children[i],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _expands(Widget child) =>
      child is DFieldContent ||
      child is DFieldLabel ||
      child is DFieldTitle ||
      (child is DFieldControl && child.expand);
}

class DFieldContent extends StatelessWidget {
  const DFieldContent({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      _column(children, 2, adjustMargins: false);
}

/// Explicit native equivalent of htmlFor / aria-describedby on one control.
///
/// Supply the same visible label/help/error strings here. This merges metadata
/// into the child's existing semantics without removing its editing, toggle or
/// adjustable actions. Do not wrap multiple independently interactive controls.
/// Set the visible label's [DFieldLabel.excludeSemantics] to avoid repeating its
/// name; descriptions may remain separately readable, like HTML help paragraphs.
/// Errors are appended to the hint and expose native invalid semantics. The
/// owning FormField still validates, saves and resets; Field adds no state.
class DFieldControl extends StatelessWidget {
  const DFieldControl({
    super.key,
    required this.label,
    required this.child,
    this.description,
    this.errors = const [],
    this.required = false,
    this.expand = true,
    this.alignIndicatorToContent = false,
  });
  final String label;
  final String? description;
  final List<String?> errors;
  final bool required;
  final bool expand;

  /// Checkbox/radio indicators sit 1px below adjacent FieldContent's top.
  /// Switches and text editors normally leave this false.
  final bool alignIndicatorToContent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _FieldScope.maybeOf(context);
    final messages = _messages(errors);
    final hint = [
      if (description != null && description!.isNotEmpty) description!,
      ...messages,
    ].join('\n');
    return MergeSemantics(
      child: Semantics(
        label: label,
        hint: hint.isEmpty ? null : hint,
        isRequired: required,
        enabled: scope?.enabled == false ? false : null,
        validationResult: (scope?.invalid ?? false) || messages.isNotEmpty
            ? SemanticsValidationResult.invalid
            : SemanticsValidationResult.none,
        child: child,
      ),
    );
  }
}

/// A wrapping label with optional activation of an associated native control.
/// It adds no tab stop. The caller owns and disposes [focusNode].
///
/// The choice constructor wraps a DField in the outlined reference surface.
/// Pass selection and enabled state from the control owner. Its descendant
/// control remains the keyboard/semantics owner; onPressed activates the card's
/// otherwise empty area. Do not place unrelated interactive links in a card.
class DFieldLabel extends StatefulWidget {
  const DFieldLabel({
    super.key,
    required this.child,
    this.focusNode,
    this.onPressed,
    this.enabled = true,
    this.excludeSemantics = false,
    this.style,
  }) : choice = false,
       selected = false;
  const DFieldLabel.choice({
    super.key,
    required this.child,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.enabled = true,
    this.excludeSemantics = false,
    this.style,
  }) : choice = true;
  final Widget child;
  final FocusNode? focusNode;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool excludeSemantics;
  final TextStyle? style;
  final bool choice;
  final bool selected;

  @override
  State<DFieldLabel> createState() => _DFieldLabelState();
}

class _DFieldLabelState extends State<DFieldLabel> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
  }

  void _highlightChanged(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _FieldScope.maybeOf(context);
    final enabled = widget.enabled && (scope?.enabled ?? true);
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final focusVisible =
        enabled &&
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final canActivate =
        enabled && (widget.onPressed != null || widget.focusNode != null);
    Widget child = DLabel(
      enabled: enabled,
      style: TextStyle(
        height: 1.375,
        color: scope?.invalid == true ? tokens.destructive : tokens.foreground,
      ).merge(widget.style),
      child: ExcludeSemantics(
        excluding: widget.excludeSemantics,
        child: widget.child,
      ),
    );
    if (widget.choice) {
      final border = focusVisible
          ? tokens.focusRing
          : widget.selected
          ? _alpha(tokens.primary, dark ? 0.2 : 0.3)
          : tokens.border;
      final background = enabled && _hovered
          ? _alpha(tokens.muted, 0.5)
          : widget.selected
          ? _alpha(tokens.primary, dark ? 0.1 : 0.05)
          : null;
      child = CustomPaint(
        foregroundPainter: focusVisible
            ? _ExteriorRing(
                color: _alpha(tokens.focusRing, 0.5),
                radius: tokens.radius,
              )
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border),
            borderRadius: tokens.borderRadius,
          ),
          child: Padding(padding: const EdgeInsets.all(11), child: child),
        ),
      );
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        cursor: !enabled
            ? SystemMouseCursors.forbidden
            : canActivate
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: canActivate
              ? () {
                  widget.focusNode?.requestFocus();
                  widget.onPressed?.call();
                }
              : null,
          child: child,
        ),
      ),
    );
  }
}

/// Label typography without label activation (e.g. a slider range or card).
class DFieldTitle extends StatelessWidget {
  const DFieldTitle({
    super.key,
    required this.child,
    this.excludeSemantics = false,
  });
  final Widget child;
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final scope = _FieldScope.maybeOf(context);
    return Opacity(
      opacity: scope?.enabled == false ? 0.5 : 1,
      child: ExcludeSemantics(
        excluding: excludeSemantics,
        child: DefaultTextStyle(
          style: _textStyle(
            context,
            weight: FontWeight.w500,
            height: 20 / 14,
            color: scope?.invalid == true
                ? DTokens.of(context).destructive
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Rich help content. Interactive links keep their own native focus/actions.
/// Flutter wraps normally rather than implementing CSS text balancing.
class DFieldDescription extends StatelessWidget {
  const DFieldDescription({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    textAlign: TextAlign.start,
    style: _textStyle(context, color: DTokens.of(context).mutedForeground),
    child: child,
  );
}

/// Decorative line with optional readable content. FieldGroup accounts for the
/// source's -8px vertical margins. Text grows beyond 20px when necessary.
class DFieldSeparator extends StatelessWidget {
  const DFieldSeparator({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 20),
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Positioned(left: 0, right: 0, child: DSeparator()),
        if (child != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(color: DTokens.of(context).background),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DefaultTextStyle(
                  style: _textStyle(
                    context,
                    height: 20 / 14,
                    color: DTokens.of(context).mutedForeground,
                  ),
                  textAlign: TextAlign.center,
                  child: child!,
                ),
              ),
            ),
          )
        else
          const SizedBox(width: double.infinity, height: 20),
      ],
    ),
  );
}

/// Deduplicates nonempty messages in first-seen order; custom child wins.
/// A live region announces changes. Empty errors render no content.
class DFieldError extends StatelessWidget {
  const DFieldError({super.key, this.child, this.errors = const []});
  final Widget? child;
  final List<String?> errors;

  @override
  Widget build(BuildContext context) {
    final messages = _messages(errors);
    if (child == null && messages.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      container: true,
      child: DefaultTextStyle(
        style: _textStyle(
          context,
          height: 20 / 14,
          color: DTokens.of(context).destructive,
        ),
        child:
            child ??
            (messages.length == 1
                ? Text(messages.single)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      for (final message in messages)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(
                              width: 16,
                              child: ExcludeSemantics(child: Text('•')),
                            ),
                            Expanded(child: Text(message)),
                          ],
                        ),
                    ],
                  )),
      ),
    );
  }
}

List<String> _messages(List<String?> errors) => errors
    .whereType<String>()
    .where((message) => message.isNotEmpty)
    .toSet()
    .toList();

Color _alpha(Color color, double factor) =>
    color.withValues(alpha: color.a * factor);

bool _visible(Widget widget) =>
    widget is! DFieldError ||
    widget.child != null ||
    _messages(widget.errors).isNotEmpty;

Widget _column(
  List<Widget> children,
  double spacing, {
  bool adjustMargins = true,
}) {
  final visible = children.where(_visible).toList();
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < visible.length; i++) ...[
        if (i > 0)
          SizedBox(height: adjustMargins ? _gap(visible, i, spacing) : spacing),
        visible[i],
      ],
    ],
  );
}

double _gap(List<Widget> children, int index, double spacing) {
  final previous = children[index - 1];
  final current = children[index];
  var gap = spacing;
  if (previous is DFieldLegend) gap += 6;
  if (current is DFieldDescription) {
    if (previous is DFieldLegend &&
        previous.variant == DFieldLegendVariant.legend) {
      gap -= 6;
    } else if (index == children.length - 2) {
      gap -= 4;
    }
  }
  if (previous is DFieldSeparator) gap -= 8;
  if (current is DFieldSeparator) gap -= 8;
  return gap.clamp(0, double.infinity);
}

class _GroupScope extends InheritedWidget {
  const _GroupScope({required this.width, required super.child});
  final double width;
  @override
  bool updateShouldNotify(_GroupScope oldWidget) => width != oldWidget.width;
}

class _FieldScope extends InheritedWidget {
  const _FieldScope({
    required this.enabled,
    required this.invalid,
    required super.child,
  });
  final bool enabled;
  final bool invalid;
  static _FieldScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FieldScope>();
  @override
  bool updateShouldNotify(_FieldScope oldWidget) =>
      enabled != oldWidget.enabled || invalid != oldWidget.invalid;
}

class _ExteriorRing extends CustomPainter {
  const _ExteriorRing({required this.color, required this.radius});
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final inner = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawDRRect(inner.inflate(3), inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ExteriorRing oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
