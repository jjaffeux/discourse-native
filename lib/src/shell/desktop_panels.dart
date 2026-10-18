import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icon, Icons;
import 'package:flutter/widgets.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/composer_placement.dart';
import '../models/forum_workspace.dart';
import 'adaptive_shell.dart';
import 'composer_presentation.dart';
import 'main_content.dart';
import 'resizable_pane.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'topic_presentation.dart';
import 'window_frame.dart';

enum _WindowResizeEdge { left, right }

/// The split between the desktop panels and which of them is minimized.
///
/// Both belong to the window rather than to the panels showing them, so they
/// outlive views that replace the panels for a while, such as a forum's sign-in
/// gate. Neither is persisted.
final class DesktopPanelsLayout extends FrameSafeNotifier {
  final mainWidth = PanelWidthController(
    initialWidth: 400 + workspacePanelGap,
    minimumWidth: 320 + workspacePanelGap,
  );

  // Only one panel stands down at a time, or there would be nothing left to
  // read.
  ForumPanel _leading = ForumPanel.main;
  ForumPanel? _minimized;
  VoidCallback? _toggle;
  bool _splitVisible = false;
  bool _canToggleSplit = false;

  bool get splitVisible => _splitVisible;
  bool get canToggleSplit => _canToggleSplit && _toggle != null;

  void toggleSplit() {
    if (canToggleSplit) _toggle!();
  }

  void _present({required bool visible, required bool enabled}) {
    if (_splitVisible == visible && _canToggleSplit == enabled) return;
    _splitVisible = visible;
    _canToggleSplit = enabled;
    notifySafely();
  }

  @override
  void dispose() {
    mainWidth.dispose();
    super.dispose();
  }
}

/// Two document panels whose identities survive either one being minimized.
class DesktopPanels extends StatefulWidget {
  const DesktopPanels({super.key, this.layout, this.windowFrame});

  /// The window's panel layout. Without one the panels keep their own, which
  /// lasts only as long as they stay mounted.
  final DesktopPanelsLayout? layout;

  /// Allows a host to supply window geometry during resizing.
  final ValueListenable<Rect?>? windowFrame;

  @override
  State<DesktopPanels> createState() => _DesktopPanelsState();
}

class _DesktopPanelsState extends State<DesktopPanels>
    with SingleTickerProviderStateMixin {
  final _panelKeys = {
    for (final panel in ForumPanel.values) panel: GlobalKey(),
  };
  // Keep recent element/render trees, not just widget configurations. Replacing
  // the only child on selection disposes its reader and rebuilds every row on
  // return. Bound retention to three visited documents in each panel.
  static const _maximumRetainedTabsPerPanel = 3;
  final _tabContents = <String, MainContent>{};
  (String, String, Object)? _contentWorkspace;
  final _panelWidgets =
      <ForumPanel, ({Object key, List<_TabContent> contents, Widget widget})>{};
  late DesktopPanelsLayout _layout;
  DesktopPanelsLayout? _ownedLayout;
  late ValueListenable<Rect?> _windowFrame;
  WindowFrame? _ownedWindowFrame;
  Rect? _previousWindowFrame;
  _WindowResizeEdge? _resizeEdge;
  double? _anchoredMainWidth;
  double? _anchoredSecondaryWidth;
  double? _anchoredWindowWidth;
  double? _swappedMainWidthLimit;
  double? _lastSplitMainWidth;
  double? _lastSplitTotalWidth;
  ForumPanel? _effectiveMinimized;
  final _swapFocus = FocusNode(debugLabel: 'Swap panels');
  bool _seamHovered = false;
  bool _seamFocused = false;
  bool _seamDragging = false;
  bool _swapAtTop = true;

  PanelWidthController get _mainWidth => _layout.mainWidth;

  ForumPanel? get _minimized => _layout._minimized;
  set _minimized(ForumPanel? panel) => _layout._minimized = panel;

  @override
  void initState() {
    super.initState();
    _layout = widget.layout ?? (_ownedLayout = DesktopPanelsLayout());
    _layout._toggle = _toggleSplit;
    _windowFrame = widget.windowFrame ?? (_ownedWindowFrame = WindowFrame());
    _previousWindowFrame = _windowFrame.value;
    _windowFrame.addListener(_frameChanged);
    _mainWidth.addListener(_preferredWidthChanged);
  }

  @override
  void didUpdateWidget(DesktopPanels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) {
      _layout._toggle = null;
      _layout._present(visible: false, enabled: false);
      _mainWidth.removeListener(_preferredWidthChanged);
      _ownedLayout?.dispose();
      _ownedLayout = null;
      _layout = widget.layout ?? (_ownedLayout = DesktopPanelsLayout());
      _layout._toggle = _toggleSplit;
      _mainWidth.addListener(_preferredWidthChanged);
    }
    if (oldWidget.windowFrame == widget.windowFrame) return;
    _windowFrame.removeListener(_frameChanged);
    _ownedWindowFrame?.dispose();
    _ownedWindowFrame = null;
    _windowFrame = widget.windowFrame ?? (_ownedWindowFrame = WindowFrame());
    _previousWindowFrame = _windowFrame.value;
    _resizeEdge = null;
    _swappedMainWidthLimit = null;
    _windowFrame.addListener(_frameChanged);
  }

  void _swapPanels() {
    if (!_layout.splitVisible || _moving.value != null || _seamDragging) return;
    setState(() {
      if (_resizeEdge != null && _lastSplitMainWidth != null) {
        _anchoredMainWidth = _lastSplitMainWidth;
        _anchoredSecondaryWidth = _lastSplitTotalWidth! - _lastSplitMainWidth!;
        _anchoredWindowWidth = _windowFrame.value?.width;
        _swappedMainWidthLimit = math.max(
          _mainWidth.value,
          _lastSplitMainWidth!,
        );
      }
      _layout._leading = _other(_layout._leading);
      _seamHovered = false;
    });
  }

  void _preferredWidthChanged() {
    // A seam drag becomes the starting split for the next window resize.
    setState(() {
      _resizeEdge = null;
      _swappedMainWidthLimit = null;
    });
  }

  void _frameChanged() {
    final frame = _windowFrame.value;
    if (frame == null) return;
    final previous = _previousWindowFrame;
    _previousWindowFrame = frame;
    if (previous == null || (frame.width - previous.width).abs() < 0.5) {
      return;
    }

    final leftMove = (frame.left - previous.left).abs();
    final rightMove = (frame.right - previous.right).abs();
    final nextEdge = leftMove > rightMove + 0.5
        ? _WindowResizeEdge.left
        : rightMove > leftMove + 0.5
        ? _WindowResizeEdge.right
        : null;
    if (nextEdge != _resizeEdge && _lastSplitMainWidth != null) {
      _swappedMainWidthLimit = null;
      _anchoredMainWidth = _lastSplitMainWidth;
      _anchoredSecondaryWidth = _lastSplitTotalWidth! - _lastSplitMainWidth!;
      _anchoredWindowWidth = previous.width;
    }
    setState(() => _resizeEdge = nextEdge);
  }

  // The panel still folding away or back into view. The motion is
  // painted only: that panel slides and fades while the other one reveals
  // itself beside it, so no frame of it lays a document out again.
  final _moving = ValueNotifier<({ForumPanel panel, bool away})?>(null);
  late final _fold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addStatusListener(_foldSettled);
  // 0 while the moving panel stands beside the other one, 1 once folded.
  late final _folded = CurvedAnimation(
    parent: _fold,
    curve: Curves.fastOutSlowIn,
    reverseCurve: Curves.fastOutSlowIn.flipped,
  );

  static ForumPanel _other(ForumPanel panel) =>
      panel == ForumPanel.main ? ForumPanel.secondary : ForumPanel.main;

  void _toggleSplit([ForumPanel target = ForumPanel.secondary]) {
    if (_effectiveMinimized case final panel?) {
      _restore(panel);
    } else {
      _minimize(target);
    }
  }

  void _minimize(ForumPanel panel) {
    final shell = ShellScope.read(context);
    final visible = shell.selectedTabIn(_other(panel));
    if (visible == null) return;
    // Keyboard input and sidebar navigation follow the active tab, so it
    // cannot stay behind in a panel that is no longer shown.
    if (shell.activeTab?.panel == panel) shell.selectTab(visible.id);
    setState(() {
      _minimized = panel;
      _move(panel, away: true);
    });
  }

  // Restoring a panel leaves input where it is, so a reply being written
  // beside it keeps its place; picking one of the panel's tabs moves it.
  void _restore(ForumPanel panel, {String? tabId, bool newTab = false}) {
    final shell = ShellScope.read(context);
    final canSplit =
        (context.size?.width ?? double.infinity) >= 640 + workspacePanelGap;
    setState(() {
      _minimized = null;
      // Restoring a rail at this window width starts a new visible split.
      _resizeEdge = null;
      _swappedMainWidthLimit = null;
      if (!canSplit) {
        // No two-panel split exists at this width. An older split would
        // otherwise become the anchor of the next window expansion.
        _lastSplitMainWidth = null;
        _lastSplitTotalWidth = null;
        _anchoredMainWidth = null;
        _anchoredSecondaryWidth = null;
        _anchoredWindowWidth = null;
      }
      _move(panel, away: false);
    });
    if (newTab) {
      shell.createTab(panel: panel);
    } else if (tabId != null) {
      shell.selectTab(tabId);
    } else if (!canSplit) {
      // Two full panels cannot fit here. Show the requested panel in the
      // single-panel layout instead of leaving its restore button inert.
      final selected = shell.selectedTabIn(panel);
      if (selected != null) shell.selectTab(selected.id);
    }
  }

  void _move(ForumPanel panel, {required bool away}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _moving.value = null;
      _fold.value = away ? 1 : 0;
      return;
    }
    // A panel turned back mid-way reverses from where it is.
    if (_moving.value?.panel != panel) {
      _moving.value = null;
      _fold.value = away ? 0 : 1;
    }
    final request = (panel: panel, away: away);
    _moving.value = request;
    // The frame that lays the panels out in their new places is the one
    // expensive frame. Started with it, the motion would lose its opening to
    // that frame's length, so it starts on the next one, unless a later
    // request has replaced this one by then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _moving.value != request) return;
      if (away) {
        _fold.forward();
      } else {
        _fold.reverse();
      }
    });
  }

  // Settling touches only the wrappers that listen to [_moving], not the
  // documents inside them.
  void _foldSettled(AnimationStatus status) {
    if (!status.isAnimating) _moving.value = null;
  }

  Widget _layoutGlyph(
    BuildContext context,
    ForumPanel? hidden,
    ForumPanel changing,
  ) {
    final placement = ComposerDock.workspacePlacementOf(context);
    final start = _layout._leading;
    return DLayoutGlyph(
      mainVisible: hidden != start,
      secondaryVisible: hidden != _other(start),
      changingPanel: changing == start ? 0 : 1,
      dock: switch (placement) {
        ComposerPlacement.left => DLayoutGlyphDock.left,
        ComposerPlacement.right => DLayoutGlyphDock.right,
        ComposerPlacement.bottom => DLayoutGlyphDock.bottom,
        ComposerPlacement.fullScreen => DLayoutGlyphDock.full,
        null => null,
      },
    );
  }

  @override
  void dispose() {
    _layout._toggle = null;
    _layout._present(visible: false, enabled: false);
    _windowFrame.removeListener(_frameChanged);
    _ownedWindowFrame?.dispose();
    _mainWidth.removeListener(_preferredWidthChanged);
    _swapFocus.dispose();
    _folded.dispose();
    _fold.dispose();
    _moving.dispose();
    _ownedLayout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final workspace = shell.currentWorkspace;
    final identity = workspace == null
        ? null
        : (
            workspace.siteUrl,
            workspace.accountIdentity,
            shell.lifecycle.capture(workspace.siteUrl).session,
          );
    if (_contentWorkspace != identity) {
      _contentWorkspace = identity;
      _tabContents.clear();
      _panelWidgets.clear();
    }
    _tabContents.removeWhere((id, _) => workspace?.tabById(id) == null);
    for (final panel in ForumPanel.values) {
      final selected = workspace?.selectedTabIn(panel);
      if (selected == null) continue;
      // Map insertion order records recency without changing document order.
      final content = _tabContents.remove(selected.id);
      _tabContents[selected.id] =
          content ??
          MainContent(key: GlobalKey(), layout: ShellLayout.expanded);
      final retained = _tabContents.keys
          .where((id) => workspace!.tabById(id)?.panel == panel)
          .toList();
      for (final id in retained.take(
        math.max(0, retained.length - _maximumRetainedTabsPerPanel),
      )) {
        _tabContents.remove(id);
      }
    }
    // Whatever becomes active in a minimized panel, whether a topic opened
    // from the list, a link or another forum's workspace, is what the reader
    // asked to see, so the panel comes back to show it.
    if (_minimized case final panel? when shell.activeTab?.panel == panel) {
      _minimized = null;
      _move(panel, away: false);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final direction = Directionality.of(context);
        final startPanel = _layout._leading;
        final mainAtStart = startPanel == ForumPanel.main;
        final mainResizeWindowEdge =
            mainAtStart == (direction == TextDirection.ltr)
            ? _WindowResizeEdge.right
            : _WindowResizeEdge.left;
        final resizingMain = _resizeEdge == mainResizeWindowEdge;
        const minimumMainWidth = 320 + workspacePanelGap;
        final maximumMainWidth = total - 320;
        final preferredMainWidth = _mainWidth.effectiveWidth(
          maximum: maximumMainWidth,
        );
        // The sidebar can disappear while the outer window shrinks, making
        // this workspace wider. Follow the dragged window edge so the panel
        // being reduced does not unexpectedly grow again at that breakpoint.
        final windowDelta = _anchoredWindowWidth == null
            ? 0.0
            : (_windowFrame.value?.width ?? _anchoredWindowWidth!) -
                  _anchoredWindowWidth!;
        final requestedMainWidth = _resizeEdge == null
            ? preferredMainWidth
            : resizingMain
            ? math.min(
                _swappedMainWidthLimit ?? _mainWidth.value,
                (_anchoredMainWidth ?? preferredMainWidth) + windowDelta,
              )
            : total -
                  (_anchoredSecondaryWidth ?? total - preferredMainWidth) -
                  windowDelta;
        final autoCollapsed = switch ((_resizeEdge, resizingMain)) {
          (null, _) => null,
          (_, true)
              when _minimized == null &&
                  shell.selectedTabIn(ForumPanel.secondary) != null &&
                  requestedMainWidth < minimumMainWidth =>
            ForumPanel.main,
          (_, false)
              when _minimized == null &&
                  shell.selectedTabIn(ForumPanel.main) != null &&
                  total - requestedMainWidth < 320 =>
            ForumPanel.secondary,
          _ => null,
        };
        final minimized = _minimized ?? autoCollapsed;
        final horizontal =
            total >= 640 + workspacePanelGap ||
            (minimized != null && total >= 320);
        _effectiveMinimized = minimized;
        _layout._present(
          visible: horizontal && minimized == null,
          enabled: total >= 640 + workspacePanelGap,
        );
        final mainWidth = requestedMainWidth
            .clamp(
              minimumMainWidth,
              math.max(minimumMainWidth, maximumMainWidth),
            )
            .toDouble();
        if (horizontal) {
          if (minimized == null) {
            _lastSplitMainWidth = mainWidth;
            _lastSplitTotalWidth = total;
          }
        }
        shell.topicPanelsVisible = horizontal;
        if (autoCollapsed != null && shell.activeTab?.panel == autoCollapsed) {
          final tabId = shell.selectedTabIn(_other(autoCollapsed))?.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && tabId != null) {
              ShellScope.read(context).selectTab(tabId);
            }
          });
        }
        // `minimizable` is null where a panel offers no minimize action.
        Widget panel(ForumPanel target, {bool? minimizable}) {
          final tab = shell.selectedTabIn(target);
          final contents = <_TabContent>[
            for (final tab in workspace?.tabsIn(target) ?? <ForumTab>[])
              if (_tabContents[tab.id] case final content?)
                (tabId: tab.id, content: content),
          ];
          // This build runs on every shell change. While a panel's inputs are
          // unchanged it keeps the same widget, so a change elsewhere, such
          // as a tab settling while a panel folds, does not rebuild its frame
          // and header.
          final inputs = (
            tab?.id,
            horizontal,
            minimizable,
            minimized,
            ComposerDock.workspacePlacementOf(context),
            startPanel,
          );
          if (_panelWidgets[target] case (
            :final key,
            contents: final previousContents,
            :final widget,
          ) when key == inputs && listEquals(previousContents, contents)) {
            return widget;
          }
          final widget = _DesktopPanel(
            key: _panelKeys[target],
            contents: contents,
            panel: target,
            tabId: tab?.id,
            showHeader: horizontal,
            action: minimizable == null
                ? null
                : DTooltip(
                    message: minimized == null
                        ? context.l10n.hideSplitView
                        : context.l10n.showSplitView,
                    child: DToggle.iconOnly(
                      key: ValueKey('panel-split-view-${target.name}'),
                      icon: _layoutGlyph(
                        context,
                        minimized,
                        minimized ?? target,
                      ),
                      interactiveIcon: _layoutGlyph(
                        context,
                        minimized == null ? target : null,
                        minimized ?? target,
                      ),
                      semanticLabel: minimized == null
                          ? context.l10n.hideSplitView
                          : context.l10n.showSplitView,
                      density: DToggleDensity.splitView,
                      pressed: minimized == null,
                      enabled: minimizable || minimized != null,
                      onPressedChanged: (_) => _toggleSplit(target),
                    ),
                  ),
          );
          _panelWidgets[target] = (
            key: inputs,
            contents: contents,
            widget: widget,
          );
          return widget;
        }

        final remaining = autoCollapsed == ForumPanel.main
            ? ForumPanel.secondary
            : ForumPanel.main;
        final active =
            autoCollapsed != null && shell.selectedTabIn(remaining) != null
            ? remaining
            : shell.activeTab?.panel ?? ForumPanel.main;
        if (!horizontal &&
            autoCollapsed != null &&
            shell.activeTab?.panel != active) {
          final tabId = shell.selectedTabIn(active)?.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && tabId != null) {
              ShellScope.read(context).selectTab(tabId);
            }
          });
        }

        // Built once per layout, so that dragging the seam or settling a fold
        // only moves and wraps them.
        final documents = {
          for (final target in ForumPanel.values)
            target: panel(
              target,
              minimizable: horizontal
                  ? shell.selectedTabIn(_other(target)) != null
                  : null,
            ),
        };
        // Keep the same panel ancestry when the composer narrows the reader
        // past the split breakpoint. Reparenting the documents would invalidate
        // every inherited dependency before the editor can paint.
        return Column(
          children: [
            if (!horizontal)
              ForumTabScope(
                tabId: shell.selectedTabIn(active)?.id,
                panel: active,
                child: TopicPanelTabs(panel: active),
              ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([_mainWidth, _moving]),
                builder: (context, _) {
                  final moving = horizontal ? _moving.value : null;
                  final seam = ResizablePane(
                    controller: _mainWidth,
                    edge: mainAtStart
                        ? ResizablePaneEdge.trailing
                        : ResizablePaneEdge.leading,
                    resizeKey: 'main-panel',
                    semanticsLabel: context.l10n.resizeMainPanel,
                    maximumWidth: maximumMainWidth,
                    widthOverride: mainWidth,
                    gap: workspacePanelGap,
                    onResizeStart: () => setState(() => _seamDragging = true),
                    onResizeEnd: () => setState(() => _seamDragging = false),
                    child: const SizedBox.shrink(),
                  );
                  // Either panel leaves the workspace entirely, including the gap.
                  final startWidth = mainAtStart
                      ? mainWidth - workspacePanelGap
                      : total - mainWidth;
                  final startExtent = startWidth + workspacePanelGap;
                  final startTravel = startExtent;
                  final endTravel = total + workspacePanelGap - startExtent;
                  final ltr = direction == TextDirection.ltr ? 1.0 : -1.0;
                  // Both panels keep one place in the tree in every layout, at rest
                  // and in motion. Moving a document under another parent would
                  // rebuild each of its widgets that reads an inherited value,
                  // thousands in an open topic, which is what made minimizing stall.
                  // A panel being restored comes back over the other one, which
                  // keeps its wide layout, clipped to the returning panel's edge,
                  // until the motion settles. Laid out narrow at once, it would
                  // leave a hole for the returning panel to cross.
                  final placed = moving != null && !moving.away
                      ? moving.panel
                      : minimized;
                  Widget slot(ForumPanel target) {
                    // A minimized panel keeps the place it returns to, so it is laid
                    // out again only when the window changes.
                    final (
                      start,
                      width,
                    ) = !horizontal || placed == _other(target)
                        ? (0.0, total)
                        : (
                            target == startPanel ? 0.0 : startExtent,
                            target == ForumPanel.main
                                ? mainWidth - workspacePanelGap
                                : math.max(320.0, total - mainWidth),
                          );
                    final folding = moving?.panel == target;
                    final revealing = moving != null && !folding;
                    final stowed = horizontal
                        ? minimized == target && !folding
                        : active != target;
                    // A panel's tickers and focus change once it has settled, off
                    // the frame that lays the other panel out anew.
                    final quiet = stowed || (folding && !moving!.away);
                    return Positioned.directional(
                      key: ValueKey(target),
                      textDirection: direction,
                      start: start,
                      width: width,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        ignoring: folding,
                        child: FadeTransition(
                          opacity: folding && !DMaterialTheme.glassOf(context)
                              ? ReverseAnimation(_folded)
                              : kAlwaysCompleteAnimation,
                          child: SlideTransition(
                            position: folding
                                ? _folded.drive(
                                    Tween(
                                      begin: Offset.zero,
                                      end: Offset(
                                        target == startPanel
                                            ? -ltr * startTravel / width
                                            : ltr * endTravel / width,
                                        0,
                                      ),
                                    ),
                                  )
                                : const AlwaysStoppedAnimation(Offset.zero),
                            child: ClipRRect(
                              clipBehavior: revealing
                                  ? Clip.antiAlias
                                  : Clip.none,
                              // The revealed edge keeps one gap from the folding
                              // panel's edge, as the seam did.
                              clipper: revealing
                                  ? _Reveal(
                                      folded: _folded,
                                      direction: direction,
                                      hidden: target == startPanel
                                          ? (folded) => (
                                              0,
                                              width -
                                                  (startExtent +
                                                      endTravel * folded -
                                                      workspacePanelGap),
                                            )
                                          : (folded) => (
                                              startExtent -
                                                  startTravel * folded -
                                                  start,
                                              0,
                                            ),
                                    )
                                  : null,
                              child: Offstage(
                                offstage: stowed,
                                child: TickerMode(
                                  enabled: !quiet,
                                  child: ExcludeFocus(
                                    excluding: quiet,
                                    // The slide, fade and reveal clip change above
                                    // this layer. Retain the panel's paint instead
                                    // of repainting its surface and document on
                                    // every animation frame.
                                    child: RepaintBoundary(
                                      child: documents[target]!,
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

                  return Stack(
                    children: [
                      for (final target in ForumPanel.values) slot(target),
                      if (horizontal && minimized == null && moving == null)
                        Positioned.fill(
                          child: Focus(
                            canRequestFocus: false,
                            onFocusChange: (focused) =>
                                setState(() => _seamFocused = focused),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                PositionedDirectional(
                                  start: mainAtStart ? 0 : total - mainWidth,
                                  top: 0,
                                  bottom: 0,
                                  child: seam,
                                ),
                                PositionedDirectional(
                                  start: startWidth,
                                  width: workspacePanelGap,
                                  top: 0,
                                  bottom: 0,
                                  child: MouseRegion(
                                    opaque: false,
                                    hitTestBehavior:
                                        HitTestBehavior.translucent,
                                    onEnter: (_) =>
                                        setState(() => _seamHovered = true),
                                    onExit: (_) =>
                                        setState(() => _seamHovered = false),
                                    onHover: (event) {
                                      final top =
                                          event.localPosition.dy <
                                          constraints.maxHeight / 2;
                                      if (top != _swapAtTop) {
                                        setState(() => _swapAtTop = top);
                                      }
                                    },
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                if (constraints.maxHeight >=
                                    2 *
                                            (44 +
                                                MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(26)) +
                                        36)
                                  PositionedDirectional(
                                    start: startWidth + workspacePanelGap / 2,
                                    top: _swapAtTop ? 44 : null,
                                    bottom: _swapAtTop ? null : 44,
                                    child: FractionalTranslation(
                                      translation: Offset(-ltr / 2, 0),
                                      child: MergeSemantics(
                                        child: Semantics(
                                          onTap: _swapPanels,
                                          onDidGainAccessibilityFocus:
                                              _swapFocus.requestFocus,
                                          child: Visibility(
                                            visible:
                                                !_seamDragging &&
                                                (_seamHovered || _seamFocused),
                                            maintainState: true,
                                            maintainAnimation: true,
                                            maintainSize: true,
                                            maintainFocusability: true,
                                            maintainSemantics: true,
                                            child: MouseRegion(
                                              onEnter: (_) => setState(
                                                () => _seamHovered = true,
                                              ),
                                              onExit: (_) => setState(
                                                () => _seamHovered = false,
                                              ),
                                              child: TextFieldTapRegion(
                                                child: DButton.iconOnly(
                                                  key: const ValueKey(
                                                    'swap-panels',
                                                  ),
                                                  focusNode: _swapFocus,
                                                  density: DButtonDensity
                                                      .chatMessageAction,
                                                  variant:
                                                      DButtonVariant.outline,
                                                  icon: const Icon(
                                                    Icons.swap_horiz,
                                                  ),
                                                  tooltip:
                                                      context.l10n.swapPanels,
                                                  onPressed: _swapPanels,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

typedef _TabContent = ({String tabId, MainContent content});

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    super.key,
    required this.panel,
    required this.tabId,
    required this.contents,
    this.showHeader = true,
    this.action,
  });

  final bool showHeader;
  final List<_TabContent> contents;
  final ForumPanel panel;
  final String? tabId;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    void activate() {
      if (tabId case final id? when shell.activeTab?.panel != panel) {
        shell.selectTab(id);
      }
    }

    return ForumTabScope(
      tabId: tabId,
      panel: panel,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          final source = shell.currentWorkspace?.tabById(details.data);
          return source != null && source.panel != panel;
        },
        onAcceptWithDetails: (details) =>
            shell.moveTabToPanel(details.data, panel),
        builder: (context, candidates, rejected) => WorkspacePanel(
          key: ValueKey('desktop-panel-${panel.name}'),
          atRightEdge: true,
          child: Column(
            children: [
              if (showHeader)
                TopicPanelTabs(
                  panel: panel,
                  incomingTabId: candidates.firstOrNull,
                  trailing: action,
                ),
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  onFocusChange: (focused) {
                    if (focused) activate();
                  },
                  child: Listener(
                    onPointerDown: (_) => activate(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final page in contents)
                          Offstage(
                            key: ValueKey(page.tabId),
                            offstage: page.tabId != tabId,
                            child: TickerMode(
                              enabled: page.tabId == tabId,
                              child: ExcludeFocus(
                                excluding: page.tabId != tabId,
                                child: ForumTabScope(
                                  tabId: page.tabId,
                                  panel: panel,
                                  child: RepaintBoundary(child: page.content),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hides the parts of a panel that its folding neighbour has not yet cleared.
class _Reveal extends CustomClipper<RRect> {
  _Reveal({required this.folded, required this.direction, required this.hidden})
    : super(reclip: folded);

  final Animation<double> folded;
  final TextDirection direction;

  /// The logical widths hidden at the panel's start and end at a given fold.
  final (double, double) Function(double folded) hidden;

  @override
  RRect getClip(Size size) {
    final (start, end) = hidden(folded.value);
    final hiddenStart = start.clamp(0.0, size.width);
    final hiddenEnd = end.clamp(0.0, size.width - hiddenStart);
    final (left, right) = direction == TextDirection.ltr
        ? (hiddenStart, hiddenEnd)
        : (hiddenEnd, hiddenStart);
    return RRect.fromLTRBR(
      left,
      0,
      size.width - right,
      size.height,
      const Radius.circular(DRadius.panel),
    );
  }

  @override
  bool shouldReclip(_Reveal oldClipper) => true;
}
