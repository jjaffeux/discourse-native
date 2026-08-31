// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/post.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import 'shell_controller.dart';

typedef TopicViewportIdentity = ({
  String siteUrl,
  int topicId,
  int navigationRevision,
});
typedef TopicViewportAnchor = ({int postId, double viewportOffset});
typedef TopicViewportSeenPost = ({int postId, int postNumber, bool caughtUp});
typedef TopicViewportScrollPosition = ({
  double pixels,
  double minScrollExtent,
  double maxScrollExtent,
});
typedef TopicViewportControllers = ({
  ScrollController scroll,
  ListController list,
});
typedef TopicViewportPostFrameScheduler = void Function(VoidCallback callback);
typedef TopicViewportTimerFactory =
    TopicViewportTimer Function(Duration duration, VoidCallback callback);
typedef TopicViewportInspector =
    void Function(TopicViewportSnapshot snapshot, {required bool saveAnchor});
typedef TopicViewportControllersFactory = TopicViewportControllers Function();
typedef TopicViewportControllersDisposer =
    void Function(TopicViewportControllers controllers);
typedef TopicViewportDiagnosticRecorder =
    void Function(String name, Map<String, Object?> data);
typedef TopicViewportLayoutDiagnostics = Map<String, Object?> Function();

abstract interface class TopicViewportTimer {
  void cancel();
}

final class _DartTopicViewportTimer implements TopicViewportTimer {
  _DartTopicViewportTimer(Duration duration, VoidCallback callback)
    : _timer = Timer(duration, callback);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// The render-owned measurements needed by the viewport state machine.
///
/// The coordinator deliberately does not retain build contexts or render
/// objects. [TopicView] remains responsible for layout and translates its
/// current geometry into this narrow interface.
abstract interface class TopicViewportGeometry {
  TopicViewportAnchor? captureAnchor(
    List<int> postIds, {
    required bool hasHeader,
  });

  double? postViewportOffset(int postId);

  bool get canCorrectAnchor;

  TopicViewportScrollPosition get scrollPosition;

  void jumpToPost(int itemIndex, {required double viewportOffset});

  void jumpToPixels(double pixels);
}

final class TopicViewportGeometryCallbacks implements TopicViewportGeometry {
  const TopicViewportGeometryCallbacks({
    required TopicViewportAnchor? Function(
      List<int> postIds, {
      required bool hasHeader,
    })
    captureAnchor,
    required double? Function(int postId) postViewportOffset,
    required bool Function() canCorrectAnchor,
    required TopicViewportScrollPosition Function() scrollPosition,
    required void Function(int itemIndex, double viewportOffset) jumpToPost,
    required void Function(double pixels) jumpToPixels,
  }) : _captureAnchor = captureAnchor,
       _postViewportOffset = postViewportOffset,
       _canCorrectAnchor = canCorrectAnchor,
       _scrollPosition = scrollPosition,
       _jumpToPost = jumpToPost,
       _jumpToPixels = jumpToPixels;

  final TopicViewportAnchor? Function(
    List<int> postIds, {
    required bool hasHeader,
  })
  _captureAnchor;
  final double? Function(int postId) _postViewportOffset;
  final bool Function() _canCorrectAnchor;
  final TopicViewportScrollPosition Function() _scrollPosition;
  final void Function(int itemIndex, double viewportOffset) _jumpToPost;
  final void Function(double pixels) _jumpToPixels;

  @override
  TopicViewportAnchor? captureAnchor(
    List<int> postIds, {
    required bool hasHeader,
  }) => _captureAnchor(postIds, hasHeader: hasHeader);

  @override
  double? postViewportOffset(int postId) => _postViewportOffset(postId);

  @override
  bool get canCorrectAnchor => _canCorrectAnchor();

  @override
  TopicViewportScrollPosition get scrollPosition => _scrollPosition();

  @override
  void jumpToPost(int itemIndex, {required double viewportOffset}) =>
      _jumpToPost(itemIndex, viewportOffset);

  @override
  void jumpToPixels(double pixels) => _jumpToPixels(pixels);
}

/// Shell operations captured for one topic viewport generation.
///
/// Tests can provide these callbacks directly. Production uses [fromShell],
/// keeping the coordinator independent from widget ancestry and BuildContext.
final class TopicViewportBinding {
  const TopicViewportBinding({
    required this.owner,
    required this.identity,
    required this.tabId,
    required this.isCurrent,
    required this.currentSnapshot,
    required this.forumActive,
    required this.loadMore,
    required this.loadEarlier,
    required this.markRead,
    required this.saveAnchor,
    required this.flushAnchorPersist,
    required this.savedPostNumber,
    required this.savedPostOffset,
    required this.postNumberFor,
  });

  factory TopicViewportBinding.fromShell(
    ShellController controller,
    TopicViewportSnapshot snapshot,
  ) {
    final tabId = controller.activeTabId;
    final identity = (
      siteUrl: snapshot.siteUrl!,
      topicId: snapshot.topicId!,
      navigationRevision: snapshot.navigationRevision,
    );
    return TopicViewportBinding(
      owner: controller,
      identity: identity,
      tabId: tabId,
      isCurrent: () =>
          controller.activeTabId == tabId &&
          controller.currentInstance?.url == identity.siteUrl &&
          controller.currentTopic?.id == identity.topicId &&
          controller.topicNavigationRevision == identity.navigationRevision,
      currentSnapshot: () => TopicViewportSnapshot.from(controller),
      forumActive: () => controller.forumActive,
      loadMore: controller.loadMorePosts,
      loadEarlier: controller.loadEarlierPosts,
      markRead:
          ({
            required String siteUrl,
            required int topicId,
            required int postNumber,
            required bool caughtUp,
          }) => controller.markTopicRead(
            siteUrl,
            topicId,
            postNumber,
            caughtUp: caughtUp,
          ),
      saveAnchor: (topicId, postNumber, viewportOffset) =>
          controller.saveTopicScrollPost(
            topicId,
            postNumber,
            viewportOffset: viewportOffset,
          ),
      flushAnchorPersist: controller.flushAnchorPersist,
      savedPostNumber: () => controller.topicScrollPostNumber(identity.topicId),
      savedPostOffset: () => controller.topicScrollPostOffset(identity.topicId),
      postNumberFor: (postId) =>
          controller.store.read<Post>(identity.siteUrl, postId)?.postNumber,
    );
  }

  final Object owner;
  final TopicViewportIdentity identity;
  final String? tabId;
  final bool Function() isCurrent;
  final TopicViewportSnapshot Function() currentSnapshot;
  final bool Function() forumActive;
  final Future<void> Function() loadMore;
  final Future<void> Function() loadEarlier;
  final Future<void> Function({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    required bool caughtUp,
  })
  markRead;
  final void Function(int topicId, int postNumber, double viewportOffset)
  saveAnchor;
  final VoidCallback flushAnchorPersist;
  final int? Function() savedPostNumber;
  final double Function() savedPostOffset;
  final int? Function(int postId) postNumberFor;
}

enum TopicViewportExtentAction { none, invalidate, replace }

/// The independently changing viewport values consumed while rendering.
abstract interface class TopicViewportListenable implements Listenable {
  DateTime? get floatingDay;

  double get floatingDayOffset;

  int? get progressPosition;
}

@immutable
final class TopicViewportWindowChange {
  const TopicViewportWindowChange({
    required this.extentAction,
    required this.previousPostIds,
    required this.currentPostIds,
    required this.previousHasHeader,
    required this.hasHeader,
    required this.prepended,
    required this.appendOnly,
  });

  final TopicViewportExtentAction extentAction;
  final List<int> previousPostIds;
  final List<int> currentPostIds;
  final bool previousHasHeader;
  final bool hasHeader;
  final bool prepended;
  final bool appendOnly;

  bool get changed =>
      !listEquals(previousPostIds, currentPostIds) ||
      previousHasHeader != hasHeader;
}

/// Owns the non-rendering lifecycle of a topic's scroll viewport.
///
/// Topic identity, controller generations, queued paging, anchor restoration,
/// read dwell, and the floating overlays all change independently of the
/// surrounding shell. The widget supplies measurements through
/// [TopicViewportGeometry] and keeps responsibility for rendering them.
final class TopicViewportCoordinator extends FrameSafeNotifier
    implements TopicViewportListenable {
  TopicViewportCoordinator({
    required TopicViewportPostFrameScheduler postFrame,
    required TopicViewportGeometry geometry,
    required TopicViewportInspector inspectViewport,
    VoidCallback? listLayoutChanged,
    TopicViewportTimerFactory? timerFactory,
    DateTime Function()? clock,
    TopicViewportControllersFactory? controllersFactory,
    TopicViewportControllersDisposer? controllersDisposer,
    bool Function()? diagnosticsEnabled,
    TopicViewportDiagnosticRecorder? recordDiagnostic,
    TopicViewportLayoutDiagnostics? layoutDiagnostics,
    this.pagingThreshold = 900,
    this.readInterval = const Duration(milliseconds: 500),
  }) : _postFrame = postFrame,
       _geometry = geometry,
       _inspectViewport = inspectViewport,
       _listLayoutChanged = listLayoutChanged,
       _timerFactory = timerFactory ?? _defaultTimerFactory,
       _clock = clock ?? DateTime.now,
       _controllersFactory = controllersFactory ?? _defaultControllersFactory,
       _controllersDisposer =
           controllersDisposer ?? _defaultControllersDisposer,
       _diagnosticsEnabled = diagnosticsEnabled,
       _recordDiagnostic = recordDiagnostic,
       _layoutDiagnostics = layoutDiagnostics;

  final TopicViewportPostFrameScheduler _postFrame;
  final TopicViewportGeometry _geometry;
  final TopicViewportInspector _inspectViewport;
  final VoidCallback? _listLayoutChanged;
  final TopicViewportTimerFactory _timerFactory;
  final DateTime Function() _clock;
  final TopicViewportControllersFactory _controllersFactory;
  final TopicViewportControllersDisposer _controllersDisposer;
  final bool Function()? _diagnosticsEnabled;
  final TopicViewportDiagnosticRecorder? _recordDiagnostic;
  final TopicViewportLayoutDiagnostics? _layoutDiagnostics;
  final double pagingThreshold;
  final Duration readInterval;

  TopicViewportBinding? _binding;
  TopicViewportControllers? _controllers;
  TopicViewportSnapshot? _laidOutSnapshot;
  List<int> _laidOutPostIds = const [];
  bool _laidOutHasHeader = false;
  int _generation = 0;

  Object? _loadMoreToken;
  (String, int, int)? _loadMoreTarget;
  Object? _loadEarlierToken;
  (String, int, int)? _loadEarlierTarget;

  Object? _anchorRestoreToken;
  int? _anchorRestorePostId;
  double _anchorRestoreViewportOffset = 0;
  bool _anchorCorrectionScheduled = false;
  bool _restored = false;
  bool _restoring = false;
  bool _userDragging = false;
  bool _applyingAnchorRestore = false;

  bool _lookScheduled = false;
  bool _saveAnchorAfterLook = false;
  int? _savedAnchorPostNumber;

  DateTime? _floatingDay;
  double _floatingDayOffset = 0;
  int? _progressPosition;
  Map<int, int>? _streamIndexes;
  List<int>? _indexedStream;

  TopicViewportTimer? _readTimer;
  DateTime? _readTimerStartedAt;
  late Duration _readTimeRemaining = readInterval;
  bool _readDwellPending = false;
  bool _tickerEnabled = true;
  bool _appResumed = true;
  ({String siteUrl, int topicId, int postNumber, bool caughtUp})? _seen;
  ({String siteUrl, int topicId, int postNumber, bool caughtUp})? _visibleSeen;

  static TopicViewportTimer _defaultTimerFactory(
    Duration duration,
    VoidCallback callback,
  ) => _DartTopicViewportTimer(duration, callback);

  static TopicViewportControllers _defaultControllersFactory() =>
      (scroll: ScrollController(), list: ListController());

  static void _defaultControllersDisposer(
    TopicViewportControllers controllers,
  ) {
    controllers.scroll.dispose();
    controllers.list.dispose();
  }

  void _record(
    String name,
    Map<String, Object?> data, {
    bool includeLayout = false,
  }) {
    if (_diagnosticsEnabled?.call() != true) return;
    _recordDiagnostic?.call(name, {
      ...data,
      if (includeLayout && _layoutDiagnostics != null)
        'sliverLayout': _layoutDiagnostics(),
    });
  }

  TopicViewportBinding? get binding => _binding;
  TopicViewportIdentity? get identity => _binding?.identity;
  Object? get owner => _binding?.owner;
  ScrollController? get scrollController => _controllers?.scroll;
  ListController? get listController => _controllers?.list;
  TopicViewportSnapshot? get laidOutSnapshot => _laidOutSnapshot;
  bool get restored => _restored;
  bool get restoring => _restoring;
  bool get userDragging => _userDragging;
  bool get applyingAnchorRestore => _applyingAnchorRestore;
  int? get savedAnchorPostNumber => _savedAnchorPostNumber;
  @override
  DateTime? get floatingDay => _floatingDay;
  @override
  double get floatingDayOffset => _floatingDayOffset;
  @override
  int? get progressPosition => _progressPosition;
  Object? get anchorRestoreToken => _anchorRestoreToken;
  int? get anchorRestorePostId => _anchorRestorePostId;
  double get anchorRestoreViewportOffset => _anchorRestoreViewportOffset;
  int get generation => _generation;

  bool get _readerActive =>
      _tickerEnabled && (_binding?.forumActive() ?? false);

  /// Replaces every topic-scoped resource when identity, tab, or shell changes.
  bool bind(TopicViewportBinding binding) {
    final previous = _binding;
    if (previous != null &&
        previous.identity == binding.identity &&
        previous.tabId == binding.tabId &&
        identical(previous.owner, binding.owner)) {
      return false;
    }

    _creditReaderNow();
    _retireControllers();
    if (previous != null && !identical(previous.owner, binding.owner)) {
      previous.flushAnchorPersist();
    }

    _binding = binding;
    _generation++;
    _loadMoreToken = null;
    _loadMoreTarget = null;
    _loadEarlierToken = null;
    _loadEarlierTarget = null;
    _anchorRestoreToken = null;
    _anchorRestorePostId = null;
    _anchorRestoreViewportOffset = 0;
    _anchorCorrectionScheduled = false;
    _laidOutSnapshot = null;
    _laidOutPostIds = const [];
    _laidOutHasHeader = false;
    _restored = false;
    _restoring = false;
    _userDragging = false;
    _applyingAnchorRestore = false;
    _lookScheduled = false;
    _saveAnchorAfterLook = false;
    _savedAnchorPostNumber = null;
    _floatingDay = null;
    _floatingDayOffset = 0;
    _progressPosition = null;
    _streamIndexes = null;
    _indexedStream = null;
    _seen = null;
    _visibleSeen = null;
    _readDwellPending = false;
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readTimeRemaining = readInterval;

    final controllers = _controllersFactory();
    _controllers = controllers;
    controllers.list.addListener(onListLayoutChanged);
    onListLayoutChanged();
    return true;
  }

  bool isCurrent(TopicViewportBinding binding) =>
      !isDisposed && identical(_binding, binding) && binding.isCurrent();

  bool isCurrentOwner(Object owner, TopicViewportIdentity identity) {
    final binding = _binding;
    return binding != null &&
        identical(binding.owner, owner) &&
        binding.identity == identity &&
        isCurrent(binding);
  }

  void _retireControllers() {
    final controllers = _controllers;
    if (controllers == null) return;
    _controllers = null;
    controllers.list.removeListener(onListLayoutChanged);
    _postFrame(() => _controllersDisposer(controllers));
  }

  void updateLaidOutSnapshot(TopicViewportSnapshot snapshot) {
    _laidOutSnapshot = snapshot;
  }

  void restoreInitialPost(TopicViewportSnapshot snapshot) {
    final binding = _binding;
    if (binding == null || _restored || snapshot.loading) return;

    final index = snapshot.initialPostIndex;
    if (index == null) {
      if (snapshot.topicId == null || binding.savedPostNumber() == null) {
        _restored = true;
      }
      return;
    }
    _restored = true;
    if (index <= 0 && binding.savedPostOffset() == 0) return;

    final generation = _generation;
    _restoring = true;

    void jumpToTarget() {
      if (!_isGenerationCurrent(binding, generation)) return;
      final current = binding.currentSnapshot();
      final currentIndex = current.initialPostIndex;
      if (currentIndex == null) return;
      final postIndex = currentIndex - (current.hasEarlier ? 1 : 0);
      final target = binding.savedPostNumber();
      final postId = postIndex >= 0 && postIndex < current.postIds.length
          ? current.postIds[postIndex]
          : null;
      final viewportOffset =
          postId != null && binding.postNumberFor(postId) == target
          ? binding.savedPostOffset()
          : 0.0;
      _jumpTo(currentIndex, viewportOffset: viewportOffset);
      if (postId != null) {
        holdViewportAnchor(
          postId,
          viewportOffset,
          token: _anchorRestoreToken ?? Object(),
        );
      }
    }

    _postFrame(() {
      jumpToTarget();
      _postFrame(() {
        if (!_isGenerationCurrent(binding, generation)) return;
        jumpToTarget();
        _restoring = false;
        scheduleLook();
        scheduleLoadEarlier(binding.currentSnapshot());
      });
    });
  }

  TopicViewportWindowChange updateWindow(
    TopicViewportSnapshot snapshot, {
    required bool hasHeader,
  }) {
    final previousPostIds = _laidOutPostIds;
    final previousHasHeader = _laidOutHasHeader;
    final samePosts = listEquals(previousPostIds, snapshot.postIds);
    final previousFirstIndex = previousPostIds.isEmpty
        ? -1
        : snapshot.postIds.indexOf(previousPostIds.first);
    final prepended = previousFirstIndex > 0;
    var appendOnly = previousPostIds.length <= snapshot.postIds.length;
    if (appendOnly) {
      for (var index = 0; index < previousPostIds.length; index++) {
        if (previousPostIds[index] != snapshot.postIds[index]) {
          appendOnly = false;
          break;
        }
      }
    }
    final headerChanged = previousHasHeader != hasHeader && samePosts;
    final extentAction =
        previousPostIds.isEmpty || (appendOnly && !headerChanged)
        ? TopicViewportExtentAction.none
        : prepended || headerChanged
        ? TopicViewportExtentAction.invalidate
        : TopicViewportExtentAction.replace;
    final shouldRestoreAnchor =
        previousPostIds.isNotEmpty &&
        !_restoring &&
        (prepended || headerChanged);
    final anchor = shouldRestoreAnchor
        ? _geometry.captureAnchor(previousPostIds, hasHeader: previousHasHeader)
        : null;

    _laidOutPostIds = List.of(snapshot.postIds);
    _laidOutHasHeader = hasHeader;

    if (anchor != null) {
      _restoreAfterWindowChange(anchor);
    } else if (shouldRestoreAnchor) {
      _record('viewport.prependAnchor.unavailable', {
        'prepended': prepended,
        'headerChanged': headerChanged,
      }, includeLayout: true);
    }

    return TopicViewportWindowChange(
      extentAction: extentAction,
      previousPostIds: previousPostIds,
      currentPostIds: snapshot.postIds,
      previousHasHeader: previousHasHeader,
      hasHeader: hasHeader,
      prepended: prepended,
      appendOnly: appendOnly,
    );
  }

  void _restoreAfterWindowChange(TopicViewportAnchor anchor) {
    final binding = _binding;
    if (binding == null) return;
    final generation = _generation;
    final token = Object();
    holdViewportAnchor(anchor.postId, anchor.viewportOffset, token: token);
    _restoring = true;

    void restore() {
      if (!identical(_anchorRestoreToken, token) ||
          !_isGenerationCurrent(binding, generation)) {
        return;
      }
      if (_userDragging) {
        cancelViewportAnchor();
        _restoring = false;
        return;
      }
      if (_laidOutSnapshot?.postIds.contains(anchor.postId) != true) return;
      correctViewportAnchor();
    }

    _postFrame(() {
      restore();
      _postFrame(() {
        restore();
        if (!identical(_anchorRestoreToken, token) ||
            !_isGenerationCurrent(binding, generation)) {
          return;
        }
        _restoring = false;
        scheduleLook();
        scheduleLoadEarlier(binding.currentSnapshot());
      });
    });
  }

  void beginRestoration() {
    cancelViewportAnchor();
    _restoring = true;
  }

  void finishRestoration({bool saveAnchor = false}) {
    _restoring = false;
    scheduleLook(saveAnchor: saveAnchor);
  }

  void setUserDragging(bool dragging) {
    _userDragging = dragging;
  }

  void cancelAnchorForExternalScroll() {
    if (_applyingAnchorRestore || _anchorRestoreToken == null) return;
    cancelViewportAnchor();
    _restoring = false;
  }

  void holdViewportAnchor(
    int postId,
    double viewportOffset, {
    required Object token,
  }) {
    _anchorRestoreToken = token;
    _anchorRestorePostId = postId;
    _anchorRestoreViewportOffset = viewportOffset;
    _record('viewport.anchor.held', {
      'postId': postId,
      'viewportOffset': viewportOffset,
    });
    scheduleAnchorCorrection();
  }

  void cancelViewportAnchor() {
    if (_anchorRestoreToken != null) {
      _record('viewport.anchor.cancelled', {
        'postId': _anchorRestorePostId,
        'viewportOffset': _anchorRestoreViewportOffset,
        'userDragging': _userDragging,
      });
    }
    _anchorRestoreToken = null;
    _anchorRestorePostId = null;
    _anchorCorrectionScheduled = false;
  }

  void scheduleAnchorCorrection() {
    if (_anchorRestoreToken == null || _anchorCorrectionScheduled) return;
    final generation = _generation;
    _anchorCorrectionScheduled = true;
    _record('viewport.anchor.correctionScheduled', {
      'postId': _anchorRestorePostId,
    });
    _postFrame(() {
      if (generation != _generation || isDisposed) return;
      _anchorCorrectionScheduled = false;
      correctViewportAnchor();
    });
  }

  void correctViewportAnchor() {
    final token = _anchorRestoreToken;
    final postId = _anchorRestorePostId;
    final binding = _binding;
    final snapshot = _laidOutSnapshot;
    if (token == null ||
        postId == null ||
        binding == null ||
        snapshot == null ||
        !isCurrent(binding) ||
        !_geometry.canCorrectAnchor) {
      return;
    }
    if (_userDragging) {
      cancelViewportAnchor();
      _restoring = false;
      return;
    }

    final currentOffset = _geometry.postViewportOffset(postId);
    if (currentOffset == null) {
      final postIndex = snapshot.postIds.indexOf(postId);
      if (postIndex < 0) return;
      final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
      _applyingAnchorRestore = true;
      try {
        _record('viewport.anchor.jumpToItem', {
          'postId': postId,
          'postIndex': postIndex,
          'leadingItemCount': leading,
          'viewportOffset': _anchorRestoreViewportOffset,
        });
        _jumpTo(
          postIndex + leading,
          viewportOffset: _anchorRestoreViewportOffset,
        );
      } finally {
        _applyingAnchorRestore = false;
      }
      return;
    }

    final position = _geometry.scrollPosition;
    final target =
        (position.pixels + currentOffset - _anchorRestoreViewportOffset)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if ((target - position.pixels).abs() < 0.5) {
      _record('viewport.anchor.aligned', {
        'postId': postId,
        'pixels': position.pixels,
        'currentViewportOffset': currentOffset,
        'requestedViewportOffset': _anchorRestoreViewportOffset,
      });
      return;
    }
    _applyingAnchorRestore = true;
    try {
      _record('viewport.anchor.correcting', {
        'postId': postId,
        'fromPixels': position.pixels,
        'toPixels': target,
        'currentViewportOffset': currentOffset,
        'requestedViewportOffset': _anchorRestoreViewportOffset,
      });
      _geometry.jumpToPixels(target);
    } finally {
      _applyingAnchorRestore = false;
    }
  }

  void _jumpTo(int itemIndex, {required double viewportOffset}) {
    if (!_geometry.canCorrectAnchor) return;
    _geometry.jumpToPost(itemIndex, viewportOffset: viewportOffset);
  }

  void onListLayoutChanged() {
    if (isDisposed) return;
    _listLayoutChanged?.call();
    scheduleLook();
    scheduleAnchorCorrection();
  }

  void scheduleLook({bool saveAnchor = false}) {
    _saveAnchorAfterLook = _saveAnchorAfterLook || saveAnchor;
    if (_lookScheduled) return;
    final generation = _generation;
    _lookScheduled = true;
    _postFrame(() {
      if (generation != _generation || isDisposed) return;
      _lookScheduled = false;
      final saveAnchor = _saveAnchorAfterLook;
      _saveAnchorAfterLook = false;
      final binding = _binding;
      final snapshot = _laidOutSnapshot;
      if (binding == null || snapshot == null || !isCurrent(binding)) return;
      _inspectViewport(snapshot, saveAnchor: saveAnchor);
      schedulePagingForViewport(snapshot);
    });
  }

  double thresholdFor(ScrollMetrics metrics) =>
      math.max(pagingThreshold, metrics.viewportDimension);

  void schedulePagingForViewport(TopicViewportSnapshot snapshot) {
    final scroll = scrollController;
    if (_restoring || scroll == null || !scroll.hasClients) return;
    final position = scroll.position;
    if (!position.hasContentDimensions) return;
    final threshold = thresholdFor(position);
    if (position.extentBefore < threshold) scheduleLoadEarlier(snapshot);
    if (position.extentAfter < threshold) scheduleLoadMore(snapshot);
  }

  void handleScroll(
    ScrollNotification notification,
    TopicViewportSnapshot snapshot,
  ) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userDragging = true;
    } else if (notification is ScrollEndNotification) {
      _userDragging = false;
    }
    if (notification is ScrollUpdateNotification) {
      cancelAnchorForExternalScroll();
    }
    scheduleLook(saveAnchor: notification is ScrollEndNotification);

    if (notification is ScrollStartNotification && !_restoring) {
      allowLoadEarlierRetry(snapshot);
      allowLoadMoreRetry(snapshot);
    }
    final threshold = thresholdFor(notification.metrics);
    if (notification.metrics.extentBefore < threshold) {
      scheduleLoadEarlier(snapshot);
    } else if (!snapshot.loadingEarlier) {
      allowLoadEarlierRetry(snapshot);
    }
    if (notification.metrics.extentAfter < threshold) {
      scheduleLoadMore(snapshot);
    } else if (!snapshot.loadingMore) {
      allowLoadMoreRetry(snapshot);
    }
  }

  void scheduleLoadMore(TopicViewportSnapshot snapshot) {
    final binding = _binding;
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    if (binding == null ||
        siteUrl == null ||
        topicId == null ||
        !snapshot.hasMore ||
        snapshot.loadingMore) {
      return;
    }

    final target = (siteUrl, topicId, snapshot.postIds.length);
    if (_loadMoreTarget == target) return;
    final token = Object();
    final generation = _generation;
    _loadMoreToken = token;
    _loadMoreTarget = target;
    _record('paging.newer.scheduled', {
      'topicId': topicId,
      'loadedPostCount': snapshot.postIds.length,
    }, includeLayout: true);
    _postFrame(() {
      if (!identical(_loadMoreToken, token) || generation != _generation) {
        return;
      }
      _loadMoreToken = null;
      if (!isCurrent(binding) || binding.currentSnapshot() != snapshot) {
        if (_loadMoreTarget == target) _loadMoreTarget = null;
        _record('paging.newer.cancelled', {
          'topicId': topicId,
          'loadedPostCount': snapshot.postIds.length,
        });
        return;
      }
      _record('paging.newer.dispatched', {
        'topicId': topicId,
        'loadedPostCount': snapshot.postIds.length,
      });
      unawaited(binding.loadMore());
    });
  }

  void allowLoadMoreRetry(TopicViewportSnapshot snapshot) {
    if (_loadMoreToken != null || !snapshot.hasMore || snapshot.loadingMore) {
      return;
    }
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    if (siteUrl == null || topicId == null) return;
    final target = (siteUrl, topicId, snapshot.postIds.length);
    if (_loadMoreTarget == target) {
      _loadMoreTarget = null;
      _record('paging.newer.retryArmed', {
        'topicId': topicId,
        'loadedPostCount': snapshot.postIds.length,
      });
    }
  }

  void scheduleLoadEarlier(TopicViewportSnapshot snapshot) {
    final binding = _binding;
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    final scroll = scrollController;
    if (binding == null ||
        siteUrl == null ||
        topicId == null ||
        snapshot.postIds.isEmpty ||
        !snapshot.hasEarlier ||
        snapshot.loadingEarlier ||
        _restoring ||
        scroll == null ||
        !scroll.hasClients) {
      return;
    }

    final position = scroll.position;
    if (!position.hasContentDimensions) {
      final generation = _generation;
      _postFrame(() {
        if (generation != _generation || !identical(scrollController, scroll)) {
          return;
        }
        scheduleLoadEarlier(snapshot);
      });
      return;
    }
    if (position.extentBefore >= thresholdFor(position)) return;

    final target = (siteUrl, topicId, snapshot.postIds.first);
    if (_loadEarlierTarget == target) return;
    final token = Object();
    final generation = _generation;
    _loadEarlierToken = token;
    _loadEarlierTarget = target;
    _record('paging.earlier.scheduled', {
      'topicId': topicId,
      'firstLoadedPostId': snapshot.postIds.first,
      'loadedPostCount': snapshot.postIds.length,
    }, includeLayout: true);
    _postFrame(() {
      if (!identical(_loadEarlierToken, token) || generation != _generation) {
        return;
      }
      _loadEarlierToken = null;
      if (_restoring ||
          !isCurrent(binding) ||
          binding.currentSnapshot() != snapshot) {
        if (_loadEarlierTarget == target) _loadEarlierTarget = null;
        _record('paging.earlier.cancelled', {
          'topicId': topicId,
          'firstLoadedPostId': snapshot.postIds.first,
        });
        return;
      }
      _record('paging.earlier.dispatched', {
        'topicId': topicId,
        'firstLoadedPostId': snapshot.postIds.first,
      });
      unawaited(binding.loadEarlier());
    });
  }

  void allowLoadEarlierRetry(TopicViewportSnapshot snapshot) {
    if (_loadEarlierToken != null ||
        !snapshot.hasEarlier ||
        snapshot.loadingEarlier) {
      return;
    }
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    if (siteUrl == null || topicId == null || snapshot.postIds.isEmpty) return;
    final target = (siteUrl, topicId, snapshot.postIds.first);
    if (_loadEarlierTarget == target) {
      _loadEarlierTarget = null;
      _record('paging.earlier.retryArmed', {
        'topicId': topicId,
        'firstLoadedPostId': snapshot.postIds.first,
      });
    }
  }

  void recordObservation({
    required TopicViewportSnapshot snapshot,
    required bool saveAnchor,
    TopicViewportSeenPost? leading,
    TopicViewportSeenPost? visible,
    TopicViewportSeenPost? readable,
  }) {
    final binding = _binding;
    if (binding == null || !_restored || _restoring) return;

    if (leading != null &&
        (saveAnchor || _savedAnchorPostNumber != leading.postNumber)) {
      final viewportOffset = _geometry.postViewportOffset(leading.postId);
      if (viewportOffset != null) {
        binding.saveAnchor(
          snapshot.topicId!,
          leading.postNumber,
          viewportOffset,
        );
        _savedAnchorPostNumber = leading.postNumber;
      }
    }

    _visibleSeen = visible == null
        ? null
        : (
            siteUrl: snapshot.siteUrl!,
            topicId: snapshot.topicId!,
            postNumber: visible.postNumber,
            caughtUp: visible.caughtUp,
          );
    if (visible != null) {
      final streamIndex = _streamIndex(snapshot.streamIds, visible.postId);
      if (streamIndex >= 0) _setProgressPosition(streamIndex + 1);
    }

    if (readable != null) {
      final seen = (
        siteUrl: snapshot.siteUrl!,
        topicId: snapshot.topicId!,
        postNumber: readable.postNumber,
        caughtUp: readable.caughtUp,
      );
      if (seen == _seen) return;
      _seen = seen;
      _startReadDwell(readInterval);
      return;
    }

    _seen = null;
    _readDwellPending = false;
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readTimeRemaining = readInterval;
  }

  int _streamIndex(List<int> streamIds, int postId) {
    if (!identical(_indexedStream, streamIds)) {
      _indexedStream = streamIds;
      final indexes = <int, int>{};
      for (var index = 0; index < streamIds.length; index++) {
        indexes.putIfAbsent(streamIds[index], () => index);
      }
      _streamIndexes = indexes;
    }
    return _streamIndexes?[postId] ?? -1;
  }

  void updateFloatingDay(DateTime? day, double offset) {
    if (_floatingDay == day && (_floatingDayOffset - offset).abs() < 0.1) {
      return;
    }
    _floatingDay = day;
    _floatingDayOffset = offset;
    notifySafely();
  }

  void _setProgressPosition(int position) {
    if (_progressPosition == position) return;
    _progressPosition = position;
    notifySafely();
  }

  void setTickerEnabled(bool enabled) {
    if (_tickerEnabled == enabled) return;
    _tickerEnabled = enabled;
    if (_readerActive) {
      if (_readDwellPending && _seen != null && _readTimer == null) {
        _startReadDwell(_readTimeRemaining);
      }
    } else {
      _pauseReadDwell();
    }
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) {
      if (_readerActive &&
          _readDwellPending &&
          _seen != null &&
          _readTimer == null) {
        _startReadDwell(_readTimeRemaining);
      }
      return;
    }
    if (!_readerActive) {
      _pauseReadDwell();
      return;
    }
    _creditReaderNow(leavingForeground: true);
  }

  void _startReadDwell(Duration duration) {
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readTimeRemaining = duration;
    _readDwellPending = true;
    if (!_readerActive || !_appResumed) return;
    _readTimerStartedAt = _clock();
    _readTimer = _timerFactory(duration, _creditReaderFromTimer);
  }

  void _pauseReadDwell() {
    final timer = _readTimer;
    final startedAt = _readTimerStartedAt;
    if (timer == null || startedAt == null) return;
    final elapsed = _clock().difference(startedAt);
    final remaining = _readTimeRemaining - elapsed;
    _readTimeRemaining = remaining > Duration.zero ? remaining : Duration.zero;
    timer.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
  }

  void _creditReaderFromTimer() {
    if (!_readerActive || !_appResumed) {
      _readTimer?.cancel();
      _readTimer = null;
      _readTimerStartedAt = null;
      _readTimeRemaining = readInterval;
      _readDwellPending = _seen != null;
      return;
    }
    _creditReaderNow();
  }

  void _creditReaderNow({bool leavingForeground = false}) {
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readTimeRemaining = readInterval;
    _readDwellPending = false;

    final seen = leavingForeground ? _visibleSeen ?? _seen : _seen;
    final binding = _binding;
    if (seen == null || binding == null || !_readerActive) return;
    if (!leavingForeground && !_appResumed) return;

    unawaited(
      Future<void>.microtask(
        () => binding.markRead(
          siteUrl: seen.siteUrl,
          topicId: seen.topicId,
          postNumber: seen.postNumber,
          caughtUp: seen.caughtUp,
        ),
      ),
    );
  }

  bool _isGenerationCurrent(TopicViewportBinding binding, int generation) =>
      generation == _generation && isCurrent(binding);

  @override
  void dispose() {
    if (isDisposed) return;
    _generation++;
    _creditReaderNow();
    _binding?.flushAnchorPersist();
    _binding = null;
    _loadMoreToken = null;
    _loadEarlierToken = null;
    _anchorRestoreToken = null;
    _readTimer?.cancel();
    _readTimer = null;
    _retireControllers();
    super.dispose();
  }
}

@immutable
final class TopicViewportSnapshot {
  const TopicViewportSnapshot({
    required this.topicId,
    required this.topic,
    required this.siteUrl,
    required this.postIds,
    required this.streamIds,
    required this.loading,
    required this.loadingMore,
    required this.loadingEarlier,
    required this.hasMore,
    required this.hasEarlier,
    required this.initialPostIndex,
    required this.recommendations,
    required this.summary,
    required this.summaryLoading,
    required this.readTimeWordCount,
    required this.showTimeGapDays,
    required this.navigationRevision,
  });

  factory TopicViewportSnapshot.from(ShellController controller) {
    final postIds = controller.currentPostIds;
    final siteUrl = controller.currentInstance?.url;
    final topicId = controller.currentContent?.topicId;
    final target = topicId == null
        ? null
        : controller.topicScrollPostNumber(topicId);
    final hasEarlier = controller.currentTopicHasEarlier;
    int? initialPostIndex;
    if (siteUrl != null && target != null) {
      for (var index = 0; index < postIds.length; index++) {
        final post = controller.store.read<Post>(siteUrl, postIds[index]);
        // If the named post has since been deleted, reveal the next visible
        // one rather than dropping the reader at the start of the window.
        if (post != null && post.postNumber >= target) {
          initialPostIndex = index + (hasEarlier ? 1 : 0);
          break;
        }
      }
    }

    return TopicViewportSnapshot(
      topicId: controller.currentTopic?.id,
      topic: controller.currentTopic,
      siteUrl: siteUrl,
      postIds: postIds,
      streamIds: controller.currentTopicStreamIds,
      loading: controller.currentTopicLoading,
      loadingMore: controller.loadingMorePosts,
      loadingEarlier: controller.loadingEarlierPosts,
      hasMore: controller.currentTopicHasMore,
      hasEarlier: hasEarlier,
      initialPostIndex: initialPostIndex,
      recommendations: controller.currentTopic?.recommendations,
      summary: controller.currentTopicSummary,
      summaryLoading: controller.currentTopicSummaryLoading,
      readTimeWordCount: controller.currentSiteConfig.readTimeWordCount,
      showTimeGapDays: siteUrl == null
          ? SiteConfig.defaultShowTimeGapDays
          : controller.siteConfigFor(siteUrl).showTimeGapDays,
      navigationRevision: controller.topicNavigationRevision,
    );
  }

  final int? topicId;
  final TopicDetail? topic;
  final String? siteUrl;
  final List<int> postIds;
  final List<int> streamIds;
  final bool loading;
  final bool loadingMore;
  final bool loadingEarlier;
  final bool hasMore;
  final bool hasEarlier;
  final int? initialPostIndex;
  final TopicRecommendations? recommendations;
  final bool summary;
  final bool summaryLoading;
  final int readTimeWordCount;
  final int showTimeGapDays;
  final int navigationRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicViewportSnapshot &&
          topicId == other.topicId &&
          identical(topic, other.topic) &&
          siteUrl == other.siteUrl &&
          listEquals(postIds, other.postIds) &&
          listEquals(streamIds, other.streamIds) &&
          loading == other.loading &&
          loadingMore == other.loadingMore &&
          loadingEarlier == other.loadingEarlier &&
          hasMore == other.hasMore &&
          hasEarlier == other.hasEarlier &&
          recommendations == other.recommendations &&
          summary == other.summary &&
          summaryLoading == other.summaryLoading &&
          readTimeWordCount == other.readTimeWordCount &&
          showTimeGapDays == other.showTimeGapDays &&
          navigationRevision == other.navigationRevision;

  @override
  int get hashCode => Object.hash(
    topicId,
    identityHashCode(topic),
    siteUrl,
    Object.hashAll(postIds),
    Object.hashAll(streamIds),
    loading,
    loadingMore,
    loadingEarlier,
    hasMore,
    hasEarlier,
    recommendations,
    summary,
    summaryLoading,
    readTimeWordCount,
    showTimeGapDays,
    navigationRevision,
  );
}
