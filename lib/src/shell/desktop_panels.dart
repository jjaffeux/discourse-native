import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/forum_workspace.dart';
import '../theme/d_icons.dart';
import 'adaptive_shell.dart';
import 'forum_tabs_bar.dart';
import 'main_content.dart';
import 'panel_rail.dart';
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
final class DesktopPanelsLayout {
  final mainWidth = PanelWidthController(
    initialWidth: 400 + workspacePanelGap,
    minimumWidth: 320 + workspacePanelGap,
  );

  // Only one panel stands down at a time, or there would be nothing left to
  // read.
  ForumPanel? _minimized;

  void dispose() => mainWidth.dispose();
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
  // Tab-strip and focus changes must not rebuild an unchanged document.
  final _tabContents = <(String, String), MainContent>{};
  final _panelWidgets = <ForumPanel, ({Object key, Widget widget})>{};
  late DesktopPanelsLayout _layout;
  DesktopPanelsLayout? _ownedLayout;
  late ValueListenable<Rect?> _windowFrame;
  WindowFrame? _ownedWindowFrame;
  Rect? _previousWindowFrame;
  _WindowResizeEdge? _resizeEdge;
  double? _anchoredMainWidth;
  double? _anchoredSecondaryWidth;
  double? _anchoredWindowWidth;
  double? _lastSplitMainWidth;
  double? _lastSplitTotalWidth;

  PanelWidthController get _mainWidth => _layout.mainWidth;

  ForumPanel? get _minimized => _layout._minimized;
  set _minimized(ForumPanel? panel) => _layout._minimized = panel;

  @override
  void initState() {
    super.initState();
    _layout = widget.layout ?? (_ownedLayout = DesktopPanelsLayout());
    _windowFrame = widget.windowFrame ?? (_ownedWindowFrame = WindowFrame());
    _previousWindowFrame = _windowFrame.value;
    _windowFrame.addListener(_frameChanged);
    _mainWidth.addListener(_preferredWidthChanged);
  }

  @override
  void didUpdateWidget(DesktopPanels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) {
      _mainWidth.removeListener(_preferredWidthChanged);
      _ownedLayout?.dispose();
      _ownedLayout = null;
      _layout = widget.layout ?? (_ownedLayout = DesktopPanelsLayout());
      _mainWidth.addListener(_preferredWidthChanged);
    }
    if (oldWidget.windowFrame == widget.windowFrame) return;
    _windowFrame.removeListener(_frameChanged);
    _ownedWindowFrame?.dispose();
    _ownedWindowFrame = null;
    _windowFrame = widget.windowFrame ?? (_ownedWindowFrame = WindowFrame());
    _previousWindowFrame = _windowFrame.value;
    _resizeEdge = null;
    _windowFrame.addListener(_frameChanged);
  }

  void _preferredWidthChanged() {
    // A seam drag becomes the starting split for the next window resize.
    setState(() => _resizeEdge = null);
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
      _anchoredMainWidth = _lastSplitMainWidth;
      _anchoredSecondaryWidth = _lastSplitTotalWidth! - _lastSplitMainWidth!;
      _anchoredWindowWidth = previous.width;
    }
    setState(() => _resizeEdge = nextEdge);
  }

  // The panel still folding into its rail or back out of it. The motion is
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

  @override
  void dispose() {
    _windowFrame.removeListener(_frameChanged);
    _ownedWindowFrame?.dispose();
    _mainWidth.removeListener(_preferredWidthChanged);
    _folded.dispose();
    _fold.dispose();
    _moving.dispose();
    _ownedLayout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    _tabContents.removeWhere(
      (owner, _) => shell.workspaceFor(owner.$1)?.tabById(owner.$2) == null,
    );
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
        final requestedMainWidth = switch (_resizeEdge) {
          _WindowResizeEdge.right => math.min(
            _mainWidth.value,
            (_anchoredMainWidth ?? preferredMainWidth) + windowDelta,
          ),
          _WindowResizeEdge.left =>
            total -
                (_anchoredSecondaryWidth ?? total - preferredMainWidth) -
                windowDelta,
          null => preferredMainWidth,
        };
        final autoCollapsed = switch (_resizeEdge) {
          _WindowResizeEdge.right
              when _minimized == null &&
                  shell.selectedTabIn(ForumPanel.secondary) != null &&
                  requestedMainWidth < minimumMainWidth =>
            ForumPanel.main,
          _WindowResizeEdge.left
              when _minimized == null &&
                  shell.selectedTabIn(ForumPanel.main) != null &&
                  total - requestedMainWidth < 320 =>
            ForumPanel.secondary,
          _ => null,
        };
        final minimized = _minimized ?? autoCollapsed;
        final horizontal =
            total >= 640 + workspacePanelGap ||
            (minimized != null &&
                total >= 320 + PanelRail.width + workspacePanelGap);
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
          final content = tab == null
              ? null
              : _tabContents.putIfAbsent(
                  (shell.currentInstance!.url, tab.id),
                  () => MainContent(
                    key: GlobalKey(),
                    layout: ShellLayout.expanded,
                  ),
                );
          // This build runs on every shell change. While a panel's inputs are
          // unchanged it keeps the same widget, so a change elsewhere, such
          // as a tab settling while a panel folds, does not rebuild its frame
          // and header.
          final inputs = (tab?.id, content, horizontal, minimizable);
          if (_panelWidgets[target] case (
            :final key,
            :final widget,
          ) when key == inputs) {
            return widget;
          }
          final widget = _DesktopPanel(
            key: _panelKeys[target],
            content: content,
            panel: target,
            tabId: tab?.id,
            showHeader: horizontal,
            action: minimizable == null
                ? null
                : DButton.iconOnly(
                    key: ValueKey('minimize-panel-${target.name}'),
                    icon: const DIcon(DIcons.downLeftAndUpRightToCenter),
                    tooltip: minimizable
                        ? context.l10n.minimizePanel
                        : context.l10n.openATabInTheOtherPanelFirst,
                    variant: DButtonVariant.transparentBackground,
                    size: DButtonSize.tabAction,
                    onPressed: minimizable ? () => _minimize(target) : null,
                  ),
          );
          _panelWidgets[target] = (key: inputs, widget: widget);
          return widget;
        }

        if (!horizontal) {
          final remaining = autoCollapsed == ForumPanel.main
              ? ForumPanel.secondary
              : ForumPanel.main;
          final active =
              autoCollapsed != null && shell.selectedTabIn(remaining) != null
              ? remaining
              : shell.activeTab?.panel ?? ForumPanel.main;
          if (autoCollapsed != null && shell.activeTab?.panel != active) {
            final tabId = shell.selectedTabIn(active)?.id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && tabId != null) {
                ShellScope.read(context).selectTab(tabId);
              }
            });
          }
          return Column(
            children: [
              ForumTabScope(
                tabId: shell.selectedTabIn(active)?.id,
                panel: active,
                child: TopicPanelTabs(panel: active),
              ),
              Expanded(
                child: Stack(
                  children: [
                    for (final target in ForumPanel.values)
                      Positioned.fill(
                        child: Offstage(
                          offstage: active != target,
                          child: TickerMode(
                            enabled: active == target,
                            child: ExcludeFocus(
                              excluding: active != target,
                              child: panel(target),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }

        final direction = Directionality.of(context);
        // Built once per layout, so that dragging the seam or settling a fold
        // only moves and wraps them.
        final documents = {
          for (final target in ForumPanel.values)
            target: panel(
              target,
              minimizable: shell.selectedTabIn(_other(target)) != null,
            ),
        };
        final rail = minimized == null
            ? null
            : Align(
                alignment: AlignmentDirectional.topStart,
                child: CurrentForumTabsRail(
                  key: ValueKey('panel-rail-${minimized.name}'),
                  panel: minimized,
                  semanticLabel: minimized == ForumPanel.main
                      ? context.l10n.mainPanelMinimized
                      : context.l10n.secondaryPanelMinimized,
                  opensTowardStart: minimized == ForumPanel.secondary,
                  onRestore: () => _restore(minimized),
                  onSelect: (id) => _restore(minimized, tabId: id),
                  onNewTab: () => _restore(minimized, newTab: true),
                ),
              );
        return ListenableBuilder(
          listenable: Listenable.merge([_mainWidth, _moving]),
          builder: (context, _) {
            final moving = _moving.value;
            final seam = ResizablePane(
              controller: _mainWidth,
              edge: ResizablePaneEdge.trailing,
              resizeKey: 'main-panel',
              semanticsLabel: context.l10n.resizeMainPanel,
              maximumWidth: maximumMainWidth,
              widthOverride: mainWidth,
              gap: workspacePanelGap,
              child: const SizedBox.shrink(),
            );
            const docked = PanelRail.width + workspacePanelGap;
            // How far each panel travels toward its own edge to fold into the
            // rail there, measured from where it stands beside the other.
            final mainTravel = mainWidth - workspacePanelGap - PanelRail.width;
            final secondaryTravel = total - PanelRail.width - mainWidth;
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
              final (start, width) = switch ((target, placed)) {
                (ForumPanel.main, ForumPanel.secondary) => (
                  0.0,
                  total - docked,
                ),
                (ForumPanel.secondary, ForumPanel.main) => (
                  docked,
                  total - docked,
                ),
                (ForumPanel.main, _) => (0.0, mainWidth - workspacePanelGap),
                (ForumPanel.secondary, _) => (
                  mainWidth,
                  math.max(320.0, total - mainWidth),
                ),
              };
              final folding = moving?.panel == target;
              final revealing = moving != null && !folding;
              final stowed = minimized == target && !folding;
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
                    opacity: folding
                        ? ReverseAnimation(_folded)
                        : kAlwaysCompleteAnimation,
                    child: SlideTransition(
                      position: folding
                          ? _folded.drive(
                              Tween(
                                begin: Offset.zero,
                                end: Offset(
                                  target == ForumPanel.main
                                      ? -ltr * mainTravel / width
                                      : ltr * secondaryTravel / width,
                                  0,
                                ),
                              ),
                            )
                          : const AlwaysStoppedAnimation(Offset.zero),
                      child: ClipRRect(
                        clipBehavior: revealing ? Clip.antiAlias : Clip.none,
                        // The revealed edge keeps one gap from the folding
                        // panel's edge, as the seam did.
                        clipper: revealing
                            ? _Reveal(
                                folded: _folded,
                                direction: direction,
                                hidden: target == ForumPanel.main
                                    ? (folded) => (
                                        0,
                                        width -
                                            (mainWidth +
                                                secondaryTravel * folded -
                                                workspacePanelGap),
                                      )
                                    : (folded) => (
                                        mainWidth - mainTravel * folded - start,
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
                              child: documents[target]!,
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
                if (rail == null && moving == null)
                  // The pane carries only the seam's handle; the panels sit
                  // beside it in their own places.
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    child: seam,
                  )
                else if (minimized != null)
                  PositionedDirectional(
                    start: minimized == ForumPanel.main ? 0 : null,
                    end: minimized == ForumPanel.secondary ? 0 : null,
                    top: 0,
                    bottom: 0,
                    width: PanelRail.width,
                    child: FadeTransition(
                      opacity: moving?.panel == minimized
                          ? _folded
                          : kAlwaysCompleteAnimation,
                      child: rail,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    super.key,
    required this.panel,
    required this.tabId,
    this.content,
    this.showHeader = true,
    this.action,
  });

  final bool showHeader;
  final MainContent? content;
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
                    child: content ?? const SizedBox.shrink(),
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
