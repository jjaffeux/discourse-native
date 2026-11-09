import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/composer_placement.dart';
import '../../models/content_route.dart';
import '../../plugin_api/plugin_registry.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../theme/app_theme.dart';
import '../desktop_panels_layout.dart';
import '../platform.dart';
import '../shell_controller.dart';
import '../shell_metrics.dart';
import '../shell_panel.dart';
import '../shell_scope.dart';
import 'controller.dart';
import 'discard.dart';
import 'header.dart';
import 'panel.dart';
import 'presentation_controller.dart';
import 'presentation_scope.dart';

/// Retains each forum's editor while its dock placement or visibility changes.
class ComposerPresentationHost extends StatefulWidget {
  const ComposerPresentationHost({
    super.key,
    required this.child,
    this.controller,
    this.panelsLayout,
  });
  final Widget child;
  final ComposerPresentationController? controller;
  final DesktopPanelsLayout? panelsLayout;

  @override
  State<ComposerPresentationHost> createState() =>
      _ComposerPresentationHostState();
}

class _ComposerEntry {
  _ComposerEntry(this.composer);
  final ComposerController composer;
  final surfaceKey = GlobalKey();
  _ComposerSurface? surface;
  bool closeMenuOpen = false;
  bool minimized = false;
  bool moving = false;
  Size size = const Size(420, 380);
}

class _ComposerPresentationHostState extends State<ComposerPresentationHost>
    implements ComposerPresentationView {
  final _entries = <ComposerController, _ComposerEntry>{};
  ComposerPlacement _previousDockPlacement = ComposerPlacement.right;
  @override
  final contentKey = GlobalKey();
  @override
  final dockKey = GlobalKey();
  final _docks = <_ComposerDockState>{};
  _ComposerDockState? _activeDock;
  bool _dockSyncScheduled = false;
  late final _presentation =
      widget.controller ?? ComposerPresentationController();
  ShellController? _shell;
  List<ComposerController> _knownComposers = const [];
  ComposerController? _knownVisibleComposer;
  int _knownRevealRevision = 0;
  GlobalKey _surfacesKey = GlobalKey();
  BuildContext? _surfacesParentContext;
  bool _retiredSurfacesPending = false;
  final _sheetCovers = ValueNotifier(false);

  ComposerController? get _presentableComposer => _shell!.visibleComposer;

  @override
  DesktopPanelsLayout? get panelsLayout => widget.panelsLayout;

  @override
  Listenable get layoutChanges => _presentation;

  ComposerActivity get _activity =>
      switch (_entries[_presentableComposer]?.minimized) {
        null => ComposerActivity.none,
        true => ComposerActivity.minimized,
        false => ComposerActivity.writing,
      };

  _ComposerEntry? get _mobileSheetEntry {
    if (!context.isTouch || _activeDock == null) return null;
    final entry = _entries[_presentableComposer];
    return entry?.minimized == false ? entry : null;
  }

  void _syncDocks() {
    // Park the editor until its dock is mounted, preserving editing state
    // across shell layout changes.
    if (_dockSyncScheduled) return;
    _dockSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dockSyncScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _presentation.addListener(_changed);
    unawaited(_presentation.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.read(context);
    if (identical(shell, _shell)) return;
    _detachReplacementConfirmation();
    _shell?.removeListener(_shellChanged);
    _shell = shell..addListener(_shellChanged);
    shell.confirmComposerReplacement = _confirmReplacement;
    _knownComposers = shell.liveComposers.toList();
    _knownVisibleComposer = shell.visibleComposer;
    _knownRevealRevision = shell.composerRevealRevision;
  }

  Future<void> _confirmReplacement(ComposerController composer) async {
    if (!mounted) return;
    await requestComposerDiscard(
      context: context,
      composer: composer,
      controller: _shell,
    );
  }

  void _detachReplacementConfirmation() {
    if (_shell?.confirmComposerReplacement == _confirmReplacement) {
      _shell?.confirmComposerReplacement = null;
    }
  }

  void _shellChanged() {
    final composers = _shell!.liveComposers.toList();
    final visible = _shell!.visibleComposer;
    final revealChanged =
        _shell!.composerRevealRevision != _knownRevealRevision;
    final reveal =
        revealChanged && identical(_shell!.composerRevealTarget, visible);
    if (!revealChanged &&
        listEquals(composers, _knownComposers) &&
        identical(visible, _knownVisibleComposer)) {
      return;
    }
    if (_knownComposers.any((composer) => !composers.contains(composer))) {
      _retiredSurfacesPending = true;
    }
    _knownComposers = composers;
    _knownVisibleComposer = visible;
    _knownRevealRevision = _shell!.composerRevealRevision;
    if (reveal && visible != null) {
      _entries[visible]?.minimized = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !visible.isDisposed &&
            identical(_presentableComposer, visible)) {
          visible.focus.requestFocus();
        }
      });
    }
    _changed();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void redockForNavigation() {
    final entry = _entries[_presentableComposer];
    if (entry == null ||
        entry.minimized ||
        _presentation.preference.placement != ComposerPlacement.fullScreen) {
      return;
    }
    unawaited(_place(entry, _previousDockPlacement, focusEditor: false));
  }

  @override
  void minimizeComposer() {
    final entry = _entries[_presentableComposer];
    if (entry != null && !entry.minimized) _putAway(entry);
  }

  @override
  void restoreComposer() {
    final entry = _entries[_presentableComposer];
    if (entry != null && entry.minimized) _restore(entry);
  }

  void _putAway(_ComposerEntry entry) =>
      context.isTouch ? unawaited(_dismissMobile(entry)) : _minimize(entry);

  void _restore(_ComposerEntry entry) {
    setState(() => entry.minimized = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!entry.composer.isDisposed) entry.composer.focus.requestFocus();
    });
  }

  void _minimize(_ComposerEntry entry) {
    if (!mounted || entry.composer.isDisposed) {
      return;
    }
    entry.composer.focus.unfocus();
    setState(() {
      entry.closeMenuOpen = false;
      entry.minimized = true;
    });
  }

  Future<void> _dismissMobile(_ComposerEntry entry) async {
    final composer = entry.composer;
    if (!mounted || composer.isDisposed) return;
    if (composer.draft.isEmpty &&
        !composer.submitting &&
        !composer.loadingBody &&
        !composer.hasActiveUploads &&
        composer.state != ComposerState.checking) {
      if (composer.canSaveDraft &&
          !await _shell!.finishComposerDraftRestore(composer)) {
        return;
      }
      if (!mounted || composer.isDisposed) return;
      if (composer.draft.isEmpty) {
        await saveComposerFromPanel(
          context: context,
          composer: composer,
          controller: _shell,
        );
        return;
      }
    }
    _minimize(entry);
  }

  Future<void> _place(
    _ComposerEntry entry,
    ComposerPlacement placement, {
    bool focusEditor = true,
  }) async {
    if (entry.moving || entry.composer.isDisposed) return;
    entry.moving = true;
    // Let the placement menu and editor selection overlay finish dismissing.
    entry.composer.focus.unfocus();
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || entry.composer.isDisposed) return;
      setState(() => entry.minimized = false);
      final previous = _presentation.preference.placement;
      if (previous != ComposerPlacement.fullScreen) {
        _previousDockPlacement = previous;
      }
      _presentation.dock(placement);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      entry.moving = false;
      if (mounted) {
        setState(() {});
        if (focusEditor) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!entry.composer.isDisposed) entry.composer.focus.requestFocus();
          });
        }
      }
    }
  }

  Widget _surface(
    _ComposerEntry entry, {
    required ComposerPlacement placement,
    required bool mobile,
    required Size size,
    bool parked = false,
  }) {
    if (!entry.minimized && !parked) entry.size = size;
    // Move the retained editor stack as a unit between docks. Individual draft
    // switches only change visibility, so editor and semantics ancestry stay
    // stable while selection, scroll position, and editing history are retained.
    return Builder(
      builder: (context) {
        if (_retiredSurfacesPending &&
            !identical(_surfacesParentContext, context)) {
          // Reparenting attaches the old subtree before pruning disposed editors.
          _surfacesKey = GlobalKey();
        }
        _retiredSurfacesPending = false;
        _surfacesParentContext = context;
        return Stack(
          key: _surfacesKey,
          fit: StackFit.expand,
          children: [
            for (final candidate in _entries.values)
              _retainedSurface(
                candidate,
                shown: !parked && identical(candidate, entry),
                placement: placement,
                mobile: mobile,
                size: identical(candidate, entry) && !parked
                    ? size
                    : candidate.size,
              ),
          ],
        );
      },
    );
  }

  Widget _retainedSurface(
    _ComposerEntry entry, {
    required bool shown,
    required ComposerPlacement placement,
    required bool mobile,
    required Size size,
  }) {
    final minimized = entry.minimized && shown;
    final presentation = (
      minimized: minimized,
      moving: entry.moving,
      mobile: mobile,
      placement: placement,
      editorSize: minimized ? entry.size : size,
      closeMenuOpen: mobile ? entry.closeMenuOpen : null,
      canDockSide:
          placement.isSide ||
          size.width >=
              ComposerPresentationController.sideMinimum +
                  ComposerPresentationController.readerMinimum +
                  workspacePanelGap,
    );
    var surface = entry.surface;
    if (surface == null || surface.presentation != presentation) {
      surface = entry.surface = _ComposerSurface(
        key: entry.surfaceKey,
        composer: entry.composer,
        presentation: presentation,
        onPlacement: (value) => unawaited(_place(entry, value)),
        onExitFullScreen: () =>
            unawaited(_place(entry, _previousDockPlacement)),
        onMinimize: () => _putAway(entry),
        onRestore: () => _restore(entry),
        onCloseMenuOpenChanged: (open) {
          if (mounted && entry.closeMenuOpen != open) {
            setState(() => entry.closeMenuOpen = open);
          }
        },
      );
    }
    return Offstage(
      key: ObjectKey(entry.composer),
      offstage: !shown,
      child: ExcludeFocus(
        excluding: !shown,
        child: TickerMode(
          enabled: shown,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: surface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = _shell!.liveComposers.toSet();
    for (final composer in live) {
      _entries.putIfAbsent(composer, () => _ComposerEntry(composer));
    }
    _entries.removeWhere((composer, _) => !live.contains(composer));
    final current = _presentableComposer;
    _activeDock = _docks.where((dock) => dock.mounted).lastOrNull;
    final mobileSheet = _mobileSheetEntry;
    return ComposerPresentationScope(
      view: this,
      hasMobileSheet: mobileSheet != null,
      child: _ComposerPresentationScope(
        owner: this,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ExcludeFocus(
                excluding: mobileSheet != null,
                child: ExcludeSemantics(
                  excluding: mobileSheet != null,
                  child: _CoveredContent(
                    covering: _sheetCovers,
                    child: ComposerActivityScope(
                      activity: _activity,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
            if (_entries.isNotEmpty && (current == null || _activeDock == null))
              Offstage(
                child: _surface(
                  _entries[current] ?? _entries.values.first,
                  placement: _presentation.preference.placement,
                  mobile: context.isTouch,
                  size: (_entries[current] ?? _entries.values.first).size,
                  parked: true,
                ),
              ),
            if (mobileSheet != null)
              Positioned.fill(
                // The sheet covers the shell without a route or overlay, so it
                // must hide the system glass drawn above the Flutter view.
                child: PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) {
                      unawaited(
                        closeComposerFromPanel(
                          context: context,
                          composer: mobileSheet.composer,
                        ),
                      );
                    }
                  },
                  child: DSheetViewport(
                    key: ObjectKey(mobileSheet.composer),
                    covering: _sheetCovers,
                    onDismiss: () => unawaited(_dismissMobile(mobileSheet)),
                    content: DSheetContent(
                      key: const ValueKey('composer-mobile-sheet'),
                      side: DSheetSide.bottom,
                      variant: DSheetVariant.menu,
                      fillAvailableHeight: true,
                      extendBehindKeyboard: true,
                      scrollWholeSheet: false,
                      showCloseButton: false,
                      semanticLabel: context.l10n.composer,
                      backgroundColor: Theme.of(context).shell.content,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, bounds) => _surface(
                              mobileSheet,
                              placement: ComposerPlacement.fullScreen,
                              mobile: true,
                              size: bounds.biggest,
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
    );
  }

  @override
  void dispose() {
    _detachReplacementConfirmation();
    _shell?.removeListener(_shellChanged);
    _presentation.removeListener(_changed);
    if (widget.controller == null) _presentation.dispose();
    _sheetCovers.dispose();
    super.dispose();
  }
}

/// Lays out the shell under the mobile sheet but skips painting it while the
/// sheet's opaque canvas hides it, so typing does not redraw what no one sees.
class _CoveredContent extends SingleChildRenderObjectWidget {
  const _CoveredContent({required this.covering, required super.child});

  final ValueListenable<bool> covering;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCoveredContent(covering);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCoveredContent renderObject,
  ) => renderObject.covering = covering;
}

class _RenderCoveredContent extends RenderProxyBox {
  _RenderCoveredContent(this._covering);

  ValueListenable<bool> _covering;
  set covering(ValueListenable<bool> value) {
    if (value == _covering) return;
    if (attached) {
      _covering.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _covering = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _covering.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _covering.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_covering.value) super.paint(context, offset);
  }
}

class _ComposerPresentationScope extends InheritedWidget {
  const _ComposerPresentationScope({required this.owner, required super.child});
  final _ComposerPresentationHostState owner;
  static _ComposerPresentationHostState of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ComposerPresentationScope>()!
      .owner;
  @override
  bool updateShouldNotify(_ComposerPresentationScope oldWidget) => true;
}

/// Docks desktop editors and floats minimized mobile editors over the reader.
class ComposerDock extends StatefulWidget {
  const ComposerDock({
    super.key,
    required this.child,
    this.appWorkspace = false,
  });
  final Widget child;
  final bool appWorkspace;

  @override
  State<ComposerDock> createState() => _ComposerDockState();
}

class _ComposerDockState extends State<ComposerDock> {
  final _readerKey = GlobalKey();
  final _readerViewportKey = GlobalKey();
  double? _resizeProposal;
  _ComposerPresentationHostState? _owner;
  ComposerController? _visibleComposer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = _ComposerPresentationScope.of(context);
    if (identical(owner, _owner)) return;
    _owner?._docks.remove(this);
    _owner?._syncDocks();
    _owner = owner;
    owner._docks.add(this);
    owner._syncDocks();
  }

  @override
  void dispose() {
    _owner?._docks.remove(this);
    _owner?._syncDocks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = _ComposerPresentationScope.of(context);
    final active = identical(owner._activeDock, this);
    final composer = active ? owner._presentableComposer : null;
    final mobile = context.isTouch;
    final composerEntry = owner._entries[composer];
    // The host presents expanded mobile editors outside the resizing shell.
    final entry = mobile && composerEntry?.minimized == false
        ? null
        : composerEntry;
    if (!identical(_visibleComposer, composer)) {
      _visibleComposer = composer;
      if (composer != null &&
          composerEntry != null &&
          !composerEntry.minimized) {
        // Autofocus may already have run while the retained editor was parked
        // offstage. Request focus after its visible dock has been laid out.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              identical(owner._activeDock, this) &&
              identical(owner._presentableComposer, composer) &&
              !composer.isDisposed &&
              !composerEntry.minimized) {
            composer.focus.requestFocus();
          }
        });
      }
    }
    final reader = KeyedSubtree(
      key: _readerKey,
      child: ExcludeFocus(
        excluding:
            entry?.minimized == false &&
            owner._presentation.preference.placement ==
                ComposerPlacement.fullScreen,
        child: widget.child,
      ),
    );
    Widget readerViewport({
      bool bottomDocked = false,
      ComposerPlacement? workspacePlacement,
    }) => SizedBox.expand(
      key: _readerViewportKey,
      child: WorkspacePanelCorner(
        radius:
            entry?.minimized == true ||
                workspacePlacement == ComposerPlacement.right ||
                workspacePlacement == ComposerPlacement.bottom
            ? null
            : WorkspacePanelCorner.of(context),
        child: RepaintBoundary(
          child: widget.appWorkspace
              ? ComposerWorkspacePlacementScope(
                  placement: workspacePlacement,
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: reader,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, bounds) => DScrollArea(
                    thumbVisibility: false,
                    child: SizedBox(
                      height: bottomDocked
                          ? math.max(
                              bounds.maxHeight,
                              MediaQuery.textScalerOf(context).scale(320),
                            )
                          : bounds.maxHeight,
                      child: reader,
                    ),
                  ),
                ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final element = _readerViewportKey.currentContext;
      final render = element is RenderObjectElement
          ? element.renderObject
          : null;
      if (mounted &&
          !widget.appWorkspace &&
          identical(owner._activeDock, this) &&
          render is RenderBox &&
          render.attached &&
          render.hasSize) {
        owner._shell!.reportReaderContentBounds(
          render.localToGlobal(Offset.zero) & render.size,
        );
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final placement = owner._presentation.effectivePlacement(
          mobile: mobile,
          width: constraints.maxWidth,
          minimumReaderWidth:
              ComposerPresentationController.readerMinimum +
              (mobile ? 0 : workspacePanelGap - 1),
        );
        if (entry == null) {
          // Keep the reader in the same panel ancestry when the editor opens.
          // Reparenting it invalidates inherited dependencies in every post.
          return DDirection(
            textDirection: TextDirection.ltr,
            child: DResizablePanelGroup(
              key: const ValueKey('composer-dock'),
              orientation: placement.isSide ? Axis.horizontal : Axis.vertical,
              children: [
                DResizablePanel(
                  id: 'reader',
                  child: DDirection(
                    textDirection: DDirection.of(context),
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: readerViewport(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final minimized = entry.minimized;
        if (minimized) {
          final height = DButton.resumeHeight(context);
          final width = mobile
              ? constraints.maxWidth - 12
              : math.min(constraints.maxWidth - 12, 460.0);
          if (mobile) {
            final surface = owner._surface(
              entry,
              placement: ComposerPlacement.fullScreen,
              mobile: true,
              size: Size(width, height),
            );
            // A parked draft waits 8 over the bar of places, out of the way
            // of a page's own composer and of the open sidebar. Hidden, it
            // stays mounted so the retained editor keeps its state.
            return ShellSelector<(ContentRoute?, bool)>(
              select: (shell) =>
                  (shell.currentContent, shell.mobileNavigation.sidebarOpen),
              child: readerViewport(),
              builder: (context, state, reader) {
                final (route, sidebarOpen) = state;
                final registry =
                    PluginScope.maybeOf(context)?.registry ??
                    PluginRegistry.empty;
                final shown =
                    !sidebarOpen &&
                    !(route != null &&
                        registry.ownsMobileComposer(context, route));
                final bar = DMobileDockGeometry.of(context);
                final noBar =
                    route != null && registry.hidesMobileDock(context, route);
                return ComposerParkedDraftScope(
                  room: shown ? height + 8 : 0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      reader!,
                      PositionedDirectional(
                        start: 6,
                        end: 6,
                        bottom: noBar
                            ? bar.foot
                            : bar.margin.bottom + bar.barHeight + 8,
                        height: height,
                        child: Offstage(
                          offstage: !shown,
                          child: ExcludeFocus(
                            excluding: !shown,
                            child: surface,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
          final content = Column(
            children: [
              Expanded(child: readerViewport()),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                child: Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: owner._surface(
                      entry,
                      placement: placement,
                      mobile: false,
                      size: Size(width, height),
                    ),
                  ),
                ),
              ),
            ],
          );
          return content;
        }
        if (mobile || placement == ComposerPlacement.fullScreen) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Offstage(offstage: true, child: readerViewport()),
              Positioned.fill(
                child: WorkspacePanel(
                  child: owner._surface(
                    entry,
                    placement: placement,
                    mobile: mobile,
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
              ),
            ],
          );
        }
        final side = placement.isSide;
        // The group reserves a 1px seam; padding supplies the rest of the gutter.
        final panelInset = mobile ? 0.0 : (workspacePanelGap - 1) / 2;
        final readerPadding = side
            ? EdgeInsets.only(
                left: placement == ComposerPlacement.left ? panelInset : 0,
                right: placement == ComposerPlacement.right ? panelInset : 0,
              )
            : EdgeInsets.only(bottom: panelInset);
        final editorPadding = side
            ? EdgeInsets.only(
                right: placement == ComposerPlacement.left ? panelInset : 0,
                left: placement == ComposerPlacement.right ? panelInset : 0,
              )
            : EdgeInsets.only(top: panelInset);
        // The divider's hit region extends into both panels. Reserve its
        // editor half so touch resizing never intercepts header buttons.
        final dividerInset = side ? 0.0 : (mobile ? 24.0 : 12.0 - panelInset);
        final topic =
            composer!.target.createsTopic || composer.target.editsTopicMetadata;
        final preference = owner._presentation.preference;
        final extent = side ? constraints.maxWidth : constraints.maxHeight;
        final readerMin =
            panelInset +
            (side
                ? ComposerPresentationController.readerMinimum
                : math.min(96.0, math.max(0.0, extent - 241)));
        final composerMin =
            panelInset +
            (side
                ? ComposerPresentationController.sideMinimum
                : math.min(
                    240.0 + dividerInset,
                    math.max(0.0, extent - readerMin - 1 - panelInset),
                  ));
        final preferred =
            panelInset +
            (side
                ? preference.sideWidth
                : composer.target.isTaxonomyEdit
                ? 190.0 + dividerInset
                : topic
                ? preference.topicHeight + dividerInset
                : preference.replyHeight + dividerInset);
        final size = preferred
            .clamp(composerMin, math.max(composerMin, extent - readerMin - 1))
            .toDouble();
        final readerPanel = DResizablePanel(
          id: 'reader',
          minSize: DResizableSize.pixels(readerMin),
          child: DDirection(
            textDirection: DDirection.of(context),
            child: Padding(
              padding: readerPadding,
              child: readerViewport(
                bottomDocked: !side,
                workspacePlacement: placement,
              ),
            ),
          ),
        );
        final direction = DDirection.of(context);
        final editorPanel = DResizablePanel(
          id: 'composer',
          minSize: DResizableSize.pixels(composerMin),
          child: DDirection(
            textDirection: direction,
            child: Padding(
              padding: editorPadding,
              child: WorkspacePanel(
                atRightEdge: placement != ComposerPlacement.left,
                child: Container(
                  padding: EdgeInsets.only(top: dividerInset),
                  child: LayoutBuilder(
                    builder: (context, bounds) => owner._surface(
                      entry,
                      placement: placement,
                      mobile: mobile,
                      size: bounds.biggest,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return DDirection(
          textDirection: TextDirection.ltr,
          child: DResizablePanelGroup(
            key: const ValueKey('composer-dock'),
            orientation: side ? Axis.horizontal : Axis.vertical,
            layout: {
              'composer': DResizableSize.pixels(size),
              'reader': DResizableSize.pixels(math.max(0, extent - size - 1)),
            },
            onLayoutChange: (layout) {
              final proposal = layout['composer']!;
              if ((proposal - size).abs() < .01) return;
              _resizeProposal = proposal;
              owner._presentation.resize(
                placement: placement,
                extent: proposal - dividerInset - panelInset,
                topic: topic,
                persist: false,
              );
            },
            onLayoutChanged: (layout) {
              if (_resizeProposal == null) return;
              final proposal = _resizeProposal!;
              _resizeProposal = null;
              owner._presentation.resize(
                placement: placement,
                extent: proposal - dividerInset - panelInset,
                topic: topic,
              );
            },
            children: [
              if (placement == ComposerPlacement.left)
                editorPanel
              else
                readerPanel,
              DResizableHandle(
                semanticLabel: context.l10n.resizeComposer,
                withHandle: !mobile,
                dividerThickness: mobile ? 1 : 0,
                focusedDividerThickness: 3,
              ),
              if (placement == ComposerPlacement.left)
                readerPanel
              else
                editorPanel,
            ],
          ),
        );
      },
    );
  }
}

typedef _ComposerSurfacePresentation = ({
  bool minimized,
  bool moving,
  bool mobile,
  ComposerPlacement placement,
  Size editorSize,
  bool? closeMenuOpen,
  bool canDockSide,
});

/// The full editor stays mounted and laid out while its compact strip is shown.
class _ComposerSurface extends StatelessWidget {
  const _ComposerSurface({
    super.key,
    required this.composer,
    required this.presentation,
    required this.onPlacement,
    required this.onExitFullScreen,
    required this.onMinimize,
    required this.onRestore,
    required this.onCloseMenuOpenChanged,
  });
  final ComposerController composer;
  final _ComposerSurfacePresentation presentation;
  final ValueChanged<ComposerPlacement> onPlacement;
  final VoidCallback onMinimize, onRestore, onExitFullScreen;
  final ValueChanged<bool> onCloseMenuOpenChanged;

  @override
  Widget build(BuildContext context) {
    final minimized = presentation.minimized;
    final mobile = presentation.mobile;
    final placement = presentation.placement;
    final size = presentation.editorSize;
    return Material(
      type: MaterialType.transparency,
      child: AbsorbPointer(
        absorbing: presentation.moving,
        child: Stack(
          children: [
            ExcludeFocus(
              excluding: minimized,
              child: Offstage(
                offstage: minimized,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: size.width,
                  maxWidth: size.width,
                  minHeight: size.height,
                  maxHeight: size.height,
                  child: ComposerPanel(
                    composer: composer,
                    closeMenuOpen: presentation.closeMenuOpen,
                    onCloseMenuOpenChanged: onCloseMenuOpenChanged,
                    height: size.height,
                    placement: placement,
                    onPlacementChanged: mobile ? null : onPlacement,
                    canDockSide: presentation.canDockSide,
                    onExitFullScreen: mobile ? null : onExitFullScreen,
                    onMinimize: onMinimize,
                  ),
                ),
              ),
            ),
            if (minimized)
              ComposerHeader(
                composer: composer,
                minimized: true,
                closeTooltip: composer.canSaveDraft
                    ? context.l10n.saveAndClose
                    : context.l10n.closeComposer,
                onClose: () => unawaited(
                  closeComposerFromPanel(context: context, composer: composer),
                ),
                onRestore: onRestore,
                placement: placement,
              ),
          ],
        ),
      ),
    );
  }
}
