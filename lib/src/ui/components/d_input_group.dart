import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/input_group_scope.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_input.dart';
import 'd_kbd.dart';
import 'd_textarea.dart';

enum DInputGroupAddonAlignment { inlineStart, inlineEnd, blockStart, blockEnd }

enum DInputGroupButtonSize { extraSmall, small, iconExtraSmall, iconSmall }

/// A single shadcn input surface composed from one editor and optional addons.
///
/// Keep the editor first in [children] for traversal and screen-reader order;
/// [DInputGroupAddon.alignment] controls visual placement. DInput and DTextarea
/// retain all editing, Form, selection, IME, controller and focus ownership.
/// The group owns only their shared border, focus/invalid ring and addon layout.
class DInputGroup extends StatefulWidget {
  const DInputGroup({
    super.key,
    required this.children,
    this.enabled = true,
    this.invalid = false,
    this.semanticLabel,
  }) : assert(children.length > 0);

  final List<Widget> children;
  final bool enabled;
  final bool invalid;
  final String? semanticLabel;

  @override
  State<DInputGroup> createState() => _DInputGroupState();
}

class _DInputGroupState extends State<DInputGroup> {
  final Map<FocusNode, ({bool enabled, bool invalid})> _controls = {};
  bool _updateQueued = false;

  void _report(FocusNode node, bool enabled, bool invalid) {
    final next = (enabled: enabled, invalid: invalid);
    if (_controls[node] == next) return;
    _controls[node] = next;
    _queueUpdate();
  }

  void _remove(FocusNode node) {
    if (_controls.remove(node) != null) _queueUpdate();
  }

  void _queueUpdate() {
    if (_updateQueued) return;
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _requestControlFocus() {
    for (final node in _controls.keys) {
      if (node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final focused = _controls.keys.any((node) => node.hasFocus);
    final controlEnabled =
        _controls.isEmpty || _controls.values.every((state) => state.enabled);
    final invalid =
        widget.invalid || _controls.values.any((state) => state.invalid);
    final border = invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .5 : 1),
          )
        : focused
        ? tokens.focusRing
        : tokens.colors.outlineVariant;
    final ring = invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .4 : .2),
          )
        : tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5);

    final inlineStart = <Widget>[];
    final inlineEnd = <Widget>[];
    final blockStart = <Widget>[];
    final blockEnd = <Widget>[];
    final controls = <Widget>[];
    var multiline = false;
    for (var index = 0; index < widget.children.length; index++) {
      final child = widget.children[index];
      final ordered = FocusTraversalOrder(
        order: NumericFocusOrder(index.toDouble()),
        child: child,
      );
      if (child is DInputGroupAddon) {
        switch (child.alignment) {
          case DInputGroupAddonAlignment.inlineStart:
            inlineStart.add(Flexible(child: ordered));
          case DInputGroupAddonAlignment.inlineEnd:
            inlineEnd.add(Flexible(child: ordered));
          case DInputGroupAddonAlignment.blockStart:
            blockStart.add(ordered);
          case DInputGroupAddonAlignment.blockEnd:
            blockEnd.add(ordered);
        }
      } else {
        multiline =
            multiline ||
            child is DInputGroupTextarea ||
            child is DInputGroupControl && child.multiline;
        controls.add(Expanded(child: ordered));
      }
    }
    assert(controls.length == 1, 'DInputGroup requires exactly one control.');

    Widget inline = Row(
      crossAxisAlignment: multiline
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [...inlineStart, ...controls, ...inlineEnd],
    );
    Widget content = blockStart.isEmpty && blockEnd.isEmpty
        ? inline
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...blockStart, inline, ...blockEnd],
          );
    content = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: content,
    );

    final surface = Semantics(
      container: true,
      label: widget.semanticLabel,
      enabled: widget.enabled && controlEnabled,
      validationResult: invalid
          ? SemanticsValidationResult.invalid
          : SemanticsValidationResult.none,
      child: MouseRegion(
        cursor: widget.enabled
            ? MouseCursor.defer
            : SystemMouseCursors.forbidden,
        child: Opacity(
          opacity: controlEnabled ? 1 : .5,
          child: IgnorePointer(
            ignoring: !widget.enabled,
            child: AnimatedContainer(
              duration: DMotion.duration(
                context,
                const Duration(milliseconds: 150),
              ),
              constraints: BoxConstraints(minHeight: multiline ? 64 : 32),
              decoration: BoxDecoration(
                color: dark
                    ? tokens.colors.outlineVariant.withValues(
                        alpha:
                            tokens.colors.outlineVariant.a *
                            (controlEnabled ? .3 : .8),
                      )
                    : controlEnabled
                    ? Colors.transparent
                    : tokens.colors.outlineVariant.withValues(
                        alpha: tokens.colors.outlineVariant.a * .5,
                      ),
                borderRadius: BorderRadius.circular(tokens.radius),
                border: Border.all(color: border),
              ),
              foregroundDecoration: _InputGroupRingDecoration(
                color: invalid || focused ? ring : ring.withValues(alpha: 0),
                radius: tokens.radius,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final inputPadding = EdgeInsetsDirectional.only(
      start: inlineStart.isEmpty ? 10 : 6,
      top: blockEnd.isEmpty ? 5 : 12,
      end: inlineEnd.isEmpty ? 10 : 6,
      bottom: blockStart.isEmpty ? 5 : 12,
    ).resolve(Directionality.of(context));
    return DInputGroupControlScope(
      report: _report,
      remove: _remove,
      requestControlFocus: _requestControlFocus,
      inputPadding: inputPadding,
      child: touch && !multiline
          ? ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DSpacing.touchTarget,
              ),
              child: Align(heightFactor: 1, child: surface),
            )
          : surface,
    );
  }
}

/// Non-editable group content positioned relative to the control.
///
/// Tapping non-action content focuses the editor. Nested buttons win the
/// gesture arena and remain independently actionable.
class DInputGroupAddon extends StatelessWidget {
  const DInputGroupAddon({
    super.key,
    Widget? child,
    List<Widget>? children,
    this.alignment = DInputGroupAddonAlignment.inlineStart,
  }) : assert(child != null || children != null),
       assert(child == null || children == null),
       child = child,
       children = children ?? const [];

  final List<Widget> children;
  final Widget? child;
  final DInputGroupAddonAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final content = child == null ? children : <Widget>[child!];
    final block =
        alignment == DInputGroupAddonAlignment.blockStart ||
        alignment == DInputGroupAddonAlignment.blockEnd;
    final hasButton = content.any((item) => item is DInputGroupButton);
    final hasKbd = content.any((item) => item is DKbd || item is DKbdGroup);
    final inlineInset = hasButton
        ? 3.2
        : hasKbd
        ? 5.6
        : 8.0;
    final padding = switch (alignment) {
      DInputGroupAddonAlignment.inlineStart => EdgeInsetsDirectional.only(
        start: inlineInset,
        top: 6,
        bottom: 6,
      ),
      DInputGroupAddonAlignment.inlineEnd => EdgeInsetsDirectional.only(
        end: inlineInset,
        top: 6,
        bottom: 6,
      ),
      DInputGroupAddonAlignment.blockStart =>
        const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 4),
      DInputGroupAddonAlignment.blockEnd =>
        const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 8),
    };
    final row = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (var index = 0; index < content.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Flexible(child: content[index]),
        ],
      ],
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: DInputGroupControlScope.maybeOf(context)?.requestControlFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Padding(
          padding: padding,
          child: IconTheme.merge(
            data: IconThemeData(size: 16, color: tokens.mutedForeground),
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: DiscourseTypography.sm,
                height: 20 / DiscourseTypography.sm,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: tokens.mutedForeground,
              ),
              child: DKbdTheme(
                foregroundColor: tokens.mutedForeground,
                backgroundColor: tokens.muted,
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Muted text or icon content for an addon.
class DInputGroupText extends StatelessWidget {
  const DInputGroupText(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ExcludeFocus(child: IgnorePointer(child: child));
}

/// A shadcn button fitted to an input-group addon.
class DInputGroupButton extends StatelessWidget {
  const DInputGroupButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconPosition = DButtonIconPosition.start,
    this.variant = DButtonVariant.ghost,
    this.size = DInputGroupButtonSize.extraSmall,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.loading = false,
    this.hasPopup = false,
  });

  const DInputGroupButton.icon({
    super.key,
    required Widget this.icon,
    required String this.tooltip,
    required this.onPressed,
    this.variant = DButtonVariant.ghost,
    this.size = DInputGroupButtonSize.iconExtraSmall,
    this.semanticLabel,
    this.focusNode,
    this.loading = false,
    this.hasPopup = false,
  }) : label = const SizedBox.shrink(),
       iconPosition = DButtonIconPosition.start;

  final Widget label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final DButtonIconPosition iconPosition;
  final DButtonVariant variant;
  final DInputGroupButtonSize size;
  final String? semanticLabel;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool loading;
  final bool hasPopup;

  @override
  Widget build(BuildContext context) {
    final buttonSize = switch (size) {
      DInputGroupButtonSize.extraSmall ||
      DInputGroupButtonSize.iconExtraSmall => DButtonSize.extraSmall,
      DInputGroupButtonSize.small ||
      DInputGroupButtonSize.iconSmall => DButtonSize.regular,
    };
    final radius = (DTokens.of(context).radius - 3)
        .clamp(0, double.infinity)
        .toDouble();
    final iconOnly =
        size == DInputGroupButtonSize.iconExtraSmall ||
        size == DInputGroupButtonSize.iconSmall;
    if (iconOnly) {
      return DButton.iconOnly(
        icon: icon!,
        tooltip: tooltip!,
        onPressed: onPressed,
        variant: variant,
        size: buttonSize,
        semanticLabel: semanticLabel,
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(radius),
        loading: loading,
        hasPopup: hasPopup,
      );
    }
    return DButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      iconPosition: iconPosition,
      variant: variant,
      size: buttonSize,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(radius),
      loading: loading,
      hasPopup: hasPopup,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

/// DInput with its standalone surface replaced by the surrounding group.
class DInputGroupInput extends DInput {
  DInputGroupInput({
    super.key,
    super.editorKey,
    super.controller,
    super.value,
    super.initialValue,
    super.focusNode,
    super.labelText,
    super.semanticLabel,
    super.hintText,
    super.helperText,
    super.errorText,
    super.invalid,
    super.isRequired,
    super.prefix,
    super.suffix,
    super.onChanged,
    super.onSubmitted,
    super.onEditingComplete,
    super.onTap,
    super.onTapOutside,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.autofocus,
    super.readOnly,
    super.obscureText,
    super.obscuringCharacter,
    super.autocorrect,
    super.enableSuggestions,
    super.enableInteractiveSelection,
    super.inputFormatters,
    super.autofillHints,
    super.maxLength,
    super.maxLengthEnforcement,
    super.textAlign,
    super.textDirection,
    super.undoController,
    super.contextMenuBuilder,
    super.enabled,
    super.onSaved,
    super.onReset,
    super.validator,
    super.autovalidateMode,
  });
}

/// DTextarea with its standalone surface replaced by the surrounding group.
class DInputGroupTextarea extends DTextarea {
  DInputGroupTextarea({
    super.key,
    super.editorKey,
    super.controller,
    super.value,
    super.initialValue,
    super.focusNode,
    super.labelText,
    super.semanticLabel,
    super.hintText,
    super.helperText,
    super.errorText,
    super.invalid,
    super.isRequired,
    super.onChanged,
    super.onSubmitted,
    super.onEditingComplete,
    super.onTap,
    super.onTapOutside,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.autofocus,
    super.readOnly,
    super.autocorrect,
    super.enableSuggestions,
    super.enableInteractiveSelection,
    super.inputFormatters,
    super.autofillHints,
    super.minLines,
    super.maxLines,
    super.scrollController,
    super.scrollPhysics,
    super.showCounter,
    super.maxLength,
    super.maxLengthEnforcement,
    super.textAlign,
    super.textDirection,
    super.undoController,
    super.contextMenuBuilder,
    super.enabled,
    super.onSaved,
    super.onReset,
    super.validator,
    super.autovalidateMode,
  });
}

/// Adapts a third-party editor while keeping focus ownership explicit.
///
/// The builder must attach the supplied focus node to its real editable. A
/// caller-supplied node is borrowed; otherwise this widget owns and disposes it.
class DInputGroupControl extends StatefulWidget {
  const DInputGroupControl({
    super.key,
    required this.builder,
    this.focusNode,
    this.enabled = true,
    this.invalid = false,
    this.multiline = false,
  });

  final Widget Function(BuildContext context, FocusNode focusNode) builder;
  final FocusNode? focusNode;
  final bool enabled;
  final bool invalid;
  final bool multiline;

  @override
  State<DInputGroupControl> createState() => _DInputGroupControlState();
}

class _DInputGroupControlState extends State<DInputGroupControl> {
  FocusNode? _ownedFocus;
  DInputGroupControlScope? _group;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) _ownedFocus = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DInputGroupControlScope.maybeOf(context);
    if (!identical(next, _group)) {
      _group?.remove(_focus);
      _group = next;
    }
  }

  @override
  void didUpdateWidget(DInputGroupControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    _group?.remove(oldWidget.focusNode ?? _ownedFocus!);
    _ownedFocus?.dispose();
    _ownedFocus = widget.focusNode == null ? FocusNode() : null;
  }

  @override
  void dispose() {
    _group?.remove(_focus);
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _group?.report(_focus, widget.enabled, widget.invalid);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: widget.multiline ? 8 : 5,
      ),
      child: widget.builder(context, _focus),
    );
  }
}

class _InputGroupRingDecoration extends Decoration {
  const _InputGroupRingDecoration({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _InputGroupRingPainter(this);
}

class _InputGroupRingPainter extends BoxPainter {
  _InputGroupRingPainter(this.decoration);
  final _InputGroupRingDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final inner = RRect.fromRectAndRadius(
      rect,
      Radius.circular(decoration.radius),
    );
    canvas.drawDRRect(
      inner.inflate(3),
      inner,
      Paint()..color = decoration.color,
    );
  }
}
