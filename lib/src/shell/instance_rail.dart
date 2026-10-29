import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';

import '../foundation/count_label.dart';
import '../models/discourse_instance.dart';
import '../models/site_appearance.dart';
import '../styleguide/styleguide_page.dart';
import '../theme/app_theme.dart';
import '../theme/color_contrast.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'add_instance_sheet.dart';
import 'app_settings_page.dart';
import 'avatar_image.dart';
import 'forum_theme_surfaces.dart';
import 'instance_actions.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'update_controller.dart';
import 'update_sheet.dart';

class InstanceRail extends StatelessWidget {
  const InstanceRail({
    super.key,
    this.onToggleSidebar,
    this.showSidebarToggle = false,
    this.sidebarExpanded = true,
  });

  final VoidCallback? onToggleSidebar;
  final bool showSidebarToggle;

  final bool sidebarExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ShellSelector<_RailSnapshot>(
      select: _RailSnapshot.from,
      builder: (context, state, _) {
        final controller = ShellScope.read(context);
        return ListenableBuilder(
          listenable: controller.accountActivity.totalsListenable,
          builder: (context, _) => ColoredBox(
            color:
                !context.isTouch &&
                    theme.extension<ForumThemeEffects>()?.windowGradient != null
                ? Colors.transparent
                : ForumWindowBackground.surfaceColor(
                    context,
                    _railSurface(context),
                  ),
            child: SafeArea(
              right: false,
              child: Column(
                children: [
                  if (showSidebarToggle)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 8,
                        bottom: DSpacing.controlGap,
                      ),
                      child: DButton.iconOnly(
                        key: const ValueKey('rail-sidebar-toggle'),
                        icon: const DIconGlyphTheme(
                          scale: 1,
                          naturalWidth: true,
                          child: DIcon(DNativeIcons.bars, size: 18),
                        ),
                        tooltipSide: DTooltipSide.right,
                        tooltip: onToggleSidebar == null
                            ? context.l10n.selectAForumToToggleItsSidebar
                            : sidebarExpanded
                            ? context.l10n.collapseSidebar
                            : context.l10n.expandSidebar,
                        variant: DButtonVariant.ghost,
                        backgroundColor: Colors.transparent,
                        interactiveBackgroundColor: Colors.transparent,
                        foregroundColor: sidebarExpanded
                            ? theme.shell.railForeground
                            : theme.shell.railForeground.withValues(alpha: 0.6),
                        size: DButtonSize.large,
                        onPressed: onToggleSidebar,
                      ),
                    ),
                  Expanded(
                    child: switch (state.loadStatus) {
                      InstanceLoadStatus.loading => const SizedBox.shrink(),
                      InstanceLoadStatus.failed => const _RailLoadFailure(),
                      InstanceLoadStatus.ready => _InstanceRailList(
                        state: state,
                        controller: controller,
                      ),
                    },
                  ),
                  _RailFooter(
                    updatesAvailable:
                        state.loadStatus == InstanceLoadStatus.ready,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _moveInstance(
    BuildContext context,
    ShellController controller,
    DiscourseInstance instance,
    int newIndex,
  ) {
    unawaited(() async {
      final persisted = await controller.moveInstance(instance, newIndex);
      if (persisted ||
          !context.mounted ||
          !identical(ShellScope.read(context), controller)) {
        return;
      }
      DToast.show(
        context,
        appL10n.couldnTSaveTheNewSiteOrderTryAgain,
        type: DToastType.error,
      );
    }());
  }
}

Color _railBackground(ThemeData theme) => usesMobileNavigation(theme.platform)
    ? theme.shell.content
    : theme.shell.rail;

Color _railSurface(BuildContext context) {
  final theme = Theme.of(context);
  return ForumWindowBackground.chromeColor(context, _railBackground(theme));
}

const double _railListPadding = 8;
const double _railIconSize = 16;
const double _railFooterIconSize = 24;
const double _railSourceOpacity = 0.3;
const double _railInsertionHorizontalInset = 5;
const double _railInsertionPinSize = 8;
const double _railInsertionStrokeWidth = 2;
const double _railAutoScrollVelocityScalar = 50;

class _InstanceRailList extends StatefulWidget {
  const _InstanceRailList({required this.state, required this.controller});

  final _RailSnapshot state;
  final ShellController controller;

  @override
  State<_InstanceRailList> createState() => _InstanceRailListState();
}

class _InstanceRailListState extends State<_InstanceRailList> {
  final GlobalKey _viewportKey = GlobalKey();

  String? _draggedUrl;
  Offset? _pointerGlobal;
  int? _insertionSlot;
  ScrollableState? _scrollable;
  EdgeDraggingAutoScroller? _autoScroller;
  bool _touchDrag = false;
  bool _touchReorderIntent = false;
  int _dragGeneration = 0;

  bool get _canReorder => widget.state.instances.length > 1;
  double get _itemExtent => DItemRail.itemExtentOf(context);
  double get _avatarSize => DItemRail.artworkDimensionOf(context);

  @override
  void didUpdateWidget(covariant _InstanceRailList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !_canReorder ||
        (_draggedUrl != null &&
            !widget.state.instances.any((item) => item.url == _draggedUrl))) {
      _clearDrag(notify: false);
    } else if (_pointerGlobal != null) {
      _insertionSlot = _slotFor(_pointerGlobal!);
    }
  }

  @override
  void dispose() {
    _clearDrag(notify: false);
    super.dispose();
  }

  bool _startDrag(
    String url,
    ScrollableState scrollable, {
    required bool touch,
  }) {
    if (_draggedUrl != null) return false;
    _clearDrag(notify: false);
    _draggedUrl = url;
    _scrollable = scrollable;
    _touchDrag = touch;
    scrollable.position.addListener(_scrollPositionChanged);
    _createAutoScroller();
    setState(() {});
    return true;
  }

  void _createAutoScroller() {
    final scrollable = _scrollable;
    if (!_touchDrag || scrollable == null || _autoScroller != null) return;
    final generation = ++_dragGeneration;
    _autoScroller = EdgeDraggingAutoScroller(
      scrollable,
      velocityScalar: _railAutoScrollVelocityScalar,
      onScrollViewScrolled: () {
        if (!mounted || generation != _dragGeneration) return;
        _recomputeInsertion();
        _driveAutoScroll();
      },
    );
  }

  void _invalidateAutoScroller() {
    _dragGeneration++;
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
  }

  void _updateDrag(
    String url,
    DragUpdateDetails details, {
    required bool canReorder,
  }) {
    if (_draggedUrl != url) return;
    _pointerGlobal = details.globalPosition;
    _touchReorderIntent = !_touchDrag || canReorder;
    if (!_touchReorderIntent) {
      _autoScroller?.stopAutoScroll();
      if (_insertionSlot != null) {
        setState(() => _insertionSlot = null);
      }
      return;
    }
    _recomputeInsertion();
    _driveAutoScroll();
  }

  void _scrollPositionChanged() {
    if (_draggedUrl == null || _pointerGlobal == null) return;
    _recomputeInsertion();
  }

  void _recomputeInsertion() {
    final pointer = _pointerGlobal;
    final slot = pointer == null ? null : _slotFor(pointer);
    if (slot == _insertionSlot || !mounted) return;
    setState(() => _insertionSlot = slot);
  }

  void _moveOverViewport(DragTargetDetails<String> details) {
    if (details.data != _draggedUrl) return;
    _pointerGlobal = details.offset;
    if (_touchDrag && !_touchReorderIntent) return;
    _recomputeInsertion();
    _driveAutoScroll();
  }

  int? _slotFor(Offset globalPosition) {
    final viewportContext = _viewportKey.currentContext;
    final scrollable = _scrollable;
    final renderObject = viewportContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        scrollable == null ||
        !scrollable.position.hasPixels) {
      return null;
    }

    final local = renderObject.globalToLocal(globalPosition);
    if (local.dx < 0 ||
        local.dx > renderObject.size.width ||
        local.dy < 0 ||
        local.dy > renderObject.size.height) {
      return null;
    }

    final contentY = local.dy + scrollable.position.pixels - _railListPadding;
    return ((contentY + _itemExtent / 2) / _itemExtent)
        .floor()
        .clamp(0, widget.state.instances.length)
        .toInt();
  }

  void _driveAutoScroll() {
    final pointer = _pointerGlobal;
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (!_touchDrag ||
        !_touchReorderIntent ||
        pointer == null ||
        _slotFor(pointer) == null ||
        renderObject is! RenderBox ||
        renderObject.size.height < _avatarSize) {
      _autoScroller?.stopAutoScroll();
      return;
    }
    _createAutoScroller();
    _autoScroller?.startAutoScrollIfNecessary(
      Rect.fromCenter(center: pointer, width: _avatarSize, height: _avatarSize),
    );
  }

  int? _destinationForSlot(int? slot, String? draggedUrl) {
    if (slot == null || draggedUrl == null) return null;
    final sourceIndex = widget.state.instances.indexWhere(
      (item) => item.url == draggedUrl,
    );
    if (sourceIndex < 0) return null;
    return slot > sourceIndex ? slot - 1 : slot;
  }

  int? get _visibleInsertionSlot {
    final slot = _insertionSlot;
    final destination = _destinationForSlot(slot, _draggedUrl);
    final sourceIndex = widget.state.instances.indexWhere(
      (item) => item.url == _draggedUrl,
    );
    if (slot == null || destination == null || destination == sourceIndex) {
      return null;
    }
    return slot;
  }

  void _acceptDrop(DragTargetDetails<String> details) {
    if (details.data != _draggedUrl) {
      return;
    }
    if (_touchDrag && !_touchReorderIntent) {
      _clearDrag();
      return;
    }
    _pointerGlobal = details.offset;
    final slot = _slotFor(details.offset);
    final destination = _destinationForSlot(slot, details.data);
    final sourceIndex = widget.state.instances.indexWhere(
      (item) => item.url == details.data,
    );
    if (sourceIndex < 0 || destination == null || destination == sourceIndex) {
      _clearDrag();
      return;
    }
    final dragged = widget.state.instances[sourceIndex];
    final controller = widget.controller;
    _clearDrag();
    InstanceRail._moveInstance(context, controller, dragged, destination);
  }

  void _leaveViewport(String? data) {
    if (data != _draggedUrl) return;
    _invalidateAutoScroller();
    _pointerGlobal = null;
    if (_insertionSlot != null && mounted) {
      setState(() => _insertionSlot = null);
    }
  }

  void _finishDrag(String url) {
    if (url != _draggedUrl) return;
    _clearDrag();
  }

  void _clearDrag({bool notify = true}) {
    _invalidateAutoScroller();
    final scrollable = _scrollable;
    if (scrollable != null) {
      scrollable.position.removeListener(_scrollPositionChanged);
    }
    _draggedUrl = null;
    _pointerGlobal = null;
    _insertionSlot = null;
    _scrollable = null;
    _touchDrag = false;
    _touchReorderIntent = false;
    if (notify && mounted) setState(() {});
  }

  Widget _draggableItem(
    BuildContext itemContext,
    int index,
    DiscourseInstance instance,
    Widget item,
  ) {
    final appearance = widget.state.appearances[index];
    final selected =
        widget.state.rootMode == ShellRootMode.forum &&
        index == widget.state.selectedIndex;
    final feedback = _RailDragFeedback(
      key: ValueKey('instance-rail-drag-feedback-${instance.url}'),
      instance: instance,
      appearance: appearance,
      selected: selected,
    );
    final actions = InstanceActions(
      instance: instance,
      onMoveUp: index == 0
          ? null
          : () => InstanceRail._moveInstance(
              itemContext,
              widget.controller,
              instance,
              index - 1,
            ),
      onMoveDown: index == widget.state.instances.length - 1
          ? null
          : () => InstanceRail._moveInstance(
              itemContext,
              widget.controller,
              instance,
              index + 1,
            ),
      touchGestureBuilder: _canReorder && itemContext.isTouch
          ? (child, openActions) => _TouchRailDraggable(
              data: instance.url,
              enabled: _draggedUrl == null || _draggedUrl == instance.url,
              feedback: Transform.translate(
                offset: Offset(-_avatarSize / 2, -_avatarSize - 12),
                child: feedback,
              ),
              onDragStarted: () => _startDrag(
                instance.url,
                Scrollable.of(itemContext),
                touch: true,
              ),
              onDragUpdate: (details, {required canReorder}) =>
                  _updateDrag(instance.url, details, canReorder: canReorder),
              onDragFinished: () => _finishDrag(instance.url),
              openActions: openActions,
              child: child,
            )
          : null,
      child: item,
    );
    if (!_canReorder || itemContext.isTouch) return actions;

    return Draggable<String>(
      data: instance.url,
      maxSimultaneousDrags: _draggedUrl == null || _draggedUrl == instance.url
          ? 1
          : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: Offset(-_avatarSize / 2, -_avatarSize / 2),
        child: feedback,
      ),
      onDragStarted: () =>
          _startDrag(instance.url, Scrollable.of(itemContext), touch: false),
      onDragUpdate: (details) =>
          _updateDrag(instance.url, details, canReorder: true),
      onDragEnd: (_) => _finishDrag(instance.url),
      onDragCompleted: () => _finishDrag(instance.url),
      onDraggableCanceled: (_, _) => _finishDrag(instance.url),
      childWhenDragging: Opacity(
        key: ValueKey('instance-rail-drag-source-${instance.url}'),
        opacity: _railSourceOpacity,
        child: actions,
      ),
      child: Opacity(
        key: ValueKey('instance-rail-drag-source-${instance.url}'),
        opacity: 1,
        child: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleSlot = _visibleInsertionSlot;
    final theme = Theme.of(context);

    return SizedBox.expand(
      key: _viewportKey,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            widget.state.instances.any((item) => item.url == details.data),
        onMove: _moveOverViewport,
        onAcceptWithDetails: _acceptDrop,
        onLeave: _leaveViewport,
        builder: (context, candidates, rejected) => DScrollFadeScope(
          topExtent: 26,
          bottomExtent: 26,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: _railListPadding),
            itemExtent: _itemExtent,
            itemCount: widget.state.instances.length + 1,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final index = widget.state.instances.indexWhere(
                (instance) => instance.url == key.value,
              );
              return index < 0 ? null : index;
            },
            itemBuilder: (itemContext, index) {
              if (index == widget.state.instances.length) {
                return const Center(child: _AddInstanceButton());
              }

              final instance = widget.state.instances[index];
              final moveUp = index == 0
                  ? null
                  : () => InstanceRail._moveInstance(
                      itemContext,
                      widget.controller,
                      instance,
                      index - 1,
                    );
              final moveDown = index == widget.state.instances.length - 1
                  ? null
                  : () => InstanceRail._moveInstance(
                      itemContext,
                      widget.controller,
                      instance,
                      index + 1,
                    );
              final item = _RailItem(
                instance: instance,
                appearance: widget.state.appearances[index],
                selected:
                    widget.state.rootMode == ShellRootMode.forum &&
                    index == widget.state.selectedIndex,
                badgeCount: widget.controller.railBadgeFor(instance),
                shortcutKey:
                    widget.controller.forumTabsEnabled &&
                        index < forumSwitchShortcutKeys.length
                    ? forumSwitchShortcutKeys[index]
                    : null,
                onTap: () => widget.controller.selectInstance(index),
                onMoveUp: moveUp,
                onMoveDown: moveDown,
                wrapControl: (control) =>
                    _draggableItem(itemContext, index, instance, control),
              );
              return KeyedSubtree(
                key: ValueKey(instance.url),
                child: _RailInsertionSlot(
                  before: visibleSlot == index,
                  after:
                      visibleSlot == widget.state.instances.length &&
                      index == widget.state.instances.length - 1,
                  color: theme.colorScheme.primary,
                  child: item,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RailInsertionSlot extends StatelessWidget {
  const _RailInsertionSlot({
    required this.before,
    required this.after,
    required this.color,
    required this.child,
  });

  final bool before;
  final bool after;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.none,
    children: [
      child,
      if (before || after)
        Positioned(
          top: before ? -_railInsertionPinSize / 2 : null,
          bottom: after ? -_railInsertionPinSize / 2 : null,
          left: _railInsertionHorizontalInset,
          right: _railInsertionHorizontalInset,
          child: SizedBox(
            key: const ValueKey('instance-rail-drop-indicator'),
            height: _railInsertionPinSize,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: _railInsertionPinSize,
                  right: 0,
                  child: Container(
                    key: const ValueKey('instance-rail-drop-indicator-line'),
                    height: _railInsertionStrokeWidth,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(
                        _railInsertionStrokeWidth / 2,
                      ),
                    ),
                  ),
                ),
                Container(
                  key: const ValueKey('instance-rail-drop-indicator-pin'),
                  width: _railInsertionPinSize,
                  height: _railInsertionPinSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color,
                      width: _railInsertionStrokeWidth,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _TouchRailDraggable extends StatefulWidget {
  const _TouchRailDraggable({
    required this.data,
    required this.enabled,
    required this.feedback,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragFinished,
    required this.openActions,
    required this.child,
  });

  final String data;
  final bool enabled;
  final Widget feedback;
  final bool Function() onDragStarted;
  final void Function(DragUpdateDetails details, {required bool canReorder})
  onDragUpdate;
  final VoidCallback onDragFinished;
  final ValueChanged<Offset> openActions;
  final Widget child;

  @override
  State<_TouchRailDraggable> createState() => _TouchRailDraggableState();
}

class _TouchRailDraggableState extends State<_TouchRailDraggable> {
  final Set<int> _downPointers = <int>{};
  int? _pointer;
  Offset? _pointerDownGlobal;
  Offset? _pointerDownLocal;
  double _maximumDistance = 0;
  double _maximumVerticalDistance = 0;
  bool _pointerCanceled = false;
  bool _dragActive = false;
  bool _ownsDrag = false;
  bool _multitouchInvalidated = false;

  void _pointerDown(PointerDownEvent event) {
    _downPointers.add(event.pointer);
    if (_downPointers.length > 1) {
      if (!_multitouchInvalidated) {
        _multitouchInvalidated = true;
        _finishOwnedDrag();
        setState(() {});
      }
      return;
    }
    _pointer = event.pointer;
    _pointerDownGlobal = event.position;
    _pointerDownLocal = event.localPosition;
    _maximumDistance = 0;
    _maximumVerticalDistance = 0;
    _pointerCanceled = false;
  }

  void _pointerUp(PointerUpEvent event) {
    _downPointers.remove(event.pointer);
    if (event.pointer == _pointer && !_dragActive) _resetPointer();
    _restoreAfterPointersLeave();
  }

  void _pointerCancel(PointerCancelEvent event) {
    _downPointers.remove(event.pointer);
    if (event.pointer == _pointer) {
      _pointerCanceled = true;
      if (!_dragActive) _resetPointer();
    }
    _restoreAfterPointersLeave();
  }

  void _restoreAfterPointersLeave() {
    if (_downPointers.isNotEmpty || !_multitouchInvalidated) return;
    _multitouchInvalidated = false;
    if (mounted) setState(() {});
  }

  void _dragStarted() {
    _dragActive = true;
    _ownsDrag = !_multitouchInvalidated && widget.onDragStarted();
  }

  void _dragUpdate(DragUpdateDetails details) {
    final origin = _pointerDownGlobal ?? details.globalPosition;
    final displacement = details.globalPosition - origin;
    _maximumDistance = math.max(_maximumDistance, displacement.distance);
    _maximumVerticalDistance = math.max(
      _maximumVerticalDistance,
      displacement.dy.abs(),
    );
    if (_ownsDrag) {
      widget.onDragUpdate(
        details,
        canReorder: _maximumVerticalDistance > kTouchSlop,
      );
    }
  }

  void _dragEnd(DraggableDetails details) {
    final openAt = _pointerDownLocal;
    final stationary =
        _ownsDrag && details.wasAccepted && _maximumDistance <= kTouchSlop;
    _finishOwnedDrag();
    if (!stationary || openAt == null) {
      _resetPointer();
      return;
    }

    // A cancel and a normal pointer-up both end the draggable. Defer the
    // fallback until raw pointer dispatch has identified which one occurred.
    scheduleMicrotask(() {
      if (mounted && !_pointerCanceled) widget.openActions(openAt);
      _resetPointer();
    });
  }

  void _finishOwnedDrag() {
    final owned = _ownsDrag;
    _dragActive = false;
    _ownsDrag = false;
    if (owned) widget.onDragFinished();
  }

  void _resetPointer() {
    _pointer = null;
    _pointerDownGlobal = null;
    _pointerDownLocal = null;
    _maximumDistance = 0;
    _maximumVerticalDistance = 0;
    _pointerCanceled = false;
    _dragActive = false;
    _ownsDrag = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _pointerDown,
    onPointerUp: _pointerUp,
    onPointerCancel: _pointerCancel,
    child: LongPressDraggable<String>(
      data: widget.data,
      maxSimultaneousDrags: widget.enabled && !_multitouchInvalidated ? 1 : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: widget.feedback,
      onDragStarted: _dragStarted,
      onDragUpdate: _dragUpdate,
      onDragEnd: _dragEnd,
      onDragCompleted: _finishOwnedDrag,
      onDraggableCanceled: (_, _) => _finishOwnedDrag(),
      childWhenDragging: Opacity(
        key: ValueKey('instance-rail-drag-source-${widget.data}'),
        opacity: _railSourceOpacity,
        child: widget.child,
      ),
      child: Opacity(
        key: ValueKey('instance-rail-drag-source-${widget.data}'),
        opacity: 1,
        child: widget.child,
      ),
    ),
  );
}

class _RailSnapshot {
  _RailSnapshot.from(ShellController controller)
    : instances = controller.instances,
      appearances = [
        for (final instance in controller.instances)
          controller.siteAppearanceFor(instance.url),
      ],
      selectedIndex = controller.instanceIndex,
      rootMode = controller.rootMode,
      loadStatus = controller.loadStatus;

  final List<DiscourseInstance> instances;
  final List<SiteAppearance?> appearances;
  final int selectedIndex;
  final ShellRootMode rootMode;
  final InstanceLoadStatus loadStatus;

  @override
  bool operator ==(Object other) {
    if (other is! _RailSnapshot ||
        selectedIndex != other.selectedIndex ||
        rootMode != other.rootMode ||
        loadStatus != other.loadStatus) {
      return false;
    }
    if (instances.length != other.instances.length) return false;
    for (var index = 0; index < instances.length; index++) {
      if (!identical(instances[index], other.instances[index])) return false;
      if (appearances[index] != other.appearances[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    selectedIndex,
    rootMode,
    loadStatus,
    Object.hashAll(instances.map(identityHashCode)),
    Object.hashAll(appearances),
  );
}

class _RailLoadFailure extends StatelessWidget {
  const _RailLoadFailure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Center(
          child: DButton.iconOnly(
            key: const ValueKey('instance-load-retry-rail'),
            tooltip: context.l10n.retryLoadingSites,
            tooltipSide: DTooltipSide.right,
            onPressed: ShellScope.read(context).load,
            variant: DButtonVariant.ghost,
            density: DButtonDensity.rail,
            backgroundColor: theme.colorScheme.error.withValues(alpha: .12),
            foregroundColor: theme.colorScheme.error,
            icon: const DIcon(DIcons.arrowsRotate),
          ),
        ),
      ),
    );
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter({required this.updatesAvailable});

  final bool updatesAvailable;

  @override
  Widget build(BuildContext context) {
    final updates = ShellScope.read(context).updates;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (updatesAvailable && updates.isSupported)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: Center(child: _UpdateButton()),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Center(
            child: _RailFooterButton(
              buttonKey: const ValueKey('styleguide-rail-button'),
              tooltip: context.l10n.openComponentStyleguide,
              onTap: () => unawaited(showComponentStyleguide(context)),
              icon: const Icon(
                Icons.palette_outlined,
                size: _railFooterIconSize,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Center(
            child: _SettingsButton(
              onTap: () {
                final shell = ShellScope.read(context);
                if (shell.currentInstance != null) {
                  shell.openCurrentSettings();
                } else {
                  unawaited(showAppSettingsModal(context));
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

// The mockup rail footer uses --text-muted (a 50% primary/secondary mix). Legacy
// palettes can map the general muted foreground to a stronger metadata color.
Color _railActionForeground(BuildContext context) {
  final tokens = DTokens.of(context);
  return Color.lerp(tokens.background, tokens.foreground, .5)!;
}

class _RailFooterButton extends StatelessWidget {
  const _RailFooterButton({
    required this.buttonKey,
    required this.tooltip,
    required this.onTap,
    required this.icon,
  });

  final Key buttonKey;
  final String tooltip;
  final VoidCallback onTap;
  final Widget icon;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    key: buttonKey,
    tooltip: tooltip,
    tooltipSide: DTooltipSide.right,
    semanticLabel: tooltip,
    variant: DButtonVariant.ghost,
    backgroundColor: Colors.transparent,
    interactiveBackgroundColor: Colors.transparent,
    foregroundColor: _railActionForeground(context),
    size: DButtonSize.large,

    onPressed: onTap,
    icon: icon,
  );
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _RailFooterButton(
      buttonKey: const ValueKey('settings-rail-button'),
      tooltip: context.l10n.interface,
      onTap: onTap,
      icon: const DIcon(DIcons.gear, size: _railFooterIconSize),
    );
  }
}

class _UpdateButton extends StatelessWidget {
  const _UpdateButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updates = ShellScope.read(context).updates;

    // Subscribed here rather than through ShellScope, so that finding an update
    // re-badges this button without rebuilding the sidebar, the topic list and
    // everything else in the shell. Same reasoning as ComposerPanel.
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final version = updates.available?.version;

        final (tooltip, icon, color, filled) = switch (updates.status) {
          UpdateStatus.available => (
            context.l10n.updateTo((version).toString()),
            DIcons.download,
            theme.colorScheme.primary,
            true,
          ),
          UpdateStatus.readyToInstall => (
            context.l10n.restartToFinishUpdating,
            DIcons.farCircleCheck,
            theme.colorScheme.primary,
            true,
          ),
          UpdateStatus.failed => (
            updates.error ?? context.l10n.theLastUpdateCheckFailed,
            DIcons.triangleExclamation,
            theme.colorScheme.error,
            false,
          ),
          _ => (
            context.l10n.checkForUpdates,
            DIcons.arrowsRotate,
            theme.shell.railForeground,
            false,
          ),
        };

        final wants =
            updates.status == UpdateStatus.available ||
            updates.status == UpdateStatus.readyToInstall;

        return Padding(
          padding: const EdgeInsets.all(6),
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DButton.iconOnly(
                  tooltip: tooltip,
                  tooltipSide: DTooltipSide.right,
                  onPressed: () => showUpdateSheet(context),
                  variant: DButtonVariant.ghost,
                  density: DButtonDensity.rail,
                  backgroundColor: filled
                      ? color.withValues(alpha: .14)
                      : Colors.transparent,
                  foregroundColor: color,
                  icon: updates.status == UpdateStatus.downloading
                      ? DProgress(
                          value: updates.progress,
                          max: 1,
                          track: const DProgressRing(size: _railIconSize),
                        )
                      : DIcon(icon),
                ),
                if (wants)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: IgnorePointer(
                      child: DNotificationDot.overlay(
                        ringColor: _railSurface(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RailDragFeedback extends StatelessWidget {
  const _RailDragFeedback({
    super.key,
    required this.instance,
    required this.appearance,
    required this.selected,
  });

  final DiscourseInstance instance;
  final SiteAppearance? appearance;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _activePalette(appearance, theme.brightness);
    final accent = palette?.tertiary ?? instance.accentColor;
    final background = selected
        ? accent
        : accent.withValues(alpha: accent.a * 0.16);
    final scaffold = opaqueColorOnCanvas(
      theme.scaffoldBackgroundColor,
      theme.brightness,
    );
    final railSurface = Color.alphaBlend(_railSurface(context), scaffold);
    final foreground = contrastSafeForeground(
      background: background,
      backdrop: railSurface,
      preferred: [
        if (!selected) theme.shell.railForeground,
        palette?.secondary,
        palette?.primary,
        if (selected) theme.shell.railForeground,
      ],
    );

    return SizedBox.square(
      dimension: DItemRail.artworkDimensionOf(context),
      child: _InstanceIcon(
        instance: instance,
        foreground: foreground,
        background: background,
        selected: selected,
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.instance,
    required this.appearance,
    required this.selected,
    required this.badgeCount,
    required this.shortcutKey,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.wrapControl,
  });

  final DiscourseInstance instance;
  final SiteAppearance? appearance;
  final bool selected;
  final int badgeCount;
  final LogicalKeyboardKey? shortcutKey;
  final VoidCallback onTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Widget Function(Widget) wrapControl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _activePalette(appearance, theme.brightness);
    final accent = palette?.tertiary ?? instance.accentColor;
    final avatarBackground = selected
        ? accent
        : accent.withValues(alpha: accent.a * 0.16);
    final scaffold = opaqueColorOnCanvas(
      theme.scaffoldBackgroundColor,
      theme.brightness,
    );
    final railSurface = Color.alphaBlend(_railSurface(context), scaffold);
    final avatarForeground = contrastSafeForeground(
      background: avatarBackground,
      backdrop: railSurface,
      preferred: [
        if (!selected) theme.shell.railForeground,
        palette?.secondary,
        palette?.primary,
        if (selected) theme.shell.railForeground,
      ],
    );
    final badgeBackground = Color.lerp(
      theme.discourse.success,
      railSurface,
      0.2,
    )!;
    final badgeForeground = contrastSafeForeground(
      background: badgeBackground,
      backdrop: railSurface,
      // Core draws high-priority notification counts with `--secondary` on
      // `--success`. Resolve both from the window theme so every rail badge
      // shares the same colors, including badges for inactive forums.
      preferred: [
        theme.discourse.notificationForeground,
        theme.colorScheme.surface,
      ],
    );

    final dimension = DItemRail.artworkDimensionOf(context);
    return DItemRail(
      selected: selected,
      onPressed: onTap,
      markerColor: theme.shell.railForeground,
      markerKey: ValueKey('instance-rail-marker-${instance.url}'),
      mouseCursor: context.isTouch ? null : SystemMouseCursors.grab,
      controlWrapper: (context, control) => wrapControl(
        _RailTooltip(
          instance: instance,
          accent: accent,
          shortcutKey: shortcutKey,
          child: Semantics(
            button: true,
            selected: selected,
            customSemanticsActions: {
              CustomSemanticsAction(label: context.l10n.moveUp): ?onMoveUp,
              CustomSemanticsAction(label: context.l10n.moveDown): ?onMoveDown,
            },
            child: control,
          ),
        ),
      ),
      artwork: SizedBox.square(
        dimension: dimension,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The tooltip names the forum. The site icon would
            // otherwise make the rail item an unnamed image, and
            // the monogram fallback an abbreviation.
            SizedBox.square(
              dimension: dimension,
              child: ExcludeSemantics(
                child: _InstanceIcon(
                  instance: instance,
                  foreground: avatarForeground,
                  background: avatarBackground,
                  selected: selected,
                ),
              ),
            ),
            if (badgeCount > 0)
              Positioned(
                right: -1.5,
                bottom: -1.5,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: dimension + 4),
                  child: DBadge.overlay(
                    key: ValueKey('instance-rail-badge-${instance.url}'),
                    backgroundColor: badgeBackground,
                    foregroundColor: badgeForeground,
                    ringColor: railSurface,
                    semanticLabel: countLabel(
                      badgeCount,
                      CountNoun.unreadNotification,
                    ),
                    child: Text(badgeCount > 999 ? '999+' : '$badgeCount'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailTooltip extends StatelessWidget {
  const _RailTooltip({
    required this.instance,
    required this.accent,
    required this.shortcutKey,
    required this.child,
  });

  final DiscourseInstance instance;
  final Color accent;
  final LogicalKeyboardKey? shortcutKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = DTokens.of(context).surface;
    final iconBackground = Color.alphaBlend(accent, surface);
    final iconForeground = contrastSafeForeground(
      background: iconBackground,
      backdrop: surface,
      preferred: [DTokens.of(context).foreground, surface],
    );
    return DTooltip(
      key: ValueKey('instance-rail-tooltip-${instance.url}'),
      message: instance.title,
      // The forum's title is the rail item's only name. The macOS and Linux
      // accessibility bridges expose a node's label but not its tooltip.
      labelTrigger: true,
      side: DTooltipSide.right,
      hoverDelay: const Duration(milliseconds: 280),
      dismissDelay: const Duration(milliseconds: 80),
      triggerMode: TooltipTriggerMode.manual,
      enableFeedback: false,
      shortcut: shortcutKey == null
          ? null
          : DShortcut(primaryShortcutForPlatform(theme.platform, shortcutKey!)),
      content: Row(
        key: ValueKey('instance-rail-callout-${instance.url}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          DAvatar.frame(
            border: false,
            borderRadius: BorderRadius.circular(DTokens.of(context).radius),
            child: AvatarImage(
              key: ValueKey('instance-rail-callout-icon-${instance.url}'),
              url: instance.iconUrl,
              size: 18,
              fit: BoxFit.contain,
              fallback: ColoredBox(
                color: iconBackground,
                child: SizedBox.square(
                  dimension: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        instance.monogram,
                        style: TextStyle(
                          color: iconForeground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(instance.title)),
        ],
      ),
      child: child,
    );
  }
}

class _InstanceIcon extends StatelessWidget {
  const _InstanceIcon({
    required this.instance,
    required this.foreground,
    required this.background,
    required this.selected,
  });

  final DiscourseInstance instance;
  final Color foreground;
  final Color background;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dimension = DItemRail.artworkDimensionOf(context);
    final radius = DItemRail.artworkBorderRadiusOf(context, selected: selected);
    return DCard(
      spacing: 0,
      border: false,
      backgroundColor: selected ? background : Colors.transparent,
      borderRadius: radius,
      child: DAvatar.frame(
        border: false,
        borderRadius: radius,
        child: AvatarImage(
          url: instance.iconUrl,
          size: dimension,
          fit: BoxFit.contain,
          fallback: DAvatarFallback(
            backgroundColor: background,
            foregroundColor: foreground,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  instance.monogram,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ResolvedSitePalette? _activePalette(
  SiteAppearance? appearance,
  Brightness brightness,
) {
  if (appearance == null) return null;
  return appearance.paletteForBrightness(brightness) ??
      appearance.base ??
      appearance.alternate;
}

class _AddInstanceButton extends StatelessWidget {
  const _AddInstanceButton();

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.addADiscourseSite;
    return DButton.iconOnly(
      key: const ValueKey('add-instance-rail-button'),
      tooltip: label,
      tooltipSide: DTooltipSide.right,
      semanticLabel: label,
      variant: DButtonVariant.ghost,
      size: DButtonSize.toolbar,
      shape: DButtonShape.pill,
      backgroundColor: Colors.transparent,
      interactiveBackgroundColor: Colors.transparent,
      foregroundColor: DTokens.of(context).foreground,
      onPressed: () => showAddInstanceSheet(context),
      icon: const DIcon(DIcons.plus, size: 17),
    );
  }
}
