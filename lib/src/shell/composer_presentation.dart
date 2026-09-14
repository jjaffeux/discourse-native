import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/composer_placement.dart';
import '../theme/app_theme.dart';
import 'composer_controller.dart';
import 'composer_discard.dart';
import 'composer_header.dart';
import 'composer_panel.dart';
import 'composer_presentation_controller.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'title_bar.dart';

/// Retains each tab's editor while its dock placement or visibility changes.
class ComposerPresentationHost extends StatefulWidget {
  const ComposerPresentationHost({
    super.key,
    required this.child,
    this.controller,
  });
  final Widget child;
  final ComposerPresentationController? controller;

  // The key is stable for the host's lifetime; reading it must not subscribe
  // the shell layout to composer presentation updates.
  static Key contentKeyOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_ComposerPresentationScope>()!
      .owner
      ._contentKey;

  static Key dockKeyOf(BuildContext context) =>
      _ComposerPresentationScope.of(context)._dockKey;

  static Listenable layoutChangesOf(BuildContext context) =>
      _ComposerPresentationScope.of(context)._presentation;

  @override
  State<ComposerPresentationHost> createState() =>
      _ComposerPresentationHostState();
}

class _ComposerEntry {
  _ComposerEntry(this.composer);
  final ComposerController composer;
  final surfaceKey = GlobalKey();
  bool minimized = false;
  bool moving = false;
  Size size = const Size(420, 380);
}

class _ComposerPresentationHostState extends State<ComposerPresentationHost> {
  final _entries = <ComposerController, _ComposerEntry>{};
  final _contentKey = GlobalKey();
  final _dockKey = GlobalKey();
  final _docks = <_ComposerDockState>{};
  _ComposerDockState? _activeDock;
  bool _dockSyncScheduled = false;
  late final _presentation =
      widget.controller ?? ComposerPresentationController();
  ShellController? _shell;

  ComposerController? get _presentableComposer => _shell!.visibleComposer;

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
    _shell?.removeListener(_changed);
    _shell = shell..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _place(_ComposerEntry entry, ComposerPlacement placement) async {
    if (entry.moving || entry.composer.isDisposed) return;
    entry.moving = true;
    // Let the placement menu and editor selection overlay finish dismissing.
    entry.composer.focus.unfocus();
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || entry.composer.isDisposed) return;
      setState(() => entry.minimized = false);
      _presentation.dock(placement);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      entry.moving = false;
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!entry.composer.isDisposed) entry.composer.focus.requestFocus();
        });
      }
    }
  }

  Widget _surface(
    _ComposerEntry entry, {
    required ComposerPlacement placement,
    required bool mobile,
    required Size size,
  }) {
    if (!entry.minimized) entry.size = size;
    return _ComposerSurface(
      key: entry.surfaceKey,
      entry: entry,
      placement: placement,
      mobile: mobile,
      size: size,
      onPlacement: (value) => unawaited(_place(entry, value)),
      onMinimize: () {
        entry.composer.focus.unfocus();
        setState(() => entry.minimized = true);
      },
      onRestore: () {
        setState(() => entry.minimized = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!entry.composer.isDisposed) entry.composer.focus.requestFocus();
        });
      },
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
    return _ComposerPresentationScope(
      owner: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: widget.child),
          for (final entry in _entries.values)
            if (entry.composer != current || _activeDock == null)
              ExcludeFocus(
                child: TickerMode(
                  enabled: false,
                  child: Offstage(
                    child: SizedBox.fromSize(
                      size: entry.size,
                      child: _surface(
                        entry,
                        placement: _presentation.preference.placement,
                        mobile: context.isTouch,
                        size: entry.size,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _shell?.removeListener(_changed);
    _presentation.removeListener(_changed);
    if (widget.controller == null) _presentation.dispose();
    super.dispose();
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

/// Reserves space for the editor alongside the desktop workspace or mobile page.
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
    final entry = owner._entries[composer];
    final reader = KeyedSubtree(key: _readerKey, child: widget.child);
    Widget readerViewport({bool bottomDocked = false}) => SizedBox.expand(
      key: _readerViewportKey,
      child: widget.appWorkspace
          ? Semantics(container: true, explicitChildNodes: true, child: reader)
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
    if (entry == null) return readerViewport();
    final mobile = context.isTouch;
    return LayoutBuilder(
      builder: (context, constraints) {
        final placement = owner._presentation.effectivePlacement(
          mobile: mobile,
          width: constraints.maxWidth,
        );
        final minimized = entry.minimized;
        if (minimized) {
          return Column(
            children: [
              Expanded(child: readerViewport()),
              SizedBox(
                height: ComposerHeader.height,
                child: owner._surface(
                  entry,
                  placement: placement,
                  mobile: mobile,
                  size: Size(constraints.maxWidth, ComposerHeader.height),
                ),
              ),
            ],
          );
        }
        final side = placement.isSide;
        // The divider's hit region extends into both panels. Reserve its
        // editor half so touch resizing never intercepts header buttons.
        final dividerInset = side ? 0.0 : (mobile ? 24.0 : 12.0);
        final topic =
            composer!.target.createsTopic || composer.target.editsTopicMetadata;
        final preference = owner._presentation.preference;
        final extent = side ? constraints.maxWidth : constraints.maxHeight;
        final readerMin = side
            ? ComposerPresentationController.readerMinimum
            : math.min(96.0, math.max(0.0, extent - 241));
        final composerMin = side
            ? ComposerPresentationController.sideMinimum
            : math.min(
                240.0 + dividerInset,
                math.max(0.0, extent - readerMin - 1),
              );
        final preferred = side
            ? preference.sideWidth
            : composer.target.isTaxonomyEdit
            ? 190.0 + dividerInset
            : topic
            ? preference.topicHeight + dividerInset
            : preference.replyHeight + dividerInset;
        final size = preferred
            .clamp(composerMin, math.max(composerMin, extent - readerMin - 1))
            .toDouble();
        final readerPanel = DResizablePanel(
          id: 'reader',
          minSize: DResizableSize.pixels(readerMin),
          child: DDirection(
            textDirection: DDirection.of(context),
            child: readerViewport(bottomDocked: !side),
          ),
        );
        final direction = DDirection.of(context);
        final editorPanel = DResizablePanel(
          id: 'composer',
          minSize: DResizableSize.pixels(composerMin),
          child: DDirection(
            textDirection: direction,
            child: Container(
              color: Theme.of(context).shell.content,
              padding: EdgeInsets.only(top: dividerInset),
              child: LayoutBuilder(
                builder: (context, bounds) => Column(
                  children: [
                    // Native window controls stay at the physical top left.
                    if (widget.appWorkspace &&
                        placement == ComposerPlacement.left &&
                        ShellTitleBar.isSupported)
                      const ShellTitleBar(showControls: false),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, bounds) => owner._surface(
                          entry,
                          placement: placement,
                          mobile: mobile,
                          size: bounds.biggest,
                        ),
                      ),
                    ),
                  ],
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
                extent: proposal - dividerInset,
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
                extent: proposal - dividerInset,
                topic: topic,
              );
            },
            children: [
              if (placement == ComposerPlacement.left)
                editorPanel
              else
                readerPanel,
              const DResizableHandle(semanticLabel: 'Resize composer'),
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

/// The full editor stays mounted and laid out while its compact strip is shown.
class _ComposerSurface extends StatelessWidget {
  const _ComposerSurface({
    super.key,
    required this.entry,
    required this.placement,
    required this.mobile,
    required this.size,
    required this.onPlacement,
    required this.onMinimize,
    required this.onRestore,
  });
  final _ComposerEntry entry;
  final ComposerPlacement placement;
  final bool mobile;
  final Size size;
  final ValueChanged<ComposerPlacement> onPlacement;
  final VoidCallback onMinimize, onRestore;

  @override
  Widget build(BuildContext context) {
    final composer = entry.composer;
    final minimized = entry.minimized;
    return Material(
      color: Theme.of(context).shell.content,
      child: AbsorbPointer(
        absorbing: entry.moving,
        child: Stack(
          children: [
            ExcludeFocus(
              excluding: minimized,
              child: Offstage(
                offstage: minimized,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: minimized ? entry.size.width : size.width,
                  maxWidth: minimized ? entry.size.width : size.width,
                  minHeight: minimized ? entry.size.height : size.height,
                  maxHeight: minimized ? entry.size.height : size.height,
                  child: ComposerPanel(
                    composer: composer,
                    height: minimized ? entry.size.height : size.height,
                    placement: placement,
                    onPlacementChanged: mobile ? null : onPlacement,
                    onMinimize: onMinimize,
                  ),
                ),
              ),
            ),
            if (minimized)
              ColoredBox(
                color: Theme.of(context).shell.content,
                child: ComposerHeader(
                  composer: composer,
                  minimized: true,
                  closeTooltip: composer.canSaveDraft
                      ? 'Save and close'
                      : 'Close composer',
                  onClose: () => unawaited(
                    closeComposerFromPanel(
                      context: context,
                      composer: composer,
                    ),
                  ),
                  onRestore: onRestore,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
