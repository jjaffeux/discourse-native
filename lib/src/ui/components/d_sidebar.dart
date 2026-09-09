import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../foundation/tokens.dart';
import 'd_input.dart';
import 'd_scroll_area.dart';
import 'd_separator.dart';
import 'd_sheet.dart';
import 'd_skeleton.dart';
import 'd_tooltip.dart';

bool _touchPlatform(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };

class _SidebarTouchTarget extends StatelessWidget {
  const _SidebarTouchTarget({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => _touchPlatform(context)
      ? ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(heightFactor: 1, child: child),
        )
      : child;
}

enum DSidebarSide { left, right }

enum DSidebarVariant { sidebar, floating, inset }

enum DSidebarCollapsible { offcanvas, icon, none }

enum DSidebarMenuButtonSize { small, normal, large }

enum DSidebarMenuButtonVariant { normal, outline }

/// State and shortcuts for a bounded sidebar composition. Persistence belongs
/// to the caller through [open] and [onOpenChange], not to a browser cookie.
class DSidebarProvider extends StatefulWidget {
  const DSidebarProvider({
    super.key,
    required this.child,
    this.defaultOpen = true,
    this.open,
    this.onOpenChange,
    this.mobileBreakpoint = 768,
  }) : assert(mobileBreakpoint >= 0);
  final Widget child;
  final bool defaultOpen;
  final bool? open;
  final ValueChanged<bool>? onOpenChange;
  final double mobileBreakpoint;

  static DSidebarProviderState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ProviderScope>()!.state;

  @override
  State<DSidebarProvider> createState() => DSidebarProviderState();
}

class DSidebarProviderState extends State<DSidebarProvider> {
  late bool _open = widget.defaultOpen;
  bool _mobileOpen = false;
  bool _mobile = false;
  FocusNode? _mobileInitialFocusNode;
  bool get open => widget.open ?? _open;
  bool get openMobile => _mobileOpen;
  bool get isMobile => _mobile;
  void setOpen(bool value) {
    if (widget.open == null) setState(() => _open = value);
    widget.onOpenChange?.call(value);
  }

  void setOpenMobile(bool value, {FocusNode? initialFocusNode}) {
    if (_mobileOpen != value ||
        (value && _mobileInitialFocusNode != initialFocusNode)) {
      setState(() {
        _mobileOpen = value;
        _mobileInitialFocusNode = value ? initialFocusNode : null;
      });
    }
  }

  void toggleSidebar() =>
      isMobile ? setOpenMobile(!openMobile) : setOpen(!open);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _mobile = constraints.maxWidth < widget.mobileBreakpoint;
      return _ProviderScope(
        state: this,
        open: open,
        mobileOpen: openMobile,
        mobile: isMobile,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyB, control: true):
                toggleSidebar,
            const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
                toggleSidebar,
          },
          child: widget.child,
        ),
      );
    },
  );
}

class _ProviderScope extends InheritedWidget {
  const _ProviderScope({
    required this.state,
    required this.open,
    required this.mobileOpen,
    required this.mobile,
    required super.child,
  });
  final DSidebarProviderState state;
  final bool open, mobileOpen, mobile;
  @override
  bool updateShouldNotify(_ProviderScope old) =>
      open != old.open || mobileOpen != old.mobileOpen || mobile != old.mobile;
}

class _PanelScope extends InheritedWidget {
  const _PanelScope({
    required this.icon,
    required this.side,
    required super.child,
  });
  final bool icon;
  final DSidebarSide side;
  static bool iconOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelScope>()?.icon ?? false;
  @override
  bool updateShouldNotify(_PanelScope old) =>
      icon != old.icon || side != old.side;
}

/// A sidebar with fixed header/footer and a bounded content slot. Place it in
/// a Row beside Expanded content. Static mode stays inline at every width.
class DSidebar extends StatefulWidget {
  const DSidebar({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.rail,
    this.width = 256,
    this.mobileWidth = 288,
    this.iconWidth = 48,
    this.side = DSidebarSide.left,
    this.variant = DSidebarVariant.sidebar,
    this.collapsible = DSidebarCollapsible.offcanvas,
    this.backgroundColor,
    this.semanticLabel = 'Sidebar',
  }) : assert(width > 0),
       assert(mobileWidth > 0),
       assert(iconWidth > 0);
  final Widget child;
  final Widget? header, footer, rail;
  final double width, mobileWidth, iconWidth;
  final DSidebarSide side;
  final DSidebarVariant variant;
  final DSidebarCollapsible collapsible;
  final Color? backgroundColor;
  final String semanticLabel;
  @override
  State<DSidebar> createState() => _DSidebarState();
}

class _DSidebarState extends State<DSidebar> {
  DSidebarProviderState? _provider;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(DSidebar old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final provider = _provider!;
      if (provider.openMobile &&
          (!provider.isMobile ||
              widget.collapsible == DSidebarCollapsible.none)) {
        provider.setOpenMobile(false);
      }
    });
  }

  Map<ShortcutActivator, VoidCallback> _mobileShortcuts(
    DSidebarProviderState provider,
  ) => {
    const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
        provider.toggleSidebar,
    const SingleActivator(LogicalKeyboardKey.keyB, control: true):
        provider.toggleSidebar,
  };

  Widget _panel(BuildContext context, bool icon, {bool mobile = false}) {
    final t = DTokens.of(context);
    final floating = widget.variant == DSidebarVariant.floating && !mobile;
    return Material(
      type: MaterialType.transparency,
      child: _PanelScope(
        icon: icon,
        side: widget.side,
        child: Semantics(
          container: !mobile,
          label: mobile ? null : widget.semanticLabel,
          child: Container(
            decoration: BoxDecoration(
              color: widget.backgroundColor ?? t.surface,
              borderRadius: floating ? t.borderRadius : null,

              boxShadow: floating
                  ? [
                      BoxShadow(
                        color: t.foreground.withValues(alpha: .05),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            foregroundDecoration: floating
                ? BoxDecoration(
                    border: Border.all(color: t.border),
                    borderRadius: t.borderRadius,
                  )
                : null,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: t.foreground,
                fontSize: 14,
                height: 20 / 14,
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.header != null) widget.header!,
                      Expanded(child: widget.child),
                      if (widget.footer != null) widget.footer!,
                    ],
                  ),
                  if (!mobile && widget.rail != null)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: widget.side == DSidebarSide.right ? 0 : null,
                      right: widget.side == DSidebarSide.left ? 0 : null,
                      child: widget.rail!,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider = DSidebarProvider.of(context);
    _schedule();
    final static = widget.collapsible == DSidebarCollapsible.none;
    if (p.isMobile && !static) {
      return DSheet<void>(
        open: p.openMobile,
        onOpenChanged: (details) {
          if (!details.open) p.setOpenMobile(false);
        },
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        initialFocusNode: p._mobileInitialFocusNode,
        trigger: DSheetTrigger(
          builder: (context, open) => const SizedBox.shrink(),
        ),
        content: DSheetContent(
          side: widget.side == DSidebarSide.left
              ? DSheetSide.left
              : DSheetSide.right,
          sidePanelMaxWidth: widget.mobileWidth,
          sidePanelWidth: widget.mobileWidth,
          scrollWholeSheet: false,
          showCloseButton: false,
          semanticLabel: widget.semanticLabel,
          children: [
            Expanded(
              child: _ProviderScope(
                state: p,
                open: p.open,
                mobileOpen: p.openMobile,
                mobile: true,
                child: CallbackShortcuts(
                  bindings: _mobileShortcuts(p),
                  child: _panel(context, false, mobile: true),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final icon =
        !static && !p.open && widget.collapsible == DSidebarCollapsible.icon;
    final hidden =
        !static &&
        !p.open &&
        widget.collapsible == DSidebarCollapsible.offcanvas;
    final padded = !static && widget.variant != DSidebarVariant.sidebar;
    final width = hidden
        ? 0.0
        : icon
        ? widget.iconWidth + (padded ? 16 : 0)
        : widget.width;
    return AnimatedContainer(
      duration: DMotion.duration(context, const Duration(milliseconds: 200)),
      curve: Curves.linear,
      width: width,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        border: !padded && !static
            ? Border(
                left: widget.side == DSidebarSide.right
                    ? BorderSide(color: DTokens.of(context).border)
                    : BorderSide.none,
                right: widget.side == DSidebarSide.left
                    ? BorderSide(color: DTokens.of(context).border)
                    : BorderSide.none,
              )
            : null,
      ),
      child: OverflowBox(
        alignment: widget.side == DSidebarSide.left
            ? Alignment.centerLeft
            : Alignment.centerRight,
        minWidth: hidden ? widget.width : width,
        maxWidth: hidden ? widget.width : width,
        child: ExcludeFocus(
          excluding: hidden,
          child: ExcludeSemantics(
            excluding: hidden,
            child: Padding(
              padding: EdgeInsets.all(padded ? 8 : 0),
              child: _panel(context, icon),
            ),
          ),
        ),
      ),
    );
  }
}

class DSidebarHeader extends StatelessWidget {
  const DSidebarHeader({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(8), child: child);
}

class DSidebarFooter extends DSidebarHeader {
  const DSidebarFooter({super.key, required super.child});
}

class DSidebarContent extends StatelessWidget {
  const DSidebarContent({super.key, required this.children, this.controller});
  final List<Widget> children;

  /// Borrowed; the caller disposes it.
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => DScrollArea(
    controller: controller,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class DSidebarGroup extends StatelessWidget {
  const DSidebarGroup({
    super.key,
    required this.child,
    this.label,
    this.action,
  });
  final Widget child;
  final Widget? label, action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null && !_PanelScope.iconOf(context))
          Row(
            children: [
              Expanded(child: label!),
              ?action,
            ],
          ),
        child,
      ],
    ),
  );
}

class DSidebarGroupLabel extends StatelessWidget {
  const DSidebarGroupLabel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => _PanelScope.iconOf(context)
      ? const SizedBox.shrink()
      : Semantics(
          header: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w500,
                color: DTokens.of(context).foreground.withValues(alpha: .7),
              ),
              child: child,
            ),
          ),
        );
}

class DSidebarGroupContent extends StatelessWidget {
  const DSidebarGroupContent({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class DSidebarMenu extends StatelessWidget {
  const DSidebarMenu({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _ItemScope extends InheritedWidget {
  const _ItemScope({
    required this.reveal,
    required this.trailing,
    required super.child,
  });
  final bool reveal;
  final double trailing;
  static _ItemScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemScope>();
  @override
  bool updateShouldNotify(_ItemScope old) =>
      reveal != old.reveal || trailing != old.trailing;
}

class DSidebarMenuItem extends StatefulWidget {
  const DSidebarMenuItem({
    super.key,
    required this.child,
    this.action,
    this.badge,
    this.submenu,
  });
  final Widget child;
  final Widget? action, badge, submenu;
  @override
  State<DSidebarMenuItem> createState() => _DSidebarMenuItemState();
}

class _DSidebarMenuItemState extends State<DSidebarMenuItem> {
  bool hover = false, focus = false;
  @override
  Widget build(BuildContext context) {
    final icon = _PanelScope.iconOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Focus(
        canRequestFocus: false,
        // This observer must not replace a content-sized button's semantic bounds
        // with the full row's box.
        includeSemantics: false,
        onFocusChange: (v) => setState(() => focus = v),
        child: _ItemScope(
          reveal: hover || focus,
          trailing: icon
              ? 0
              : (widget.action != null
                        ? (_touchPlatform(context) ? 48 : 28)
                        : 0) +
                    (widget.badge != null ? 28 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                alignment: AlignmentDirectional.centerEnd,
                children: [
                  widget.child,
                  if (!icon)
                    PositionedDirectional(
                      end: 4,
                      top: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.badge != null) widget.badge!,
                          if (widget.action != null) widget.action!,
                        ],
                      ),
                    ),
                ],
              ),
              if (!icon && widget.submenu != null) widget.submenu!,
            ],
          ),
        ),
      ),
    );
  }
}

/// An accessible navigation action; null [onPressed] disables it. Height is a
/// minimum: native text scaling can grow rows. The default matches h-8 (32px).
class DSidebarMenuButton extends StatefulWidget {
  const DSidebarMenuButton({
    super.key,
    required this.child,
    this.onPressed,
    this.icon,
    this.iconSize = 16,
    this.isActive = false,
    this.size = DSidebarMenuButtonSize.normal,
    this.variant = DSidebarMenuButtonVariant.normal,
    this.tooltip,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.height,
    this.expanded,
  }) : assert(iconSize > 0);
  final Widget child;
  final Widget? icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final bool isActive, autofocus;
  final bool? expanded;
  final DSidebarMenuButtonSize size;
  final DSidebarMenuButtonVariant variant;
  final String? tooltip, semanticLabel;

  /// Borrowed; never disposed by this widget.
  final FocusNode? focusNode;
  final double? height;
  @override
  State<DSidebarMenuButton> createState() => _DSidebarMenuButtonState();
}

class _DSidebarMenuButtonState extends State<DSidebarMenuButton> {
  bool hover = false, focus = false, pressed = false;
  final _ownedFocus = FocusNode();
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocus;
  void _activate() {
    _focusNode.requestFocus();
    widget.onPressed?.call();
  }

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTokens.of(context);
    final iconOnly = _PanelScope.iconOf(context);
    final enabled = widget.onPressed != null;
    final fontSize = widget.size == DSidebarMenuButtonSize.small ? 12.0 : 14.0;
    final minHeight =
        widget.height ??
        switch (widget.size) {
          DSidebarMenuButtonSize.small => 28.0,
          DSidebarMenuButtonSize.normal => 32.0,
          DSidebarMenuButtonSize.large => 48.0,
        };
    final active = hover || pressed || widget.isActive;
    final collapsedLarge =
        iconOnly && widget.size == DSidebarMenuButtonSize.large;
    Widget result = Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: widget.isActive,
      expanded: widget.expanded,
      label: widget.semanticLabel ?? (iconOnly ? widget.tooltip : null),
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (v) => setState(() => focus = v),
        onShowHoverHighlight: (v) => setState(() => hover = v),
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed == null ? null : _activate,
          onTapDown: enabled ? (_) => setState(() => pressed = true) : null,
          onTapCancel: () => setState(() => pressed = false),
          onTapUp: (_) => setState(() => pressed = false),
          child: _SidebarTouchTarget(
            child: Opacity(
              opacity: enabled ? 1 : .5,
              child: Container(
                constraints: BoxConstraints(
                  minHeight: iconOnly ? 32 : minHeight,
                ),
                padding: EdgeInsetsDirectional.only(
                  start: collapsedLarge ? 0 : 8,
                  end: collapsedLarge
                      ? 0
                      : 8 + (_ItemScope.of(context)?.trailing ?? 0),
                  top: collapsedLarge ? 0 : (iconOnly ? 8 : 4),
                  bottom: collapsedLarge ? 0 : (iconOnly ? 8 : 4),
                ),
                decoration: BoxDecoration(
                  color: active
                      ? t.hover
                      : widget.variant == DSidebarMenuButtonVariant.outline
                      ? t.background
                      : null,
                  borderRadius: BorderRadius.circular(t.radius * .8),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.radius * .8),
                  border: focus
                      ? Border.all(color: t.focusRing, width: 2)
                      : widget.variant == DSidebarMenuButtonVariant.outline
                      ? Border.all(color: t.border)
                      : null,
                ),
                child: IconTheme(
                  data: IconThemeData(size: 16, color: t.foreground),
                  child: DefaultTextStyle(
                    maxLines:
                        iconOnly ||
                            MediaQuery.textScalerOf(context).scale(14) <= 14
                        ? 1
                        : null,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: fontSize,
                      height: (fontSize == 12 ? 16 : 20) / fontSize,
                      color: t.foreground,
                      fontWeight: widget.isActive
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                    child: Row(
                      children: [
                        if (widget.icon != null)
                          ExcludeSemantics(
                            child: SizedBox(
                              width: widget.iconSize,
                              height: widget.iconSize,
                              child: widget.icon,
                            ),
                          ),
                        if (iconOnly &&
                            widget.icon != null &&
                            widget.semanticLabel == null &&
                            widget.tooltip == null)
                          SizedBox.shrink(
                            child: Opacity(
                              opacity: 0,
                              alwaysIncludeSemantics: true,
                              child: widget.child,
                            ),
                          ),
                        if (!iconOnly) ...[
                          if (widget.icon != null) const SizedBox(width: 8),
                          Flexible(
                            child: ExcludeSemantics(
                              excluding: widget.semanticLabel != null,
                              child: widget.child,
                            ),
                          ),
                        ],
                        if (iconOnly && widget.icon == null)
                          Expanded(
                            child: ExcludeSemantics(
                              excluding:
                                  widget.semanticLabel != null ||
                                  widget.tooltip != null,
                              child: widget.child,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (iconOnly && widget.tooltip != null) {
      result = DTooltip(
        message: widget.tooltip!,
        side: DTooltipSide.inlineEnd,
        child: result,
      );
    }
    return result;
  }
}

class DSidebarMenuAction extends StatefulWidget {
  const DSidebarMenuAction({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.onPressed,
    this.showOnHover = false,
  });
  final Widget child;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool showOnHover;
  @override
  State<DSidebarMenuAction> createState() => _DSidebarMenuActionState();
}

class _DSidebarMenuActionState extends State<DSidebarMenuAction> {
  bool focus = false, hover = false;
  final _focusNode = FocusNode();
  void _activate() {
    _focusNode.requestFocus();
    widget.onPressed?.call();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_PanelScope.iconOf(context)) return const SizedBox.shrink();
    final reveal =
        !widget.showOnHover ||
        (_ItemScope.of(context)?.reveal ?? false) ||
        focus ||
        hover ||
        MediaQuery.sizeOf(context).width < 768;
    final t = DTokens.of(context);
    return FocusableActionDetector(
      focusNode: _focusNode,
      enabled: widget.onPressed != null,
      onShowFocusHighlight: (v) => setState(() => focus = v),
      onShowHoverHighlight: (v) => setState(() => hover = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: widget.onPressed != null,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed == null ? null : _activate,
          child: _SidebarTouchTarget(
            child: Opacity(
              opacity: reveal ? (widget.onPressed != null ? 1 : .5) : 0,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hover ? t.hover : null,
                  borderRadius: BorderRadius.circular(t.radius * .8),
                ),
                foregroundDecoration: focus
                    ? BoxDecoration(
                        border: Border.all(color: t.focusRing, width: 2),
                        borderRadius: BorderRadius.circular(t.radius * .8),
                      )
                    : null,
                child: IconTheme(
                  data: IconThemeData(size: 16, color: t.foreground),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DSidebarGroupAction extends DSidebarMenuAction {
  const DSidebarGroupAction({
    super.key,
    required super.child,
    required super.semanticLabel,
    super.onPressed,
  });
}

class DSidebarMenuBadge extends StatelessWidget {
  const DSidebarMenuBadge({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => _PanelScope.iconOf(context)
      ? const SizedBox.shrink()
      : IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              child: child,
            ),
          ),
        );
}

class DSidebarMenuSub extends StatelessWidget {
  const DSidebarMenuSub({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _PanelScope.iconOf(context)
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsetsDirectional.only(start: 14, end: 14),
          padding: const EdgeInsetsDirectional.only(
            start: 10,
            end: 10,
            top: 2,
            bottom: 2,
          ),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: DTokens.of(context).border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: children,
          ),
        );
}

class DSidebarMenuSubItem extends DSidebarGroupContent {
  const DSidebarMenuSubItem({super.key, required super.child});
}

class DSidebarMenuSubButton extends DSidebarMenuButton {
  const DSidebarMenuSubButton({
    super.key,
    required super.child,
    super.onPressed,
    super.icon,
    super.isActive,
    super.semanticLabel,
    super.focusNode,
    super.size,
  }) : super(height: 28);
}

class DSidebarMenuSkeleton extends StatelessWidget {
  const DSidebarMenuSkeleton({
    super.key,
    this.showIcon = false,
    this.widthFactor = .7,
  }) : assert(widthFactor > 0 && widthFactor <= 1);
  final bool showIcon;
  final double widthFactor;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (showIcon) ...[
            const DSkeleton(width: 16, height: 16),
            const SizedBox(width: 8),
          ],
          if (!_PanelScope.iconOf(context))
            Expanded(
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                alignment: AlignmentDirectional.centerStart,
                child: const DSkeleton(height: 16),
              ),
            ),
        ],
      ),
    ),
  );
}

class DSidebarSeparator extends StatelessWidget {
  const DSidebarSeparator({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: DSeparator(),
  );
}

class DSidebarTrigger extends StatelessWidget {
  const DSidebarTrigger({
    super.key,
    this.semanticLabel = 'Toggle Sidebar',
    this.focusNode,
  });
  final String semanticLabel;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: _touchPlatform(context) ? 48 : 32,
    child: DSidebarMenuButton(
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      onPressed: DSidebarProvider.of(context).toggleSidebar,
      child: Transform.flip(
        flipX: Directionality.of(context) == TextDirection.rtl,
        child: SvgPicture.string(
          '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/></svg>',
          colorFilter: ColorFilter.mode(
            DTokens.of(context).foreground,
            BlendMode.srcIn,
          ),
        ),
      ),
    ),
  );
}

class DSidebarRail extends StatefulWidget {
  const DSidebarRail({super.key, this.semanticLabel = 'Toggle Sidebar'});
  final String semanticLabel;
  @override
  State<DSidebarRail> createState() => _DSidebarRailState();
}

class _DSidebarRailState extends State<DSidebarRail> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: DSidebarProvider.of(context).toggleSidebar,
          child: SizedBox(
            width: 16,
            height: double.infinity,
            child: Center(
              child: Container(
                width: 2,
                color: hover ? DTokens.of(context).border : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class DSidebarInset extends StatelessWidget {
  const DSidebarInset({
    super.key,
    required this.child,
    this.side = DSidebarSide.left,
  });
  final Widget child;
  final DSidebarSide side;
  @override
  Widget build(BuildContext context) {
    final provider = DSidebarProvider.of(context);
    final t = DTokens.of(context);
    return Container(
      margin: provider.isMobile
          ? EdgeInsets.zero
          : EdgeInsets.only(
              top: 8,
              bottom: 8,
              left: side == DSidebarSide.left && provider.open ? 0 : 8,
              right: side == DSidebarSide.right && provider.open ? 0 : 8,
            ),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(t.radius * 1.4),
        boxShadow: [
          BoxShadow(
            color: t.foreground.withValues(alpha: .05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Compact Sidebar adapter backed by the shared Input editing and rendering owner.
class DSidebarInput extends StatelessWidget {
  const DSidebarInput({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.onChanged,
    this.enabled = true,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DInput(
    controller: controller,
    focusNode: focusNode,
    hintText: hintText,
    onChanged: onChanged,
    enabled: enabled,
  );
}
