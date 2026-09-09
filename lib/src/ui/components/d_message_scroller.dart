import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_scroll_area.dart';

/// Where a transcript lands on its first non-empty layout.
enum DMessageScrollerInitialPosition { start, end, lastAnchor }

/// A logical transcript edge, independent of a reversed Flutter viewport.
enum DMessageScrollerDirection { start, end }

/// Alignment used by [DMessageScrollerController.scrollToMessage].
enum DMessageScrollerAlignment { start, center, end, nearest }

/// Motion used by imperative transcript commands.
enum DMessageScrollerScrollBehavior { instant, smooth }

/// Per-command overrides for a transcript jump.
@immutable
class DMessageScrollerScrollOptions {
  const DMessageScrollerScrollOptions({
    this.alignment = DMessageScrollerAlignment.start,
    this.behavior = DMessageScrollerScrollBehavior.instant,
    this.scrollMargin,
  });

  final DMessageScrollerAlignment alignment;
  final DMessageScrollerScrollBehavior behavior;
  final double? scrollMargin;
}

/// Scroll and reader-position state exposed without rebuilding transcript rows.
@immutable
class DMessageScrollerState {
  const DMessageScrollerState({
    this.canScrollStart = false,
    this.canScrollEnd = false,
    this.autoScrolling = false,
    this.pendingInitialScroll = false,
    this.followingLiveEdge = false,
    this.currentAnchorId,
    this.visibleMessageIds = const [],
  });

  final bool canScrollStart;
  final bool canScrollEnd;
  final bool autoScrolling;
  final bool pendingInitialScroll;
  final bool followingLiveEdge;
  final String? currentAnchorId;
  final List<String> visibleMessageIds;

  bool canScroll(DMessageScrollerDirection direction) => switch (direction) {
    DMessageScrollerDirection.start => canScrollStart,
    DMessageScrollerDirection.end => canScrollEnd,
  };

  DMessageScrollerState copyWith({
    bool? canScrollStart,
    bool? canScrollEnd,
    bool? autoScrolling,
    bool? pendingInitialScroll,
    bool? followingLiveEdge,
    Object? currentAnchorId = _notProvided,
    List<String>? visibleMessageIds,
  }) => DMessageScrollerState(
    canScrollStart: canScrollStart ?? this.canScrollStart,
    canScrollEnd: canScrollEnd ?? this.canScrollEnd,
    autoScrolling: autoScrolling ?? this.autoScrolling,
    pendingInitialScroll: pendingInitialScroll ?? this.pendingInitialScroll,
    followingLiveEdge: followingLiveEdge ?? this.followingLiveEdge,
    currentAnchorId: identical(currentAnchorId, _notProvided)
        ? this.currentAnchorId
        : currentAnchorId as String?,
    visibleMessageIds: List.unmodifiable(
      visibleMessageIds ?? this.visibleMessageIds,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is DMessageScrollerState &&
      other.canScrollStart == canScrollStart &&
      other.canScrollEnd == canScrollEnd &&
      other.autoScrolling == autoScrolling &&
      other.pendingInitialScroll == pendingInitialScroll &&
      other.followingLiveEdge == followingLiveEdge &&
      other.currentAnchorId == currentAnchorId &&
      _listsEqual(other.visibleMessageIds, visibleMessageIds);

  @override
  int get hashCode => Object.hash(
    canScrollStart,
    canScrollEnd,
    autoScrolling,
    pendingInitialScroll,
    followingLiveEdge,
    currentAnchorId,
    Object.hashAll(visibleMessageIds),
  );
}

const _notProvided = Object();

bool _listsEqual(List<Object?> first, List<Object?> second) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

abstract interface class _DMessageScrollerBinding {
  bool scrollToStart(DMessageScrollerScrollBehavior behavior);
  bool scrollToEnd(DMessageScrollerScrollBehavior behavior);
  bool scrollToMessage(String messageId, DMessageScrollerScrollOptions options);
  void stopFollowing();
}

/// Imperative commands and externally observable state for one viewport.
///
/// The controller may be supplied to [DMessageScrollerProvider]. Borrowed
/// controllers are never disposed by the component. A command targeting an id
/// before the first items mount is queued; after a non-empty transcript mounts,
/// an unknown id returns false.
class DMessageScrollerController extends ChangeNotifier {
  DMessageScrollerState get state => _state;
  DMessageScrollerState _state = const DMessageScrollerState();

  _DMessageScrollerBinding? _binding;
  ({String id, DMessageScrollerScrollOptions options})? _pendingMessage;

  bool scrollToStart({
    DMessageScrollerScrollBehavior behavior =
        DMessageScrollerScrollBehavior.instant,
  }) => _binding?.scrollToStart(behavior) ?? false;

  bool scrollToEnd({
    DMessageScrollerScrollBehavior behavior =
        DMessageScrollerScrollBehavior.instant,
  }) => _binding?.scrollToEnd(behavior) ?? false;

  bool scrollToMessage(
    String messageId, {
    DMessageScrollerScrollOptions options =
        const DMessageScrollerScrollOptions(),
  }) {
    final binding = _binding;
    if (binding == null) {
      _pendingMessage = (id: messageId, options: options);
      return true;
    }
    return binding.scrollToMessage(messageId, options);
  }

  /// Releases live-edge following without moving the viewport.
  void stopFollowing() => _binding?.stopFollowing();

  void _attach(_DMessageScrollerBinding binding) {
    assert(
      _binding == null || identical(_binding, binding),
      'A DMessageScrollerController can only control one mounted viewport.',
    );
    _binding = binding;
    final pending = _pendingMessage;
    if (pending != null &&
        binding.scrollToMessage(pending.id, pending.options)) {
      _pendingMessage = null;
    }
  }

  void _detach(_DMessageScrollerBinding binding) {
    if (identical(_binding, binding)) _binding = null;
  }

  void _setState(DMessageScrollerState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }
}

/// Headless owner for transcript behavior and controller lifecycle.
class DMessageScrollerProvider extends StatefulWidget {
  const DMessageScrollerProvider({
    super.key,
    required this.child,
    this.controller,
    this.autoScroll = false,
    this.initialPosition = DMessageScrollerInitialPosition.end,
    this.manageInitialPosition = true,
    this.scrollEdgeThreshold = 8,
    this.scrollMargin = 0,
    this.previousItemPeek = 64,
  }) : assert(scrollEdgeThreshold >= 0),
       assert(scrollMargin >= 0),
       assert(previousItemPeek >= 0);

  final Widget child;
  final DMessageScrollerController? controller;
  final bool autoScroll;
  final DMessageScrollerInitialPosition initialPosition;

  /// Set false only when an application adapter already owns a specialized
  /// restoration target. The generic default and all catalogue compositions
  /// apply [initialPosition].
  final bool manageInitialPosition;
  final double scrollEdgeThreshold;
  final double scrollMargin;
  final double previousItemPeek;

  @override
  State<DMessageScrollerProvider> createState() =>
      _DMessageScrollerProviderState();
}

class _DMessageScrollerProviderState extends State<DMessageScrollerProvider> {
  final DMessageScrollerController _owned = DMessageScrollerController();

  DMessageScrollerController get _controller => widget.controller ?? _owned;

  @override
  void dispose() {
    _owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DMessageScrollerScope(
    controller: _controller,
    autoScroll: widget.autoScroll,
    initialPosition: widget.initialPosition,
    manageInitialPosition: widget.manageInitialPosition,
    scrollEdgeThreshold: widget.scrollEdgeThreshold,
    scrollMargin: widget.scrollMargin,
    previousItemPeek: widget.previousItemPeek,
    child: widget.child,
  );
}

class _DMessageScrollerScope extends InheritedWidget {
  const _DMessageScrollerScope({
    required this.controller,
    required this.autoScroll,
    required this.initialPosition,
    required this.manageInitialPosition,
    required this.scrollEdgeThreshold,
    required this.scrollMargin,
    required this.previousItemPeek,
    required super.child,
  });

  final DMessageScrollerController controller;
  final bool autoScroll;
  final DMessageScrollerInitialPosition initialPosition;
  final bool manageInitialPosition;
  final double scrollEdgeThreshold;
  final double scrollMargin;
  final double previousItemPeek;

  static _DMessageScrollerScope of(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<_DMessageScrollerScope>();
    assert(
      result != null,
      'Message Scroller parts require a DMessageScrollerProvider ancestor.',
    );
    return result!;
  }

  @override
  bool updateShouldNotify(_DMessageScrollerScope oldWidget) =>
      controller != oldWidget.controller ||
      autoScroll != oldWidget.autoScroll ||
      initialPosition != oldWidget.initialPosition ||
      manageInitialPosition != oldWidget.manageInitialPosition ||
      scrollEdgeThreshold != oldWidget.scrollEdgeThreshold ||
      scrollMargin != oldWidget.scrollMargin ||
      previousItemPeek != oldWidget.previousItemPeek;
}

/// The base-nova frame. It fills its constrained parent and layers controls
/// over the viewport.
class DMessageScroller extends StatelessWidget {
  const DMessageScroller({
    super.key,
    required this.children,
    this.clipBehavior = Clip.hardEdge,
  });

  final List<Widget> children;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    clipBehavior: clipBehavior,
    children: children,
  );
}

/// A real transcript row. Stable ids drive jumps, visibility, and restoration.
@immutable
class DMessageScrollerItem extends StatelessWidget {
  const DMessageScrollerItem({
    super.key,
    required this.messageId,
    required this.child,
    this.scrollAnchor = false,
    this.announcement,
  }) : assert(messageId != '');

  final String messageId;
  final bool scrollAnchor;
  final String? announcement;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Direct-child transcript composition with the base-nova 24px row gap.
///
/// This is consumed by [DMessageScrollerViewport]. Its own build remains useful
/// for unstyled/static composition, but does not acquire scrolling behavior.
class DMessageScrollerContent extends StatelessWidget {
  const DMessageScrollerContent({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.gap = 24,
    this.busy = false,
  }) : assert(gap >= 0);

  final List<DMessageScrollerItem> children;
  final EdgeInsetsGeometry padding;
  final double gap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: !busy,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index + 1 < children.length) SizedBox(height: gap),
          ],
        ],
      ),
    ),
  );
}

typedef DMessageScrollerIndexedWidgetBuilder =
    Widget Function(BuildContext context, int index);
typedef DMessageScrollerIndexedIdBuilder = String Function(int index);
typedef DMessageScrollerIndexedBoolBuilder = bool Function(int index);
typedef DMessageScrollerIndexedStringBuilder = String? Function(int index);
typedef DMessageScrollerScrollableBuilder =
    Widget Function(
      BuildContext context,
      ScrollController controller,
      Widget scrollable,
    );

/// The labelled native viewport, backed by a variable-height virtualized list.
///
/// The default constructor preserves the documented direct Item composition.
/// [DMessageScrollerViewport.builder] lets a virtualizer or production timeline
/// own row creation while this component retains scroll behavior. Controllers
/// supplied by a caller are borrowed and never disposed.
class DMessageScrollerViewport extends StatefulWidget {
  const DMessageScrollerViewport({
    super.key,
    required DMessageScrollerContent content,
    this.scrollController,
    this.listController,
    this.focusNode,
    this.preserveScrollOnPrepend = true,
    this.preserveReaderPositionOnResize = true,
    this.preserveChildIdentity = true,
    this.reverse = false,
    this.physics,
    this.restorationId,
    this.cacheExtent,
    this.semanticLabel = 'Messages',
    this.showScrollbar = true,
    this.styled = true,
    this.onScrollNotification,
    this.onUserScrollIntent,
    this.scrollableBuilder,
  }) : // Named private formals would make this public constructor unusable.
       // ignore: prefer_initializing_formals
       _content = content,
       _itemCount = null,
       _itemBuilder = null,
       _itemIdBuilder = null,
       _scrollAnchorBuilder = null,
       _announcementBuilder = null,
       contentPadding = null,
       gap = null,
       busy = null;

  const DMessageScrollerViewport.builder({
    super.key,
    required int itemCount,
    required DMessageScrollerIndexedWidgetBuilder itemBuilder,
    required DMessageScrollerIndexedIdBuilder itemIdBuilder,
    DMessageScrollerIndexedBoolBuilder? scrollAnchorBuilder,
    DMessageScrollerIndexedStringBuilder? announcementBuilder,
    this.contentPadding = EdgeInsets.zero,
    this.gap = 24,
    this.busy = false,
    this.scrollController,
    this.listController,
    this.focusNode,
    this.preserveScrollOnPrepend = true,
    this.preserveReaderPositionOnResize = true,
    this.preserveChildIdentity = true,
    this.reverse = false,
    this.physics,
    this.restorationId,
    this.cacheExtent,
    this.semanticLabel = 'Messages',
    this.showScrollbar = true,
    this.styled = true,
    this.onScrollNotification,
    this.onUserScrollIntent,
    this.scrollableBuilder,
  }) : assert(itemCount >= 0),
       assert((gap ?? 0) >= 0),
       _content = null,
       _itemCount = itemCount,
       // Named private formals would make this public constructor unusable.
       // ignore: prefer_initializing_formals
       _itemBuilder = itemBuilder,
       // ignore: prefer_initializing_formals
       _itemIdBuilder = itemIdBuilder,
       // ignore: prefer_initializing_formals
       _scrollAnchorBuilder = scrollAnchorBuilder,
       // ignore: prefer_initializing_formals
       _announcementBuilder = announcementBuilder;

  final DMessageScrollerContent? _content;
  final int? _itemCount;
  final DMessageScrollerIndexedWidgetBuilder? _itemBuilder;
  final DMessageScrollerIndexedIdBuilder? _itemIdBuilder;
  final DMessageScrollerIndexedBoolBuilder? _scrollAnchorBuilder;
  final DMessageScrollerIndexedStringBuilder? _announcementBuilder;

  final EdgeInsetsGeometry? contentPadding;
  final double? gap;
  final bool? busy;
  final ScrollController? scrollController;
  final ListController? listController;
  final FocusNode? focusNode;
  final bool preserveScrollOnPrepend;

  /// Keeps the first visible stable row fixed when measured content changes.
  /// Turn this off only for an adapter whose reversed virtualizer already owns
  /// the same invariant.
  final bool preserveReaderPositionOnResize;

  /// Lets keyed rows follow stable ids across insertions. A reversed adapter
  /// that already preserves offsets by physical index may disable this while
  /// continuing to expose ids for commands and state.
  final bool preserveChildIdentity;
  final bool reverse;
  final ScrollPhysics? physics;
  final String? restorationId;
  final double? cacheExtent;
  final String semanticLabel;
  final bool showScrollbar;
  final bool styled;
  final bool Function(ScrollNotification notification)? onScrollNotification;
  final VoidCallback? onUserScrollIntent;
  final DMessageScrollerScrollableBuilder? scrollableBuilder;

  int get itemCount => _content?.children.length ?? _itemCount!;
  EdgeInsetsGeometry get resolvedPadding =>
      _content?.padding ?? contentPadding!;
  double get resolvedGap => _content?.gap ?? gap!;
  bool get resolvedBusy => _content?.busy ?? busy!;

  String itemId(int index) =>
      _content?.children[index].messageId ?? _itemIdBuilder!(index);
  bool itemIsAnchor(int index) =>
      _content?.children[index].scrollAnchor ??
      (_scrollAnchorBuilder?.call(index) ?? false);
  String? itemAnnouncement(int index) =>
      _content?.children[index].announcement ??
      _announcementBuilder?.call(index);
  Widget buildItem(BuildContext context, int index) =>
      _content?.children[index] ?? _itemBuilder!(context, index);

  @override
  State<DMessageScrollerViewport> createState() =>
      _DMessageScrollerViewportState();
}

enum _ScrollerMode { free, followingEnd, anchored, settling }

class _DMessageScrollerViewportState extends State<DMessageScrollerViewport>
    implements _DMessageScrollerBinding {
  final ScrollController _ownedScroll = ScrollController();
  final ListController _ownedList = ListController();
  final FocusNode _ownedFocus = FocusNode(debugLabel: 'Message transcript');
  final GlobalKey _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _rowKeys = {};

  ScrollController get _scroll => widget.scrollController ?? _ownedScroll;
  ListController get _list => widget.listController ?? _ownedList;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  _DMessageScrollerScope? _scope;
  DMessageScrollerController? _attachedController;
  _ScrollerMode _mode = _ScrollerMode.free;
  bool _initialApplied = false;
  bool _pendingInitial = false;
  bool _syncScheduled = false;
  bool _contentChangeScheduled = false;
  bool _readerCaptureScheduled = false;
  bool _restoring = false;
  bool _focusVisible = false;
  int _programmaticGeneration = 0;
  int _programmaticDepth = 0;
  double _spacerExtent = 0;
  String? _anchoredId;
  double? _anchoredTop;
  ({String id, double top})? _readerHold;
  ({String id, double top})? _pendingRestore;
  ({String id, DMessageScrollerScrollOptions options})? _pendingTarget;
  List<String> _ids = const [];
  List<bool> _anchors = const [];
  final List<String> _pendingAnnouncements = [];

  @override
  void initState() {
    super.initState();
    _list.addListener(_handleExtentsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _DMessageScrollerScope.of(context);
    final controllerChanged = !identical(next.controller, _attachedController);
    if (controllerChanged) {
      _attachedController?._detach(this);
      _attachedController = next.controller.._attach(this);
    }
    final initialChanged =
        _scope != null && _scope!.initialPosition != next.initialPosition;
    _scope = next;
    if (initialChanged) {
      _initialApplied = false;
    }
    if (!_initialApplied) {
      _mode = next.autoScroll ? _ScrollerMode.followingEnd : _ScrollerMode.free;
      _pendingInitial =
          next.manageInitialPosition &&
          next.initialPosition != DMessageScrollerInitialPosition.start;
    }
    _captureItems();
    _scheduleContentChange();
  }

  @override
  void didUpdateWidget(DMessageScrollerViewport oldWidget) {
    final previousIds = _ids;
    final previousAnchors = _anchors;
    final prependHold = widget.preserveScrollOnPrepend
        ? _captureReaderHold(previousIds)
        : null;
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.listController, widget.listController)) {
      (oldWidget.listController ?? _ownedList).removeListener(
        _handleExtentsChanged,
      );
      _list.addListener(_handleExtentsChanged);
    }

    _captureItems();
    _collectAnnouncements(previousIds);
    if (oldWidget.resolvedBusy && !widget.resolvedBusy) {
      _scheduleAnnouncements();
    }
    final prepended = _prependedCount(previousIds, _ids);
    if (prependHold != null && prepended > 0) _pendingRestore = prependHold;

    final appendedAt = _appendedStart(previousIds, _ids);
    if (appendedAt != null) {
      final newAnchor = _firstAnchorFrom(appendedAt);
      if (newAnchor != null &&
          !_wasExistingAnchor(newAnchor, previousIds, previousAnchors)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _anchorNewTurn(newAnchor, appendedAt: appendedAt);
        });
      }
    }
    _scheduleContentChange();
  }

  @override
  void dispose() {
    _attachedController?._detach(this);
    _list.removeListener(_handleExtentsChanged);
    _ownedScroll.dispose();
    _ownedList.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }

  void _captureItems() {
    final ids = <String>[];
    final anchors = <bool>[];
    final seen = <String>{};
    for (var index = 0; index < widget.itemCount; index++) {
      final id = widget.itemId(index);
      assert(seen.add(id), 'Message Scroller ids must be unique: $id');
      ids.add(id);
      anchors.add(widget.itemIsAnchor(index));
    }
    _ids = List.unmodifiable(ids);
    _anchors = List.unmodifiable(anchors);
    _rowKeys.removeWhere((id, _) => !seen.contains(id));
    for (final id in ids) {
      _rowKeys.putIfAbsent(id, GlobalKey.new);
    }
  }

  int _prependedCount(List<String> oldIds, List<String> newIds) {
    if (oldIds.isEmpty || newIds.length <= oldIds.length) return 0;
    final added = newIds.length - oldIds.length;
    for (var index = 0; index < oldIds.length; index++) {
      if (newIds[index + added] != oldIds[index]) return 0;
    }
    return added;
  }

  int? _appendedStart(List<String> oldIds, List<String> newIds) {
    if (newIds.length <= oldIds.length) return null;
    for (var index = 0; index < oldIds.length; index++) {
      if (newIds[index] != oldIds[index]) return null;
    }
    return oldIds.length;
  }

  String? _firstAnchorFrom(int start) {
    for (var index = start; index < _anchors.length; index++) {
      if (_anchors[index]) return _ids[index];
    }
    return null;
  }

  bool _wasExistingAnchor(
    String id,
    List<String> oldIds,
    List<bool> oldAnchors,
  ) {
    final index = oldIds.indexOf(id);
    return index >= 0 && oldAnchors[index];
  }

  void _collectAnnouncements(List<String> previousIds) {
    if (previousIds.isEmpty) return;
    final previous = previousIds.toSet();
    for (var index = 0; index < _ids.length; index++) {
      if (previous.contains(_ids[index])) continue;
      final announcement = widget.itemAnnouncement(index)?.trim();
      if (announcement != null && announcement.isNotEmpty) {
        _pendingAnnouncements.add(announcement);
      }
    }
    if (!widget.resolvedBusy) _scheduleAnnouncements();
  }

  void _scheduleAnnouncements() {
    if (_pendingAnnouncements.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.resolvedBusy || _pendingAnnouncements.isEmpty) {
        return;
      }
      final message = _pendingAnnouncements.join(' ');
      _pendingAnnouncements.clear();
      if (!MediaQuery.supportsAnnounceOf(context)) return;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  ({String id, double top})? _captureReaderHold([List<String>? ids]) {
    if (!_list.isAttached || !_scroll.hasClients) return _readerHold;
    final range = _list.visibleRange;
    if (range == null || range.$1 < 0) return _readerHold;
    final available = ids ?? _ids;
    if (range.$1 >= available.length) return _readerHold;
    final id = available[range.$1];
    final top = _rowTop(id);
    return top == null ? _readerHold : (id: id, top: top);
  }

  void _handleExtentsChanged() {
    if (!_list.isAttached || _restoring) return;
    _scheduleContentChange();
  }

  void _scheduleContentChange() {
    if (_contentChangeScheduled) return;
    _contentChangeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentChangeScheduled = false;
      if (!mounted) return;
      _handleContentChange();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _handleContentChange() {
    if (!_scroll.hasClients || !_list.isAttached) {
      _scheduleStateSync();
      return;
    }

    if (!_initialApplied) {
      if (_ids.isEmpty) {
        _setPendingInitial(false);
        _publishState();
        return;
      }
      if (!_scope!.manageInitialPosition) {
        _initialApplied = true;
        _setPendingInitial(false);
        _publishState();
        _scheduleReaderHoldCapture();
        return;
      }
      _applyInitialPosition();
      return;
    }

    if (_pendingTarget case final pending?) {
      if (_indexOf(pending.id) case final index?) {
        _pendingTarget = null;
        _scrollToIndex(index, pending.options);
        return;
      }
    }

    if (_pendingRestore case final hold? when _mode == _ScrollerMode.free) {
      if (_restoreHold(hold)) return;
      _pendingRestore = null;
    }
    if (_readerHold case final hold?
        when _mode == _ScrollerMode.free &&
            widget.preserveReaderPositionOnResize) {
      if (_restoreHold(hold)) return;
    }
    if (_mode == _ScrollerMode.anchored && _anchoredId != null) {
      if (_restoreAnchor()) return;
    }
    if (_mode == _ScrollerMode.followingEnd && _scope!.autoScroll) {
      _moveToEdge(
        DMessageScrollerDirection.end,
        DMessageScrollerScrollBehavior.instant,
        markAutoScrolling: true,
      );
      return;
    }
    _scheduleStateSync();
  }

  void _applyInitialPosition() {
    final position = _scope!.initialPosition;
    _initialApplied = true;
    switch (position) {
      case DMessageScrollerInitialPosition.start:
        _moveToEdge(
          DMessageScrollerDirection.start,
          DMessageScrollerScrollBehavior.instant,
        );
      case DMessageScrollerInitialPosition.end:
        _moveToEdge(
          DMessageScrollerDirection.end,
          DMessageScrollerScrollBehavior.instant,
        );
      case DMessageScrollerInitialPosition.lastAnchor:
        final anchor = _lastAnchorId();
        if (anchor == null || _turnFromAnchorFits(anchor)) {
          _moveToEdge(
            DMessageScrollerDirection.end,
            DMessageScrollerScrollBehavior.instant,
          );
        } else {
          _scrollToMessage(
            anchor,
            const DMessageScrollerScrollOptions(),
            keepPreviousPeek: true,
          );
        }
    }
    _setPendingInitial(false);
    _publishState();
    _scheduleReaderHoldCapture();
  }

  void _setPendingInitial(bool value) {
    if (_pendingInitial == value) return;
    setState(() => _pendingInitial = value);
  }

  String? _lastAnchorId() {
    for (var index = _anchors.length - 1; index >= 0; index--) {
      if (_anchors[index]) return _ids[index];
    }
    return null;
  }

  bool _turnFromAnchorFits(String id) {
    final index = _indexOf(id);
    if (index == null || !_scroll.hasClients) return true;
    var extent = 0.0;
    if (widget.reverse) {
      for (var row = 0; row <= index; row++) {
        extent += _list.extentForIndex(row).$1 + widget.resolvedGap;
      }
    } else {
      for (var row = index; row < _ids.length; row++) {
        extent += _list.extentForIndex(row).$1 + widget.resolvedGap;
      }
    }
    return extent <= _scroll.position.viewportDimension;
  }

  void _anchorNewTurn(String id, {required int appendedAt}) {
    if (!_initialApplied || !_scroll.hasClients || !_list.isAttached) return;
    final newAnchorCount = _anchors
        .skip(appendedAt)
        .where((value) => value)
        .length;
    if (_scope!.autoScroll &&
        _mode == _ScrollerMode.followingEnd &&
        newAnchorCount > 1) {
      scrollToEnd();
      return;
    }
    _scrollToMessage(
      id,
      const DMessageScrollerScrollOptions(),
      keepPreviousPeek: true,
    );
  }

  bool _restoreHold(({String id, double top}) hold) {
    final index = _indexOf(hold.id);
    if (index == null) {
      _readerHold = null;
      return false;
    }
    final currentTop = _rowTop(hold.id);
    if (currentTop == null) return false;
    final target = _scroll.offset + currentTop - hold.top;
    if ((currentTop - hold.top).abs() <= .5) {
      _readerHold = _captureReaderHold();
      _scheduleStateSync();
      return false;
    }
    _restoring = true;
    _jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoring = false;
      if (!mounted) return;
      _pendingRestore = null;
      _readerHold = _captureReaderHold();
      _scheduleStateSync();
    });
    return true;
  }

  bool _restoreAnchor() {
    final id = _anchoredId;
    final top = _anchoredTop;
    if (id == null || top == null) return false;
    final index = _indexOf(id);
    if (index == null) {
      _mode = _ScrollerMode.free;
      _anchoredId = null;
      _anchoredTop = null;
      return false;
    }
    return _restoreHold((id: id, top: top));
  }

  int? _indexOf(String id) {
    final index = _ids.indexOf(id);
    return index < 0 ? null : index;
  }

  @override
  bool scrollToStart([
    DMessageScrollerScrollBehavior behavior =
        DMessageScrollerScrollBehavior.instant,
  ]) {
    _spacerExtent = 0;
    _anchoredId = null;
    _anchoredTop = null;
    _mode = _ScrollerMode.free;
    return _moveToEdge(DMessageScrollerDirection.start, behavior);
  }

  @override
  bool scrollToEnd([
    DMessageScrollerScrollBehavior behavior =
        DMessageScrollerScrollBehavior.instant,
  ]) {
    _spacerExtent = 0;
    _anchoredId = null;
    _anchoredTop = null;
    _mode = _scope?.autoScroll == true
        ? _ScrollerMode.followingEnd
        : _ScrollerMode.free;
    return _moveToEdge(
      DMessageScrollerDirection.end,
      behavior,
      markAutoScrolling: true,
    );
  }

  @override
  bool scrollToMessage(
    String messageId,
    DMessageScrollerScrollOptions options,
  ) => _scrollToMessage(messageId, options);

  bool _scrollToMessage(
    String messageId,
    DMessageScrollerScrollOptions options, {
    bool keepPreviousPeek = false,
  }) {
    final index = _indexOf(messageId);
    if (index == null) {
      if (_ids.isEmpty) {
        _pendingTarget = (id: messageId, options: options);
        _initialApplied = true;
        _pendingInitial = false;
        return true;
      }
      return false;
    }
    if (!_list.isAttached || !_scroll.hasClients) {
      _pendingTarget = (id: messageId, options: options);
      return true;
    }
    _mode = keepPreviousPeek ? _ScrollerMode.anchored : _ScrollerMode.settling;
    _anchoredId = keepPreviousPeek ? messageId : null;
    return _scrollToIndex(
      index,
      options,
      extraMargin: keepPreviousPeek ? _scope!.previousItemPeek : 0,
    );
  }

  bool _scrollToIndex(
    int index,
    DMessageScrollerScrollOptions options, {
    double extraMargin = 0,
  }) {
    final generation = ++_programmaticGeneration;
    final keepAnchored = _mode == _ScrollerMode.anchored;
    if (!keepAnchored) _mode = _ScrollerMode.settling;
    final margin = (options.scrollMargin ?? _scope!.scrollMargin) + extraMargin;
    final alignment = switch (options.alignment) {
      DMessageScrollerAlignment.start => 0.0,
      DMessageScrollerAlignment.center => .5,
      DMessageScrollerAlignment.end => 1.0,
      DMessageScrollerAlignment.nearest => _nearestAlignment(index, margin),
    };
    if (options.alignment == DMessageScrollerAlignment.start) {
      final rowExtent = _list.extentForIndex(index).$1;
      _setSpacer(
        (_scroll.position.viewportDimension - rowExtent + margin).clamp(
          0,
          double.infinity,
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          generation != _programmaticGeneration) {
        return;
      }
      if (options.behavior == DMessageScrollerScrollBehavior.smooth &&
          !MediaQuery.disableAnimationsOf(context)) {
        _programmaticDepth++;
        _list.animateToItem(
          index: index,
          scrollController: _scroll,
          alignment: alignment,
          duration: (_) => const Duration(milliseconds: 200),
          curve: (_) => Curves.easeOutCubic,
        );
        Future<void>.delayed(const Duration(milliseconds: 220), () {
          if (!mounted) return;
          _programmaticDepth = (_programmaticDepth - 1).clamp(0, 1 << 20);
          if (generation != _programmaticGeneration) {
            _publishState();
            return;
          }
          _correctItemMargin(index, alignment, margin);
          if (!keepAnchored) _mode = _ScrollerMode.free;
          _readerHold = _captureReaderHold();
          _publishState();
        });
      } else {
        _list.jumpToItem(
          index: index,
          scrollController: _scroll,
          alignment: alignment,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _programmaticGeneration) return;
          _correctItemMargin(index, alignment, margin);
          if (!keepAnchored) _mode = _ScrollerMode.free;
          _readerHold = _captureReaderHold();
        });
        WidgetsBinding.instance.scheduleFrame();
      }
      if (keepAnchored) {
        _anchoredTop = margin;
      }
    });
    WidgetsBinding.instance.scheduleFrame();
    return true;
  }

  double _nearestAlignment(int index, double margin) {
    final id = _ids[index];
    final rowTop = _rowTop(id);
    final rowContext = _rowKeys[id]?.currentContext;
    final rowBox = rowContext?.findRenderObject() as RenderBox?;
    if (rowTop == null || rowBox == null) return 0;
    final rowBottom = rowTop + rowBox.size.height;
    final viewport = _scroll.position.viewportDimension;
    if (rowTop >= margin && rowBottom <= viewport - margin) {
      return rowTop.abs() < (viewport - rowBottom).abs() ? 0 : 1;
    }
    return rowTop < margin ? 0 : 1;
  }

  void _correctItemMargin(int index, double alignment, double margin) {
    if (!_scroll.hasClients || index < 0 || index >= _ids.length) return;
    final id = _ids[index];
    final top = _rowTop(id);
    final rowBox =
        _rowKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (top == null || rowBox == null) return;
    final desired = switch (alignment) {
      0 => margin,
      1 => _scroll.position.viewportDimension - rowBox.size.height - margin,
      _ => (_scroll.position.viewportDimension - rowBox.size.height) / 2,
    };
    _jumpTo(_scroll.offset + top - desired);
    _scheduleStateSync();
  }

  double? _rowTop(String id) {
    final rowBox =
        _rowKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final viewportBox =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox == null || viewportBox == null || !rowBox.attached) return null;
    return rowBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
  }

  void _setSpacer(double value) {
    final next = value.ceilToDouble().clamp(0.0, double.infinity);
    if (next == _spacerExtent) return;
    setState(() => _spacerExtent = next);
  }

  bool _moveToEdge(
    DMessageScrollerDirection direction,
    DMessageScrollerScrollBehavior behavior, {
    bool markAutoScrolling = false,
  }) {
    if (!_scroll.hasClients) return false;
    final start = widget.reverse
        ? _scroll.position.maxScrollExtent
        : _scroll.position.minScrollExtent;
    final end = widget.reverse
        ? _scroll.position.minScrollExtent
        : _scroll.position.maxScrollExtent;
    _performScroll(
      direction == DMessageScrollerDirection.start ? start : end,
      behavior,
      autoScrolling: markAutoScrolling,
    );
    return true;
  }

  void _performScroll(
    double target,
    DMessageScrollerScrollBehavior behavior, {
    required bool autoScrolling,
  }) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final generation = ++_programmaticGeneration;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final settles = _mode != _ScrollerMode.followingEnd;
    if (settles) _mode = _ScrollerMode.settling;
    if (behavior == DMessageScrollerScrollBehavior.instant || reduceMotion) {
      _jumpTo(clamped);
      if (settles) _mode = _ScrollerMode.free;
      _scheduleReaderHoldCapture();
      _scheduleStateSync();
      return;
    }
    _programmaticDepth++;
    _publishState(autoScrolling: autoScrolling);
    unawaited(
      _scroll
          .animateTo(
            clamped,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted) return;
            _programmaticDepth = (_programmaticDepth - 1).clamp(0, 1 << 20);
            if (generation != _programmaticGeneration) {
              _publishState();
              return;
            }
            if (settles) _mode = _ScrollerMode.free;
            _readerHold = _captureReaderHold();
            _publishState();
          }),
    );
  }

  void _jumpTo(double target) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  void stopFollowing() => _noteUserIntent();

  void _noteUserIntent() {
    _programmaticGeneration++;
    _mode = _ScrollerMode.free;
    _anchoredId = null;
    _anchoredTop = null;
    _readerHold = _captureReaderHold();
    widget.onUserScrollIntent?.call();
    _scheduleReaderHoldCapture();
    _scheduleStateSync();
  }

  void _scheduleReaderHoldCapture() {
    if (_readerCaptureScheduled) return;
    _readerCaptureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readerCaptureScheduled = false;
      if (!mounted || _pendingRestore != null || _restoring) return;
      _readerHold = _captureReaderHold();
      _publishState();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return widget.onScrollNotification?.call(notification) ?? false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _noteUserIntent();
    } else if (notification is ScrollEndNotification &&
        _mode == _ScrollerMode.free) {
      _scheduleReaderHoldCapture();
    }
    _scheduleStateSync();
    final handled = widget.onScrollNotification?.call(notification) ?? false;
    return handled;
  }

  void _scheduleStateSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _publishState();
    });
  }

  void _publishState({bool? autoScrolling}) {
    final controller = _attachedController;
    if (controller == null) return;
    if (!_scroll.hasClients || !_list.isAttached) {
      controller._setState(
        DMessageScrollerState(pendingInitialScroll: _pendingInitial),
      );
      return;
    }
    final position = _scroll.position;
    final threshold = _scope!.scrollEdgeThreshold;
    final towardMin = position.pixels - position.minScrollExtent > threshold;
    final towardMax = position.maxScrollExtent - position.pixels > threshold;
    final canStart = widget.reverse ? towardMax : towardMin;
    final canEnd = widget.reverse ? towardMin : towardMax;

    if (_scope!.autoScroll && !canEnd && _mode == _ScrollerMode.free) {
      _mode = _ScrollerMode.followingEnd;
    }

    final visibility = _visibility();
    controller._setState(
      DMessageScrollerState(
        canScrollStart: canStart,
        canScrollEnd: _mode == _ScrollerMode.followingEnd ? false : canEnd,
        autoScrolling: autoScrolling ?? _programmaticDepth > 0,
        pendingInitialScroll: _pendingInitial,
        followingLiveEdge: _mode == _ScrollerMode.followingEnd,
        currentAnchorId: visibility.$1,
        visibleMessageIds: visibility.$2,
      ),
    );
  }

  (String?, List<String>) _visibility() {
    final range = _list.visibleRange;
    if (range == null || _ids.isEmpty) return (null, const []);
    final first = range.$1.clamp(0, _ids.length - 1);
    final last = range.$2.clamp(0, _ids.length - 1);
    final visible = <String>[];
    if (first <= last) {
      for (var index = first; index <= last; index++) {
        visible.add(_ids[index]);
      }
    } else {
      for (var index = first; index >= last; index--) {
        visible.add(_ids[index]);
      }
    }

    String? currentAnchor;
    if (!widget.reverse) {
      final readingLine =
          _scroll.offset + _scope!.scrollMargin + _scope!.previousItemPeek + .5;
      for (var index = 0; index < _anchors.length; index++) {
        if (!_anchors[index]) continue;
        final top = _rowTop(_ids[index]);
        if (top == null || top <= readingLine - _scroll.offset) {
          currentAnchor = _ids[index];
        } else {
          break;
        }
      }
    } else {
      for (var index = first; index < _anchors.length; index++) {
        if (_anchors[index]) {
          currentAnchor = _ids[index];
          break;
        }
      }
    }
    return (currentAnchor, List.unmodifiable(visible));
  }

  Key? _findIndexKey(Key key) {
    if (key is! _DMessageScrollerRowKey) return null;
    return key;
  }

  int? _findChildIndex(Key key) {
    final rowKey = _findIndexKey(key) as _DMessageScrollerRowKey?;
    if (rowKey == null) return null;
    final index = _ids.indexOf(rowKey.id);
    return index < 0 ? null : index;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_focus.hasPrimaryFocus || event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        (keyboard.isShiftPressed &&
            event.logicalKey != LogicalKeyboardKey.space)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    double? delta;
    if (key == LogicalKeyboardKey.home) {
      scrollToStart();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      scrollToEnd();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      delta = 40;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -40;
    } else if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      delta = _scroll.position.viewportDimension * .9;
      if (key == LogicalKeyboardKey.space && keyboard.isShiftPressed) {
        delta = -delta;
      }
    } else if (key == LogicalKeyboardKey.pageUp) {
      delta = -_scroll.position.viewportDimension * .9;
    } else {
      return KeyEventResult.ignored;
    }
    _noteUserIntent();
    _performScroll(
      _scroll.offset + delta,
      DMessageScrollerScrollBehavior.smooth,
      autoScrolling: false,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final direction = Directionality.of(context);
    final padding = widget.resolvedPadding.resolve(direction);
    final physicalPadding = EdgeInsets.fromLTRB(
      padding.left,
      padding.top,
      padding.right,
      padding.bottom + _spacerExtent,
    );
    final state = _attachedController?.state ?? const DMessageScrollerState();

    Widget viewport = SuperListView.builder(
      key: const ValueKey('d-message-scroller-list'),
      controller: _scroll,
      listController: _list,
      reverse: widget.reverse,
      physics: widget.physics,
      restorationId: widget.restorationId,
      cacheExtent: widget.cacheExtent,
      padding: physicalPadding,
      itemCount: widget.itemCount,
      findChildIndexCallback: widget.preserveChildIdentity
          ? _findChildIndex
          : null,
      itemBuilder: (context, index) {
        final gap = index + 1 < widget.itemCount ? widget.resolvedGap : 0.0;
        return KeyedSubtree(
          key: widget.preserveChildIdentity
              ? _DMessageScrollerRowKey(widget.itemId(index))
              : null,
          child: Semantics(
            container: true,
            child: SizedBox(
              key: widget.preserveChildIdentity
                  ? _rowKeys[widget.itemId(index)]
                  : null,
              child: Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: widget.buildItem(context, index),
              ),
            ),
          ),
        );
      },
    );

    if (widget.scrollableBuilder case final builder?) {
      viewport = builder(context, _scroll, viewport);
    }

    if (widget.styled) {
      viewport = DScrollBar(
        controller: _scroll,
        thumbVisibility: widget.showScrollbar && !state.autoScrolling,
        child: viewport,
      );
    }
    viewport = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleContentChange();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: viewport,
      ),
    );
    viewport = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _noteUserIntent(),
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) _noteUserIntent();
      },
      child: viewport,
    );
    viewport = KeyedSubtree(
      key: _viewportKey,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: Semantics(
          container: true,
          liveRegion: !widget.resolvedBusy,
          child: viewport,
        ),
      ),
    );
    viewport = FocusableActionDetector(
      focusNode: _focus,
      onShowFocusHighlight: (value) {
        if (value != _focusVisible) setState(() => _focusVisible = value);
      },
      child: CustomPaint(
        foregroundPainter: _focusVisible
            ? _MessageScrollerFocusRing(
                color: tokens.focusRing.withValues(
                  alpha: tokens.focusRing.a * .5,
                ),
                radius: BorderRadius.circular(tokens.radius * .8),
              )
            : null,
        child: viewport,
      ),
    );
    viewport = Focus(
      canRequestFocus: false,
      onKeyEvent: _handleKey,
      child: viewport,
    );
    if (_pendingInitial || state.pendingInitialScroll) {
      viewport = Visibility(
        visible: false,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        maintainSemantics: false,
        child: viewport,
      );
    }
    return viewport;
  }
}

class _DMessageScrollerRowKey extends ValueKey<String> {
  const _DMessageScrollerRowKey(super.value);
  String get id => value;
}

class _MessageScrollerFocusRing extends CustomPainter {
  const _MessageScrollerFocusRing({required this.color, required this.radius});

  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final inner = radius.toRRect(Offset.zero & size);
    canvas.drawDRRect(inner.inflate(3), inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MessageScrollerFocusRing oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// Base-nova's centered start/end scroll control. Inactive controls remain
/// mounted for motion but are excluded from hit testing, focus, and semantics.
class DMessageScrollerButton extends StatelessWidget {
  const DMessageScrollerButton({
    super.key,
    this.direction = DMessageScrollerDirection.end,
    this.behavior = DMessageScrollerScrollBehavior.smooth,
    this.child,
    this.semanticLabel,
    this.onPressed,
  });

  final DMessageScrollerDirection direction;
  final DMessageScrollerScrollBehavior behavior;
  final Widget? child;
  final String? semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scope = _DMessageScrollerScope.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      left: 0,
      right: 0,
      top: direction == DMessageScrollerDirection.start ? 16 : null,
      bottom: direction == DMessageScrollerDirection.end ? 16 : null,
      child: Center(
        child: AnimatedBuilder(
          animation: scope.controller,
          builder: (context, _) {
            final active = scope.controller.state.canScroll(direction);
            final duration = reduceMotion
                ? Duration.zero
                : active
                ? const Duration(milliseconds: 200)
                : const Duration(milliseconds: 400);
            final curve = active
                ? Curves.easeOutCubic
                : const Cubic(.7, 0, .84, 0);
            final offset = direction == DMessageScrollerDirection.end
                ? const Offset(0, 1)
                : const Offset(0, -1);
            final label =
                semanticLabel ??
                (direction == DMessageScrollerDirection.end
                    ? 'Scroll to end'
                    : 'Scroll to start');
            return ExcludeSemantics(
              excluding: !active,
              child: ExcludeFocus(
                excluding: !active,
                child: IgnorePointer(
                  ignoring: !active,
                  child: AnimatedSlide(
                    duration: duration,
                    curve: curve,
                    offset: active ? Offset.zero : offset,
                    child: AnimatedScale(
                      duration: duration,
                      curve: curve,
                      scale: active ? 1 : .95,
                      child: AnimatedOpacity(
                        duration: duration,
                        curve: curve,
                        opacity: active ? 1 : 0,
                        child: DButton.iconOnly(
                          icon:
                              child ??
                              _MessageScrollerArrow(
                                up:
                                    direction ==
                                    DMessageScrollerDirection.start,
                              ),
                          tooltip: label,
                          semanticLabel: label,
                          size: DButtonSize.regular,
                          variant: DButtonVariant.secondary,
                          onPressed: active
                              ? () {
                                  onPressed?.call();
                                  if (direction ==
                                      DMessageScrollerDirection.start) {
                                    scope.controller.scrollToStart(
                                      behavior: behavior,
                                    );
                                  } else {
                                    scope.controller.scrollToEnd(
                                      behavior: behavior,
                                    );
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MessageScrollerArrow extends StatelessWidget {
  const _MessageScrollerArrow({required this.up});
  final bool up;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: up ? 3.141592653589793 : 0,
    child: CustomPaint(
      size: const Size.square(16),
      painter: _ArrowPainter(
        color: IconTheme.of(context).color ?? DTokens.of(context).foreground,
      ),
    ),
  );
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(3, 6)
      ..lineTo(8, 11)
      ..lineTo(13, 6);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => oldDelegate.color != color;
}
