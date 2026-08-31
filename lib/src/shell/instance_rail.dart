import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../diagnostics/diagnostics_scope.dart';
import '../models/discourse_instance.dart';
import '../models/site_appearance.dart';
import '../theme/app_theme.dart';
import '../theme/color_contrast.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'add_instance_sheet.dart';
import 'avatar_image.dart';
import 'instance_actions.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'update_controller.dart';
import 'update_sheet.dart';

class InstanceRail extends StatelessWidget {
  const InstanceRail({super.key});

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
            color: theme.shell.rail,
            child: SafeArea(
              right: false,
              child: Column(
                children: [
                  if (state.loadStatus == InstanceLoadStatus.ready &&
                      state.instances.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                      child: _AggregateRailButton(
                        selected: state.rootMode == ShellRootMode.aggregate,
                        onTap: controller.selectAggregate,
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Divider(
                        height: 1,
                        color: theme.shell.railForeground.withValues(
                          alpha: 0.18,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: switch (state.loadStatus) {
                      InstanceLoadStatus.loading => Center(
                        child: SizedBox.square(
                          dimension: 24,
                          child: AdaptiveActivityIndicator(
                            color: theme.shell.railForeground,
                            cupertinoRadius: 12,
                            materialStrokeWidth: 2,
                          ),
                        ),
                      ),
                      InstanceLoadStatus.failed => const _RailLoadFailure(),
                      InstanceLoadStatus.ready => _InstanceRailList(
                        state: state,
                        controller: controller,
                      ),
                    },
                  ),
                  _RailFooter(
                    siteActionsAvailable:
                        state.loadStatus == InstanceLoadStatus.ready,
                    settingsSelected: state.rootMode == ShellRootMode.settings,
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't save the new site order. Try again."),
        ),
      );
    }());
  }
}

const double _railListPadding = 12;
const double _railItemExtent = 52;
const double _railAvatarSize = 44;
const double _railSourceOpacity = 0.3;
const double _railInsertionLineOpacity = 0.6;
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
    return ((contentY + _railItemExtent / 2) / _railItemExtent)
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
        renderObject.size.height < _railAvatarSize) {
      _autoScroller?.stopAutoScroll();
      return;
    }
    _createAutoScroller();
    _autoScroller?.startAutoScrollIfNecessary(
      Rect.fromCenter(
        center: pointer,
        width: _railAvatarSize,
        height: _railAvatarSize,
      ),
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
                offset: const Offset(-22, -56),
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
        offset: const Offset(-22, -22),
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
    final scaffold = opaqueColorOnCanvas(
      theme.scaffoldBackgroundColor,
      theme.brightness,
    );
    final indicatorColor = contrastSafeForeground(
      background: theme.shell.rail,
      backdrop: scaffold,
      preferred: [theme.colorScheme.primary, theme.shell.railForeground],
    );

    return SizedBox.expand(
      key: _viewportKey,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            widget.state.instances.any((item) => item.url == details.data),
        onMove: _moveOverViewport,
        onAcceptWithDetails: _acceptDrop,
        onLeave: _leaveViewport,
        builder: (context, candidates, rejected) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: _railListPadding),
          itemExtent: _railItemExtent,
          itemCount: widget.state.instances.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final index = widget.state.instances.indexWhere(
              (instance) => instance.url == key.value,
            );
            return index < 0 ? null : index;
          },
          itemBuilder: (itemContext, index) {
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
              onTap: () => widget.controller.selectInstance(index),
            );
            return KeyedSubtree(
              key: ValueKey(instance.url),
              child: Semantics(
                customSemanticsActions: {
                  const CustomSemanticsAction(label: 'Move up'): ?moveUp,
                  const CustomSemanticsAction(label: 'Move down'): ?moveDown,
                },
                child: _RailInsertionSlot(
                  before: visibleSlot == index,
                  after:
                      visibleSlot == widget.state.instances.length &&
                      index == widget.state.instances.length - 1,
                  color: indicatorColor.withValues(
                    alpha: _railInsertionLineOpacity,
                  ),
                  child: _draggableItem(itemContext, index, instance, item),
                ),
              ),
            );
          },
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
          top: before ? -1 : null,
          bottom: after ? -1 : null,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              key: const ValueKey('instance-rail-drop-indicator'),
              width: _railAvatarSize,
              height: 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
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

class _AggregateRailButton extends StatefulWidget {
  const _AggregateRailButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AggregateRailButton> createState() => _AggregateRailButtonState();
}

class _AggregateRailButtonState extends State<_AggregateRailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.shell.railForeground;
    final markerHeight = widget.selected ? 40.0 : (_hovered ? 20.0 : 8.0);

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        AnimatedContainer(
          key: const ValueKey('aggregate-rail-marker'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 4,
          height: markerHeight,
          decoration: BoxDecoration(
            color: foreground,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(4),
            ),
          ),
        ),
        Center(
          child: Tooltip(
            message: 'Aggregate',
            child: InkWell(
              key: const ValueKey('aggregate-rail-button'),
              onTap: widget.onTap,
              onHover: (hovered) => setState(() => _hovered = hovered),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? foreground
                      : foreground.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(
                    widget.selected || _hovered ? 16 : 22,
                  ),
                ),
                child: DIcon(
                  DIcons.house,
                  size: 20,
                  color: widget.selected ? theme.shell.rail : foreground,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailLoadFailure extends StatelessWidget {
  const _RailLoadFailure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Tooltip(
        message: 'Retry loading sites',
        child: InkWell(
          key: const ValueKey('instance-load-retry-rail'),
          onTap: ShellScope.read(context).load,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: DIcon(
              DIcons.arrowsRotate,
              size: 20,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter({
    required this.siteActionsAvailable,
    required this.settingsSelected,
  });

  final bool siteActionsAvailable;
  final bool settingsSelected;

  @override
  Widget build(BuildContext context) {
    final updates = ShellScope.read(context).updates;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (siteActionsAvailable) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Center(child: _AddInstanceButton()),
          ),
          if (updates.isSupported)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Center(child: _UpdateButton()),
            ),
        ],
        if (DiagnosticsScope.maybeRead(context) != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Center(child: _DiagnosticsButton()),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: Center(
            child: _SettingsButton(
              selected: settingsSelected,
              onTap: ShellScope.read(context).selectSettings,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsButton extends StatefulWidget {
  const _SettingsButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.shell.railForeground;
    final markerHeight = widget.selected ? 40.0 : (_hovered ? 20.0 : 8.0);

    return Semantics(
      button: true,
      selected: widget.selected,
      label: 'Settings',
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          AnimatedContainer(
            key: const ValueKey('settings-rail-marker'),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 4,
            height: markerHeight,
            decoration: BoxDecoration(
              color: foreground,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
          Center(
            child: Tooltip(
              message: 'Settings',
              child: InkWell(
                key: const ValueKey('settings-rail-button'),
                onTap: widget.onTap,
                onHover: (hovered) => setState(() => _hovered = hovered),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? foreground
                        : foreground.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      widget.selected || _hovered ? 16 : 22,
                    ),
                  ),
                  child: DIcon(
                    DIcons.gear,
                    size: 20,
                    color: widget.selected ? theme.shell.rail : foreground,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsButton extends StatelessWidget {
  const _DiagnosticsButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnostics = DiagnosticsScope.read(context);
    final pluginDiagnostics = DiagnosticsScope.pluginsOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        diagnostics.panelListenable,
        diagnostics.unseenErrorsListenable,
        for (final plugin in pluginDiagnostics)
          plugin.diagnosticsStatusListenable,
      ]),
      builder: (context, _) {
        final open = diagnostics.isPanelOpen;
        final unseen = diagnostics.unseenErrorCountListenable.value;
        final baseTooltip = unseen == 0
            ? 'Diagnostics'
            : 'Diagnostics, $unseen unseen ${unseen == 1 ? 'error' : 'errors'}';
        final recordingLabels = [
          for (final plugin in pluginDiagnostics)
            if (plugin.isDiagnosticsRecording) plugin.diagnosticsRecordingLabel,
        ].whereType<String>();
        final tooltip = recordingLabels.isEmpty
            ? baseTooltip
            : '$baseTooltip, ${recordingLabels.join(', ')}';

        return Semantics(
          button: true,
          selected: open,
          label: tooltip,
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              key: const ValueKey('diagnostics-rail-button'),
              onTap: diagnostics.togglePanel,
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    width: 44,
                    height: 44,
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: open
                          ? theme.colorScheme.primary.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(open ? 14 : 22),
                    ),
                    child: DIcon(
                      DIcons.bug,
                      size: 20,
                      color: open
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (unseen > 0)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      // The parent announces the exact unseen count. Keep the
                      // visually capped badge from adding a contradictory
                      // second number to the accessible label.
                      child: ExcludeSemantics(
                        child: _CountBadge(
                          key: const ValueKey('diagnostics-rail-badge'),
                          count: unseen,
                          background: theme.colorScheme.error,
                          foreground: theme.colorScheme.onError,
                        ),
                      ),
                    ),
                  if (recordingLabels.isNotEmpty)
                    Positioned(
                      key: const ValueKey(
                        'plugin-diagnostics-recording-indicator',
                      ),
                      right: -3,
                      top: -3,
                      child: ExcludeSemantics(
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.shell.rail,
                              width: 2,
                            ),
                          ),
                        ),
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
            'Update to $version',
            DIcons.download,
            theme.colorScheme.primary,
            true,
          ),
          UpdateStatus.readyToInstall => (
            'Restart to finish updating',
            DIcons.farCircleCheck,
            theme.colorScheme.primary,
            true,
          ),
          UpdateStatus.failed => (
            updates.error ?? 'The last update check failed',
            DIcons.triangleExclamation,
            theme.colorScheme.error,
            false,
          ),
          _ => (
            'Check for updates',
            DIcons.arrowsRotate,
            theme.shell.railForeground,
            false,
          ),
        };

        final wants =
            updates.status == UpdateStatus.available ||
            updates.status == UpdateStatus.readyToInstall;

        return Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: () => showUpdateSheet(context),
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: filled
                        ? color.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: updates.status == UpdateStatus.downloading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: updates.progress,
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : DIcon(icon, size: 20, color: color),
                ),
                if (wants)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.shell.rail, width: 2),
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
    final palette = _activePalette(
      appearance,
      MediaQuery.platformBrightnessOf(context),
    );
    final accent = palette?.tertiary ?? instance.accentColor;
    final background = selected
        ? accent
        : accent.withValues(alpha: accent.a * 0.16);
    final scaffold = opaqueColorOnCanvas(
      theme.scaffoldBackgroundColor,
      theme.brightness,
    );
    final railSurface = Color.alphaBlend(theme.shell.rail, scaffold);
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

    return Material(
      type: MaterialType.transparency,
      child: SizedBox.square(
        dimension: 44,
        child: _InstanceAvatar(
          instance: instance,
          foreground: foreground,
          background: background,
          selected: selected,
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.instance,
    required this.appearance,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  final DiscourseInstance instance;
  final SiteAppearance? appearance;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  void _handleHover(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _activePalette(
      widget.appearance,
      MediaQuery.platformBrightnessOf(context),
    );
    final accent = palette?.tertiary ?? widget.instance.accentColor;
    final avatarBackground = widget.selected
        ? accent
        : accent.withValues(alpha: accent.a * 0.16);
    final scaffold = opaqueColorOnCanvas(
      theme.scaffoldBackgroundColor,
      theme.brightness,
    );
    final railSurface = Color.alphaBlend(theme.shell.rail, scaffold);
    final avatarForeground = contrastSafeForeground(
      background: avatarBackground,
      backdrop: railSurface,
      preferred: [
        if (!widget.selected) theme.shell.railForeground,
        palette?.secondary,
        palette?.primary,
        if (widget.selected) theme.shell.railForeground,
      ],
    );
    final badgeBackground = palette?.success ?? theme.discourse.success;
    final badgeForeground = contrastSafeForeground(
      background: badgeBackground,
      backdrop: railSurface,
      // Core draws high-priority notification counts with `--secondary` on
      // `--success`. Preserve that pairing when the forum's palette keeps it
      // readable, then fall back safely for custom colour schemes.
      preferred: [palette?.secondary, theme.colorScheme.surface],
    );
    final indicatorHeight = widget.selected ? 40.0 : (_hovered ? 20.0 : 8.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          AnimatedContainer(
            key: ValueKey('instance-rail-marker-${widget.instance.url}'),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 4,
            height: indicatorHeight,
            decoration: BoxDecoration(
              color: theme.shell.railForeground,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
          Center(
            child: _RailTooltip(
              instance: widget.instance,
              accent: accent,
              child: InkWell(
                onTap: widget.onTap,
                onHover: _handleHover,
                mouseCursor: context.isTouch ? null : SystemMouseCursors.grab,
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox.square(
                      dimension: 44,
                      child: _InstanceAvatar(
                        instance: widget.instance,
                        foreground: avatarForeground,
                        background: avatarBackground,
                        selected: widget.selected,
                      ),
                    ),
                    if (widget.badgeCount > 0)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: _CountBadge(
                          key: ValueKey(
                            'instance-rail-badge-${widget.instance.url}',
                          ),
                          count: widget.badgeCount,
                          background: badgeBackground,
                          foreground: badgeForeground,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTooltip extends StatelessWidget {
  const _RailTooltip({
    required this.instance,
    required this.accent,
    required this.child,
  });

  static const hoverDelay = Duration(milliseconds: 280);
  static const dismissDelay = Duration(milliseconds: 80);
  static const animationStyle = AnimationStyle(
    duration: Duration(milliseconds: 120),
    reverseDuration: Duration(milliseconds: 80),
    curve: Curves.linear,
  );

  final DiscourseInstance instance;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return RawTooltip(
      key: ValueKey(
        'instance-rail-tooltip-${instance.url}-${disableAnimations ? 'still' : 'motion'}',
      ),
      semanticsTooltip: instance.title,
      hoverDelay: hoverDelay,
      dismissDelay: dismissDelay,
      triggerMode: TooltipTriggerMode.manual,
      enableFeedback: false,
      animationStyle: disableAnimations
          ? AnimationStyle.noAnimation
          : animationStyle,
      positionDelegate: _positionRailTooltip,
      ignorePointer: true,
      tooltipBuilder: (context, animation) {
        final callout = ExcludeSemantics(
          child: RepaintBoundary(
            child: _RailTooltipCallout(instance: instance, accent: accent),
          ),
        );

        return _RailTooltipTransition(animation: animation, child: callout);
      },
      child: child,
    );
  }
}

class _RailTooltipTransition extends StatefulWidget {
  const _RailTooltipTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_RailTooltipTransition> createState() => _RailTooltipTransitionState();
}

class _RailTooltipTransitionState extends State<_RailTooltipTransition> {
  late CurvedAnimation _eased;

  @override
  void initState() {
    super.initState();
    _eased = _createAnimation();
  }

  @override
  void didUpdateWidget(_RailTooltipTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    _eased.dispose();
    _eased = _createAnimation();
  }

  CurvedAnimation _createAnimation() => CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _eased.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _eased,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(_eased),
        alignment: Alignment.centerLeft,
        child: widget.child,
      ),
    );
  }
}

class _RailTooltipCallout extends StatelessWidget {
  const _RailTooltipCallout({required this.instance, required this.accent});

  static const surface = Color(0xFF3C3D43);
  static const decoration = ShapeDecoration(
    color: surface,
    shape: _RailTooltipBorder(),
    shadows: [
      BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
      BoxShadow(color: Color(0x24000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
  );

  final DiscourseInstance instance;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconBackground = Color.alphaBlend(accent, surface);
    final iconForeground = contrastSafeForeground(
      background: iconBackground,
      backdrop: surface,
      preferred: const [Colors.white, Colors.black],
    );

    return Container(
      key: ValueKey('instance-rail-callout-${instance.url}'),
      constraints: const BoxConstraints(minHeight: 36, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: AvatarImage(
                key: ValueKey('instance-rail-callout-icon-${instance.url}'),
                url: instance.iconUrl,
                size: 18,
                fit: BoxFit.contain,
                fallback: ColoredBox(
                  color: iconBackground,
                  child: SizedBox.square(
                    dimension: 18,
                    child: Center(
                      child: Text(
                        instance.monogram,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: iconForeground,
                          fontSize: DiscourseTypography.fontDown3,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              instance.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFFF3F3F4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.15,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Offset _positionRailTooltip(TooltipPositionContext context) {
  const horizontalGap = 6.0;
  const viewportMargin = 8.0;
  return Offset(
    _fitRailTooltip(
      wanted: context.target.dx + context.targetSize.width / 2 + horizontalGap,
      extent: context.overlaySize.width,
      childExtent: context.tooltipSize.width,
      margin: viewportMargin,
    ),
    _fitRailTooltip(
      wanted: context.target.dy - context.tooltipSize.height / 2,
      extent: context.overlaySize.height,
      childExtent: context.tooltipSize.height,
      margin: viewportMargin,
    ),
  );
}

double _fitRailTooltip({
  required double wanted,
  required double extent,
  required double childExtent,
  required double margin,
}) {
  if (!extent.isFinite || !childExtent.isFinite) return wanted;
  final slack = extent - childExtent;
  if (slack <= margin * 2) return slack / 2;
  return wanted.clamp(margin, slack - margin);
}

class _RailTooltipBorder extends OutlinedBorder {
  const _RailTooltipBorder({
    super.side = const BorderSide(color: Color(0xFF47484E)),
    this.pointerWidth = 7,
    this.pointerHeight = 14,
    this.radius = 7,
  });

  final double pointerWidth;
  final double pointerHeight;
  final double radius;

  @override
  EdgeInsetsGeometry get dimensions {
    final inset = side.strokeInset.clamp(0.0, double.infinity);
    return EdgeInsets.fromLTRB(pointerWidth + inset, inset, inset, inset);
  }

  Path _path(Rect rect) {
    if (rect.isEmpty) return Path();

    final body = Rect.fromLTRB(
      rect.left + pointerWidth,
      rect.top,
      rect.right,
      rect.bottom,
    );
    final corner = radius.clamp(0, body.shortestSide / 2);
    final pointerHalfHeight = pointerHeight.clamp(0, body.height) / 2;

    return Path()
      ..moveTo(body.left + corner, body.top)
      ..lineTo(body.right - corner, body.top)
      ..quadraticBezierTo(body.right, body.top, body.right, body.top + corner)
      ..lineTo(body.right, body.bottom - corner)
      ..quadraticBezierTo(
        body.right,
        body.bottom,
        body.right - corner,
        body.bottom,
      )
      ..lineTo(body.left + corner, body.bottom)
      ..quadraticBezierTo(
        body.left,
        body.bottom,
        body.left,
        body.bottom - corner,
      )
      ..lineTo(body.left, body.center.dy + pointerHalfHeight)
      ..lineTo(rect.left, body.center.dy)
      ..lineTo(body.left, body.center.dy - pointerHalfHeight)
      ..lineTo(body.left, body.top + corner)
      ..quadraticBezierTo(body.left, body.top, body.left + corner, body.top)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _path(rect.deflate(side.strokeInset));
  }

  @override
  _RailTooltipBorder copyWith({
    BorderSide? side,
    double? pointerWidth,
    double? pointerHeight,
    double? radius,
  }) {
    return _RailTooltipBorder(
      side: side ?? this.side,
      pointerWidth: pointerWidth ?? this.pointerWidth,
      pointerHeight: pointerHeight ?? this.pointerHeight,
      radius: radius ?? this.radius,
    );
  }

  @override
  ShapeBorder scale(double t) => _RailTooltipBorder(
    side: side.scale(t),
    pointerWidth: pointerWidth * t,
    pointerHeight: pointerHeight * t,
    radius: radius * t,
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final strokeOffset = (side.strokeOutset - side.strokeInset) / 2;
    canvas.drawPath(_path(rect.inflate(strokeOffset)), side.toPaint());
  }

  @override
  bool operator ==(Object other) {
    return other is _RailTooltipBorder &&
        other.side == side &&
        other.pointerWidth == pointerWidth &&
        other.pointerHeight == pointerHeight &&
        other.radius == radius;
  }

  @override
  int get hashCode => Object.hash(side, pointerWidth, pointerHeight, radius);
}

class _InstanceAvatar extends StatelessWidget {
  const _InstanceAvatar({
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
    final theme = Theme.of(context);

    final monogram = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(selected ? 14 : 22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: Text(
          instance.monogram,
          style: theme.textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AvatarImage(
        url: instance.iconUrl,
        size: 44,
        fit: BoxFit.contain,
        fallback: monogram,
      ),
    );
  }
}

ResolvedSitePalette? _activePalette(
  SiteAppearance? appearance,
  Brightness platformBrightness,
) {
  if (appearance == null) return null;
  return switch (appearance.mode) {
    SiteAppearanceMode.base => appearance.base ?? appearance.alternate,
    SiteAppearanceMode.alternate => appearance.alternate ?? appearance.base,
    SiteAppearanceMode.followSystem =>
      platformBrightness == Brightness.dark
          ? appearance.alternate ?? appearance.base
          : appearance.base ?? appearance.alternate,
  };
}

class _AddInstanceButton extends StatelessWidget {
  const _AddInstanceButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Add a Discourse site',
      child: InkWell(
        onTap: () => showAddInstanceSheet(context),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.shell.railForeground.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(22),
          ),
          child: DIcon(
            DIcons.plus,
            size: 22,
            color: theme.shell.railForeground,
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    super.key,
    required this.count,
    required this.background,
    required this.foreground,
  });

  final int count;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.shell.rail, width: 2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
