import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/d_icons.dart';
import 'forum_theme_surfaces.dart';

/// One tab a minimized panel still holds.
@immutable
class PanelRailTab {
  const PanelRailTab({
    required this.id,
    required this.title,
    required this.icon,
    this.label,
    this.selected = false,
  });

  final String id;

  /// Names the tab in its tooltip and to assistive technology.
  final String title;

  /// Drawn in the ambient [IconTheme], which follows the button's state.
  final Widget icon;

  /// How the read-out draws [title]; plain text when null.
  final Widget? label;
  final bool selected;
}

/// What is left of a minimized panel: the way back to it, its tabs, and a new
/// tab, docked at the top of the column the panel held.
///
/// Pointing at the rail reads it out in full over the neighbouring panel
/// rather than pushing that panel along, so nothing moves under the pointer.
/// The read-out repeats the rail for the pointer only; keyboard and assistive
/// technology use the rail's own buttons and their tooltips.
class PanelRail extends StatefulWidget {
  const PanelRail({
    super.key,
    required this.semanticLabel,
    required this.tabs,
    required this.onRestore,
    required this.onSelect,
    required this.onNewTab,
    this.opensTowardStart = false,
  });

  static const double width = 38;
  static const double readOutWidth = 214;

  // Rail and read-out share one vertical rhythm so their rows line up.
  static const double _inset = 10;
  static const double _gap = 3;
  static const double _slot = 28;
  static const double _readOutRadius = 14;
  static const Duration _reveal = Duration(milliseconds: 130);

  final String semanticLabel;
  final List<PanelRailTab> tabs;
  final VoidCallback onRestore;
  final ValueChanged<String> onSelect;

  /// Null while the workspace cannot hold another tab.
  final VoidCallback? onNewTab;

  /// A rail docked at the end of the workspace reads out toward its start.
  final bool opensTowardStart;

  @override
  State<PanelRail> createState() => _PanelRailState();
}

typedef _Entry = ({
  String slot,
  String title,
  Widget icon,
  Widget? label,
  // Null for the panel's own actions, which are not tabs.
  bool? selected,
  VoidCallback? onPressed,
});

class _PanelRailState extends State<PanelRail>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _railScroll = ScrollController();
  ScrollController? _readOutScroll;
  late final _reveal = AnimationController(
    vsync: this,
    duration: PanelRail._reveal,
  );
  late final _revealCurve = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOut,
  );

  bool _overRail = false;
  bool _overReadOut = false;

  void _enterRail() {
    _overRail = true;
    // A rail that appears under the pointer, as it does when the minimize
    // button sat where the rail now is, has not been pointed at. The mouse
    // tracker reports that entry after a frame rather than while dispatching
    // a pointer event, and the rail waits for the pointer to leave and come
    // back before it reads itself out.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.postFrameCallbacks) {
      return;
    }
    _open();
  }

  void _exitRail() {
    _overRail = false;
    _closeUnlessPointed();
  }

  void _open() {
    if (_portal.isShowing) return;
    final previous = _readOutScroll;
    _readOutScroll = ScrollController(
      initialScrollOffset: _railScroll.hasClients ? _railScroll.offset : 0,
    );
    if (previous != null) {
      // The read-out that used it is removed by the frame this one builds.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    setState(_portal.show);
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
      return;
    }
    // The frame that builds the rows is the read-out's expensive one, and it
    // still shows only the rail's width. Growing from the next frame lets the
    // whole motion play instead of losing its opening to that build.
    _reveal.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _portal.isShowing) _reveal.forward();
    });
  }

  // The read-out covers the rail as it opens, so the rail reports an exit
  // just before the read-out reports its entry. Both arrive in one dispatch;
  // deciding after it keeps that hand-over from closing the read-out.
  void _closeUnlessPointed() => scheduleMicrotask(() {
    if (!mounted || _overRail || _overReadOut || !_portal.isShowing) return;
    final readOut = _readOutScroll;
    if (readOut != null && readOut.hasClients && _railScroll.hasClients) {
      _railScroll.jumpTo(
        readOut.offset.clamp(0, _railScroll.position.maxScrollExtent),
      );
    }
    _reveal.value = 0;
    setState(_portal.hide);
  });

  @override
  void dispose() {
    _revealCurve.dispose();
    _reveal.dispose();
    _railScroll.dispose();
    _readOutScroll?.dispose();
    super.dispose();
  }

  List<_Entry> get _entries => [
    (
      slot: 'restore',
      title: 'Restore panel',
      icon: const DIcon(DIcons.upRightAndDownLeftFromCenter),
      label: null,
      selected: null,
      onPressed: widget.onRestore,
    ),
    for (final tab in widget.tabs)
      (
        slot: 'tab-${tab.id}',
        title: tab.title,
        icon: tab.icon,
        label: tab.label,
        selected: tab.selected,
        onPressed: () => widget.onSelect(tab.id),
      ),
    (
      slot: 'new-tab',
      title: widget.onNewTab == null
          ? 'Close a tab before opening another'
          : 'New tab',
      icon: const DIcon(DIcons.plus),
      label: const Text('New tab'),
      selected: null,
      onPressed: widget.onNewTab,
    ),
  ];

  static Color _mix(DTokens tokens, double amount) =>
      Color.lerp(tokens.background, tokens.foreground, amount)!;

  // Holding nothing, a rail sits a step below the panel that is being read:
  // still a panel, just not the one being worked in.
  static Color _surface(BuildContext context) =>
      ForumWindowBackground.footerColor(
        context,
        DTokens.of(context).footerBackground,
      );

  Widget _slot(BuildContext context, _Entry entry) {
    final tokens = DTokens.of(context);
    final selected = entry.selected ?? false;
    final button = DButton.iconOnly(
      key: ValueKey('panel-rail-${entry.slot}'),
      icon: entry.icon,
      tooltip: entry.title,
      tooltipSide: widget.opensTowardStart
          ? DTooltipSide.inlineStart
          : DTooltipSide.inlineEnd,
      size: DControlSize.segment,
      shape: DButtonShape.pill,
      variant: DButtonVariant.transparentBackground,
      backgroundColor: selected ? _mix(tokens, .10) : null,
      borderColor: selected ? _mix(tokens, .22) : null,
      foregroundColor: selected ? tokens.foreground : null,
      onPressed: entry.onPressed,
    );
    return switch (entry.selected) {
      null => button,
      final selected => MergeSemantics(
        child: Semantics(selected: selected, child: button),
      ),
    };
  }

  Widget _row(BuildContext context, _Entry entry) {
    final tokens = DTokens.of(context);
    final selected = entry.selected ?? false;
    return SizedBox(
      height: PanelRail._slot,
      child: DButton(
        key: ValueKey('panel-rail-read-out-${entry.slot}'),
        label: entry.label ?? Text(entry.title),
        icon: entry.icon,
        size: DControlSize.segment,
        variant: DButtonVariant.transparentBackground,
        alignment: AlignmentDirectional.centerStart,
        backgroundColor: selected ? _mix(tokens, .10) : null,
        borderColor: selected ? _mix(tokens, .22) : null,
        foregroundColor: selected ? tokens.foreground : null,
        onPressed: entry.onPressed,
      ),
    );
  }

  List<Widget> _spaced(List<Widget> children) => [
    for (var index = 0; index < children.length; index++) ...[
      if (index > 0) const SizedBox(height: PanelRail._gap),
      children[index],
    ],
  ];

  Widget _readOut(BuildContext context, OverlayChildLayoutInfo info) {
    if (info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final rail = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final towardLeft =
        widget.opensTowardStart ==
        (Directionality.of(context) == TextDirection.ltr);
    final room = towardLeft ? rail.right : info.overlaySize.width - rail.left;
    final width = math.max(rail.width, math.min(PanelRail.readOutWidth, room));
    final tokens = DTokens.of(context);
    final border = _mix(tokens, .22);
    final shadow = DControlStyle.shadow(tokens);
    final entries = _entries;
    return Positioned(
      key: const ValueKey('panel-rail-read-out'),
      top: rail.top,
      height: rail.height,
      left: towardLeft ? null : rail.left,
      right: towardLeft ? info.overlaySize.width - rail.right : null,
      child: MouseRegion(
        onEnter: (_) => _overReadOut = true,
        onExit: (_) {
          _overReadOut = false;
          _closeUnlessPointed();
        },
        child: ExcludeFocus(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _revealCurve,
              builder: (context, content) {
                final reveal = _revealCurve.value;
                return Container(
                  // It grows from the width the rail had, anchored where the
                  // rail is docked, so the rows are revealed rather than
                  // reflowed as it opens.
                  width: lerpDouble(rail.width, width, reveal),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _surface(context),
                    borderRadius: BorderRadius.circular(
                      lerpDouble(
                        rail.width / 2,
                        PanelRail._readOutRadius,
                        reveal,
                      )!,
                    ),
                    border: Border.all(
                      color: DControlStyle.alpha(border, reveal),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: DControlStyle.alpha(shadow, reveal),
                        offset: const Offset(0, 14),
                        blurRadius: 34,
                      ),
                    ],
                  ),
                  child: content,
                );
              },
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                minWidth: width - 2,
                maxWidth: width - 2,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _readOutScroll,
                    padding: const EdgeInsets.fromLTRB(
                      4,
                      PanelRail._inset - 1,
                      4,
                      PanelRail._inset - 1,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _spaced([
                        for (final entry in entries) _row(context, entry),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return SizedBox(
      width: PanelRail.width,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: _readOut,
        child: MouseRegion(
          onEnter: (_) => _enterRail(),
          onExit: (_) => _exitRail(),
          child: Opacity(
            // The read-out stands in for the rail while it is open, for the
            // pointer only: the rail still carries the accessible actions.
            opacity: _portal.isShowing ? 0 : 1,
            alwaysIncludeSemantics: true,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: widget.semanticLabel,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _surface(context),
                  borderRadius: BorderRadius.circular(DRadius.pill),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DRadius.pill),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _railScroll,
                      padding: const EdgeInsets.symmetric(
                        vertical: PanelRail._inset,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _spaced([
                            for (final entry in entries) _slot(context, entry),
                          ]),
                        ),
                      ),
                    ),
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
