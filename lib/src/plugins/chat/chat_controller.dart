// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../data/discourse_api_contracts.dart'
    show SiteLookupException, SiteLookupFailure, WriteException, WriteFailure;
import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../models/bookmark.dart';
import '../../models/composer_upload.dart';
import '../../models/discourse_user.dart';
import '../../models/json.dart';
import '../../models/post_flag.dart';
import '../../models/site_config.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/live_channels.dart';
import 'chat_api.dart';
import 'chat_channel.dart';
import 'chat_direct_message_search.dart';
import 'chat_live_sync_coordinator.dart';
import 'chat_message.dart';
import 'chat_message_timeline.dart';
import 'chat_pin.dart';
import 'chat_plugin_data.dart';
import 'chat_preview.dart';
import 'chat_reactors.dart';
import 'chat_send_coordinator.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';
import 'chat_wire.dart';

typedef _ChatReactionWriteKey = ({String siteUrl, int messageId, String emoji});
typedef _ChatReactorsKey = ({
  String siteUrl,
  int channelId,
  int messageId,
  String? filter,
});
typedef ChatNotificationsDelta = void Function(String siteUrl, int delta);

/// The part of an unsent Chat message that can safely survive its composer
/// widget being unmounted. Drawer collapse and close both remove the composer
/// from the tree, while the Chat session itself remains alive.
@immutable
class ChatComposerDraft {
  ChatComposerDraft({
    required this.raw,
    required Iterable<ComposerUploadResult> uploads,
  }) : uploads = List.unmodifiable(uploads);

  final String raw;
  final List<ComposerUploadResult> uploads;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatComposerDraft ||
        other.raw != raw ||
        other.uploads.length != uploads.length) {
      return false;
    }
    for (var index = 0; index < uploads.length; index++) {
      if (!_sameUpload(uploads[index], other.uploads[index])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    raw,
    Object.hashAll(
      uploads.map(
        (upload) => Object.hash(
          upload.id,
          upload.originalFilename,
          upload.shortUrl,
          upload.url,
          upload.width,
          upload.height,
          upload.thumbnailWidth,
          upload.thumbnailHeight,
          upload.thumbnailUrl,
        ),
      ),
    ),
  );

  static bool _sameUpload(
    ComposerUploadResult first,
    ComposerUploadResult second,
  ) =>
      first.id == second.id &&
      first.originalFilename == second.originalFilename &&
      first.shortUrl == second.shortUrl &&
      first.url == second.url &&
      first.width == second.width &&
      first.height == second.height &&
      first.thumbnailWidth == second.thumbnailWidth &&
      first.thumbnailHeight == second.thumbnailHeight &&
      first.thumbnailUrl == second.thumbnailUrl;
}

@immutable
class ChatPinsState {
  const ChatPinsState({
    this.pins = const [],
    this.loading = false,
    this.fetched = false,
    this.error,
  });

  final List<ChatPin> pins;
  final bool loading;
  final bool fetched;
  final String? error;

  ChatPinsState copyWith({
    List<ChatPin>? pins,
    bool? loading,
    bool? fetched,
    String? error,
    bool clearError = false,
  }) => ChatPinsState(
    pins: pins ?? this.pins,
    loading: loading ?? this.loading,
    fetched: fetched ?? this.fetched,
    error: clearError ? null : error ?? this.error,
  );
}

@immutable
class ChatHeaderIndicator {
  const ChatHeaderIndicator._({this.urgentCount, this.unread = false});

  static const none = ChatHeaderIndicator._();
  static const dot = ChatHeaderIndicator._(unread: true);

  const ChatHeaderIndicator.urgent(int count) : this._(urgentCount: count);

  final int? urgentCount;
  final bool unread;

  bool get isVisible => urgentCount != null || unread;

  /// Core caps the header number, but not the underlying count, at 99.
  String? get label => switch (urgentCount) {
    null => null,
    > 99 => '99+',
    final count => '$count',
  };
}

/// Holds channel ordering while canonical messages live in the [Store].
@immutable
class ChatStreamState {
  const ChatStreamState({
    this.messageIds = const [],
    this.localMessageIds = const [],
    this.loading = false,
    this.loadingOlder = false,
    this.loadingNewer = false,
    this.canLoadMorePast = false,
    this.canLoadMoreFuture = false,
    this.pendingNewMessages = 0,
    this.fetchedOnce = false,
    this.fetches = 0,
    this.lastReadOnOpen,
    this.anchorMessageId,
    this.notice,
    this.error,
    this.threadUnavailable = false,
    this.revision = 0,
  });

  /// Oldest first and contiguous; paging can only extend either edge.
  final List<int> messageIds;

  /// Negative local IDs kept outside the contiguous canonical paging window.
  final List<int> localMessageIds;

  final bool loading;

  final bool loadingOlder;

  final bool loadingNewer;

  final bool canLoadMorePast;

  /// True only for a window anchored behind the present.
  final bool canLoadMoreFuture;

  /// Live replies parked beyond an anchored, contiguous window.
  final int pendingNewMessages;

  /// Distinguishes an empty channel from one not fetched yet.
  final bool fetchedOnce;

  /// Changes only when replacing the window, cueing the view to re-anchor.
  final int fetches;

  /// Fetch-time snapshot so the unread divider does not move with read receipts.
  final int? lastReadOnOpen;

  /// May target an exact reply without moving the pinned unread divider.
  final int? anchorMessageId;

  final String? notice;

  final String? error;

  /// Set only for authoritative 403/404 responses, not transport failures.
  final bool threadUnavailable;

  /// Invalidates grouped projections when a record changes without an ID change.
  final int revision;

  bool get isEmpty =>
      fetchedOnce &&
      error == null &&
      messageIds.isEmpty &&
      localMessageIds.isEmpty;

  int? get oldestId => messageIds.firstOrNull;

  int? get newestId => messageIds.lastOrNull;

  bool get atPresent => !canLoadMoreFuture && pendingNewMessages == 0;

  ChatStreamState copyWith({
    List<int>? messageIds,
    List<int>? localMessageIds,
    bool? loading,
    bool? loadingOlder,
    bool? loadingNewer,
    bool? canLoadMorePast,
    bool? canLoadMoreFuture,
    int? pendingNewMessages,
    bool? fetchedOnce,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    bool? threadUnavailable,
    int? revision,
  }) => ChatStreamState(
    messageIds: messageIds ?? this.messageIds,
    localMessageIds: localMessageIds ?? this.localMessageIds,
    loading: loading ?? this.loading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    loadingNewer: loadingNewer ?? this.loadingNewer,
    canLoadMorePast: canLoadMorePast ?? this.canLoadMorePast,
    canLoadMoreFuture: canLoadMoreFuture ?? this.canLoadMoreFuture,
    pendingNewMessages: pendingNewMessages ?? this.pendingNewMessages,
    fetchedOnce: fetchedOnce ?? this.fetchedOnce,
    // These remain tied to the fetch that built this window.
    fetches: fetches,
    lastReadOnOpen: lastReadOnOpen,
    anchorMessageId: anchorMessageId,
    notice: clearNotice ? null : (notice ?? this.notice),
    error: clearError ? null : (error ?? this.error),
    threadUnavailable: threadUnavailable ?? this.threadUnavailable,
    revision: revision ?? this.revision,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatStreamState &&
          listEquals(other.messageIds, messageIds) &&
          listEquals(other.localMessageIds, localMessageIds) &&
          other.loading == loading &&
          other.loadingOlder == loadingOlder &&
          other.loadingNewer == loadingNewer &&
          other.canLoadMorePast == canLoadMorePast &&
          other.canLoadMoreFuture == canLoadMoreFuture &&
          other.pendingNewMessages == pendingNewMessages &&
          other.fetchedOnce == fetchedOnce &&
          other.fetches == fetches &&
          other.lastReadOnOpen == lastReadOnOpen &&
          other.anchorMessageId == anchorMessageId &&
          other.notice == notice &&
          other.error == error &&
          other.threadUnavailable == threadUnavailable &&
          other.revision == revision;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(messageIds),
    Object.hashAll(localMessageIds),
    loading,
    loadingOlder,
    loadingNewer,
    canLoadMorePast,
    canLoadMoreFuture,
    pendingNewMessages,
    fetchedOnce,
    fetches,
    lastReadOnOpen,
    anchorMessageId,
    notice,
    error,
    threadUnavailable,
    revision,
  );
}

enum _ChatWindowFetchResult { loaded, missingTarget, failed, cancelled }

/// Owns chat requests and ordering; records and row-level notifications live
/// in the [Store] to avoid rebuilding the host shell.
class ChatController extends FrameSafeNotifier {
  ChatController({
    required this.api,
    required PluginRequestHost requests,
    required Store store,
    DiscourseUser? Function(String siteUrl)? currentUserFor,
    SiteConfig Function(String siteUrl)? siteConfigFor,
    ChatPreviewEngine? previewEngine,
    this.reporter = const PluginDiagnosticsReporter.noop(),
    this.onChatNotificationsDelta,
    this.onSiteUnreachable,
    this.minimumWindowRefreshInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    ChatSendCoordinatorFactory? sendCoordinatorFactory,
    ChatMessageContext? Function(String siteUrl)? messageContextFor,
  }) : assert(minimumWindowRefreshInterval >= Duration.zero),
       _requests = requests,
       _store = store,
       _currentUserFor = currentUserFor ?? _noCurrentUser,
       _siteConfigFor = siteConfigFor ?? _unknownSiteConfig,
       _previewEngine = previewEngine ?? ChatPreviewEngine(),
       _clock = clock ?? DateTime.now {
    final sendHost = ChatSendCoordinatorHost(
      isDisposed: () => isDisposed,
      canSend: canSendMessageTo,
      currentUserFor: _currentUserFor,
      projectPreview: _projectPreview,
      stage: _stageOutgoing,
      markSent: _markOutgoingSent,
      markFailed: _markOutgoingFailed,
      onSent: _onOutgoingSent,
      hasUnsettledMessages: _hasUnsettledOutgoingMessages,
      reconcileSentEvent: _applySendMessage,
      messageContextFor: messageContextFor ?? (_) => null,
      report: (error, stackTrace, operation, severity) =>
          _report(error, stackTrace, operation, severity: severity),
    );
    _sendCoordinator =
        sendCoordinatorFactory?.call(sendHost) ??
        DefaultChatSendCoordinator(
          api: api,
          requests: requests,
          host: sendHost,
          clock: _clock,
        );
    _liveSync = ChatLiveSyncCoordinator(
      requests: requests,
      host: ChatLiveSyncHost(
        isDisposed: () => isDisposed,
        clock: _clock,
        currentUserFor: _currentUserFor,
        channelFor: channel,
        messageFor: (siteUrl, messageId) =>
            _store.read<ChatMessage>(siteUrl, messageId),
        threadFor: thread,
        hasThreads: hasThreads,
        putChannel: (siteUrl, channel) => _store.put(siteUrl, channel),
        putMessage: (siteUrl, message) => _store.put(siteUrl, message),
        putLiveMessage: (siteUrl, message, preservePersonalizedState) =>
            _putLiveMessage(
              siteUrl,
              message,
              preservePersonalizedState: preservePersonalizedState,
            ),
        putThread: (siteUrl, thread) => _store.put(siteUrl, thread),
        publishNotificationChange: _publishNotificationChange,
        notifyCanonicalChange: notifySafely,
        removeKickedChannelState: _removeKickedChannelState,
        isChannelListed: (siteUrl, channelId) =>
            (_directIds[siteUrl]?.contains(channelId) ?? false) ||
            (_publicIds[siteUrl]?.contains(channelId) ?? false),
        resolvePartialChannel: (siteUrl, channelId) =>
            _partialChannelIds[siteUrl]?.remove(channelId),
        insertListedChannel: _insertLiveChannel,
        advanceLastViewedAt: (siteUrl, channelId) =>
            _advanceLastViewedAt(siteUrl, channelId, notify: false),
        beginChannelFollow: _beginLiveChannelFollow,
        ownsChannelFollow: _ownsLiveChannelFollow,
        endChannelFollow: _endLiveChannelFollow,
        followChannel: (siteUrl, apiKey, clientId, channelId) =>
            api.followChatChannel(
              siteUrl: siteUrl,
              apiKey: apiKey,
              clientId: clientId,
              channelId: channelId,
            ),
        revealThreads: (siteUrl) {
          if (hasThreads(siteUrl)) return;
          _hasThreads[siteUrl] = true;
          notifySafely();
        },
        admitActivityMessage: _admitActivityMessage,
        streamContainsMessage: (siteUrl, target, messageId) =>
            streamFor(siteUrl, target).messageIds.contains(messageId),
        admitLiveMessage: _admitLiveMessage,
        bumpStreamsHolding: _bumpStreamsHolding,
        setLoadedThreadOriginalDeleted:
            (siteUrl, channelId, originalMessageId, deletedAt, clear) =>
                _setLoadedThreadOriginalDeleted(
                  siteUrl,
                  channelId,
                  originalMessageId,
                  deletedAt: deletedAt,
                  clear: clear,
                ),
        scheduleThreadDetailRefresh: _scheduleThreadDetailRefresh,
        applyDeleteMutation: (siteUrl, data, channelId, thread) =>
            _applyDeleteEvent(
              siteUrl,
              data,
              channelId: channelId,
              thread: thread,
            ),
        applyBulkDeleteMutation:
            (siteUrl, data, channelId, thread, skipMessageId) =>
                _applyBulkDeleteEvent(
                  siteUrl,
                  data,
                  channelId: channelId,
                  thread: thread,
                  skipMessageId: skipMessageId,
                ),
        applyReactionMutation: _applyReactionEvent,
        applyPinMutation: (siteUrl, data, channelId) =>
            _applyPinEvent(siteUrl, data, channelId: channelId),
        applySelfFlagMutation: _applySelfFlaggedEvent,
        applyFlagMutation: _applyFlagEvent,
        showStreamNotice: _showStreamNotice,
        reconcileSentEvent: _sendCoordinator.reconcileSentEvent,
        attachReconciliationTracker: _sendCoordinator.attachTracker,
        cancelReconciliationChannel: _sendCoordinator.cancelChannel,
        forgetReconciliation: _sendCoordinator.forget,
        disposeReconciliation: _sendCoordinator.dispose,
        report: (error, stackTrace, operation, severity) =>
            _report(error, stackTrace, operation, severity: severity),
      ),
    );
  }

  final ChatApi api;
  final PluginRequestHost _requests;
  final Store _store;
  final Duration minimumWindowRefreshInterval;
  final DiscourseUser? Function(String siteUrl) _currentUserFor;
  final SiteConfig Function(String siteUrl) _siteConfigFor;
  final ChatPreviewEngine _previewEngine;
  final PluginDiagnosticsReporter reporter;
  final ChatNotificationsDelta? onChatNotificationsDelta;
  final ValueChanged<String>? onSiteUnreachable;
  final DateTime Function() _clock;
  late final ChatSendCoordinator _sendCoordinator;
  late final ChatLiveSyncCoordinator _liveSync;

  ChatPreviewEngine get previewEngine => _previewEngine;

  static DiscourseUser? _noCurrentUser(String _) => null;
  static SiteConfig _unknownSiteConfig(String _) => const SiteConfig.unknown();

  DiscourseUser? currentUserFor(String siteUrl) => _currentUserFor(siteUrl);
  SiteConfig siteConfigFor(String siteUrl) => _siteConfigFor(siteUrl);

  @visibleForTesting
  T putRecordForTesting<T extends Storable<T>>(String siteUrl, T record) =>
      _store.put(siteUrl, record);

  @visibleForTesting
  List<T> putRecordsForTesting<T extends Storable<T>>(
    String siteUrl,
    Iterable<T> records,
  ) => _store.putAll(siteUrl, records);

  @visibleForTesting
  T? readRecordForTesting<T extends Storable<T>>(String siteUrl, Object id) =>
      _store.read<T>(siteUrl, id);

  @visibleForTesting
  StorePolicy? get cachePolicyForTesting => _store.policy;

  PluginSiteLease captureSession(String siteUrl) => _requests.capture(siteUrl);

  void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool degraded = true,
  }) {
    reporter.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'chat',
      severity: severity,
      handled: true,
      degraded: degraded,
    );
  }

  /// Discourse caps chat pages at 50.
  static const int pageSize = 50;

  /// Allows retries when no later UI event would trigger one.
  static const int maxChannelAttempts = 3;

  final Set<String> _loading = {};
  final Map<String, String> _errors = {};
  final Map<String, int> _attempts = {};
  final Map<String, Future<void>> _channelRequests = {};
  final Map<String, Object> _channelRuns = {};
  final Map<String, Future<ChatChannel?>> _channelDetailRequests = {};
  final Map<String, Object> _channelDetailRuns = {};
  final Map<String, Future<void>> _myThreadRequests = {};
  final Map<String, Object> _myThreadRuns = {};
  final Map<String, Future<void>> _channelThreadListRequests = {};
  final Map<String, Object> _channelThreadListRuns = {};

  /// Sidebar orderings not represented by individual store records.
  final Map<String, List<int>> _publicIds = {};
  final Map<String, List<int>> _directIds = {};
  final Map<String, List<int>> _myThreadIds = {};
  final Map<String, int> _myThreadOffsets = {};
  final Map<String, bool> _myThreadsHaveMore = {};
  final Map<String, bool> _hasThreads = {};
  final Map<String, Set<int>> _partialChannelIds = {};
  final Map<String, List<int>> _channelThreadIds = {};
  final Map<String, int> _channelThreadOffsets = {};
  final Map<String, bool> _channelThreadsHaveMore = {};
  final Map<String, int> _lastOpenedChannelIds = {};

  final Map<String, Future<ChatThread?>> _threadDetailRequests = {};
  final Set<String> _threadDetailDirty = {};

  final Map<String, ChatStreamState> _streams = {};
  final Map<String, FrameSafeValueNotifier<ChatStreamState>> _streamRefs = {};
  final Map<String, Object> _streamGenerations = {};
  final Map<String, DateTime> _windowAttemptedAt = {};
  final Map<String, Object> _pageRequests = {};
  final Map<String, Set<int>> _pendingLiveMessageIds = {};
  final Map<String, Timer> _streamNoticeTimers = {};
  final Map<
    String,
    ({
      String siteUrl,
      ChatStreamTarget target,
      int messageId,
      PluginSiteLease lease,
    })
  >
  _queuedReadReceipts = {};
  final Map<String, Future<void>> _readReceiptTasks = {};
  final Map<String, Object> _readReceiptRuns = {};
  final Map<String, int> _threadNotificationRevisions = {};
  final Map<String, Future<void>> _threadNotificationTails = {};
  final Map<String, ChatThreadMembership?> _threadNotificationConfirmed = {};
  final Map<String, Object> _channelStarWrites = {};
  final Map<String, Object> _channelNotificationWrites = {};
  final Map<String, Object> _channelFollowWrites = {};
  final Map<String, Object> _channelSettingsWrites = {};
  final Map<({String siteUrl, int messageId}), Object> _messageEditWrites = {};
  final Map<({String siteUrl, int messageId}), Object> _messageDeletionWrites =
      {};
  final Map<({String siteUrl, int messageId}), Object> _messagePinWrites = {};
  final Map<({String siteUrl, int messageId}), Object> _messageFlagWrites = {};
  final Map<({String siteUrl, int messageId}), Object> _messageRebakeWrites =
      {};
  final Map<({String siteUrl, int channelId}), Object> _messageQuoteWrites = {};
  final Map<String, Object> _pinListRequests = {};
  final Map<String, FrameSafeValueNotifier<ChatPinsState>> _pinListRefs = {};
  final Map<String, Object> _threadTitleWrites = {};
  final Map<_ChatReactionWriteKey, Object> _reactionWrites = {};
  final Map<_ChatReactorsKey, Object> _reactorRequests = {};
  final Map<_ChatReactorsKey, String> _reactorErrors = {};
  final Map<String, int> _bookmarkVersions = {};
  final Map<String, FrameSafeValueNotifier<ChatComposerDraft?>>
  _composerDraftRefs = {};

  static String _channelsKey(String siteUrl) => '$siteUrl~channels';
  static String _myThreadsKey(String siteUrl) => '$siteUrl~my-threads';
  static String _channelThreadsKey(String siteUrl, int channelId) =>
      '$siteUrl~channel-$channelId-threads';
  static String _targetKey(String siteUrl, ChatStreamTarget target) =>
      '$siteUrl~${target.storageKey}';
  static String _streamKey(String siteUrl, int id) =>
      _targetKey(siteUrl, ChatChannelTarget(id));
  static String _pinsKey(String siteUrl, int channelId) =>
      '$siteUrl~channel-$channelId-pins';
  static String _olderTargetKey(String siteUrl, ChatStreamTarget target) =>
      '${_targetKey(siteUrl, target)}~past';
  static String _newerTargetKey(String siteUrl, ChatStreamTarget target) =>
      '${_targetKey(siteUrl, target)}~future';

  /// Rechecks ownership after credential awaits so stale account requests are
  /// never sent after disconnect, disposal, or generation replacement.
  bool _requestIsCurrent(PluginSiteLease lease, bool Function() ownsRequest) =>
      !isDisposed && lease.isCurrent && ownsRequest();

  List<ChatChannel> publicChannels(String siteUrl) =>
      _resolve(siteUrl, _publicIds[siteUrl]);

  List<ChatChannel> directChannels(String siteUrl) =>
      _resolve(siteUrl, _directIds[siteUrl]);

  /// Public channels in the web drawer's unread-first activity order.
  List<ChatChannel> activitySortedPublicChannels(String siteUrl) {
    final channels = [...publicChannels(siteUrl)];
    final originalPositions = <int, int>{};
    for (final channel in channels) {
      originalPositions[channel.id] = originalPositions.length;
    }
    channels.sort((a, b) {
      int urgent(ChatChannel channel) =>
          channel.tracking.mentionCount +
          channel.tracking.watchedThreadsUnreadCount;
      int unread(ChatChannel channel) =>
          channel.tracking.unreadCount +
          channel.unreadThreadsCountSinceLastViewed;
      int bySlug(ChatChannel first, ChatChannel second) {
        final compared = (first.slug ?? first.title).toLowerCase().compareTo(
          (second.slug ?? second.title).toLowerCase(),
        );
        return compared != 0
            ? compared
            : originalPositions[first.id]!.compareTo(
                originalPositions[second.id]!,
              );
      }

      final aUrgent = urgent(a);
      final bUrgent = urgent(b);
      if (aUrgent > 0 && bUrgent > 0) return bySlug(a, b);
      if ((aUrgent > 0) != (bUrgent > 0)) return aUrgent > 0 ? -1 : 1;

      final aUnread = unread(a);
      final bUnread = unread(b);
      if (aUnread > 0 && bUnread > 0) return bySlug(a, b);
      if ((aUnread > 0) != (bUnread > 0)) return aUnread > 0 ? -1 : 1;
      return bySlug(a, b);
    });
    return List.unmodifiable(channels);
  }

  bool channelsLoaded(String siteUrl) =>
      _publicIds.containsKey(siteUrl) && _directIds.containsKey(siteUrl);

  ChatComposerDraft? composerDraftFor(
    String siteUrl,
    ChatStreamTarget target,
  ) => _composerDraftRefs[_targetKey(siteUrl, target)]?.value;

  /// A target-scoped draft signal shared by every mounted presentation of the
  /// same channel or thread. The drawer and full-page route can coexist while
  /// one is offstage, so a snapshot-only lookup would leave one composer stale.
  ValueListenable<ChatComposerDraft?> composerDraftListenableFor(
    String siteUrl,
    ChatStreamTarget target,
  ) {
    final key = _targetKey(siteUrl, target);
    return _composerDraftRefs.putIfAbsent(
      key,
      () => FrameSafeValueNotifier<ChatComposerDraft?>(null),
    );
  }

  /// Retains local-only drafts while their drawer or full-page view is absent.
  /// Empty documents are removed so a successfully sent message cannot return
  /// when the composer is mounted again.
  void retainComposerDraft(
    String siteUrl,
    ChatStreamTarget target, {
    required String raw,
    required Iterable<ComposerUploadResult> uploads,
  }) {
    if (isDisposed) return;
    final key = _targetKey(siteUrl, target);
    final retainedUploads = List<ComposerUploadResult>.unmodifiable(uploads);
    if (raw.isEmpty && retainedUploads.isEmpty) {
      _composerDraftRefs[key]?.value = null;
      return;
    }
    final next = ChatComposerDraft(raw: raw, uploads: retainedUploads);
    _composerDraftRefs
            .putIfAbsent(
              key,
              () => FrameSafeValueNotifier<ChatComposerDraft?>(null),
            )
            .value =
        next;
  }

  bool hasThreads(String siteUrl) => _hasThreads[siteUrl] ?? false;

  bool channelStarWriteInFlight(String siteUrl, int channelId) =>
      _channelStarWrites.containsKey(_streamKey(siteUrl, channelId));

  bool channelNotificationWriteInFlight(String siteUrl, int channelId) =>
      _channelNotificationWrites.containsKey(_streamKey(siteUrl, channelId));

  Future<String?> updateChannelStarred(
    String siteUrl,
    int channelId,
    bool starred,
  ) async {
    if (isDisposed || channelId <= 0) {
      return 'This channel can no longer be changed.';
    }
    final held = channel(siteUrl, channelId);
    if (held == null || !held.membership.following) {
      return 'Only followed channels can be starred.';
    }
    if (held.membership.starred == starred) return null;

    final key = _streamKey(siteUrl, channelId);
    if (_channelStarWrites.containsKey(key)) {
      return 'Another channel change is still finishing.';
    }
    final token = Object();
    final lease = _requests.capture(siteUrl);
    _channelStarWrites[key] = token;

    bool isCurrent() =>
        identical(_channelStarWrites[key], token) &&
        lease.isCurrent &&
        !isDisposed;

    // The star is the only field this write owns. Tracking, mentions, and
    // read cursors that arrive while the request is in flight belong to the
    // live record, so both the optimistic write and its rollback rebase on
    // it rather than on the [held] snapshot.
    void project(bool starred) {
      lease.commit(() {
        final current = channel(siteUrl, channelId) ?? held;
        _store.put(siteUrl, current.withStarred(starred));
        notifySafely();
      });
    }

    project(starred);
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent()) return null;
      if (apiKey == null) {
        project(held.membership.starred);
        return 'Reconnect this site to change the channel.';
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrent()) return null;
      await api.updateChatChannelStarred(
        siteUrl: siteUrl,
        apiKey: apiKey,
        channelId: channelId,
        starred: starred,
        clientId: clientId,
      );
      return null;
    } on WriteException catch (error) {
      if (isCurrent()) project(held.membership.starred);
      return error.message;
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _report(
          error,
          stackTrace,
          'chat.updateChannelStarred',
          severity: DiagnosticSeverity.warning,
        );
        project(held.membership.starred);
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channelStarWrites[key], token)) {
        final _ = _channelStarWrites.remove(key);
      }
      if (!isDisposed) notifySafely();
    }
  }

  /// Muting and push frequency are independent Discourse fields.
  Future<String?> updateChannelNotifications(
    String siteUrl,
    int channelId, {
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
  }) async {
    if (isDisposed || channelId <= 0) {
      return 'This channel can no longer be changed.';
    }
    if (muted == null && notificationLevel == null) {
      return 'Choose a channel notification setting to change.';
    }
    final held = channel(siteUrl, channelId);
    if (held == null || !held.membership.following) {
      return 'Only followed channels have notification settings.';
    }
    final projectedMembership = held.membership.withNotifications(
      muted: muted,
      notificationLevel: notificationLevel,
    );
    if (projectedMembership == held.membership) return null;

    final key = _streamKey(siteUrl, channelId);
    if (_channelNotificationWrites.containsKey(key)) {
      return 'Another notification change is still finishing.';
    }
    final token = Object();
    final lease = _requests.capture(siteUrl);
    _channelNotificationWrites[key] = token;

    bool isCurrent() =>
        identical(_channelNotificationWrites[key], token) &&
        lease.isCurrent &&
        !isDisposed;

    // This write owns only muting and the push level. A read, star, or pin
    // view that lands while the request is in flight stays on the live
    // membership: the server's answer carries cursors older than a read that
    // happened locally meanwhile, and the rollback must not undo a
    // concurrent optimistic star.
    void project(ChatMembership source) {
      lease.commit(() {
        final current = channel(siteUrl, channelId) ?? held;
        _store.put(
          siteUrl,
          current.withMembership(
            current.membership.withNotifications(
              muted: source.muted,
              notificationLevel: source.notificationLevel,
            ),
          ),
        );
        notifySafely();
      });
    }

    project(projectedMembership);
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent()) return null;
      if (apiKey == null) {
        project(held.membership);
        return 'Reconnect this site to change channel notifications.';
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrent()) return null;
      final membership = await api.updateChatChannelNotifications(
        siteUrl: siteUrl,
        apiKey: apiKey,
        channelId: channelId,
        muted: muted,
        notificationLevel: notificationLevel,
        clientId: clientId,
      );
      if (isCurrent()) project(membership);
      return null;
    } on WriteException catch (error) {
      if (isCurrent()) project(held.membership);
      return error.message;
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _report(
          error,
          stackTrace,
          'chat.updateChannelNotifications',
          severity: DiagnosticSeverity.warning,
        );
        project(held.membership);
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channelNotificationWrites[key], token)) {
        final _ = _channelNotificationWrites.remove(key);
      }
      if (!isDisposed) notifySafely();
    }
  }

  Future<ChatChannelMembersResult> fetchChannelMembers(
    String siteUrl,
    int channelId, {
    String username = '',
    int offset = 0,
    int limit = 20,
  }) async {
    if (isDisposed || channelId <= 0) {
      return (page: null, error: 'This member list is no longer available.');
    }
    final held = channel(siteUrl, channelId);
    if (held == null || !held.membership.following) {
      return (page: null, error: 'Only followed channels show their members.');
    }
    final lease = _requests.capture(siteUrl);
    bool isCurrent() => !isDisposed && lease.isCurrent;
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent()) return (page: null, error: null);
      if (apiKey == null) {
        return (
          page: null,
          error: 'Reconnect this site to see channel members.',
        );
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrent()) return (page: null, error: null);
      final page = await api.chatChannelMembers(
        siteUrl: siteUrl,
        apiKey: apiKey,
        channelId: channelId,
        username: username,
        offset: offset,
        limit: limit,
        clientId: clientId,
      );
      return isCurrent()
          ? (page: page, error: null)
          : (page: null, error: null);
    } on SiteLookupException catch (error, stackTrace) {
      if (isCurrent()) {
        _report(error, stackTrace, 'chat.loadChannelMembers');
      }
      return (page: null, error: error.message);
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _report(error, stackTrace, 'chat.loadChannelMembers');
      }
      return (page: null, error: "Couldn't load this channel's members.");
    }
  }

  Future<ChatChannelBrowseResult> fetchBrowseChannels(
    String siteUrl, {
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
  }) async {
    if (isDisposed) {
      return (
        page: null,
        error: 'The channel directory is no longer available.',
      );
    }
    final lease = _requests.capture(siteUrl);
    bool isCurrent() => !isDisposed && lease.isCurrent;
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent()) return (page: null, error: null);
      if (apiKey == null) {
        return (
          page: null,
          error: 'Reconnect this site to browse chat channels.',
        );
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrent()) return (page: null, error: null);
      final page = await api.browseChatChannels(
        siteUrl: siteUrl,
        apiKey: apiKey,
        filter: filter,
        status: status,
        offset: offset,
        limit: limit,
        clientId: clientId,
      );
      return isCurrent()
          ? (page: page, error: null)
          : (page: null, error: null);
    } on SiteLookupException catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'chat.browseChannels');
      return (page: null, error: error.message);
    } catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'chat.browseChannels');
      return (page: null, error: "Couldn't load chat channels.");
    }
  }

  bool channelFollowWriteInFlight(String siteUrl, int channelId) =>
      _channelFollowWrites.containsKey(_streamKey(siteUrl, channelId));

  bool channelSettingsWriteInFlight(String siteUrl, int channelId) =>
      _channelSettingsWrites.containsKey(_streamKey(siteUrl, channelId));

  bool canEditChannelMetadata(String siteUrl, int channelId) {
    final held = channel(siteUrl, channelId);
    return _currentUserFor(siteUrl)?.staff == true &&
        held?.isCategoryChannel == true &&
        held!.membership.following;
  }

  /// Discourse requires the existing slug for title edits and an empty string
  /// to remove a description.
  Future<String?> updateChannelMetadata(
    String siteUrl,
    int channelId, {
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
  }) async {
    final held = channel(siteUrl, channelId);
    if (held == null || !canEditChannelMetadata(siteUrl, channelId)) {
      return 'This channel cannot be edited.';
    }
    if (name == null &&
        slug == null &&
        description == null &&
        threadingEnabled == null) {
      return null;
    }
    if (slug != null && (slug.trim().isEmpty || slug.trim().length > 100)) {
      return 'The channel slug must be between 1 and 100 characters.';
    }
    if (description != null && description.length > 280) {
      return 'The channel description cannot exceed 280 characters.';
    }
    final nextName = name?.trim();
    final nextSlug = slug?.trim();
    final nameChanged = name != null && nextName != held.title;
    final slugChanged = slug != null && nextSlug != held.slug;
    final descriptionChanged =
        description != null && description != held.description;
    final threadingChanged =
        threadingEnabled != null && threadingEnabled != held.threadingEnabled;
    if (!nameChanged &&
        !slugChanged &&
        !descriptionChanged &&
        !threadingChanged) {
      return null;
    }

    final key = _streamKey(siteUrl, channelId);
    if (_channelSettingsWrites.containsKey(key)) {
      return 'Another channel change is still finishing.';
    }
    final token = Object();
    final lease = _requests.capture(siteUrl);
    _channelSettingsWrites[key] = token;
    bool isCurrent() =>
        identical(_channelSettingsWrites[key], token) &&
        lease.isCurrent &&
        !isDisposed;
    if (threadingChanged) {
      _store.put(siteUrl, held.withThreadingEnabled(threadingEnabled));
    }
    notifySafely();

    void restoreThreading() {
      if (!threadingChanged || !isCurrent()) return;
      lease.commit(() {
        final current = channel(siteUrl, channelId);
        if (current != null) {
          _store.put(
            siteUrl,
            current.withThreadingEnabled(held.threadingEnabled),
          );
        }
        notifySafely();
      });
    }

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent()) return null;
      if (apiKey == null) return 'Reconnect this site to edit the channel.';
      final clientId = requestCredentials.clientId;
      if (!isCurrent()) return null;
      final fresh = await api.updateChatChannel(
        siteUrl: siteUrl,
        apiKey: apiKey,
        channelId: channelId,
        name: name == null ? null : nextName,
        slug: nextSlug,
        description: description,
        threadingEnabled: threadingEnabled,
        clientId: clientId,
      );
      if (!isCurrent()) return null;
      lease.commit(() {
        final current = channel(siteUrl, channelId);
        if (current != null) {
          _store.put(siteUrl, current.withServerSettings(fresh));
        }
        notifySafely();
      });
      return null;
    } on WriteException catch (error) {
      restoreThreading();
      return error.message;
    } catch (error, stackTrace) {
      restoreThreading();
      if (isCurrent()) _report(error, stackTrace, 'chat.updateChannelMetadata');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channelSettingsWrites[key], token)) {
        _channelSettingsWrites.remove(key);
        if (!isDisposed) notifySafely();
      }
    }
  }

  Future<String?> updateChannelThreading(
    String siteUrl,
    int channelId,
    bool enabled,
  ) {
    final held = channel(siteUrl, channelId);
    if (held == null ||
        !canEditChannelMetadata(siteUrl, channelId) ||
        held.status != ChatChannelStatus.open) {
      return Future.value('Threading cannot be changed for this channel.');
    }
    return updateChannelMetadata(siteUrl, channelId, threadingEnabled: enabled);
  }

  bool canChangeChannelStatus(String siteUrl, int channelId) {
    final held = channel(siteUrl, channelId);
    return _currentUserFor(siteUrl)?.staff == true &&
        held?.isCategoryChannel == true &&
        held!.membership.following &&
        (held.status == ChatChannelStatus.open ||
            held.status == ChatChannelStatus.closed);
  }

  /// Discourse reserves read-only and archived transitions for its archive flow.
  Future<String?> setChannelClosed(
    String siteUrl,
    int channelId, {
    required bool closed,
  }) async {
    final held = channel(siteUrl, channelId);
    final target = closed ? ChatChannelStatus.closed : ChatChannelStatus.open;
    if (held == null || !canChangeChannelStatus(siteUrl, channelId)) {
      return 'This channel’s status cannot be changed.';
    }
    if (held.status == target) return null;
    if ((closed && held.status != ChatChannelStatus.open) ||
        (!closed && held.status != ChatChannelStatus.closed)) {
      return 'This channel’s status cannot be changed.';
    }

    final key = _streamKey(siteUrl, channelId);
    if (_channelSettingsWrites.containsKey(key)) {
      return 'Another channel change is still finishing.';
    }
    final token = Object();
    final lease = _requests.capture(siteUrl);
    _channelSettingsWrites[key] = token;
    bool isCurrent() =>
        identical(_channelSettingsWrites[key], token) &&
        lease.isCurrent &&
        !isDisposed;
    notifySafely();

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent()) return null;
      if (apiKey == null) return 'Reconnect this site to change the channel.';
      final clientId = requestCredentials.clientId;
      if (!isCurrent()) return null;
      final fresh = await api.updateChatChannelStatus(
        siteUrl: siteUrl,
        apiKey: apiKey,
        channelId: channelId,
        status: target,
        clientId: clientId,
      );
      if (!isCurrent()) return null;
      lease.commit(() {
        final current = channel(siteUrl, channelId);
        if (current != null) {
          _store.put(siteUrl, current.withServerSettings(fresh));
        }
        notifySafely();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'chat.setChannelClosed');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channelSettingsWrites[key], token)) {
        _channelSettingsWrites.remove(key);
        if (!isDisposed) notifySafely();
      }
    }
  }

  /// Closing a direct message is Discourse's reversible membership follow write.
  Future<String?> updateChannelFollowing(
    String siteUrl,
    ChatChannel candidate,
    bool following,
  ) async {
    if (isDisposed || candidate.id <= 0) {
      return 'This channel can no longer be changed.';
    }
    final held = channel(siteUrl, candidate.id) ?? candidate;
    if (held.isDirectMessage && following) {
      return 'Direct messages cannot be joined from Browse Channels.';
    }
    if (held.membership.following == following) return null;
    if (following && (!held.canJoin || held.status != ChatChannelStatus.open)) {
      return 'This channel cannot be joined.';
    }

    final key = _streamKey(siteUrl, held.id);
    if (_channelFollowWrites.containsKey(key)) {
      return 'Another channel change is still finishing.';
    }
    final token = Object();
    final lease = _requests.capture(siteUrl);
    _channelFollowWrites[key] = token;

    bool isCurrent() =>
        identical(_channelFollowWrites[key], token) &&
        lease.isCurrent &&
        !isDisposed;

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent()) return null;
      if (apiKey == null) {
        return 'Reconnect this site to change the channel.';
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrent()) return null;
      final membership = following
          ? await api.followChatChannel(
              siteUrl: siteUrl,
              apiKey: apiKey,
              channelId: held.id,
              clientId: clientId,
            )
          : await api.unfollowChatChannel(
              siteUrl: siteUrl,
              apiKey: apiKey,
              channelId: held.id,
              clientId: clientId,
            );
      if (!isCurrent()) return null;

      lease.commit(() {
        // The commit builds on the record as it stands now, not the [held]
        // snapshot: tracking and a live member count that arrived during the
        // request stay in place.
        final current = channel(siteUrl, held.id) ?? held;
        final changed = membership.following != current.membership.following;
        final memberDelta = current.isDirectMessage || !changed
            ? 0
            : membership.following
            ? 1
            : -1;
        final next = current.withMembership(
          membership,
          membershipsCount: current.membershipsCount + memberDelta,
        );
        _store.put(siteUrl, next);
        final ids = (next.isDirectMessage ? _directIds : _publicIds)
            .putIfAbsent(siteUrl, () => []);
        if (membership.following) {
          if (!ids.contains(next.id)) ids.add(next.id);
          if (!next.isDirectMessage) {
            ids.sort((left, right) {
              final a = channel(siteUrl, left);
              final b = channel(siteUrl, right);
              return (a?.slug ?? a?.title ?? '').toLowerCase().compareTo(
                (b?.slug ?? b?.title ?? '').toLowerCase(),
              );
            });
          }
          _liveSync.adoptChannel(siteUrl, next, includeActivity: true);
        } else {
          ids.remove(next.id);
          _liveSync.stopFollowingChannel(siteUrl, next.id);
        }
        notifySafely();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _report(
          error,
          stackTrace,
          'chat.updateChannelFollowing',
          severity: DiagnosticSeverity.warning,
        );
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channelFollowWrites[key], token)) {
        final _ = _channelFollowWrites.remove(key);
      }
      if (!isDisposed) notifySafely();
    }
  }

  List<ChatThread> myThreads(String siteUrl) => [
    for (final id in _myThreadIds[siteUrl] ?? const <int>[])
      ?_store.read<ChatThread>(siteUrl, id),
  ];

  bool myThreadsLoaded(String siteUrl) => _myThreadIds.containsKey(siteUrl);

  bool myThreadsLoading(String siteUrl) =>
      _myThreadRequests.containsKey(_myThreadsKey(siteUrl)) &&
      !myThreadsLoaded(siteUrl);

  bool myThreadsLoadingMore(String siteUrl) =>
      _myThreadRequests.containsKey(_myThreadsKey(siteUrl)) &&
      myThreadsLoaded(siteUrl);

  bool myThreadsHaveMore(String siteUrl) =>
      _myThreadsHaveMore[siteUrl] ?? false;

  String? myThreadsError(String siteUrl) => _errors[_myThreadsKey(siteUrl)];

  List<ChatThread> channelThreads(String siteUrl, int channelId) {
    final key = _channelThreadsKey(siteUrl, channelId);
    final threads = <ChatThread>[
      for (final id in _channelThreadIds[key] ?? const <int>[])
        if (_store.read<ChatThread>(siteUrl, id) case final thread?
            when thread.channelId == channelId &&
                thread.originalMessage?.deletedAt == null &&
                thread.originalMessage?.id != thread.lastMessageId)
          thread,
    ];
    threads.sort(_compareChannelThreads);
    return List.unmodifiable(threads);
  }

  bool channelThreadsLoaded(String siteUrl, int channelId) =>
      _channelThreadIds.containsKey(_channelThreadsKey(siteUrl, channelId));

  bool channelThreadsLoading(String siteUrl, int channelId) {
    final key = _channelThreadsKey(siteUrl, channelId);
    return _channelThreadListRequests.containsKey(key) &&
        !_channelThreadIds.containsKey(key);
  }

  bool channelThreadsLoadingMore(String siteUrl, int channelId) {
    final key = _channelThreadsKey(siteUrl, channelId);
    return _channelThreadListRequests.containsKey(key) &&
        _channelThreadIds.containsKey(key);
  }

  bool channelThreadsHaveMore(String siteUrl, int channelId) =>
      _channelThreadsHaveMore[_channelThreadsKey(siteUrl, channelId)] ?? false;

  String? channelThreadsError(String siteUrl, int channelId) =>
      _errors[_channelThreadsKey(siteUrl, channelId)];

  static int _compareChannelThreads(ChatThread a, ChatThread b) {
    final aWatched = a.tracking.watchedThreadsUnreadCount > 0;
    final bWatched = b.tracking.watchedThreadsUnreadCount > 0;
    if (aWatched != bWatched) return aWatched ? -1 : 1;

    final aUnread = a.tracking.unreadCount > 0;
    final bUnread = b.tracking.unreadCount > 0;
    if (aUnread != bUnread) return aUnread ? -1 : 1;

    final aAt = a.preview?.lastReplyAt;
    final bAt = b.preview?.lastReplyAt;
    if (aAt != null && bAt != null) {
      final byActivity = bAt.compareTo(aAt);
      if (byActivity != 0) return byActivity;
    } else if (aAt != bAt) {
      return aAt == null ? 1 : -1;
    }
    return b.id.compareTo(a.id);
  }

  Future<ChatChannel?> upsertDirectMessageChannel(
    String siteUrl,
    String username,
  ) => createDirectMessageChannel(siteUrl, usernames: [username], upsert: true);

  /// Group DMs use `upsert: false`, so identical membership may produce
  /// distinct conversations; Discourse enforces permissions and member limits.
  Future<ChatChannel?> createDirectMessageChannel(
    String siteUrl, {
    required Iterable<String> usernames,
    Iterable<String> groups = const [],
    String? name,
    bool upsert = false,
  }) async {
    final targets = <String>{
      for (final username in usernames)
        if (username.trim().isNotEmpty) username.trim(),
    }.toList(growable: false);
    final targetGroups = <String>{
      for (final group in groups)
        if (group.trim().isNotEmpty) group.trim(),
    }.toList(growable: false);
    final channelName = switch (name?.trim()) {
      final value? when value.isNotEmpty => value,
      _ => null,
    };
    if (isDisposed || targets.isEmpty && targetGroups.isEmpty) return null;
    final lease = _requests.capture(siteUrl);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (isDisposed || !lease.isCurrent) return null;
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final clientId = requestCredentials.clientId;
      if (isDisposed || !lease.isCurrent) return null;
      final channel = await api.createChatDirectMessageChannel(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        usernames: targets,
        groups: targetGroups,
        name: channelName,
        upsert: upsert,
      );
      if (isDisposed || !lease.isCurrent || channel.id <= 0) return null;

      lease.commit(() {
        _store.put(siteUrl, channel);
        final direct = _directIds[siteUrl] ?? const <int>[];
        _directIds[siteUrl] = [
          channel.id,
          for (final id in direct)
            if (id != channel.id) id,
        ];
        _liveSync.adoptChannel(siteUrl, channel, includeActivity: true);
        notifySafely();
      });
      return channel;
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _report(error, stackTrace, 'chat.createDirectMessage');
      }
      rethrow;
    }
  }

  /// Adopts conversations omitted by the capped sidebar snapshot and discards
  /// results from a superseded account session.
  Future<ChatDirectMessageSearchResults> searchDirectMessages(
    String siteUrl,
    String term, {
    bool includeGroups = false,
    bool includeDirectMessageChannels = true,
  }) async {
    final query = term.trim();
    if (isDisposed || query.isEmpty) {
      return ChatDirectMessageSearchResults(const []);
    }
    final lease = _requests.capture(siteUrl);
    final requestCredentials = await _requests.credentialsFor(siteUrl);
    final apiKey = requestCredentials.apiKey;
    if (isDisposed || !lease.isCurrent) {
      return ChatDirectMessageSearchResults(const []);
    }
    if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
    final result = await api.searchChatDirectMessages(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: requestCredentials.clientId,
      term: query,
      includeGroups: includeGroups,
      includeDirectMessageChannels: includeDirectMessageChannels,
    );
    if (isDisposed || !lease.isCurrent) {
      return ChatDirectMessageSearchResults(const []);
    }

    lease.commit(() {
      final listed = _directIds[siteUrl];
      var sidebarChanged = false;
      for (final item in result.items) {
        if (item case ChatDirectMessageChannel(:final channel)) {
          final held = _store.read<ChatChannel>(siteUrl, channel.id);
          _store.put(siteUrl, held?.withServerSettings(channel) ?? channel);
          if (listed != null &&
              channel.membership.following &&
              !listed.contains(channel.id)) {
            listed.insert(0, channel.id);
            _liveSync.adoptChannel(siteUrl, channel, includeActivity: true);
            sidebarChanged = true;
          }
        }
      }
      if (sidebarChanged) {
        notifySafely();
      }
    });
    return result;
  }

  static int _notificationContribution(ChatChannel channel) =>
      channel.isDirectMessage
      ? channel.tracking.unreadCount
      : channel.tracking.mentionCount;

  int _chatNotifications(String siteUrl) => [
    ...publicChannels(siteUrl),
    ...directChannels(siteUrl),
  ].fold(0, (count, channel) => count + _notificationContribution(channel));

  void _publishNotificationChange(
    String siteUrl,
    ChatChannel before,
    ChatChannel after,
  ) {
    final delta =
        _notificationContribution(after) - _notificationContribution(before);
    if (delta != 0) onChatNotificationsDelta?.call(siteUrl, delta);
  }

  void _insertLiveChannel(String siteUrl, ChatChannel incoming) {
    if (incoming.isDirectMessage && incoming.membership.following) {
      final ids = _directIds.putIfAbsent(siteUrl, () => []);
      if (!ids.contains(incoming.id)) ids.add(incoming.id);
      return;
    }
    if (!incoming.isCategoryChannel) return;
    final ids = _publicIds.putIfAbsent(siteUrl, () => []);
    if (!ids.contains(incoming.id)) ids.add(incoming.id);
    ids.sort((a, b) {
      final left = channel(siteUrl, a);
      final right = channel(siteUrl, b);
      return (left?.slug ?? left?.title ?? '').toLowerCase().compareTo(
        (right?.slug ?? right?.title ?? '').toLowerCase(),
      );
    });
  }

  Object? _beginLiveChannelFollow(String siteUrl, int channelId) {
    final key = _streamKey(siteUrl, channelId);
    if (_channelFollowWrites.containsKey(key)) return null;
    final token = Object();
    _channelFollowWrites[key] = token;
    return token;
  }

  bool _ownsLiveChannelFollow(String siteUrl, int channelId, Object token) =>
      identical(_channelFollowWrites[_streamKey(siteUrl, channelId)], token);

  void _endLiveChannelFollow(String siteUrl, int channelId, Object token) {
    final key = _streamKey(siteUrl, channelId);
    if (identical(_channelFollowWrites[key], token)) {
      _channelFollowWrites.remove(key);
    }
  }

  /// Matches Discourse: starred public channels precede title-sorted starred DMs.
  List<ChatChannel> starredChannels(String siteUrl) {
    final direct = directChannels(
      siteUrl,
    ).where((channel) => channel.membership.starred).toList();
    direct.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return [
      for (final channel in publicChannels(siteUrl))
        if (channel.membership.starred) channel,
      ...direct,
    ];
  }

  List<ChatChannel> unstarredPublicChannels(String siteUrl) => [
    for (final channel in publicChannels(siteUrl))
      if (!channel.membership.starred) channel,
  ];

  List<ChatChannel> unstarredDirectChannels(String siteUrl) {
    final channels = [
      for (final channel in directChannels(siteUrl))
        if (!channel.membership.starred) channel,
    ];
    return List.unmodifiable(_sortDirectMessageActivity(channels));
  }

  /// All direct-message channels in the same activity order used by the web
  /// drawer, before its 50-row display limit is applied.
  List<ChatChannel> activitySortedDirectChannels(String siteUrl) =>
      List.unmodifiable(
        _sortDirectMessageActivity([...directChannels(siteUrl)]),
      );

  /// Starred drawer rows follow web's four buckets—active public, active DMs,
  /// read public, read DMs—with urgency and last activity inside each bucket.
  List<ChatChannel> activitySortedStarredChannels(String siteUrl) {
    final channels = [...starredChannels(siteUrl)];
    final originalPositions = <int, int>{};
    for (final channel in channels) {
      originalPositions[channel.id] = originalPositions.length;
    }

    int urgent(ChatChannel channel) => channel.isDirectMessage
        ? channel.tracking.unreadCount +
              channel.tracking.mentionCount +
              channel.tracking.watchedThreadsUnreadCount
        : channel.tracking.mentionCount +
              channel.tracking.watchedThreadsUnreadCount;
    int unread(ChatChannel channel) =>
        channel.tracking.unreadCount +
        channel.unreadThreadsCountSinceLastViewed;
    int byActivity(ChatChannel a, ChatChannel b) {
      final compared = _newestActivityFirst(a, b);
      return compared != 0
          ? compared
          : originalPositions[a.id]!.compareTo(originalPositions[b.id]!);
    }

    channels.sort((a, b) {
      final aUrgent = urgent(a);
      final bUrgent = urgent(b);
      final aUnread = unread(a);
      final bUnread = unread(b);
      final aHasActivity = aUrgent > 0 || aUnread > 0;
      final bHasActivity = bUrgent > 0 || bUnread > 0;
      if (aHasActivity != bHasActivity) return aHasActivity ? -1 : 1;
      if (a.isDirectMessage != b.isDirectMessage) {
        return a.isDirectMessage ? 1 : -1;
      }
      if (aHasActivity) {
        if (aUrgent > 0 && bUrgent > 0) return byActivity(a, b);
        if ((aUrgent > 0) != (bUrgent > 0)) return aUrgent > 0 ? -1 : 1;
        if (aUnread > 0 && bUnread > 0) return byActivity(a, b);
        if ((aUnread > 0) != (bUnread > 0)) return aUnread > 0 ? -1 : 1;
      }
      return byActivity(a, b);
    });
    return List.unmodifiable(channels);
  }

  List<ChatChannel> _sortDirectMessageActivity(List<ChatChannel> channels) {
    final originalPositions = {
      for (var index = 0; index < channels.length; index++)
        channels[index].id: index,
    };
    channels.sort((a, b) {
      final compared = _compareDirectMessageActivity(a, b);
      return compared != 0
          ? compared
          : originalPositions[a.id]!.compareTo(originalPositions[b.id]!);
    });
    return channels;
  }

  /// Mirrors core's activity ordering for unstarred direct messages.
  static int _compareDirectMessageActivity(ChatChannel a, ChatChannel b) {
    final aHasMessage = a.lastMessageId != null && a.lastMessageAt != null;
    final bHasMessage = b.lastMessageId != null && b.lastMessageAt != null;
    if (aHasMessage != bHasMessage) return aHasMessage ? -1 : 1;

    final aUrgent =
        a.tracking.unreadCount +
        a.tracking.mentionCount +
        a.tracking.watchedThreadsUnreadCount;
    final bUrgent =
        b.tracking.unreadCount +
        b.tracking.mentionCount +
        b.tracking.watchedThreadsUnreadCount;
    if (aUrgent > 0 && bUrgent > 0) {
      return _newestActivityFirst(a, b);
    }
    if ((aUrgent > 0) != (bUrgent > 0)) return aUrgent > 0 ? -1 : 1;

    final aThreads = a.unreadThreadsCountSinceLastViewed;
    final bThreads = b.unreadThreadsCountSinceLastViewed;
    if (aThreads > 0 && bThreads > 0) {
      final aAt = a.lastUnreadThreadAt;
      final bAt = b.lastUnreadThreadAt;
      if (aAt != null && bAt != null) {
        final byThreadDate = bAt.compareTo(aAt);
        if (byThreadDate != 0) return byThreadDate;
      }
      return _newestActivityFirst(a, b);
    }
    if ((aThreads > 0) != (bThreads > 0)) return aThreads > 0 ? -1 : 1;

    return _newestActivityFirst(a, b);
  }

  static int _newestActivityFirst(ChatChannel a, ChatChannel b) {
    final aAt = a.lastMessageAt;
    final bAt = b.lastMessageAt;
    if (aAt == null || bAt == null) {
      if (aAt == bAt) return 0;
      return aAt == null ? 1 : -1;
    }
    final byDate = bAt.compareTo(aAt);
    if (byDate != 0) return byDate;
    return (b.lastMessageId ?? 0).compareTo(a.lastMessageId ?? 0);
  }

  /// Mirrors core: DMs, mentions, and watched threads are urgent; ordinary
  /// activity is a dot only under the `all_new` preference.
  ChatHeaderIndicator headerIndicator(
    String siteUrl,
    ChatHeaderIndicatorPreference preference,
  ) {
    final public = publicChannels(siteUrl);
    final direct = directChannels(siteUrl);
    final all = [...public, ...direct];
    final mentions = all.fold(
      0,
      (count, channel) => count + channel.tracking.mentionCount,
    );

    if (preference == ChatHeaderIndicatorPreference.never) {
      return ChatHeaderIndicator.none;
    }
    if (preference == ChatHeaderIndicatorPreference.onlyMentions) {
      return mentions > 0
          ? ChatHeaderIndicator.urgent(mentions)
          : ChatHeaderIndicator.none;
    }

    final urgent = all.fold(0, (count, channel) {
      final tracking = channel.tracking;
      return count +
          tracking.mentionCount +
          tracking.watchedThreadsUnreadCount +
          (channel.isDirectMessage ? tracking.unreadCount : 0);
    });
    if (urgent > 0) return ChatHeaderIndicator.urgent(urgent);

    if (preference == ChatHeaderIndicatorPreference.allNew &&
        all.any(
          (channel) =>
              channel.tracking.unreadCount > 0 || channel.unreadThreadCount > 0,
        )) {
      return ChatHeaderIndicator.dot;
    }
    return ChatHeaderIndicator.none;
  }

  ChatChannel? shortcutChannel(String siteUrl, {int? lastChannelId}) {
    final preferredId = _lastOpenedChannelIds[siteUrl] ?? lastChannelId;
    if (preferredId != null) {
      final last = channel(siteUrl, preferredId);
      if (last?.membership.following == true) return last;
    }
    return _sortDirectMessageActivity(
          directChannels(siteUrl).toList(),
        ).firstOrNull ??
        publicChannels(siteUrl).firstOrNull;
  }

  List<ChatChannel> _resolve(String siteUrl, List<int>? ids) => [
    for (final id in ids ?? const <int>[])
      ?_store.read<ChatChannel>(siteUrl, id),
  ];

  ChatChannel? channel(String siteUrl, int channelId) =>
      _store.read<ChatChannel>(siteUrl, channelId);

  /// Fetches membership absent from partial search hits outside the capped snapshot.
  Future<ChatChannel?> ensureChannel(String siteUrl, int channelId) {
    if (isDisposed || channelId <= 0) return Future.value();
    final held = channel(siteUrl, channelId);
    if (held != null &&
        !(_partialChannelIds[siteUrl]?.contains(channelId) ?? false)) {
      return Future.value(held);
    }
    final key = _streamKey(siteUrl, channelId);
    final active = _channelDetailRequests[key];
    if (active != null) return active;

    final run = Object();
    _channelDetailRuns[key] = run;
    late final Future<ChatChannel?> request;
    request = _ensureChannel(siteUrl, channelId, key, run).whenComplete(() {
      if (identical(_channelDetailRequests[key], request)) {
        final removed = _channelDetailRequests.remove(key);
        assert(identical(removed, request));
      }
      if (identical(_channelDetailRuns[key], run)) {
        _channelDetailRuns.remove(key);
      }
    });
    _channelDetailRequests[key] = request;
    return request;
  }

  Future<ChatChannel?> _ensureChannel(
    String siteUrl,
    int channelId,
    String key,
    Object run,
  ) async {
    final lease = _requests.capture(siteUrl);
    bool ownsRequest() => identical(_channelDetailRuns[key], run);
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest) || apiKey == null) return null;
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return null;
      final fetched = await api.chatChannel(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
      );
      if (!_requestIsCurrent(lease, ownsRequest) || fetched.id != channelId) {
        return null;
      }
      return lease.commit(() {
            _partialChannelIds[siteUrl]?.remove(channelId);
            _store.put(siteUrl, fetched);
            _liveSync.adoptChannel(siteUrl, fetched, includeActivity: false);
          })
          ? channel(siteUrl, channelId)
          : null;
    } catch (error, stackTrace) {
      if (_requestIsCurrent(lease, ownsRequest)) {
        _report(error, stackTrace, 'chat.loadChannel');
      }
      rethrow;
    }
  }

  ChatThread? thread(String siteUrl, int threadId) =>
      _store.read<ChatThread>(siteUrl, threadId);

  Ref<ChatThread> threadRef(String siteUrl, int threadId) =>
      _store.ref<ChatThread>(siteUrl, threadId);

  /// Advances core's `lastViewedAt`, which filters old thread overview entries.
  Object beginViewingChannel(String siteUrl, int channelId) {
    final token = _liveSync.beginViewingChannel(siteUrl, channelId);
    if (isDisposed) return token;
    _advanceLastViewedAt(siteUrl, channelId);
    return token;
  }

  /// Ignores disposal from an older overlapping pane generation.
  void endViewingChannel(String siteUrl, int channelId, Object token) {
    _liveSync.endViewingChannel(siteUrl, channelId, token);
  }

  Object beginViewingThread(String siteUrl, ChatThreadTarget target) =>
      _liveSync.beginViewingThread(siteUrl, target);

  void endViewingThread(String siteUrl, ChatThreadTarget target, Object token) {
    _liveSync.endViewingThread(siteUrl, target, token);
  }

  void _advanceLastViewedAt(
    String siteUrl,
    int channelId, {
    bool notify = true,
  }) {
    final held = channel(siteUrl, channelId);
    if (held == null) return;
    final viewedAt = _clock().toUtc();
    final previous = held.membership.lastViewedAt;
    if (previous != null && !viewedAt.isAfter(previous)) return;
    _store.put(siteUrl, held.withLastViewedAt(viewedAt));
    if (notify) notifySafely();
  }

  Ref<ChatChannel> channelRef(String siteUrl, int channelId) =>
      _store.ref<ChatChannel>(siteUrl, channelId);

  Ref<ChatMessage> messageRef(String siteUrl, int messageId) =>
      _store.ref<ChatMessage>(siteUrl, messageId);

  ChatMessage? message(String siteUrl, int messageId) =>
      _store.read<ChatMessage>(siteUrl, messageId);

  ValueListenable<ChatPinsState> pinsListenable(
    String siteUrl,
    int channelId,
  ) => _pinListRefs.putIfAbsent(
    _pinsKey(siteUrl, channelId),
    () => FrameSafeValueNotifier(const ChatPinsState()),
  );

  Future<void> loadPinnedMessages(
    String siteUrl,
    int channelId, {
    bool force = false,
  }) async {
    final key = _pinsKey(siteUrl, channelId);
    final ref = _pinListRefs.putIfAbsent(
      key,
      () => FrameSafeValueNotifier(const ChatPinsState()),
    );
    if (!force && (ref.value.fetched || _pinListRequests.containsKey(key))) {
      return;
    }
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _pinListRequests[key] = request;
    ref.value = ref.value.copyWith(loading: true, clearError: true);

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_pinListRequests[key], request);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return;
      final snapshot = await api.chatPinnedMessages(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
      );
      if (!ownsRequest()) return;
      lease.commit(() {
        for (final pin in snapshot.pins) {
          _putLiveMessage(siteUrl, pin.message);
        }
        final heldChannel = channel(siteUrl, channelId);
        if (heldChannel != null) {
          _store.put(
            siteUrl,
            heldChannel.withPinSnapshot(
              count: snapshot.pins.length,
              membership: snapshot.membership,
            ),
          );
        }
        ref.value = ChatPinsState(
          pins: List.unmodifiable(snapshot.pins),
          fetched: true,
        );
      });
    } catch (error, stackTrace) {
      if (!ownsRequest()) return;
      _report(error, stackTrace, 'chat.loadPinnedMessages');
      ref.value = ref.value.copyWith(
        loading: false,
        fetched: true,
        error: 'Could not load pinned messages.',
      );
    } finally {
      if (identical(_pinListRequests[key], request)) {
        _pinListRequests.remove(key);
      }
    }
  }

  Future<void> markPinnedMessagesRead(String siteUrl, int channelId) async {
    final held = channel(siteUrl, channelId);
    if (held == null || !held.membership.following) return;
    final lease = _requests.capture(siteUrl);
    _store.put(siteUrl, held.withPinsViewed(_clock().toUtc()));
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (isDisposed || !lease.isCurrent || apiKey == null) return;
      final clientId = requestCredentials.clientId;
      if (isDisposed || !lease.isCurrent) return;
      await api.markChatPinsRead(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _report(
          error,
          stackTrace,
          'chat.markPinnedMessagesRead',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
  }

  bool canBookmarkMessage(String siteUrl, ChatMessage message) {
    final user = _currentUserFor(siteUrl);
    final heldChannel = channel(siteUrl, message.channelId);
    return user != null &&
        message.id > 0 &&
        !message.isOptimistic &&
        !message.isDeleted &&
        heldChannel != null &&
        heldChannel.canModifyMessages(isStaff: user.staff);
  }

  bool canEditMessage(String siteUrl, ChatMessage message) {
    final user = _currentUserFor(siteUrl);
    final heldChannel = channel(siteUrl, message.channelId);
    return !isDisposed &&
        user?.id != null &&
        user!.id == message.author.id &&
        message.id > 0 &&
        message.raw.trim().isNotEmpty &&
        !message.isOptimistic &&
        !message.isDeleted &&
        heldChannel != null &&
        heldChannel.canModifyMessages(isStaff: user.staff);
  }

  bool canDeleteMessage(String siteUrl, ChatMessage message) {
    final user = _currentUserFor(siteUrl);
    final heldChannel = channel(siteUrl, message.channelId);
    if (isDisposed ||
        user?.id == null ||
        message.id <= 0 ||
        message.isOptimistic ||
        message.isDeleted ||
        heldChannel == null ||
        !heldChannel.canModifyMessages(isStaff: user!.staff)) {
      return false;
    }
    return message.author.id == user.id
        ? heldChannel.canDeleteSelf
        : heldChannel.canDeleteOthers;
  }

  /// Mirrors core's pin feature and guardian permission boundary.
  bool canPinMessage(String siteUrl, ChatMessage message) =>
      !isDisposed &&
      _currentUserFor(siteUrl) != null &&
      message.id > 0 &&
      !message.isOptimistic &&
      !message.isDeleted &&
      channel(siteUrl, message.channelId)?.canManagePins == true;

  /// Core exposes Rebuild HTML only to staff in writable channels.
  bool canRebakeMessage(String siteUrl, ChatMessage message) {
    final user = _currentUserFor(siteUrl);
    final heldChannel = channel(siteUrl, message.channelId);
    return !isDisposed &&
        user?.staff == true &&
        message.id > 0 &&
        !message.isOptimistic &&
        heldChannel != null &&
        heldChannel.canModifyMessages(isStaff: true);
  }

  bool canFlagMessage(String siteUrl, ChatMessage message) {
    final user = _currentUserFor(siteUrl);
    return !isDisposed &&
        user?.id != null &&
        user!.id != message.author.id &&
        message.id > 0 &&
        !message.isOptimistic &&
        !message.isDeleted &&
        !message.isWebhook &&
        message.userFlagStatus == null &&
        message.reviewableId == null &&
        message.availableFlags.isNotEmpty &&
        channel(siteUrl, message.channelId)?.canFlag == true;
  }

  List<PostFlagType> availableChatFlagTypes(
    String siteUrl,
    ChatMessage message,
    List<PostFlagType> catalog,
  ) {
    if (!canFlagMessage(siteUrl, message)) return const [];
    final available = message.availableFlags.toSet();
    return List.unmodifiable([
      for (final type in catalog)
        if (type.enabled &&
            type.appliesToTarget(chatMessageWireType) &&
            available.contains(type.nameKey))
          type,
    ]);
  }

  int flagMessageMinimumLength(String siteUrl) =>
      _siteConfigFor(siteUrl).minPersonalMessagePostLength;

  Future<String?> flagMessage(
    String siteUrl,
    int messageId,
    PostFlagType flagType, {
    String? message,
  }) async {
    final held = _store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !canFlagMessage(siteUrl, held)) {
      return 'This message can no longer be flagged.';
    }
    if (!flagType.enabled ||
        !flagType.appliesToTarget(chatMessageWireType) ||
        !held.availableFlags.contains(flagType.nameKey)) {
      return 'This flag reason is no longer available.';
    }
    final submittedMessage = flagType.requireMessage ? message ?? '' : null;
    final minimum = flagMessageMinimumLength(siteUrl);
    final length = submittedMessage?.length ?? 0;
    if (flagType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return 'Your message must be between $minimum and '
          '${PostFlagType.maximumMessageLength} characters.';
    }

    final key = (siteUrl: siteUrl, messageId: messageId);
    if (_messageFlagWrites.containsKey(key) ||
        _messageEditWrites.containsKey(key) ||
        _messageDeletionWrites.containsKey(key) ||
        _messagePinWrites.containsKey(key) ||
        _messageRebakeWrites.containsKey(key)) {
      return 'Another message change is still finishing.';
    }
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _messageFlagWrites[key] = request;

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_messageFlagWrites[key], request);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = _store.read<ChatMessage>(siteUrl, messageId);
      if (current == null ||
          !canFlagMessage(siteUrl, current) ||
          !current.availableFlags.contains(flagType.nameKey)) {
        return 'This message can no longer be flagged.';
      }
      await api.flagChatMessage(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: current.channelId,
        messageId: current.id,
        flagTypeId: flagType.id,
        message: submittedMessage,
      );
      if (!ownsRequest()) return null;
      lease.commit(() {
        _store.update<ChatMessage>(
          siteUrl,
          messageId,
          (message) => message.withUserFlagStatus(0),
        );
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (ownsRequest()) _report(error, stackTrace, 'chat.flagMessage');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_messageFlagWrites[key], request)) {
        _messageFlagWrites.remove(key);
      }
    }
  }

  bool messagePinWriteInFlight(String siteUrl, int messageId) =>
      _messagePinWrites.containsKey((siteUrl: siteUrl, messageId: messageId));

  /// Rollback preserves unrelated fields changed while the pin request runs.
  Future<String?> setMessagePinned(
    String siteUrl,
    int messageId, {
    required bool pinned,
  }) async {
    final held = _store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !canPinMessage(siteUrl, held)) {
      return 'This message can no longer be ${pinned ? 'pinned' : 'unpinned'}.';
    }
    if (held.pinned == pinned) return null;

    final key = (siteUrl: siteUrl, messageId: messageId);
    if (_messagePinWrites.containsKey(key) ||
        _messageEditWrites.containsKey(key) ||
        _messageDeletionWrites.containsKey(key) ||
        _messageFlagWrites.containsKey(key) ||
        _messageRebakeWrites.containsKey(key)) {
      return 'Another message change is still finishing.';
    }
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _messagePinWrites[key] = request;

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_messagePinWrites[key], request);

    void project(bool next) {
      lease.commit(() {
        final latest = _store.read<ChatMessage>(siteUrl, messageId);
        if (latest == null || latest.pinned == next) return;
        _store.put(siteUrl, latest.withPinned(next));
        _store.update<ChatChannel>(
          siteUrl,
          latest.channelId,
          (channel) => channel.withPinnedMessagesCount(
            channel.pinnedMessagesCount + (next ? 1 : -1),
          ),
        );
        // Pinning forces the message to begin a speaker run in core.
        _bumpStreamsHolding(siteUrl, messageId);
      });
    }

    project(pinned);
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = _store.read<ChatMessage>(siteUrl, messageId);
      if (current == null || !canPinMessage(siteUrl, current)) {
        project(held.pinned);
        return 'This message can no longer be ${pinned ? 'pinned' : 'unpinned'}.';
      }
      await api.updateChatMessagePinned(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: held.channelId,
        messageId: held.id,
        pinned: pinned,
      );
      return null;
    } on WriteException catch (error) {
      if (ownsRequest()) project(held.pinned);
      return error.message;
    } catch (error, stackTrace) {
      if (ownsRequest()) {
        _report(error, stackTrace, 'chat.${pinned ? 'pin' : 'unpin'}Message');
        project(held.pinned);
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_messagePinWrites[key], request)) {
        _messagePinWrites.remove(key);
      }
    }
  }

  bool canRestoreMessage(String siteUrl, ChatMessage message) {
    final user = _currentUserFor(siteUrl);
    final heldChannel = channel(siteUrl, message.channelId);
    if (isDisposed ||
        user?.id == null ||
        message.id <= 0 ||
        !message.isDeleted ||
        heldChannel == null ||
        !heldChannel.canModifyMessages(isStaff: user!.staff)) {
      return false;
    }
    if (message.author.id != user.id) {
      return user.staff || heldChannel.canModerate;
    }
    return user.staff ||
        heldChannel.canModerate ||
        message.deletedById == user.id;
  }

  bool messageDeletionWriteInFlight(String siteUrl, int messageId) =>
      _messageDeletionWrites.containsKey((
        siteUrl: siteUrl,
        messageId: messageId,
      ));

  Future<String?> deleteMessage(String siteUrl, int messageId) =>
      _setMessageDeleted(siteUrl, messageId, deleted: true);

  static const int maximumBulkDeleteMessages = 200;

  bool canDeleteMessages(
    String siteUrl,
    int channelId,
    Iterable<int> messageIds,
  ) {
    final ids = messageIds.toSet();
    if (ids.isEmpty || ids.length > maximumBulkDeleteMessages) return false;
    return ids.every((id) {
      final message = _store.read<ChatMessage>(siteUrl, id);
      return message != null &&
          message.channelId == channelId &&
          canDeleteMessage(siteUrl, message);
    });
  }

  Future<String?> deleteMessages(
    String siteUrl,
    int channelId,
    Iterable<int> messageIds,
  ) async {
    final ids = messageIds.toSet().toList()..sort();
    if (ids.isEmpty) return 'Select at least one message.';
    if (ids.length > maximumBulkDeleteMessages) {
      return 'Select no more than $maximumBulkDeleteMessages messages to delete.';
    }
    if (!canDeleteMessages(siteUrl, channelId, ids)) {
      return 'One or more messages can no longer be deleted.';
    }

    final keys = [for (final id in ids) (siteUrl: siteUrl, messageId: id)];
    for (final key in keys) {
      if (_messageDeletionWrites.containsKey(key) ||
          _messageEditWrites.containsKey(key) ||
          _messagePinWrites.containsKey(key) ||
          _messageFlagWrites.containsKey(key) ||
          _messageRebakeWrites.containsKey(key)) {
        return 'Another message change is still finishing.';
      }
    }

    final request = Object();
    final lease = _requests.capture(siteUrl);
    for (final key in keys) {
      _messageDeletionWrites[key] = request;
    }

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        keys.every((key) => identical(_messageDeletionWrites[key], request));

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      if (!canDeleteMessages(siteUrl, channelId, ids)) {
        return 'One or more messages can no longer be deleted.';
      }

      await api.deleteChatMessages(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
        messageIds: ids,
      );
      if (!ownsRequest()) return null;

      lease.commit(() => _markMessagesDeleted(siteUrl, channelId, ids));
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (ownsRequest()) {
        _report(error, stackTrace, 'chat.deleteMessages');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      for (final key in keys) {
        if (identical(_messageDeletionWrites[key], request)) {
          _messageDeletionWrites.remove(key);
        }
      }
    }
  }

  bool canMoveMessages(
    String siteUrl,
    int channelId,
    Iterable<int> messageIds,
  ) {
    final source = channel(siteUrl, channelId);
    final ids = messageIds.toSet();
    if (isDisposed ||
        _currentUserFor(siteUrl) == null ||
        source == null ||
        !source.isCategoryChannel ||
        !source.canModerate ||
        ids.isEmpty) {
      return false;
    }
    return ids.every((id) {
      final message = _store.read<ChatMessage>(siteUrl, id);
      return message != null &&
          message.id > 0 &&
          message.channelId == channelId &&
          !message.isOptimistic &&
          !message.isDeleted;
    });
  }

  List<ChatChannel> messageMoveDestinations(
    String siteUrl,
    int sourceChannelId,
  ) => List.unmodifiable([
    for (final channel in publicChannels(siteUrl))
      if (channel.id != sourceChannelId && channel.isCategoryChannel) channel,
  ]);

  Future<({ChatMessageMove? move, String? error})> moveMessages(
    String siteUrl,
    int channelId,
    int destinationChannelId,
    Iterable<int> messageIds,
  ) async {
    final ids = messageIds.toSet().toList()..sort();
    if (!canMoveMessages(siteUrl, channelId, ids)) {
      return (
        move: null,
        error: 'One or more messages can no longer be moved.',
      );
    }
    final destinations = messageMoveDestinations(siteUrl, channelId);
    if (!destinations.any((channel) => channel.id == destinationChannelId)) {
      return (move: null, error: 'Choose another public channel.');
    }

    final keys = [for (final id in ids) (siteUrl: siteUrl, messageId: id)];
    for (final key in keys) {
      if (_messageDeletionWrites.containsKey(key) ||
          _messageEditWrites.containsKey(key) ||
          _messagePinWrites.containsKey(key) ||
          _messageFlagWrites.containsKey(key) ||
          _messageRebakeWrites.containsKey(key)) {
        return (
          move: null,
          error: 'Another message change is still finishing.',
        );
      }
    }

    final request = Object();
    final lease = _requests.capture(siteUrl);
    for (final key in keys) {
      _messageDeletionWrites[key] = request;
    }

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        keys.every((key) => identical(_messageDeletionWrites[key], request));

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return (move: null, error: null);
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return (move: null, error: null);
      if (!canMoveMessages(siteUrl, channelId, ids) ||
          !messageMoveDestinations(
            siteUrl,
            channelId,
          ).any((channel) => channel.id == destinationChannelId)) {
        return (
          move: null,
          error: 'The selected messages or destination changed.',
        );
      }

      final move = await api.moveChatMessages(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
        destinationChannelId: destinationChannelId,
        messageIds: ids,
      );
      if (!ownsRequest()) return (move: null, error: null);

      lease.commit(() => _markMessagesDeleted(siteUrl, channelId, ids));
      return (move: move, error: null);
    } on WriteException catch (error) {
      return (move: null, error: error.message);
    } catch (error, stackTrace) {
      if (ownsRequest()) _report(error, stackTrace, 'chat.moveMessages');
      return (
        move: null,
        error: const WriteException(WriteFailure.unreachable).message,
      );
    } finally {
      for (final key in keys) {
        if (identical(_messageDeletionWrites[key], request)) {
          _messageDeletionWrites.remove(key);
        }
      }
    }
  }

  Future<String?> restoreMessage(String siteUrl, int messageId) =>
      _setMessageDeleted(siteUrl, messageId, deleted: false);

  Future<String?> _setMessageDeleted(
    String siteUrl,
    int messageId, {
    required bool deleted,
  }) async {
    final held = _store.read<ChatMessage>(siteUrl, messageId);
    final allowed =
        held != null &&
        (deleted
            ? canDeleteMessage(siteUrl, held)
            : canRestoreMessage(siteUrl, held));
    if (!allowed) {
      return deleted
          ? 'This message can no longer be deleted.'
          : 'This message can no longer be restored.';
    }

    final key = (siteUrl: siteUrl, messageId: messageId);
    if (_messageDeletionWrites.containsKey(key) ||
        _messageEditWrites.containsKey(key) ||
        _messagePinWrites.containsKey(key) ||
        _messageFlagWrites.containsKey(key) ||
        _messageRebakeWrites.containsKey(key)) {
      return 'Another message change is still finishing.';
    }
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _messageDeletionWrites[key] = request;

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_messageDeletionWrites[key], request);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = _store.read<ChatMessage>(siteUrl, messageId);
      if (current == null ||
          !(deleted
              ? canDeleteMessage(siteUrl, current)
              : canRestoreMessage(siteUrl, current))) {
        return deleted
            ? 'This message can no longer be deleted.'
            : 'This message can no longer be restored.';
      }
      if (deleted) {
        await api.deleteChatMessage(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: held.channelId,
          messageId: held.id,
        );
      } else {
        await api.restoreChatMessage(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: held.channelId,
          messageId: held.id,
        );
      }
      if (!ownsRequest()) return null;
      lease.commit(() {
        final latest = _store.read<ChatMessage>(siteUrl, messageId);
        if (latest == null || latest.isDeleted == deleted) return;
        final deletedAt = deleted ? _clock().toUtc() : null;
        _store.put(
          siteUrl,
          latest.withDeletedAt(
            deletedAt,
            deletedById: deleted ? _currentUserFor(siteUrl)?.id : null,
            clearDeletedById: !deleted,
          ),
        );
        _bumpStreamsHolding(siteUrl, messageId);
        _setLoadedThreadOriginalDeleted(
          siteUrl,
          latest.channelId,
          messageId,
          deletedAt: deletedAt,
          clear: !deleted,
        );
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (ownsRequest()) {
        _report(
          error,
          stackTrace,
          'chat.${deleted ? 'delete' : 'restore'}Message',
        );
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_messageDeletionWrites[key], request)) {
        _messageDeletionWrites.remove(key);
      }
    }
  }

  bool messageEditWriteInFlight(String siteUrl, int messageId) =>
      _messageEditWrites.containsKey((siteUrl: siteUrl, messageId: messageId));

  bool messageRebakeWriteInFlight(String siteUrl, int messageId) =>
      _messageRebakeWrites.containsKey((
        siteUrl: siteUrl,
        messageId: messageId,
      ));

  Future<String?> rebakeMessage(String siteUrl, int messageId) async {
    final held = _store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !canRebakeMessage(siteUrl, held)) {
      return 'This message can no longer be rebuilt.';
    }

    final key = (siteUrl: siteUrl, messageId: messageId);
    if (_messageRebakeWrites.containsKey(key) ||
        _messageEditWrites.containsKey(key) ||
        _messageDeletionWrites.containsKey(key) ||
        _messagePinWrites.containsKey(key) ||
        _messageFlagWrites.containsKey(key)) {
      return 'Another message change is still finishing.';
    }
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _messageRebakeWrites[key] = request;

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_messageRebakeWrites[key], request);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = _store.read<ChatMessage>(siteUrl, messageId);
      if (current == null || !canRebakeMessage(siteUrl, current)) {
        return 'This message can no longer be rebuilt.';
      }
      await api.rebakeChatMessage(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: current.channelId,
        messageId: current.id,
      );
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (ownsRequest()) _report(error, stackTrace, 'chat.rebakeMessage');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_messageRebakeWrites[key], request)) {
        _messageRebakeWrites.remove(key);
      }
    }
  }

  bool messageQuoteWriteInFlight(String siteUrl, int channelId) =>
      _messageQuoteWrites.containsKey((siteUrl: siteUrl, channelId: channelId));

  /// Uses core's transcript serializer to preserve web-compatible `[chat]` markup.
  Future<({String? markdown, String? error})> generateMessageQuote(
    String siteUrl,
    int channelId,
    Iterable<int> messageIds,
  ) async {
    final ids = messageIds.toSet().toList()..sort();
    if (ids.isEmpty) {
      return (markdown: null, error: 'Select at least one message.');
    }
    for (final id in ids) {
      final held = _store.read<ChatMessage>(siteUrl, id);
      if (id <= 0 || held == null || held.channelId != channelId) {
        return (
          markdown: null,
          error: 'One of those messages is no longer available.',
        );
      }
    }

    final key = (siteUrl: siteUrl, channelId: channelId);
    if (_messageQuoteWrites.containsKey(key)) {
      return (markdown: null, error: 'That transcript is still being built.');
    }
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _messageQuoteWrites[key] = request;

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_messageQuoteWrites[key], request);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return (markdown: null, error: null);
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return (markdown: null, error: null);
      final markdown = await api.generateChatQuote(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
        messageIds: ids,
      );
      return ownsRequest()
          ? (markdown: markdown, error: null)
          : (markdown: null, error: null);
    } on WriteException catch (error) {
      return (markdown: null, error: error.message);
    } catch (error, stackTrace) {
      if (ownsRequest()) {
        _report(error, stackTrace, 'chat.generateMessageQuote');
      }
      return (
        markdown: null,
        error: const WriteException(WriteFailure.unreachable).message,
      );
    } finally {
      if (identical(_messageQuoteWrites[key], request)) {
        _messageQuoteWrites.remove(key);
      }
    }
  }

  Future<String?> editMessage(
    String siteUrl,
    int messageId,
    String raw, {
    List<ChatUpload>? uploads,
  }) async {
    final held = _store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !canEditMessage(siteUrl, held)) {
      return 'This message can no longer be edited.';
    }
    if (raw.trim().isEmpty) return 'A message cannot be empty.';
    if (raw.length > ChatMessage.maximumEditLength) {
      return 'Messages can be at most ${ChatMessage.maximumEditLength} characters.';
    }
    final editedUploads = List<ChatUpload>.unmodifiable(
      (uploads ?? held.uploads).take(ChatMessage.maximumUploadsPerMessage),
    );
    final uploadIds = [
      for (final upload in editedUploads)
        if (upload.id > 0) upload.id,
    ];
    bool hasUploadIds(List<ChatUpload> candidate) => listEquals([
      for (final upload in candidate)
        if (upload.id > 0) upload.id,
    ], uploadIds);
    if (raw == held.raw && hasUploadIds(held.uploads)) return null;

    final key = (siteUrl: siteUrl, messageId: messageId);
    if (_messageEditWrites.containsKey(key) ||
        _messageDeletionWrites.containsKey(key) ||
        _messagePinWrites.containsKey(key) ||
        _messageFlagWrites.containsKey(key) ||
        _messageRebakeWrites.containsKey(key)) {
      return 'Another edit is still finishing.';
    }
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _messageEditWrites[key] = request;

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_messageEditWrites[key], request);

    final preview = _previewEngine.project(
      ChatPreviewRequest(raw: raw, siteConfig: _siteConfigFor(siteUrl)),
    );
    _store.put(
      siteUrl,
      held.withPendingEdit(raw, preview, uploads: editedUploads),
    );

    bool canonicalEditArrived() {
      final current = _store.read<ChatMessage>(siteUrl, messageId);
      return current?.canonicalReceived == true &&
          current?.raw == raw &&
          hasUploadIds(current!.uploads);
    }

    void rollback() {
      if (!ownsRequest() || canonicalEditArrived()) return;
      lease.commit(() {
        final latest = _store.read<ChatMessage>(siteUrl, messageId);
        if (latest != null) _store.put(siteUrl, latest.withContentOf(held));
      });
    }

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = _store.read<ChatMessage>(siteUrl, messageId);
      if (current == null ||
          current.raw != raw ||
          !hasUploadIds(current.uploads)) {
        rollback();
        return 'This message changed before the edit could be saved.';
      }
      await api.editChatMessage(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: held.channelId,
        messageId: held.id,
        message: raw,
        uploadIds: uploadIds,
      );
      return null;
    } on WriteException catch (error) {
      if (canonicalEditArrived()) return null;
      rollback();
      return error.message;
    } catch (error, stackTrace) {
      if (canonicalEditArrived()) return null;
      if (ownsRequest()) _report(error, stackTrace, 'chat.editMessage');
      rollback();
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_messageEditWrites[key], request)) {
        _messageEditWrites.remove(key);
      }
    }
  }

  int _bookmarkVersion(String siteUrl) => _bookmarkVersions[siteUrl] ?? 0;

  void _advanceBookmarkVersion(String siteUrl) {
    _bookmarkVersions[siteUrl] = _bookmarkVersion(siteUrl) + 1;
  }

  void putMessageBookmark(String siteUrl, int messageId, Bookmark bookmark) {
    _advanceBookmarkVersion(siteUrl);
    _store.update<ChatMessage>(
      siteUrl,
      messageId,
      (message) => message.withBookmark(bookmark),
    );
  }

  void removeMessageBookmark(String siteUrl, int messageId) {
    _advanceBookmarkVersion(siteUrl);
    _store.update<ChatMessage>(
      siteUrl,
      messageId,
      (message) => message.withBookmark(null),
    );
  }

  Future<void> reconcileMessageBookmark(String siteUrl, ChatMessage message) {
    final threadId = message.threadId;
    if (threadId != null && message.thread == null) {
      return openThread(
        siteUrl,
        ChatThreadTarget(channelId: message.channelId, threadId: threadId),
        targetMessageId: message.id,
        force: true,
      );
    }
    return openChannel(
      siteUrl,
      message.channelId,
      targetMessageId: message.id,
      force: true,
    );
  }

  void _putMessages(
    String siteUrl,
    Iterable<ChatMessage> incoming, {
    required int bookmarkVersionAtDispatch,
  }) {
    final preserveBookmarks =
        bookmarkVersionAtDispatch != _bookmarkVersion(siteUrl);
    _store.putAll(
      siteUrl,
      preserveBookmarks
          ? [
              for (final message in incoming)
                switch (_store.read<ChatMessage>(siteUrl, message.id)) {
                  final held? => message.withBookmarkOf(held),
                  null => message,
                },
            ]
          : incoming,
    );
  }

  /// Adding requires both message interaction permission and channel membership.
  bool canAddReactionToMessage(String siteUrl, ChatMessage message) =>
      _canChangeMessageReaction(siteUrl, message, requireFollowing: true);

  /// Discourse permits removing a reaction after leaving the channel.
  bool canRemoveReactionFromMessage(String siteUrl, ChatMessage message) =>
      _canChangeMessageReaction(siteUrl, message, requireFollowing: false);

  bool _canChangeMessageReaction(
    String siteUrl,
    ChatMessage message, {
    required bool requireFollowing,
  }) {
    if (isDisposed ||
        message.id <= 0 ||
        message.isDeleted ||
        message.isOptimistic) {
      return false;
    }
    final heldChannel = channel(siteUrl, message.channelId);
    return heldChannel != null &&
        (!requireFollowing || heldChannel.membership.following) &&
        heldChannel.canModifyMessages(
          isStaff: _currentUserFor(siteUrl)?.staff ?? false,
        );
  }

  /// Picker selection is an explicit add, not a toggle.
  Future<String?> addMessageReaction(
    String siteUrl,
    int messageId,
    String emoji,
  ) => _setMessageReaction(siteUrl, messageId, emoji, reacted: true);

  /// Serializes writes per message/emoji. A refusal rolls back only this
  /// reader's participation, preserving concurrent reaction changes.
  Future<String?> toggleMessageReaction(
    String siteUrl,
    int messageId,
    String emoji,
  ) => _setMessageReaction(siteUrl, messageId, emoji);

  Future<String?> _setMessageReaction(
    String siteUrl,
    int messageId,
    String emoji, {
    bool? reacted,
  }) async {
    if (isDisposed) return null;
    final message = _store.read<ChatMessage>(siteUrl, messageId);
    if (message == null ||
        message.id <= 0 ||
        message.isDeleted ||
        message.isOptimistic ||
        emoji.isEmpty) {
      return null;
    }
    final held = message.reactions
        .where((reaction) => reaction.emoji == emoji)
        .firstOrNull;
    final wasReacted = held?.reacted ?? false;
    final adding = reacted ?? !wasReacted;
    if (adding == wasReacted) return null;
    if (!(adding
        ? canAddReactionToMessage(siteUrl, message)
        : canRemoveReactionFromMessage(siteUrl, message))) {
      return null;
    }

    final key = (siteUrl: siteUrl, messageId: messageId, emoji: emoji);
    if (_reactionWrites.containsKey(key)) return null;
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _reactionWrites[key] = request;

    final readerId = _currentUserFor(siteUrl)?.id;
    _store.put(
      siteUrl,
      message.withReaction(emoji, reacted: adding, userId: readerId),
    );

    bool ownsRequest() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_reactionWrites[key], request);

    void rollback() {
      if (!ownsRequest()) return;
      lease.commit(() {
        final latest = _store.read<ChatMessage>(siteUrl, messageId);
        if (latest != null) {
          _store.put(
            siteUrl,
            latest.withReaction(emoji, reacted: !adding, userId: readerId),
          );
        }
      });
    }

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = _store.read<ChatMessage>(siteUrl, messageId);
      if (current == null ||
          !(adding
              ? canAddReactionToMessage(siteUrl, current)
              : canRemoveReactionFromMessage(siteUrl, current))) {
        rollback();
        return null;
      }
      await api.setChatMessageReaction(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: message.channelId,
        messageId: message.id,
        emoji: emoji,
        action: adding ? ChatReactionAction.add : ChatReactionAction.remove,
      );
      if (!ownsRequest()) return null;
      lease.commit(() {
        final latest = _store.read<ChatMessage>(siteUrl, messageId);
        if (latest != null) {
          _store.put(
            siteUrl,
            latest.withReaction(emoji, reacted: adding, userId: readerId),
          );
        }
      });
      return null;
    } on WriteException catch (error) {
      rollback();
      return error.message;
    } catch (error, stackTrace) {
      if (ownsRequest()) {
        _report(error, stackTrace, 'chat.toggleReaction');
      }
      rollback();
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_reactionWrites[key], request)) {
        _reactionWrites.remove(key);
      }
    }
  }

  ChatMessageReactors? messageReactors(
    String siteUrl,
    int channelId,
    int messageId, {
    String? filter,
  }) => _store.read<ChatMessageReactors>(
    siteUrl,
    ChatMessageReactors.key(channelId, messageId, filter),
  );

  String? messageReactorsError(
    String siteUrl,
    int channelId,
    int messageId, {
    String? filter,
  }) =>
      _reactorErrors[(
        siteUrl: siteUrl,
        channelId: channelId,
        messageId: messageId,
        filter: filter,
      )];

  /// Uses chat's authenticated channel-scoped endpoint and retains the previous
  /// page while one request per exact filter refreshes it.
  Future<void> loadMessageReactors({
    required String siteUrl,
    required int channelId,
    required int messageId,
    String? filter,
  }) async {
    if (isDisposed) return;
    final key = (
      siteUrl: siteUrl,
      channelId: channelId,
      messageId: messageId,
      filter: filter,
    );
    if (_reactorRequests.containsKey(key)) return;
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _reactorRequests[key] = request;
    notifySafely();

    bool ownsRequest() => identical(_reactorRequests[key], request);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      if (apiKey == null) {
        throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
      }

      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final fetched = await api.chatMessageReactors(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
        messageId: messageId,
        reaction: filter,
      );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        _store.put(siteUrl, fetched);
        _reactorErrors.remove(key);
      });
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      _report(
        error,
        stackTrace,
        'chat.loadReactionUsers',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        if (messageReactors(siteUrl, channelId, messageId, filter: filter) ==
            null) {
          _reactorErrors[key] = 'Could not find out who reacted.';
        }
      });
    } finally {
      if (!isDisposed && identical(_reactorRequests[key], request)) {
        _reactorRequests.remove(key);
        notifySafely();
      }
    }
  }

  ChatStreamState stream(String siteUrl, int channelId) =>
      streamFor(siteUrl, ChatChannelTarget(channelId));

  ChatStreamState streamFor(String siteUrl, ChatStreamTarget target) =>
      _streams[_targetKey(siteUrl, target)] ?? const ChatStreamState();

  ValueListenable<ChatStreamState> streamListenable(
    String siteUrl,
    int channelId,
  ) => streamListenableFor(siteUrl, ChatChannelTarget(channelId));

  ValueListenable<ChatStreamState> streamListenableFor(
    String siteUrl,
    ChatStreamTarget target,
  ) {
    final key = _targetKey(siteUrl, target);
    return _streamRefs.putIfAbsent(
      key,
      () => FrameSafeValueNotifier(_streams[key] ?? const ChatStreamState()),
    );
  }

  bool isOnline(String siteUrl, int userId) =>
      _liveSync.isOnline(siteUrl, userId);

  /// Limits presence rebuilds to consumers of the row-scoped set.
  ValueListenable<Set<int>> onlineUserIdsListenable(String siteUrl) =>
      _liveSync.onlineUserIdsListenable(siteUrl);

  /// Chat owns subscriptions, while core retains MessageBus lifetime ownership.
  void attachTracker(String siteUrl, PluginLiveChannelHandle channels) =>
      _liveSync.attachTracker(siteUrl, channels);

  void _removeKickedChannelState(String siteUrl, int channelId) {
    final key = _streamKey(siteUrl, channelId);
    _publicIds[siteUrl]?.remove(channelId);
    _directIds[siteUrl]?.remove(channelId);
    _partialChannelIds[siteUrl]?.remove(channelId);
    final threadPrefix = '$siteUrl~channel-$channelId-thread-';
    final unavailableStreams = _streams.keys
        .where(
          (targetKey) => targetKey == key || targetKey.startsWith(threadPrefix),
        )
        .toList(growable: false);
    for (final targetKey in unavailableStreams) {
      final current = _streams[targetKey]!;
      _setStream(
        targetKey,
        ChatStreamState(
          fetchedOnce: true,
          fetches: current.fetches,
          error: 'You no longer have access to this channel.',
          revision: current.revision + 1,
        ),
      );
    }
    _store.remove<ChatChannel>(siteUrl, channelId);
    notifySafely();
  }

  void _admitActivityMessage(
    String siteUrl,
    int channelId,
    ChatMessage canonical,
  ) {
    final key = _streamKey(siteUrl, channelId);
    // Live events extend only a present window. An anchored window keeps its
    // gap and obtains the message through forward paging.
    final window = stream(siteUrl, channelId);
    if (window.fetchedOnce &&
        window.atPresent &&
        !window.messageIds.contains(canonical.id)) {
      _putLiveMessage(siteUrl, canonical, preservePersonalizedState: true);
      _setStream(
        key,
        window.copyWith(
          // Root and thread channels race to deliver this event; reduction
          // makes clock-skewed insertion deterministic in either order.
          messageIds: ChatMessageTimeline.admitLive(
            held: _timelineSnapshot(siteUrl, window.messageIds),
            message: canonical,
          ),
          localMessageIds: _retireCanonicalLocals(siteUrl, window, [canonical]),
        ),
      );
    }
  }

  void _admitLiveMessage(
    String siteUrl,
    ChatStreamTarget target,
    ChatMessage message,
  ) {
    final key = _targetKey(siteUrl, target);
    _applyLiveMessage(siteUrl, key, streamFor(siteUrl, target), message);
  }

  /// Lazy lookup means only clock-skew insertion walks the canonical window.
  ChatTimelineSnapshot _timelineSnapshot(String siteUrl, List<int> ids) =>
      ChatTimelineSnapshot(
        ids: ids,
        messageById: (id) => _store.read<ChatMessage>(siteUrl, id),
      );

  /// Atomically drains sent events that outran the page closing a window's seam;
  /// otherwise they exist in neither the response nor the held list.
  ({List<int> ids, List<ChatMessage> stragglers}) _withSeamStragglers(
    String siteUrl,
    Set<int> pendingIds,
    List<int> held,
  ) {
    final seam = ChatMessageTimeline.closeSeam(
      held: _timelineSnapshot(siteUrl, held),
      pending: [
        for (final id in pendingIds) ?_store.read<ChatMessage>(siteUrl, id),
      ],
    );
    pendingIds.clear();
    // Return stragglers so their matching optimistic overlays retire atomically.
    return (ids: seam.ids, stragglers: seam.admittedPending);
  }

  /// Invalidates ID-keyed projections when a live record changes rendered shape.
  void _putLiveMessage(
    String siteUrl,
    ChatMessage message, {
    bool preservePersonalizedState = false,
  }) {
    final replaced = _store.read<ChatMessage>(siteUrl, message.id);
    final effective = replaced == null
        ? message
        : preservePersonalizedState
        ? message.withPersonalizedStateOf(
            replaced,
            currentUserId: _currentUserFor(siteUrl)?.id,
          )
        : replaced.bookmark != null && message.bookmark == null
        ? message.withBookmarkOf(replaced)
        : message;
    _store.put(siteUrl, effective);
    if (replaced != null &&
        (replaced.isDeleted != effective.isDeleted ||
            replaced.pinned != effective.pinned)) {
      _bumpStreamsHolding(siteUrl, message.id);
    }
  }

  void _bumpStreamsHolding(String siteUrl, int messageId) {
    final prefix = '$siteUrl~';
    final stale = [
      for (final entry in _streams.entries)
        if (entry.key.startsWith(prefix) &&
            entry.value.messageIds.contains(messageId))
          entry.key,
    ];
    for (final key in stale) {
      final window = _streams[key]!;
      _setStream(key, window.copyWith(revision: window.revision + 1));
    }
  }

  void _applyPinEvent(
    String siteUrl,
    Map<String, dynamic> data, {
    int? channelId,
  }) {
    final messageId = jsonIntOrNull(data['chat_message_id']);
    if (messageId == null) return;
    final message = _store.read<ChatMessage>(siteUrl, messageId);
    final pinned = data['type'] == 'pin';
    var changed = false;
    if (message != null && message.pinned != pinned) {
      changed = true;
      _store.put(siteUrl, message.withPinned(pinned));
      _bumpStreamsHolding(siteUrl, messageId);
    }

    final resolvedChannelId =
        message?.channelId ?? channelId ?? jsonIntOrNull(data['channel_id']);
    if (resolvedChannelId != null) {
      _store.update<ChatChannel>(siteUrl, resolvedChannelId, (channel) {
        final authoritative = jsonIntOrNull(data['pinned_message_count']);
        final count =
            authoritative ??
            channel.pinnedMessagesCount + (changed ? (pinned ? 1 : -1) : 0);
        final actor = jsonIntOrNull(data['pinned_by_id']);
        final unseen =
            pinned && actor != null && actor != _currentUserFor(siteUrl)?.id
            ? true
            : channel.membership.hasUnseenPins;
        return channel.withPinnedMessagesCount(count, hasUnseenPins: unseen);
      });

      final ref = _pinListRefs[_pinsKey(siteUrl, resolvedChannelId)];
      if (ref != null && ref.value.fetched) {
        if (!pinned) {
          ref.value = ref.value.copyWith(
            pins: List.unmodifiable([
              for (final pin in ref.value.pins)
                if (pin.messageId != messageId) pin,
            ]),
            clearError: true,
          );
        } else {
          unawaited(
            loadPinnedMessages(siteUrl, resolvedChannelId, force: true),
          );
        }
      }
    }
  }

  void _applySelfFlaggedEvent(String siteUrl, Map<String, dynamic> data) {
    final messageId = jsonIntOrNull(data['chat_message_id']);
    final status = jsonIntOrNull(data['user_flag_status']);
    if (messageId == null || status == null) return;
    _store.update<ChatMessage>(
      siteUrl,
      messageId,
      (message) => message.withUserFlagStatus(status),
    );
  }

  void _applyFlagEvent(String siteUrl, Map<String, dynamic> data) {
    final messageId = jsonIntOrNull(data['chat_message_id']);
    final reviewableId = jsonIntOrNull(data['reviewable_id']);
    if (messageId == null || reviewableId == null) return;
    _store.update<ChatMessage>(
      siteUrl,
      messageId,
      (message) => message.withReviewableId(reviewableId),
    );
  }

  /// Tombstones [ids] locally once the site has accepted their deletion or
  /// move, ahead of the bus echo that confirms it.
  void _markMessagesDeleted(String siteUrl, int channelId, List<int> ids) {
    final deletedAt = _clock().toUtc();
    final deletedById = _currentUserFor(siteUrl)?.id;
    for (final id in ids) {
      final latest = _store.read<ChatMessage>(siteUrl, id);
      if (latest == null || latest.isDeleted) continue;
      _store.put(
        siteUrl,
        latest.withDeletedAt(deletedAt, deletedById: deletedById),
      );
      _bumpStreamsHolding(siteUrl, id);
      _setLoadedThreadOriginalDeleted(
        siteUrl,
        channelId,
        id,
        deletedAt: deletedAt,
      );
    }
  }

  /// Applies one deleted id from a delete event. A reader allowed to inspect
  /// the tombstone keeps the row; anyone else loses it. Answers the message
  /// as it was held, or null when it was not held at all.
  ChatMessage? _applyDeletedId(
    String siteUrl,
    Map<String, dynamic> data,
    int deletedId,
  ) {
    final message = _store.read<ChatMessage>(siteUrl, deletedId);
    if (message == null) return null;
    if (_canInspectDeletedMessage(siteUrl, message)) {
      _store.put(
        siteUrl,
        message.withDeletedAt(
          jsonDate(data['deleted_at']) ?? _clock().toUtc(),
          deletedById: jsonIntOrNull(data['deleted_by_id']),
        ),
      );
    } else {
      _store.remove<ChatMessage>(siteUrl, deletedId);
    }
    if (!message.isDeleted) _bumpStreamsHolding(siteUrl, deletedId);
    return message;
  }

  void _applyDeleteEvent(
    String siteUrl,
    Map<String, dynamic> data, {
    int? channelId,
    ChatThread? thread,
  }) {
    final deletedId = jsonIntOrNull(data['deleted_id']);
    if (deletedId == null) return;
    final message = _applyDeletedId(siteUrl, data, deletedId);

    final latest = jsonIntOrNull(data['latest_not_deleted_message_id']);
    final resolvedChannelId = channelId ?? message?.channelId;
    final heldChannel = resolvedChannelId == null
        ? null
        : channel(siteUrl, resolvedChannelId);
    if (heldChannel?.membership.lastReadMessageId == deletedId) {
      _store.put(siteUrl, heldChannel!.withLastReadAfterDelete(latest));
    }
    if (thread == null) return;

    final membership = thread.membership;
    final movesReadCursor = membership?.lastReadMessageId == deletedId;
    final movesLastMessage = thread.lastMessageId == deletedId;
    if (!movesReadCursor && !movesLastMessage) return;
    _store.update<ChatThread>(siteUrl, thread.id, (current) {
      final currentMembership = current.membership;
      return current.copyWith(
        lastMessageId: movesLastMessage ? latest : current.lastMessageId,
        clearLastMessageId: movesLastMessage && latest == null,
        membership: movesReadCursor && currentMembership != null
            ? currentMembership.copyWith(
                lastReadMessageId: latest,
                clearLastReadMessageId: latest == null,
              )
            : currentMembership,
      );
    });
  }

  void _applyBulkDeleteEvent(
    String siteUrl,
    Map<String, dynamic> data, {
    int? channelId,
    ChatThread? thread,
    int? skipMessageId,
  }) {
    final deletedIds = <int>{};
    for (final value
        in data['deleted_ids'] is List
            ? data['deleted_ids'] as List
            : const []) {
      final deletedId = jsonIntOrNull(value);
      if (deletedId == null || deletedId == skipMessageId) continue;
      deletedIds.add(deletedId);
      _applyDeletedId(siteUrl, data, deletedId);
    }
    final heldChannel = channelId == null ? null : channel(siteUrl, channelId);
    if (heldChannel != null &&
        deletedIds.contains(heldChannel.membership.lastReadMessageId)) {
      _store.put(siteUrl, heldChannel.withLastReadAfterDelete(null));
    }
    if (thread != null) {
      final movesRead = deletedIds.contains(
        thread.membership?.lastReadMessageId,
      );
      final movesLast = deletedIds.contains(thread.lastMessageId);
      if (movesRead || movesLast) {
        _store.update<ChatThread>(siteUrl, thread.id, (current) {
          final membership = current.membership;
          return current.copyWith(
            clearLastMessageId: movesLast,
            membership: movesRead && membership != null
                ? membership.copyWith(clearLastReadMessageId: true)
                : membership,
          );
        });
      }
    }
  }

  bool _canInspectDeletedMessage(String siteUrl, ChatMessage message) {
    final user = _currentUserFor(siteUrl);
    return user?.staff == true ||
        channel(siteUrl, message.channelId)?.canModerate == true ||
        user?.id == message.author.id;
  }

  /// Projects root deletion into compact thread-list copies held outside the
  /// canonical message record.
  void _setLoadedThreadOriginalDeleted(
    String siteUrl,
    int channelId,
    int originalMessageId, {
    DateTime? deletedAt,
    bool clear = false,
  }) {
    final candidateIds = <int>{
      ...?_channelThreadIds[_channelThreadsKey(siteUrl, channelId)],
      ...?_myThreadIds[siteUrl],
    };
    var changed = false;
    for (final threadId in candidateIds) {
      final held = thread(siteUrl, threadId);
      final original = held?.originalMessage;
      if (held == null ||
          held.channelId != channelId ||
          original == null ||
          original.id != originalMessageId) {
        continue;
      }
      final nextDeletedAt = clear ? null : deletedAt;
      if (original.deletedAt == nextDeletedAt) continue;
      _store.put(
        siteUrl,
        held.copyWith(
          originalMessage: original.copyWith(
            deletedAt: deletedAt,
            clearDeletedAt: clear,
          ),
        ),
      );
      changed = true;
    }
    if (changed) notifySafely();
  }

  /// Applies non-idempotent reaction deltas. HTTP pages expose no MessageBus
  /// cursor, so remount replay can leave truncated reactions off until refresh.
  void _applyReactionEvent(String siteUrl, Map<String, dynamic> data) {
    final messageId = jsonIntOrNull(data['chat_message_id']);
    final emoji = jsonText(data['emoji']);
    final action = jsonText(data['action']);
    if (messageId == null || emoji == null || action == null) return;
    if (action != 'add' && action != 'remove') return;
    final message = _store.read<ChatMessage>(siteUrl, messageId);
    if (message == null) return;

    final reactions = message.reactions.toList();
    final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
    final existing = index < 0 ? null : reactions[index];
    final actorId = jsonIntOrNull(jsonObject(data['user'])['id']);
    final isCurrentUser =
        actorId != null && actorId == _currentUserFor(siteUrl)?.id;
    // The personalized bit deduplicates this reader's echo whether it arrives
    // before or after the HTTP response.
    if (isCurrentUser &&
        ((action == 'add' && existing?.reacted == true) ||
            (action == 'remove' && existing?.reacted != true))) {
      return;
    }
    // Pages have no bus cursor, so actor identity deduplicates replay. The site
    // names only five reactors; once truncated, ambiguous events must still
    // advance the live count.
    if (actorId != null && existing != null && !isCurrentUser) {
      if (action == 'add' && existing.hasReactor(actorId)) return;
      if (action == 'remove' &&
          !existing.hasReactor(actorId) &&
          existing.namesEveryReactor) {
        return;
      }
    }
    if (action == 'add') {
      final next = ChatReaction(
        emoji: emoji,
        count: (existing?.count ?? 0) + 1,
        reacted: (existing?.reacted ?? false) || isCurrentUser,
        reactorIds:
            existing?.reactorIdsWith(actorId, reacted: true) ?? [?actorId],
      );
      if (index < 0) {
        if (reactions.length >= ChatMessage.maximumReactionsPerMessage) return;
        reactions.add(next);
      } else {
        reactions[index] = next;
      }
    } else if (existing != null) {
      if (existing.count <= 1) {
        reactions.removeAt(index);
      } else {
        reactions[index] = ChatReaction(
          emoji: emoji,
          count: existing.count - 1,
          reacted: isCurrentUser ? false : existing.reacted,
          reactorIds: existing.reactorIdsWith(actorId, reacted: false),
        );
      }
    } else {
      return;
    }
    _store.put(siteUrl, message.withReactions(reactions));
  }

  void _applyLiveMessage(
    String siteUrl,
    String key,
    ChatStreamState window,
    ChatMessage message,
  ) {
    if (window.canLoadMoreFuture) {
      // Never merge a live edge into anchored history; the resulting hole
      // could not be filled by either paging direction.
      final pending = _pendingLiveMessageIds.putIfAbsent(key, () => {});
      if (!pending.add(message.id)) return;
      _setStream(
        key,
        window.copyWith(pendingNewMessages: pending.length, clearError: true),
      );
      return;
    }
    _pendingLiveMessageIds[key]?.remove(message.id);
    _setStream(
      key,
      window.copyWith(
        messageIds: ChatMessageTimeline.admitLive(
          held: _timelineSnapshot(siteUrl, window.messageIds),
          message: message,
        ),
        localMessageIds: _retireCanonicalLocals(siteUrl, window, [message]),
        clearError: true,
      ),
    );
  }

  void _scheduleThreadDetailRefresh(String siteUrl, ChatThreadTarget target) {
    // A refresh during the in-flight request dirties its answer and makes the
    // per-target drain fetch again before callers complete.
    unawaited(refreshThreadDetail(siteUrl, target));
  }

  void _setStream(String key, ChatStreamState stream) {
    _streams[key] = stream;
    _streamRefs[key]?.value = stream;
  }

  void _showStreamNotice(
    String siteUrl,
    ChatStreamTarget target,
    String notice,
  ) {
    final key = _targetKey(siteUrl, target);
    _streamNoticeTimers.remove(key)?.cancel();
    _setStream(key, streamFor(siteUrl, target).copyWith(notice: notice));

    final lease = _requests.capture(siteUrl);
    late final Timer timer;
    timer = Timer(const Duration(seconds: 4), () {
      if (!identical(_streamNoticeTimers[key], timer)) return;
      _streamNoticeTimers.remove(key);
      if (!lease.isCurrent || isDisposed) return;
      final current = _streams[key];
      if (current?.notice == notice) {
        _setStream(key, current!.copyWith(clearNotice: true));
      }
    });
    _streamNoticeTimers[key] = timer;
  }

  /// Retires optimistic overlays by server ID, or by author, target, and
  /// millisecond wire timestamp when a GET outruns both POST and MessageBus.
  List<int> _retireCanonicalLocals(
    String siteUrl,
    ChatStreamState stream,
    Iterable<ChatMessage> canonical,
  ) {
    if (stream.localMessageIds.isEmpty) return stream.localMessageIds;
    final canonicalMessages = canonical.toList(growable: false);
    final arrived = {for (final message in canonicalMessages) message.id};
    if (arrived.isEmpty) return stream.localMessageIds;

    // Reserve explicit IDs before timestamp fallback so simultaneous local
    // sends cannot claim the same canonical row.
    final explicitlyClaimed = <int>{};
    for (final id in stream.localMessageIds) {
      final serverId = _store.read<ChatMessage>(siteUrl, id)?.serverId;
      if (serverId != null && arrived.contains(serverId)) {
        explicitlyClaimed.add(serverId);
      }
    }
    final unclaimedBySend =
        <({int authorId, int createdAtMs, int? threadId}), Queue<int>>{};
    for (final message in canonicalMessages) {
      final createdAt = message.createdAt;
      if (createdAt == null || explicitlyClaimed.contains(message.id)) {
        continue;
      }
      final correlation = (
        authorId: message.author.id,
        createdAtMs: createdAt.toUtc().millisecondsSinceEpoch,
        threadId: message.threadId,
      );
      (unclaimedBySend[correlation] ??= Queue<int>()).add(message.id);
    }

    List<int>? remaining;
    for (var index = 0; index < stream.localMessageIds.length; index++) {
      final id = stream.localMessageIds[index];
      final local = _store.read<ChatMessage>(siteUrl, id);
      var matched =
          local?.serverId != null && arrived.contains(local!.serverId);
      final createdAt = local?.createdAt;
      final canUseClientTimestamp =
          !matched &&
          local != null &&
          local.serverId == null &&
          local.author.id > 0 &&
          createdAt != null &&
          !(local.delivery == ChatMessageDelivery.failed &&
              !local.deliveryUncertain);
      if (canUseClientTimestamp) {
        final correlation = (
          authorId: local.author.id,
          createdAtMs: createdAt.toUtc().millisecondsSinceEpoch,
          threadId: local.threadId,
        );
        final candidates = unclaimedBySend[correlation];
        if (candidates != null && candidates.isNotEmpty) {
          candidates.removeFirst();
          matched = true;
        }
      }
      if (!matched) {
        remaining?.add(id);
        continue;
      }

      remaining ??= stream.localMessageIds.sublist(0, index);
      _store.remove<ChatMessage>(siteUrl, id);
    }
    return remaining == null
        ? stream.localMessageIds
        : List.unmodifiable(remaining);
  }

  List<ChatMessage> messages(String siteUrl, int channelId) {
    return messagesFor(siteUrl, ChatChannelTarget(channelId));
  }

  List<ChatMessage> messagesFor(String siteUrl, ChatStreamTarget target) {
    final held = streamFor(siteUrl, target);
    return [
      for (final id in [...held.messageIds, ...held.localMessageIds])
        ?_store.read<ChatMessage>(siteUrl, id),
    ];
  }

  String? channelsError(String siteUrl) => _errors[_channelsKey(siteUrl)];

  /// In-flight network sends do not block synchronous staging.
  bool canSendMessage(String siteUrl, int channelId) =>
      canSendMessageTo(siteUrl, ChatChannelTarget(channelId));

  bool canSendMessageTo(String siteUrl, ChatStreamTarget target) {
    if (isDisposed || target.channelId <= 0 || (target.threadId ?? 1) <= 0) {
      return false;
    }
    final heldChannel = channel(siteUrl, target.channelId);
    final canModify =
        heldChannel?.canModifyMessages(
          isStaff: _currentUserFor(siteUrl)?.staff ?? false,
        ) ??
        true;
    if (target is! ChatThreadTarget) return canModify;

    final heldThread = thread(siteUrl, target.threadId);
    return heldChannel != null &&
        heldChannel.membership.following &&
        canModify &&
        heldThread != null &&
        heldThread.channelId == target.channelId &&
        heldThread.status == 'open' &&
        (heldChannel.threadingEnabled || heldThread.force) &&
        !streamFor(siteUrl, target).threadUnavailable;
  }

  bool _canCreateThread(String siteUrl, int channelId) {
    final held = channel(siteUrl, channelId);
    return !isDisposed &&
        held != null &&
        held.membership.following &&
        held.threadingEnabled &&
        held.canModifyMessages(
          isStaff: _currentUserFor(siteUrl)?.staff ?? false,
        );
  }

  /// Commits the local row before its first await; `staged_id` lets MessageBus
  /// replace it without an extra newest-page fetch.
  ChatSendHandle? sendMessage(
    String siteUrl,
    int channelId,
    OutgoingChatMessage message,
  ) => sendMessageTo(siteUrl, ChatChannelTarget(channelId), message);

  ChatSendHandle? sendMessageTo(
    String siteUrl,
    ChatStreamTarget target,
    OutgoingChatMessage message,
  ) => _sendCoordinator.sendMessage(siteUrl, target, message);

  void _stageOutgoing(
    String siteUrl,
    ChatStreamTarget target,
    ChatMessage local,
  ) {
    final key = _targetKey(siteUrl, target);
    _store.put(siteUrl, local);
    final held = streamFor(siteUrl, target);
    _setStream(
      key,
      held.copyWith(
        localMessageIds: List.unmodifiable([...held.localMessageIds, local.id]),
        clearError: true,
      ),
    );
  }

  ChatPreviewResult _projectPreview(
    String siteUrl,
    OutgoingChatMessage message,
  ) {
    try {
      return _previewEngine.project(
        ChatPreviewRequest(
          raw: message.raw,
          siteConfig: _siteConfigFor(siteUrl),
          trustedSeed: message.trustedPreviewSeed,
        ),
      );
    } catch (_) {
      return SourceFallback(
        message.raw,
        ChatPreviewFallbackReason.internalFailure,
      );
    }
  }

  void _markOutgoingSent(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
    int? serverId,
  ) {
    final localId = _updateOutgoing(
      siteUrl,
      target,
      stagedId,
      (held) => held.withSendState(
        delivery: ChatMessageDelivery.sent,
        serverId: serverId,
      ),
    );
    if (serverId != null &&
        localId != null &&
        streamFor(siteUrl, target).messageIds.contains(serverId)) {
      _removeLocalMessage(siteUrl, target, localId);
    }
  }

  bool _markOutgoingFailed(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
    WriteException failure,
  ) {
    var canonicalAlreadyArrived = false;
    _updateOutgoing(siteUrl, target, stagedId, (held) {
      canonicalAlreadyArrived = held.serverId != null;
      return canonicalAlreadyArrived
          ? held
          : held.withSendState(
              delivery: ChatMessageDelivery.failed,
              error: failure.message,
              deliveryUncertain: failure.failure == WriteFailure.unreachable,
            );
    });
    return canonicalAlreadyArrived;
  }

  void _onOutgoingSent(String siteUrl, ChatStreamTarget target) {
    if (target is ChatThreadTarget) {
      _scheduleThreadDetailRefresh(siteUrl, target);
    }
  }

  int? _updateOutgoing(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
    ChatMessage Function(ChatMessage held) update,
  ) {
    final window = streamFor(siteUrl, target);
    for (final id in window.localMessageIds) {
      final held = _store.read<ChatMessage>(siteUrl, id);
      if (held?.stagedId != stagedId) continue;
      _store.put(siteUrl, update(held!));
      return id;
    }
    return null;
  }

  void _removeLocalMessage(
    String siteUrl,
    ChatStreamTarget target,
    int localId,
  ) {
    final key = _targetKey(siteUrl, target);
    final window = _streams[key];
    if (window == null || !window.localMessageIds.contains(localId)) return;
    _setStream(
      key,
      window.copyWith(
        localMessageIds: List.unmodifiable(
          window.localMessageIds.where((id) => id != localId),
        ),
      ),
    );
    _store.remove<ChatMessage>(siteUrl, localId);
    _sendCoordinator.releaseReconciliationIfSettled(siteUrl, target);
  }

  bool _hasUnsettledOutgoingMessages(String siteUrl, ChatStreamTarget target) {
    final window = streamFor(siteUrl, target);
    for (final id in window.localMessageIds) {
      final local = _store.read<ChatMessage>(siteUrl, id);
      if (local == null) continue;
      if (local.delivery == ChatMessageDelivery.sending ||
          local.deliveryUncertain ||
          local.delivery == ChatMessageDelivery.sent &&
              !local.canonicalReceived) {
        return true;
      }
    }
    return false;
  }

  void _applySendMessage(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
    Object? payload,
  ) {
    final window = streamFor(siteUrl, target);
    for (final id in window.localMessageIds) {
      final local = _store.read<ChatMessage>(siteUrl, id);
      if (local?.stagedId != stagedId) continue;

      // This temporary listener only reconciles this client's remaining local rows.
      if (payload is! Map<String, dynamic>) return;
      final canonical = ChatMessage.fromJson(payload, siteUrl);
      if (canonical.id <= 0 ||
          canonical.channelId != target.channelId ||
          canonical.threadId != target.threadId) {
        return;
      }
      final currentUserId = _currentUserFor(siteUrl)?.id;
      if (currentUserId != null && canonical.author.id != currentUserId) return;

      _putLiveMessage(siteUrl, canonical, preservePersonalizedState: true);
      final sentAt = canonical.createdAt ?? local!.createdAt;
      final heldChannel = channel(siteUrl, target.channelId);
      if (target is ChatChannelTarget &&
          sentAt != null &&
          heldChannel != null &&
          (heldChannel.lastMessageId == null ||
              canonical.id > heldChannel.lastMessageId!)) {
        final updated = heldChannel.withNewMessage(
          canonical.id,
          sentAt,
          markRead: true,
          incrementUnread: false,
        );
        _store.put(siteUrl, updated);
        _publishNotificationChange(siteUrl, heldChannel, updated);
        notifySafely();
      }
      if (window.messageIds.contains(canonical.id)) {
        _removeLocalMessage(siteUrl, target, id);
      } else {
        _store.put(siteUrl, local!.withCanonical(canonical));
      }
      return;
    }
  }

  /// Shares one bounded initial sidebar load per site; live tracking keeps it
  /// fresh, while failure leaves the site without a chat section.
  Future<void> loadChannels(String siteUrl, {bool force = false}) {
    if (isDisposed) return Future.value();
    final key = _channelsKey(siteUrl);
    if (!force && _publicIds.containsKey(siteUrl)) return Future.value();
    if ((_attempts[key] ?? 0) >= maxChannelAttempts) return Future.value();

    // The shortcut must await the shared task before choosing its destination.
    final active = _channelRequests[key];
    if (active != null) return active;

    final run = Object();
    _channelRuns[key] = run;
    late final Future<void> request;
    request = _loadChannels(siteUrl, key, run).whenComplete(() {
      if (identical(_channelRequests[key], request)) {
        final removed = _channelRequests.remove(key);
        assert(identical(removed, request));
      }
      if (identical(_channelRuns[key], run)) {
        _channelRuns.remove(key);
      }
    });
    _channelRequests[key] = request;
    return request;
  }

  Future<void> _loadChannels(String siteUrl, String key, Object run) async {
    if (!_loading.add(key)) return;

    final lease = _requests.capture(siteUrl);
    bool ownsRequest() => identical(_channelRuns[key], run);
    _attempts[key] = (_attempts[key] ?? 0) + 1;

    try {
      // Unsigned macOS keychain reads may throw; keep them inside cleanup guards.
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final channels = await api.chatChannels(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        final replacingSnapshot = _publicIds.containsKey(siteUrl);
        final previousNotifications = replacingSnapshot
            ? _chatNotifications(siteUrl)
            : 0;
        _store.putAll(siteUrl, channels.public);
        _store.putAll(siteUrl, channels.direct);
        _partialChannelIds[siteUrl]?.removeAll([
          for (final channel in [...channels.public, ...channels.direct])
            channel.id,
        ]);
        for (final channel in [...channels.public, ...channels.direct]) {
          if (_liveSync.isViewingChannel(siteUrl, channel.id)) {
            _advanceLastViewedAt(siteUrl, channel.id, notify: false);
          }
        }
        _publicIds[siteUrl] = [for (final c in channels.public) c.id];
        _directIds[siteUrl] = [for (final c in channels.direct) c.id];
        _hasThreads[siteUrl] = channels.hasThreads;
        if (replacingSnapshot) {
          final delta = _chatNotifications(siteUrl) - previousNotifications;
          if (delta != 0) onChatNotificationsDelta?.call(siteUrl, delta);
        }
        _liveSync.replace(siteUrl, channels);
        _errors.remove(key);
        _attempts.remove(key);
      });
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      _report(error, stackTrace, 'chat.loadChannels');
      lease.commit(() {
        _errors[key] = 'Could not load this site’s chat channels.';
      });
    } finally {
      if (_requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          _loading.remove(key);
          notifySafely();
        });
      }
    }
  }

  /// Uses the wire offset, not deduplicated row count, for core's thread pages.
  Future<void> loadMyThreads(
    String siteUrl, {
    bool more = false,
    bool force = false,
  }) {
    if (isDisposed) return Future.value();
    if (more && !myThreadsHaveMore(siteUrl)) return Future.value();
    if (!more && !force && myThreadsLoaded(siteUrl)) return Future.value();

    final key = _myThreadsKey(siteUrl);
    final active = _myThreadRequests[key];
    // A refresh supersedes a page already in flight: joining it would append
    // that page and leave the list unrefreshed. Replacing the run token drops
    // the older request's commit and error write.
    if (active != null && (more || !force)) return active;

    final offset = more ? (_myThreadOffsets[siteUrl] ?? 0) : 0;
    final run = Object();
    _myThreadRuns[key] = run;
    late final Future<void> request;
    request = _loadMyThreads(siteUrl, key, offset, run).whenComplete(() {
      if (identical(_myThreadRequests[key], request)) {
        final _ = _myThreadRequests.remove(key);
      }
      if (identical(_myThreadRuns[key], run)) _myThreadRuns.remove(key);
      notifySafely();
    });
    _myThreadRequests[key] = request;
    notifySafely();
    return request;
  }

  Future<void> _loadMyThreads(
    String siteUrl,
    String key,
    int offset,
    Object run,
  ) async {
    final lease = _requests.capture(siteUrl);
    bool ownsRequest() => identical(_myThreadRuns[key], run);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final page = await api.chatThreads(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        offset: offset,
      );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        for (final embedded in page.channels) {
          if (channel(siteUrl, embedded.id) != null) continue;
          _store.put(siteUrl, embedded);
          (_partialChannelIds[siteUrl] ??= {}).add(embedded.id);
        }
        _store.putAll(siteUrl, page.threads);
        final incoming = [for (final thread in page.threads) thread.id];
        if (offset == 0) {
          _myThreadIds[siteUrl] = List.unmodifiable(incoming);
        } else {
          final seen = <int>{};
          _myThreadIds[siteUrl] = List.unmodifiable([
            for (final id in [...?_myThreadIds[siteUrl], ...incoming])
              if (seen.add(id)) id,
          ]);
        }
        _myThreadOffsets[siteUrl] = offset + page.threads.length;
        _myThreadsHaveMore[siteUrl] = page.hasMore;
        if (page.threads.isNotEmpty || page.hasMore) {
          _hasThreads[siteUrl] = true;
        } else if (offset == 0) {
          _hasThreads[siteUrl] = false;
        }
        _errors.remove(key);
      });
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      _report(error, stackTrace, 'chat.loadMyThreads');
      lease.commit(() {
        _errors[key] = 'Could not load your chat threads.';
      });
    }
  }

  Future<void> loadChannelThreads(
    String siteUrl,
    int channelId, {
    bool more = false,
    bool force = false,
  }) {
    if (isDisposed || channelId <= 0) return Future.value();
    final heldChannel = channel(siteUrl, channelId);
    if (heldChannel?.threadingEnabled != true) return Future.value();
    final key = _channelThreadsKey(siteUrl, channelId);
    if (more && !channelThreadsHaveMore(siteUrl, channelId)) {
      return Future.value();
    }
    if (!more && !force && _channelThreadIds.containsKey(key)) {
      return Future.value();
    }
    final active = _channelThreadListRequests[key];
    // A refresh supersedes a page already in flight: joining it would append
    // that page and leave the list unrefreshed. Replacing the run token drops
    // the older request's commit and error write.
    if (active != null && (more || !force)) return active;

    final offset = more ? (_channelThreadOffsets[key] ?? 0) : 0;
    final run = Object();
    _channelThreadListRuns[key] = run;
    late final Future<void> request;
    request = _loadChannelThreads(siteUrl, channelId, key, offset, run)
        .whenComplete(() {
          if (identical(_channelThreadListRequests[key], request)) {
            final _ = _channelThreadListRequests.remove(key);
          }
          if (identical(_channelThreadListRuns[key], run)) {
            _channelThreadListRuns.remove(key);
          }
          notifySafely();
        });
    _channelThreadListRequests[key] = request;
    notifySafely();
    return request;
  }

  Future<void> _loadChannelThreads(
    String siteUrl,
    int channelId,
    String key,
    int offset,
    Object run,
  ) async {
    final lease = _requests.capture(siteUrl);
    bool ownsRequest() => identical(_channelThreadListRuns[key], run);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest) || apiKey == null) return;
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final page = await api.chatChannelThreads(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
        offset: offset,
      );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        _store.putAll(siteUrl, page.threads);
        final incoming = [
          for (final thread in page.threads)
            if (thread.channelId == channelId) thread.id,
        ];
        if (offset == 0) {
          _channelThreadIds[key] = List.unmodifiable(incoming);
        } else {
          final seen = <int>{};
          _channelThreadIds[key] = List.unmodifiable([
            for (final id in [...?_channelThreadIds[key], ...incoming])
              if (seen.add(id)) id,
          ]);
        }
        _channelThreadOffsets[key] = offset + page.threads.length;
        _channelThreadsHaveMore[key] = page.hasMore;
        _errors.remove(key);
      });
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      _report(error, stackTrace, 'chat.loadChannelThreads');
      lease.commit(() {
        _errors[key] = 'Could not load this channel’s threads.';
      });
    }
  }

  /// Opens at last-read so viewport-based receipts cannot credit an unseen
  /// backlog. First-time readers resolve to the latest page server-side.
  /// Remount refreshes are throttled, and each answer replaces rather than
  /// merges the window to preserve contiguity.
  Future<void> openChannel(
    String siteUrl,
    int channelId, {
    bool force = false,
    int? targetMessageId,
  }) async {
    if (isDisposed || channelId <= 0) return;
    _lastOpenedChannelIds[siteUrl] = channelId;
    final target = ChatChannelTarget(channelId);
    final key = _targetKey(siteUrl, target);
    if (!force && targetMessageId == null && _windowAttemptedRecently(key)) {
      return;
    }
    await reporter.runOperation(
      'chat.loadWindow',
      () => _fetchWindow(
        siteUrl,
        target,
        fromLastRead: targetMessageId == null,
        targetMessageId: targetMessageId,
      ),
    );
  }

  bool _windowAttemptedRecently(String key) {
    final attemptedAt = _windowAttemptedAt[key];
    return attemptedAt != null &&
        _clock().difference(attemptedAt) < minimumWindowRefreshInterval;
  }

  Future<void> openThread(
    String siteUrl,
    ChatThreadTarget target, {
    int? targetMessageId,
    bool force = false,
  }) async {
    if (isDisposed || target.channelId <= 0 || target.threadId <= 0) return;
    final key = _targetKey(siteUrl, target);
    if (!force && targetMessageId == null && _windowAttemptedRecently(key)) {
      return;
    }
    final detail = await refreshThreadDetail(siteUrl, target);
    if (detail == null || isDisposed) return;
    _liveSync.ensureThreadSubscription(siteUrl, target);
    final result = await reporter.runOperation(
      'chat.loadThreadWindow',
      () => _fetchWindow(
        siteUrl,
        target,
        fromLastRead: false,
        targetMessageId: targetMessageId,
      ),
    );
    if (result == _ChatWindowFetchResult.missingTarget &&
        targetMessageId != null) {
      final fallback = await reporter.runOperation(
        'chat.loadThreadWindowFallback',
        () => _fetchWindow(siteUrl, target, fromLastRead: false),
      );
      if (fallback == _ChatWindowFetchResult.loaded) {
        _showStreamNotice(
          siteUrl,
          target,
          'That message is unavailable. Showing the thread instead.',
        );
      }
    }
  }

  Future<ChatThread?> refreshThreadDetail(
    String siteUrl,
    ChatThreadTarget target,
  ) {
    if (isDisposed || target.channelId <= 0 || target.threadId <= 0) {
      return Future.value();
    }
    final key = _targetKey(siteUrl, target);
    _threadDetailDirty.add(key);
    final current = _threadDetailRequests[key];
    if (current != null) return current;

    late final Future<ChatThread?> request;
    request = _drainThreadDetail(siteUrl, target, key).whenComplete(() {
      if (identical(_threadDetailRequests[key], request)) {
        final _ = _threadDetailRequests.remove(key);
        _threadDetailDirty.remove(key);
      }
    });
    _threadDetailRequests[key] = request;
    return request;
  }

  Future<ChatThread?> _drainThreadDetail(
    String siteUrl,
    ChatThreadTarget target,
    String key,
  ) async {
    final lease = _requests.capture(siteUrl);
    _setStream(
      key,
      streamFor(
        siteUrl,
        target,
      ).copyWith(clearError: true, threadUnavailable: false),
    );
    while (_threadDetailDirty.remove(key)) {
      try {
        final requestCredentials = await _requests.credentialsFor(siteUrl);
        final apiKey = requestCredentials.apiKey;
        if (!lease.isCurrent || isDisposed) return null;
        final clientId = requestCredentials.clientId;
        if (!lease.isCurrent || isDisposed) return null;
        final detail = await api.chatThread(
          siteUrl: siteUrl,
          channelId: target.channelId,
          threadId: target.threadId,
          apiKey: apiKey,
          clientId: clientId,
        );
        if (!lease.isCurrent || isDisposed) return null;
        if (detail.id != target.threadId ||
            detail.channelId != target.channelId) {
          throw StateError('Thread detail did not match its requested target.');
        }
        // A preview event made this response stale; refetch before completing waiters.
        if (_threadDetailDirty.contains(key)) continue;

        ChatThread? stored;
        lease.commit(() {
          final held = thread(siteUrl, detail.id);
          if (held == null) {
            stored = _store.put(siteUrl, detail);
          } else {
            _store.update<ChatThread>(
              siteUrl,
              detail.id,
              (current) => current.withDetail(detail),
            );
            stored = thread(siteUrl, detail.id);
          }
          final merged = stored!;
          _liveSync.adoptThreadCursor(siteUrl, target, merged.messageBusLastId);
          _syncThreadOriginalPreview(siteUrl, merged);
          _setStream(
            key,
            streamFor(
              siteUrl,
              target,
            ).copyWith(clearError: true, threadUnavailable: false),
          );
        });
        _liveSync.ensureThreadSubscription(siteUrl, target);
        return stored;
      } catch (error, stackTrace) {
        if (!lease.isCurrent || isDisposed) return null;
        if (_threadDetailDirty.contains(key)) continue;

        final terminal =
            error is SiteLookupException &&
            (error.statusCode == 403 || error.statusCode == 404);
        _report(error, stackTrace, 'chat.loadThreadDetail', degraded: false);
        lease.commit(() {
          if (terminal) _store.remove<ChatThread>(siteUrl, target.threadId);
          final window = streamFor(siteUrl, target);
          _setStream(
            key,
            window.copyWith(
              fetchedOnce: true,
              error: window.messageIds.isEmpty
                  ? terminal
                        ? 'This thread is no longer available.'
                        : 'Could not load this thread.'
                  : null,
              threadUnavailable: terminal,
            ),
          );
        });
        return null;
      }
    }
    return thread(siteUrl, target.threadId);
  }

  void _syncThreadOriginalPreview(String siteUrl, ChatThread detail) {
    final originalId = detail.originalMessage?.id;
    final preview = detail.preview;
    if (originalId == null || preview == null) return;
    final original = _store.read<ChatMessage>(siteUrl, originalId);
    if (original == null || original.channelId != detail.channelId) return;
    _store.put(siteUrl, original.withThreadPreview(preview));
  }

  Future<ChatThread?> createThread(
    String siteUrl, {
    required int channelId,
    required int originalMessageId,
  }) async {
    if (originalMessageId <= 0 || !_canCreateThread(siteUrl, channelId)) {
      return null;
    }
    final lease = _requests.capture(siteUrl);
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!lease.isCurrent || isDisposed || apiKey == null) return null;
      final clientId = requestCredentials.clientId;
      if (!lease.isCurrent || !_canCreateThread(siteUrl, channelId)) {
        return null;
      }
      final created = await api.createChatThread(
        siteUrl: siteUrl,
        apiKey: apiKey,
        channelId: channelId,
        originalMessageId: originalMessageId,
        clientId: clientId,
      );
      if (!lease.isCurrent || !_canCreateThread(siteUrl, channelId)) {
        return null;
      }
      lease.commit(() {
        _store.put(siteUrl, created);
        _hasThreads[siteUrl] = true;
        if (_myThreadIds[siteUrl] case final ids?) {
          final alreadyListed = ids.contains(created.id);
          _myThreadIds[siteUrl] = [
            created.id,
            for (final id in ids)
              if (id != created.id) id,
          ];
          if (!alreadyListed) {
            _myThreadOffsets[siteUrl] =
                (_myThreadOffsets[siteUrl] ?? ids.length) + 1;
          }
        }
        final channelThreadsKey = _channelThreadsKey(siteUrl, channelId);
        if (_channelThreadIds[channelThreadsKey] case final ids?) {
          final alreadyListed = ids.contains(created.id);
          _channelThreadIds[channelThreadsKey] = [
            created.id,
            for (final id in ids)
              if (id != created.id) id,
          ];
          if (!alreadyListed) {
            _channelThreadOffsets[channelThreadsKey] =
                (_channelThreadOffsets[channelThreadsKey] ?? ids.length) + 1;
          }
        }
        final original = _store.read<ChatMessage>(siteUrl, originalMessageId);
        if (original != null && created.preview != null) {
          _store.put(siteUrl, original.withThreadPreview(created.preview));
        }
        notifySafely();
      });
      return created;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _report(error, stackTrace, 'chat.createThread');
      }
      return null;
    }
  }

  /// Mirrors core's staff-or-original-author presentation gate; the server
  /// remains authoritative.
  bool canEditThreadTitle(String siteUrl, ChatThread? thread) {
    final user = _currentUserFor(siteUrl);
    final authorId = thread?.originalMessage?.author.id;
    return thread != null &&
        user != null &&
        (user.staff || (user.id != null && user.id == authorId));
  }

  /// The write returns no thread record, so project the title and dirty detail
  /// to defeat an older concurrent refresh.
  Future<bool> updateThreadTitle(
    String siteUrl,
    ChatThreadTarget target,
    String title,
  ) async {
    if (isDisposed ||
        target.channelId <= 0 ||
        target.threadId <= 0 ||
        title.length > 100) {
      return false;
    }
    final held = thread(siteUrl, target.threadId);
    if (held?.channelId != target.channelId ||
        !canEditThreadTitle(siteUrl, held)) {
      return false;
    }
    final key = _targetKey(siteUrl, target);
    if (_threadTitleWrites.containsKey(key)) return false;
    final token = Object();
    final lease = _requests.capture(siteUrl);
    _threadTitleWrites[key] = token;

    bool isCurrent() =>
        identical(_threadTitleWrites[key], token) &&
        lease.isCurrent &&
        !isDisposed;

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent() || apiKey == null) return false;
      final clientId = requestCredentials.clientId;
      if (!isCurrent() ||
          !canEditThreadTitle(siteUrl, thread(siteUrl, target.threadId))) {
        return false;
      }
      await api.updateChatThreadTitle(
        siteUrl: siteUrl,
        apiKey: apiKey,
        channelId: target.channelId,
        threadId: target.threadId,
        title: title,
        clientId: clientId,
      );
      if (!isCurrent()) return false;
      lease.commit(() {
        _store.update<ChatThread>(
          siteUrl,
          target.threadId,
          (current) => current.copyWith(title: title),
        );
        _threadDetailDirty.add(key);
      });
      return true;
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _report(
          error,
          stackTrace,
          'chat.updateThreadTitle',
          severity: DiagnosticSeverity.warning,
        );
      }
      return false;
    } finally {
      if (identical(_threadTitleWrites[key], token)) {
        final _ = _threadTitleWrites.remove(key);
      }
    }
  }

  Future<bool> updateThreadNotificationLevel(
    String siteUrl,
    ChatThreadTarget target,
    ChatThreadNotificationLevel level,
  ) {
    if (isDisposed || target.channelId <= 0 || target.threadId <= 0) {
      return Future.value(false);
    }
    final held = thread(siteUrl, target.threadId);
    if (held == null || held.channelId != target.channelId) {
      return Future.value(false);
    }
    final key = _targetKey(siteUrl, target);
    if (!_threadNotificationConfirmed.containsKey(key)) {
      _threadNotificationConfirmed[key] = held.membership;
    }
    final revision = (_threadNotificationRevisions[key] ?? 0) + 1;
    _threadNotificationRevisions[key] = revision;

    final previous = held.membership;
    final optimistic =
        (previous ?? ChatThreadMembership(threadId: target.threadId))
            .withNotificationLevel(level);
    _store.update<ChatThread>(
      siteUrl,
      target.threadId,
      (current) => current.copyWith(membership: optimistic),
    );

    final write = _QueuedThreadNotification(
      siteUrl: siteUrl,
      target: target,
      level: level,
      revision: revision,
      lease: _requests.capture(siteUrl),
    );
    final previousTail = _threadNotificationTails[key] ?? Future.value();
    late final Future<void> tail;
    tail = previousTail
        .catchError((_) {
          // One unexpected failure must not strand later queued selections.
        })
        .then((_) => _performThreadNotificationWrite(key, write))
        .whenComplete(() {
          if (!identical(_threadNotificationTails[key], tail)) return;
          final _ = _threadNotificationTails.remove(key);
          _threadNotificationRevisions.remove(key);
          _threadNotificationConfirmed.remove(key);
        });
    _threadNotificationTails[key] = tail;
    unawaited(tail);
    return write.result.future;
  }

  Future<void> _performThreadNotificationWrite(
    String key,
    _QueuedThreadNotification write,
  ) async {
    bool isLatest() =>
        _threadNotificationRevisions[key] == write.revision &&
        write.lease.isCurrent &&
        !isDisposed;

    // Collapse a selection superseded before it reaches the server.
    if (!isLatest()) {
      write.complete(false);
      return;
    }

    try {
      final requestCredentials = await _requests.credentialsFor(write.siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (apiKey == null) {
        _rollbackThreadNotification(key, write);
        write.complete(false);
        return;
      }
      final clientId = requestCredentials.clientId;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      final membership = await api.updateChatThreadNotificationLevel(
        siteUrl: write.siteUrl,
        apiKey: apiKey,
        channelId: write.target.channelId,
        threadId: write.target.threadId,
        notificationLevel: write.level,
        clientId: clientId,
      );
      if (!write.lease.isCurrent || isDisposed) {
        write.complete(false);
        return;
      }
      final currentRead = thread(
        write.siteUrl,
        write.target.threadId,
      )?.membership?.lastReadMessageId;
      final responseRead = membership.lastReadMessageId;
      final confirmed = membership.copyWith(
        lastReadMessageId:
            currentRead != null &&
                (responseRead == null || currentRead > responseRead)
            ? currentRead
            : responseRead,
      );
      _threadNotificationConfirmed[key] = confirmed;
      if (isLatest()) {
        write.lease.commit(() {
          final current = thread(write.siteUrl, write.target.threadId);
          if (current != null) {
            _store.update<ChatThread>(
              write.siteUrl,
              current.id,
              (held) => held.copyWith(membership: confirmed),
            );
          }
        });
      }
      write.complete(true);
    } catch (error, stackTrace) {
      if (write.lease.isCurrent && !isDisposed) {
        _report(
          error,
          stackTrace,
          'chat.updateThreadNotificationLevel',
          severity: DiagnosticSeverity.warning,
        );
        if (isLatest()) _rollbackThreadNotification(key, write);
      }
      write.complete(false);
    }
  }

  void _rollbackThreadNotification(
    String key,
    _QueuedThreadNotification write,
  ) {
    if (!write.lease.isCurrent || isDisposed) return;
    final previous = _threadNotificationConfirmed[key];
    write.lease.commit(() {
      final current = thread(write.siteUrl, write.target.threadId);
      if (current != null) {
        _store.update<ChatThread>(
          write.siteUrl,
          current.id,
          (held) => held.copyWith(
            membership: previous,
            clearMembership: previous == null,
          ),
        );
      }
    });
  }

  /// Fetches only when the held window is not already at the present.
  Future<void> showLatest(String siteUrl, int channelId) {
    return showLatestFor(siteUrl, ChatChannelTarget(channelId));
  }

  Future<void> showLatestFor(String siteUrl, ChatStreamTarget target) async {
    if (isDisposed || target.channelId <= 0) return;
    if (streamFor(siteUrl, target).atPresent) return;
    await reporter.runOperation(
      'chat.loadLatest',
      () => _fetchWindow(siteUrl, target, fromLastRead: false),
    );
  }

  Future<_ChatWindowFetchResult> _fetchWindow(
    String siteUrl,
    ChatStreamTarget target, {
    required bool fromLastRead,
    int? targetMessageId,
  }) async {
    final key = _targetKey(siteUrl, target);
    // Replacement fetches are latest-wins; generations cancel stale targets.
    _loading.add(key);
    _streamNoticeTimers.remove(key)?.cancel();
    _windowAttemptedAt[key] = _clock();

    final lease = _requests.capture(siteUrl);
    final generation = Object();
    _streamGenerations[key] = generation;
    bool ownsRequest() => identical(_streamGenerations[key], generation);
    _pageRequests.remove(_olderTargetKey(siteUrl, target));
    _pageRequests.remove(_newerTargetKey(siteUrl, target));
    final held = streamFor(siteUrl, target);
    _setStream(
      key,
      held.copyWith(
        loading: held.messageIds.isEmpty,
        loadingOlder: false,
        loadingNewer: false,
        clearError: true,
        clearNotice: true,
      ),
    );

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }

      final bookmarkVersion = _bookmarkVersion(siteUrl);
      final page = target.threadId == null
          ? await api.chatMessages(
              siteUrl: siteUrl,
              channelId: target.channelId,
              targetMessageId: targetMessageId,
              fromLastRead: fromLastRead,
              pageSize: pageSize,
              apiKey: apiKey,
              clientId: clientId,
            )
          : await api.chatThreadMessages(
              siteUrl: siteUrl,
              channelId: target.channelId,
              threadId: target.threadId!,
              targetMessageId: targetMessageId,
              pageSize: pageSize,
              apiKey: apiKey,
              clientId: clientId,
            );
      if (!_requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation)) return;
        final current = _streams[key] ?? held;
        final heldIds = held.messageIds.toSet();
        final pageIds = {for (final message in page.messages) message.id};
        final arrivedWhileLoading = [
          for (final id in current.messageIds)
            if (!heldIds.contains(id) && !pageIds.contains(id))
              ?_store.read<ChatMessage>(siteUrl, id),
        ];
        _putMessages(
          siteUrl,
          page.messages,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        final pendingIds = _pendingLiveMessageIds.putIfAbsent(key, () => {});
        final List<int> messageIds;
        var retired = page.messages;
        if (page.canLoadMoreFuture) {
          messageIds = ChatMessageTimeline.merge(
            held: _timelineSnapshot(siteUrl, const []),
            arrived: page.messages,
            mode: ChatTimelineMergeMode.sortedUnion,
          );
          pendingIds.addAll(arrivedWhileLoading.map((message) => message.id));
        } else {
          // Admit parked sent events that outran the page reaching present.
          final seam = _withSeamStragglers(
            siteUrl,
            pendingIds,
            ChatMessageTimeline.merge(
              held: _timelineSnapshot(siteUrl, const []),
              arrived: [...page.messages, ...arrivedWhileLoading],
              mode: ChatTimelineMergeMode.sortedUnion,
            ),
          );
          messageIds = seam.ids;
          retired = [...page.messages, ...seam.stragglers];
        }
        final lastReadOnOpen = target.threadId == null
            ? channel(siteUrl, target.channelId)?.membership.lastReadMessageId
            : thread(siteUrl, target.threadId!)?.membership?.lastReadMessageId;
        _setStream(
          key,
          ChatStreamState(
            messageIds: messageIds,
            localMessageIds: _retireCanonicalLocals(siteUrl, current, retired),
            canLoadMorePast: page.canLoadMorePast,
            canLoadMoreFuture: page.canLoadMoreFuture,
            pendingNewMessages: pendingIds.length,
            fetchedOnce: true,
            fetches: held.fetches + 1,
            lastReadOnOpen: lastReadOnOpen,
            anchorMessageId:
                targetMessageId ?? page.targetMessageId ?? lastReadOnOpen,
          ),
        );
        _sendCoordinator.releaseReconciliationIfSettled(siteUrl, target);
      });
      return _ChatWindowFetchResult.loaded;
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }
      _report(error, stackTrace, 'chat.loadWindow', degraded: false);
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation)) return;
        final current = _streams[key] ?? const ChatStreamState();
        final replacesDestination =
            current.messageIds.isEmpty && current.localMessageIds.isEmpty;
        _setStream(
          key,
          current.copyWith(
            fetchedOnce: true,
            error: replacesDestination
                ? target.threadId == null
                      ? 'Could not load this channel.'
                      : 'Could not load this thread.'
                : null,
          ),
        );
        final siteDidNotAnswer =
            error is SiteLookupException &&
            error.failure == SiteLookupFailure.unreachable &&
            error.statusCode == null;
        if (replacesDestination && siteDidNotAnswer) {
          onSiteUnreachable?.call(siteUrl);
        }
      });
      return targetMessageId != null &&
              error is SiteLookupException &&
              error.statusCode == 404
          ? _ChatWindowFetchResult.missingTarget
          : _ChatWindowFetchResult.failed;
    } finally {
      if (_requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          if (!identical(_streamGenerations[key], generation)) return;
          final current = _streams[key];
          if (current != null && current.loading) {
            _setStream(key, current.copyWith(loading: false));
          }
          _loading.remove(key);
        });
      }
    }
  }

  Future<void> loadOlder(String siteUrl, int channelId) async {
    return loadOlderFor(siteUrl, ChatChannelTarget(channelId));
  }

  Future<void> loadOlderFor(String siteUrl, ChatStreamTarget target) async {
    if (isDisposed || target.channelId <= 0) return;
    final key = _targetKey(siteUrl, target);
    final held = streamFor(siteUrl, target);
    final before = held.oldestId;
    if (!held.canLoadMorePast || before == null) return;

    final guard = _olderTargetKey(siteUrl, target);
    if (_loading.contains(key) || _pageRequests.containsKey(guard)) return;

    final lease = _requests.capture(siteUrl);
    final generation = _streamGenerations.putIfAbsent(key, Object.new);
    final request = Object();
    _pageRequests[guard] = request;
    bool ownsRequest() =>
        identical(_streamGenerations[key], generation) &&
        identical(_pageRequests[guard], request);
    _setStream(key, held.copyWith(loadingOlder: true));

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final bookmarkVersion = _bookmarkVersion(siteUrl);
      final page = target.threadId == null
          ? await api.chatMessages(
              siteUrl: siteUrl,
              channelId: target.channelId,
              before: before,
              pageSize: pageSize,
              apiKey: apiKey,
              clientId: clientId,
            )
          : await api.chatThreadMessages(
              siteUrl: siteUrl,
              channelId: target.channelId,
              threadId: target.threadId!,
              before: before,
              pageSize: pageSize,
              apiKey: apiKey,
              clientId: clientId,
            );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation) ||
            !identical(_pageRequests[guard], request)) {
          return;
        }
        _putMessages(
          siteUrl,
          page.messages,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        final current = _streams[key] ?? const ChatStreamState();
        final merged = ChatMessageTimeline.merge(
          held: _timelineSnapshot(siteUrl, current.messageIds),
          arrived: page.messages,
          mode: ChatTimelineMergeMode.prependPage,
        );
        _setStream(
          key,
          current.copyWith(
            messageIds: merged,
            localMessageIds: _retireCanonicalLocals(
              siteUrl,
              current,
              page.messages,
            ),
            canLoadMorePast:
                merged.length > current.messageIds.length &&
                page.canLoadMorePast,
            fetchedOnce: true,
          ),
        );
        _sendCoordinator.releaseReconciliationIfSettled(siteUrl, target);
      });
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) {
        return;
      }
      _report(
        error,
        stackTrace,
        'chat.loadOlder',
        severity: DiagnosticSeverity.warning,
      );
      // Paging failure leaves valid held history and retries on the next scroll.
    } finally {
      if (_requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          if (!identical(_streamGenerations[key], generation) ||
              !identical(_pageRequests[guard], request)) {
            return;
          }
          final current = _streams[key];
          if (current != null) {
            _setStream(key, current.copyWith(loadingOlder: false));
          }
          _pageRequests.remove(guard);
        });
      }
    }
  }

  Future<void> loadNewer(String siteUrl, int channelId) async {
    return loadNewerFor(siteUrl, ChatChannelTarget(channelId));
  }

  Future<void> loadNewerFor(String siteUrl, ChatStreamTarget target) async {
    if (isDisposed || target.channelId <= 0) return;
    final key = _targetKey(siteUrl, target);
    final held = streamFor(siteUrl, target);
    final after = held.newestId;
    if (!held.canLoadMoreFuture || after == null) return;

    final guard = _newerTargetKey(siteUrl, target);
    if (_loading.contains(key) || _pageRequests.containsKey(guard)) return;

    final lease = _requests.capture(siteUrl);
    final generation = _streamGenerations.putIfAbsent(key, Object.new);
    final request = Object();
    _pageRequests[guard] = request;
    bool ownsRequest() =>
        identical(_streamGenerations[key], generation) &&
        identical(_pageRequests[guard], request);
    _setStream(key, held.copyWith(loadingNewer: true));

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final bookmarkVersion = _bookmarkVersion(siteUrl);
      final page = target.threadId == null
          ? await api.chatMessages(
              siteUrl: siteUrl,
              channelId: target.channelId,
              after: after,
              pageSize: pageSize,
              apiKey: apiKey,
              clientId: clientId,
            )
          : await api.chatThreadMessages(
              siteUrl: siteUrl,
              channelId: target.channelId,
              threadId: target.threadId!,
              after: after,
              pageSize: pageSize,
              apiKey: apiKey,
              clientId: clientId,
            );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation) ||
            !identical(_pageRequests[guard], request)) {
          return;
        }
        _putMessages(
          siteUrl,
          page.messages,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        final current = _streams[key] ?? const ChatStreamState();
        var merged = ChatMessageTimeline.merge(
          held: _timelineSnapshot(siteUrl, current.messageIds),
          arrived: page.messages,
          mode: ChatTimelineMergeMode.appendPage,
        );
        final canLoadMoreFuture =
            merged.length > current.messageIds.length && page.canLoadMoreFuture;
        final pendingIds = _pendingLiveMessageIds[key];
        var retired = page.messages;
        if (pendingIds != null) {
          pendingIds.removeAll(page.messages.map((message) => message.id));
          if (!canLoadMoreFuture) {
            final seam = _withSeamStragglers(siteUrl, pendingIds, merged);
            merged = seam.ids;
            retired = [...page.messages, ...seam.stragglers];
          }
        }

        _setStream(
          key,
          current.copyWith(
            messageIds: merged,
            localMessageIds: _retireCanonicalLocals(siteUrl, current, retired),
            canLoadMoreFuture: canLoadMoreFuture,
            pendingNewMessages: canLoadMoreFuture
                ? pendingIds?.length ?? current.pendingNewMessages
                : 0,
            fetchedOnce: true,
          ),
        );
        _sendCoordinator.releaseReconciliationIfSettled(siteUrl, target);
      });
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) {
        return;
      }
      _report(
        error,
        stackTrace,
        'chat.loadNewer',
        severity: DiagnosticSeverity.warning,
      );
      // Paging failure leaves valid held history and retries on the next scroll.
    } finally {
      if (_requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          if (!identical(_streamGenerations[key], generation) ||
              !identical(_pageRequests[guard], request)) {
            return;
          }
          final current = _streams[key];
          if (current != null) {
            _setStream(key, current.copyWith(loadingNewer: false));
          }
          _pageRequests.remove(guard);
        });
      }
    }
  }

  /// Optimistic read receipts are not rolled back; the next channel snapshot
  /// reconciles server state without restoring a badge under visible messages.
  Future<void> markRead(String siteUrl, int channelId, int messageId) {
    return markReadFor(siteUrl, ChatChannelTarget(channelId), messageId);
  }

  Future<void> markReadFor(
    String siteUrl,
    ChatStreamTarget target,
    int messageId,
  ) {
    if (isDisposed) return Future.value();
    final lease = _requests.capture(siteUrl);
    final window = streamFor(siteUrl, target);

    // A negative optimistic ID must never become the server's read cursor.
    if (messageId <= 0 || window.localMessageIds.contains(messageId)) {
      return Future.value();
    }

    // Discourse returns 404 when no followed membership row can be advanced.
    final channelHeld = channel(siteUrl, target.channelId);
    final threadHeld = target.threadId == null
        ? null
        : thread(siteUrl, target.threadId!);
    if (target.threadId == null &&
        (channelHeld == null || !channelHeld.membership.following)) {
      return Future.value();
    }
    if (target.threadId != null && threadHeld?.membership == null) {
      return Future.value();
    }

    // Read cursors are monotonic, also deduplicating repeated viewport ticks.
    final lastRead = target.threadId == null
        ? channelHeld!.membership.lastReadMessageId
        : threadHeld!.membership!.lastReadMessageId;
    final alreadyRead = lastRead != null && lastRead >= messageId;

    // Membership and tracking can briefly disagree. Clear stale aggregate
    // counts locally without sending a duplicate receipt.
    final caughtUp =
        target.threadId == null &&
        window.atPresent &&
        window.newestId == messageId;
    final hasStaleChannelCounts =
        caughtUp &&
        (channelHeld!.tracking.unreadCount > 0 ||
            channelHeld.tracking.mentionCount > 0);
    if (alreadyRead && !hasStaleChannelCounts) return Future.value();

    // Queue before the credential await so concurrent viewport ticks coalesce.
    final viewedAt = _clock().toUtc();
    if (target.threadId == null) {
      // Root caught-up state cannot use channel.last_message_id, which may name
      // a thread reply deliberately absent from the root stream.
      ChatChannel? updatedChannel;
      _store.update<ChatChannel>(siteUrl, target.channelId, (current) {
        final readThrough = alreadyRead
            ? current.membership.lastReadMessageId
            : messageId;
        if (readThrough == null) return current;
        var updated = current.withLastRead(readThrough, caughtUp: caughtUp);
        final previous = updated.membership.lastViewedAt;
        if (previous == null || viewedAt.isAfter(previous)) {
          updated = updated.withLastViewedAt(viewedAt);
        }
        updatedChannel = updated;
        return updated;
      });
      if (updatedChannel case final updated?) {
        _publishNotificationChange(siteUrl, channelHeld!, updated);
      }
    } else {
      _store.update<ChatThread>(siteUrl, target.threadId!, (current) {
        final membership = current.membership;
        if (membership == null ||
            (membership.lastReadMessageId ?? 0) >= messageId) {
          return current;
        }
        return current.copyWith(
          membership: membership.withLastReadMessageId(messageId),
        );
      });
    }
    notifySafely();

    if (alreadyRead) return Future.value();

    return _queueReadReceipt(
      siteUrl: siteUrl,
      target: target,
      messageId: messageId,
      lease: lease,
    );
  }

  Future<void> _queueReadReceipt({
    required String siteUrl,
    required ChatStreamTarget target,
    required int messageId,
    required PluginSiteLease lease,
  }) {
    final key = _targetKey(siteUrl, target);
    // Serialize per channel and retain only the furthest queued cursor.
    _queuedReadReceipts[key] = (
      siteUrl: siteUrl,
      target: target,
      messageId: messageId,
      lease: lease,
    );

    final running = _readReceiptTasks[key];
    if (running != null) return running;

    final run = Object();
    _readReceiptRuns[key] = run;
    final task = _drainReadReceipts(key, run);
    _readReceiptTasks[key] = task;
    return task;
  }

  Future<void> _drainReadReceipts(String key, Object run) async {
    while (true) {
      // An invalidated run must not dequeue a new session's same-key receipt.
      if (!identical(_readReceiptRuns[key], run)) return;
      final receipt = _queuedReadReceipts.remove(key);
      if (receipt == null) {
        // Identity prevents an old session from clearing a replacement run.
        if (identical(_readReceiptRuns[key], run)) {
          _readReceiptRuns.remove(key);
          final _ = _readReceiptTasks.remove(key);
        }
        return;
      }
      bool ownsRequest() => identical(_readReceiptRuns[key], run);
      try {
        final requestCredentials = await _requests.credentialsFor(
          receipt.siteUrl,
        );
        final apiKey = requestCredentials.apiKey;
        if (!_requestIsCurrent(receipt.lease, ownsRequest)) continue;
        // Unsigned macOS keychain failure leaves the optimistic read in place.
        if (apiKey == null) continue;

        final clientId = requestCredentials.clientId;
        if (!_requestIsCurrent(receipt.lease, ownsRequest)) continue;
        if (receipt.target.threadId == null) {
          await api.markChatChannelRead(
            siteUrl: receipt.siteUrl,
            apiKey: apiKey,
            channelId: receipt.target.channelId,
            messageId: receipt.messageId,
            clientId: clientId,
          );
        } else {
          await api.markChatThreadRead(
            siteUrl: receipt.siteUrl,
            apiKey: apiKey,
            channelId: receipt.target.channelId,
            threadId: receipt.target.threadId!,
            messageId: receipt.messageId,
            clientId: clientId,
          );
        }
      } catch (error, stackTrace) {
        if (_requestIsCurrent(receipt.lease, ownsRequest)) {
          _report(
            error,
            stackTrace,
            'chat.markRead',
            severity: DiagnosticSeverity.warning,
          );
        }
        // Keep draining newer queued positions after a failed receipt.
      }
    }
  }

  void forget(String siteUrl) {
    _liveSync.forget(siteUrl);
    final forgottenDraftRefs = <FrameSafeValueNotifier<ChatComposerDraft?>>[];
    _composerDraftRefs.removeWhere((key, ref) {
      if (!key.startsWith('$siteUrl~')) return false;
      forgottenDraftRefs.add(ref);
      return true;
    });
    // Detach first so a reentrant lookup cannot reuse an old account's ref.
    // Existing widgets still receive the empty value during their removal
    // frame and can safely detach their listeners afterwards.
    for (final ref in forgottenDraftRefs) {
      ref.value = null;
    }
    _reactionWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    _messageEditWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    _messageDeletionWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    _messagePinWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    _messageFlagWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    _messageRebakeWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    _messageQuoteWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    _pinListRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    final forgottenPinRefs = <FrameSafeValueNotifier<ChatPinsState>>[];
    _pinListRefs.removeWhere((key, ref) {
      if (!key.startsWith('$siteUrl~')) return false;
      forgottenPinRefs.add(ref);
      return true;
    });
    for (final ref in forgottenPinRefs) {
      ref.value = const ChatPinsState();
    }
    _reactorRequests.removeWhere((key, _) => key.siteUrl == siteUrl);
    _reactorErrors.removeWhere((key, _) => key.siteUrl == siteUrl);
    _bookmarkVersions.remove(siteUrl);
    _threadDetailRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _threadDetailDirty.removeWhere((key) => key.startsWith('$siteUrl~'));
    _loading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _channelRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelDetailRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelDetailRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _myThreadRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _myThreadRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelThreadListRequests.removeWhere(
      (key, _) => key.startsWith('$siteUrl~'),
    );
    _channelThreadListRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _errors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _attempts.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _streams.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _streamGenerations.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _windowAttemptedAt.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _pageRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _pendingLiveMessageIds.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    for (final key
        in _streamNoticeTimers.keys
            .where((key) => key.startsWith('$siteUrl~'))
            .toList()) {
      _streamNoticeTimers.remove(key)?.cancel();
    }
    _queuedReadReceipts.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _readReceiptTasks.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _readReceiptRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _threadNotificationRevisions.removeWhere(
      (key, _) => key.startsWith('$siteUrl~'),
    );
    _threadNotificationTails.removeWhere(
      (key, _) => key.startsWith('$siteUrl~'),
    );
    _threadNotificationConfirmed.removeWhere(
      (key, _) => key.startsWith('$siteUrl~'),
    );
    _channelStarWrites.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelNotificationWrites.removeWhere(
      (key, _) => key.startsWith('$siteUrl~'),
    );
    _channelFollowWrites.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelSettingsWrites.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _threadTitleWrites.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    final forgottenRefs = <FrameSafeValueNotifier<ChatStreamState>>[];
    _streamRefs.removeWhere((key, ref) {
      if (!key.startsWith('$siteUrl~')) return false;
      forgottenRefs.add(ref);
      return true;
    });
    // Detach before notifying so a reentrant lookup gets a new-session ref;
    // widgets may still listen to the old ref during their removal frame.
    for (final ref in forgottenRefs) {
      ref.value = const ChatStreamState();
    }
    _publicIds.remove(siteUrl);
    _directIds.remove(siteUrl);
    _myThreadIds.remove(siteUrl);
    _myThreadOffsets.remove(siteUrl);
    _myThreadsHaveMore.remove(siteUrl);
    _hasThreads.remove(siteUrl);
    _partialChannelIds.remove(siteUrl);
    _channelThreadIds.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelThreadOffsets.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelThreadsHaveMore.removeWhere(
      (key, _) => key.startsWith('$siteUrl~'),
    );
    _lastOpenedChannelIds.remove(siteUrl);
    _store.forget(siteUrl);
    notifySafely();
  }

  @override
  void dispose() {
    _liveSync.dispose();
    _threadDetailRequests.clear();
    _threadDetailDirty.clear();
    _channelDetailRequests.clear();
    _channelDetailRuns.clear();
    _windowAttemptedAt.clear();
    _pendingLiveMessageIds.clear();
    for (final timer in _streamNoticeTimers.values) {
      timer.cancel();
    }
    _streamNoticeTimers.clear();
    _queuedReadReceipts.clear();
    _readReceiptTasks.clear();
    _readReceiptRuns.clear();
    _threadNotificationRevisions.clear();
    _threadNotificationTails.clear();
    _threadNotificationConfirmed.clear();
    _channelStarWrites.clear();
    _channelNotificationWrites.clear();
    _channelFollowWrites.clear();
    _channelSettingsWrites.clear();
    _threadTitleWrites.clear();
    _myThreadRequests.clear();
    _myThreadRuns.clear();
    _channelThreadListRequests.clear();
    _channelThreadListRuns.clear();
    _reactionWrites.clear();
    _messageEditWrites.clear();
    _messageDeletionWrites.clear();
    _messagePinWrites.clear();
    _messageFlagWrites.clear();
    _messageRebakeWrites.clear();
    _messageQuoteWrites.clear();
    _pinListRequests.clear();
    for (final ref in _pinListRefs.values) {
      ref.dispose();
    }
    _pinListRefs.clear();
    _reactorRequests.clear();
    _reactorErrors.clear();
    _bookmarkVersions.clear();
    for (final ref in _composerDraftRefs.values) {
      ref.dispose();
    }
    _composerDraftRefs.clear();
    for (final ref in _streamRefs.values) {
      ref.dispose();
    }
    _streamRefs.clear();
    super.dispose();
  }
}

final class _QueuedThreadNotification {
  _QueuedThreadNotification({
    required this.siteUrl,
    required this.target,
    required this.level,
    required this.revision,
    required this.lease,
  });

  final String siteUrl;
  final ChatThreadTarget target;
  final ChatThreadNotificationLevel level;
  final int revision;
  final PluginSiteLease lease;
  final Completer<bool> result = Completer<bool>();

  void complete(bool succeeded) {
    if (!result.isCompleted) result.complete(succeeded);
  }
}
