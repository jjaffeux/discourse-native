// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'chat_api.dart';
import 'chat_channel.dart';
import 'chat_channel_list.dart';
import 'chat_channel_list_controller.dart';
import 'chat_channel_list_preferences.dart';
import 'chat_channel_refresh.dart';
import 'chat_cooking_coordinator.dart';
import 'chat_direct_message_search.dart';
import 'chat_inbox_filters.dart';
import 'chat_live_sync_coordinator.dart';
import 'chat_message.dart';
import 'chat_message_summary.dart';
import 'chat_message_timeline.dart';
import 'chat_pin.dart';
import 'chat_plugin_data.dart';
import 'chat_prepared_cooking.dart';
import 'chat_preview.dart';
import 'chat_reactors.dart';
import 'chat_read_receipt_owner.dart';
import 'chat_route.dart';
import 'chat_send_coordinator.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';
import 'chat_thread_list_refresh.dart';
import 'chat_thread_metadata_owner.dart';
import 'chat_wire.dart';

part 'chat_conversation_stream.dart';
part 'chat_channel_directory.dart';
part 'chat_channel_projections.dart';
part 'chat_thread_catalog.dart';
part 'chat_message_write_owner.dart';
part 'chat_reaction_owner.dart';
part 'chat_channel_pins.dart';

typedef ChatNotificationsDelta = void Function(String siteUrl, int delta);

/// The part of an unsent Chat message that can safely survive its composer
/// widget being unmounted while the Chat session itself remains alive.
@immutable
class ChatComposerDraft {
  ChatComposerDraft({
    required this.raw,
    required Iterable<ComposerUploadResult> uploads,
    this.replyTo,
  }) : uploads = List.unmodifiable(uploads);

  final String raw;
  final List<ComposerUploadResult> uploads;
  final ChatReplyTo? replyTo;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatComposerDraft ||
        other.raw != raw ||
        other.replyTo != replyTo ||
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
    replyTo,
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

enum _ChatWindowGrowth { replacement, past, future }

/// Pins records through Store's existing observed-ref contract.
///
/// One target owns one set. Optimistic rows are always retained; canonical
/// rows join the set only while a presentation actively views the target.
final class _ChatMessagePinSet {
  _ChatMessagePinSet(this._store, this.siteUrl);

  final Store _store;
  final String siteUrl;
  final Map<int, Ref<ChatMessage>> _refs = {};

  int get length => _refs.length;

  static void _keepObserved() {}

  void retain(Iterable<int> messageIds) {
    final desired = messageIds.toSet();
    for (final id in _refs.keys.toList(growable: false)) {
      if (desired.contains(id)) continue;
      _refs.remove(id)?.removeListener(_keepObserved);
    }
    for (final id in desired) {
      if (_refs.containsKey(id) ||
          !_store.containsRecord<ChatMessage>(siteUrl, id)) {
        continue;
      }
      final ref = _store.ref<ChatMessage>(siteUrl, id)
        ..addListener(_keepObserved);
      _refs[id] = ref;
    }
  }

  void release() {
    for (final ref in _refs.values) {
      ref.removeListener(_keepObserved);
    }
    _refs.clear();
  }
}

/// Every account field that [ChatController]'s permission checks read: who the
/// reader is, for their own messages, and whether they are staff. Chat panes
/// redraw their rows for the account only when this changes or the account
/// signs in or out, and not for the rest of the record, which draft counts,
/// the reader's status, do-not-disturb and notification counts replace far
/// more often.
typedef ChatAccountAccess = ({int? id, bool staff});

extension ChatAccountAccessOf on DiscourseUser {
  ChatAccountAccess get chatAccountAccess => (id: id, staff: staff);
}

/// Owns chat requests and ordering; records and row-level notifications live
/// in the [Store] to avoid rebuilding the host shell.
class ChatController extends FrameSafeNotifier {
  ChatController({
    required this.api,
    required PluginRequestHost requests,
    required Store store,
    PluginUserOptionsHost? userOptionsHost,
    DiscourseUser? Function(String siteUrl)? currentUserFor,
    SiteConfig Function(String siteUrl)? siteConfigFor,
    ChatPreviewEngine? previewEngine,
    PluginCookingHost? cookingHost,
    ChatCookingCoordinator? cookingScheduler,
    String Function(String siteUrl)? cookingTimezoneFor,

    this.onChatNotificationsDelta,
    this.onSiteUnreachable,
    this.minimumWindowRefreshInterval = const Duration(seconds: 30),
    int? maxRetainedCanonicalMessageIdsPerSite,
    DateTime Function()? clock,
    ChatSendCoordinatorFactory? sendCoordinatorFactory,
    ChatMessageContext? Function(String siteUrl)? messageContextFor,
  }) : assert(minimumWindowRefreshInterval >= Duration.zero),
       assert(
         maxRetainedCanonicalMessageIdsPerSite == null ||
             maxRetainedCanonicalMessageIdsPerSite > 0,
       ),
       _requests = requests,
       _store = store,
       _maxRetainedCanonicalMessageIdsPerSite =
           maxRetainedCanonicalMessageIdsPerSite ??
           _defaultCanonicalMessageBudget(store),
       _currentUserFor = currentUserFor ?? _noCurrentUser,
       _siteConfigFor = siteConfigFor ?? _unknownSiteConfig,
       _previewEngine = previewEngine ?? ChatPreviewEngine(),
       _cookingTimezoneFor = cookingTimezoneFor,
       _clock = clock ?? DateTime.now {
    if (cookingHost != null) {
      _preparedCooking = ChatPreparedCooking(
        host: cookingHost,
        contextFor: (siteUrl) => _cookingContext(siteUrl),
        scheduler: cookingScheduler,
      );
    }
    channelListPreferences = ChatChannelListController(
      requests: requests,
      currentUserFor: _currentUserFor,
      host: userOptionsHost,
    )..addListener(notifySafely);
    final sendHost = ChatSendCoordinatorHost(
      isDisposed: () => isDisposed,
      canSend: canSendMessageTo,
      currentUserFor: _currentUserFor,
      projectPreview: _projectPreview,
      stage: _stageOutgoing,
      markSent: _markOutgoingSent,
      markFailed: _markOutgoingFailed,
      outgoing: _outgoingMessage,
      setRetryState:
          (siteUrl, target, stagedId, {required sending, required waiting}) {
            _updateOutgoing(siteUrl, target, stagedId, (held) {
              if (held.serverId != null || held.canonicalReceived) return held;
              return held.withSendState(
                delivery: sending
                    ? ChatMessageDelivery.sending
                    : ChatMessageDelivery.failed,
                error: sending ? null : held.sendError,
                failure: sending ? null : held.sendFailure,
                retryWaiting: waiting,
              );
            });
          },
      onSent: _onOutgoingSent,
      hasUnsettledMessages: _hasUnsettledOutgoingMessages,
      reconcileSentEvent: _applySendMessage,
      messageContextFor: messageContextFor ?? (_) => null,
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
        putChannel: _putChannel,
        didReceiveTrackingState: (siteUrl, channel) =>
            _heldDirectory(siteUrl)?.recordTrackingState(channel),
        didReceiveChannelEdit: (siteUrl, channelId) {
          _heldDirectory(siteUrl)?.recordMetadataEdit(channelId);
        },
        didReceiveChannelStatus: (siteUrl, channelId) {
          _heldDirectory(siteUrl)?.recordStatusEdit(channelId);
        },
        putMessage: _putMessage,
        putLiveMessage: (siteUrl, message, preservePersonalizedState) =>
            _putLiveMessage(
              siteUrl,
              message,
              preservePersonalizedState: preservePersonalizedState,
            ),
        putThread: _putThread,
        publishNotificationChange: _publishNotificationChange,
        notifyCanonicalChange: notifySafely,
        removeKickedChannelState: _removeKickedChannelState,
        isChannelListed: (siteUrl, channelId) =>
            _heldDirectory(siteUrl)?.isListed(channelId) ?? false,
        resolvePartialChannel: (siteUrl, channelId) =>
            _heldDirectory(siteUrl)?.resolvePartial(channelId),
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
          _threadCatalog(siteUrl).hasThreads = true;
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
        resyncChannels: (siteUrl) =>
            unawaited(loadChannels(siteUrl, revalidate: true)),
      ),
    );
  }

  final ChatApi api;
  final PluginRequestHost _requests;
  final Store _store;
  final Duration minimumWindowRefreshInterval;
  final int? _maxRetainedCanonicalMessageIdsPerSite;
  final DiscourseUser? Function(String siteUrl) _currentUserFor;
  final SiteConfig Function(String siteUrl) _siteConfigFor;
  final ChatPreviewEngine _previewEngine;
  final String Function(String siteUrl)? _cookingTimezoneFor;
  ChatPreparedCooking? _preparedCooking;
  final Map<String, String> _cookingLocales = {};
  final Map<String, int> _cookingLocaleRevisions = {};
  final Map<(String, int), Object> _messageCookingTokens = {};

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

  /// Shared by Chat composers; unchanged locales do no work.
  void setCookingLocale(String siteUrl, String locale) {
    if (isDisposed || (_cookingLocales[siteUrl] ?? 'en') == locale) return;
    _cookingLocales[siteUrl] = locale;
    _cookingLocaleRevisions.update(
      siteUrl,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _preparedCooking?.refreshSite(siteUrl);
  }

  CookingContext _cookingContext(String siteUrl, {ChatMessage? author}) {
    final user = _currentUserFor(siteUrl);
    return CookingContext(
      authorId: author?.author.id ?? user?.id,
      authorUsername: author?.author.username ?? user?.username ?? '',
      editorId: user?.id,
      locale: _cookingLocales[siteUrl] ?? 'en',
      timezone:
          _cookingTimezoneFor?.call(siteUrl) ?? user?.timezone ?? 'Etc/UTC',
      asOfEpochMilliseconds: _clock().millisecondsSinceEpoch,
      sourcePolicy: CookingSourcePolicy.submission,
    );
  }

  /// Each editor owns its preparation without changing the timeline.
  void prepareEditCooking(
    String siteUrl,
    ChatMessage message,
    String raw, {
    Object? owner,
  }) {
    if (isDisposed) return;
    _preparedCooking?.prepare(
      key: ('editDraft', siteUrl, message.id, owner),
      siteUrl: siteUrl,
      raw: raw,
      contextBuilder: () => _cookingContext(siteUrl, author: message),
    );
  }

  void cancelEditCooking(String siteUrl, int messageId, {Object? owner}) =>
      _preparedCooking?.cancel(('editDraft', siteUrl, messageId, owner));

  /// Keeps the draft and ready HTML when its last presentation closes, while
  /// stopping debounce work until a composer opens it again.
  void suspendComposerCookingIfUnobserved(
    String siteUrl,
    ChatStreamTarget target,
  ) {
    final key = _targetKey(siteUrl, target);
    if (!(_composerDraftRefs[key]?.hasListeners ?? false)) {
      _preparedCooking?.suspend(('draft', key));
    }
  }

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

  @visibleForTesting
  int? get canonicalMessageRetentionBudgetForTesting =>
      _maxRetainedCanonicalMessageIdsPerSite;

  @visibleForTesting
  int retainedTargetCountForTesting(String siteUrl) =>
      _conversations.values.where((owner) => owner.siteUrl == siteUrl).length;

  @visibleForTesting
  int retainedCanonicalMessageIdCountForTesting(String siteUrl) =>
      _conversations.values
          .where((owner) => owner.siteUrl == siteUrl)
          .fold(
            0,
            (total, owner) => total + (owner._window?.messageIds.length ?? 0),
          );

  @visibleForTesting
  int retainedChannelThreadRecordsForTesting(String siteUrl) =>
      _heldThreadCatalog(siteUrl)?._lists.values.fold<int>(
        0,
        (total, entry) => total + (entry.projection?.threads.length ?? 0),
      ) ??
      0;

  @visibleForTesting
  int pinSnapshotCountForTesting(String siteUrl) =>
      _pinLists.keys.where((key) => key.startsWith('$siteUrl~')).length;

  @visibleForTesting
  int pinnedMessageCountForTesting(String siteUrl) => _conversations.values
      .where((owner) => owner.siteUrl == siteUrl)
      .fold(0, (total, owner) => total + (owner._messagePins?.length ?? 0));

  PluginSiteLease captureSession(String siteUrl) => _requests.capture(siteUrl);

  /// Discourse caps chat pages at 50.
  static const int pageSize = 50;

  /// Leaves room for the page being admitted before its prior edge is trimmed.
  static int? _defaultCanonicalMessageBudget(Store store) {
    final partition = store.policy?.maxEntriesPerSiteAndType;
    if (partition == null || partition <= pageSize) return partition;
    return partition - pageSize;
  }

  /// Allows retries when no later UI event would trigger one.
  static const int maxChannelAttempts = 3;

  /// How long the app must have been away before returning re-reads every
  /// held channel list and every viewed message window. MessageBus keeps a
  /// bounded backlog per channel (100 messages on a default Discourse), so a
  /// resumed poll cannot replay activity, tracking, presence or messages
  /// published beyond it. A shorter switch rarely outruns that backlog, and
  /// re-reading on every app switch would cost requests for nothing.
  static const Duration resumeResyncThreshold = Duration(minutes: 1);

  final Map<String, _ChatChannelDirectory> _directories = {};

  _ChatChannelDirectory? _heldDirectory(String siteUrl) {
    final held = _directories[siteUrl];
    return held?.isCurrent == true ? held : null;
  }

  _ChatChannelDirectory _directory(String siteUrl) {
    assert(!isDisposed);
    final held = _directories[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    final directory = _ChatChannelDirectory(
      siteUrl: siteUrl,
      lease: _requests.capture(siteUrl),
      api: api,
      requests: _requests,
      store: _store,
      liveSync: _liveSync,
      currentUserFor: _currentUserFor,
      onChanged: notifySafely,
      onPinCountAccepted: (channelId) =>
          _messageWriteOwners[siteUrl]?.acceptPinCount(channelId),

      onChatNotificationsDelta: onChatNotificationsDelta,
      hasThreads: () => hasThreads(siteUrl),
      replaceHasThreads: (previous, next) {
        if (hasThreads(siteUrl) == previous) {
          _threadCatalog(siteUrl).hasThreads = next;
        }
      },
      advanceLastViewedAt: (channelId) =>
          _advanceLastViewedAt(siteUrl, channelId, notify: false),
    );
    _directories[siteUrl] = directory;
    return directory;
  }

  DateTime? _backgroundedAt;
  final Map<String, _ChatThreadCatalog> _threadCatalogs = {};

  _ChatThreadCatalog? _heldThreadCatalog(String siteUrl) {
    final held = _threadCatalogs[siteUrl];
    return held?.isCurrent == true ? held : null;
  }

  _ChatThreadCatalog _threadCatalog(String siteUrl) {
    assert(!isDisposed);
    final held = _threadCatalogs[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    return _threadCatalogs[siteUrl] = _ChatThreadCatalog(
      siteUrl: siteUrl,
      lease: _requests.capture(siteUrl),
      api: api,
      requests: _requests,
      store: _store,
      hydrateChannel: (channel) =>
          _directory(siteUrl).hydratePartialIfMissing(channel),
      onChanged: notifySafely,
    );
  }

  _ChatThreadListSnapshot _threadList(String siteUrl, _ChatThreadListId id) =>
      _heldThreadCatalog(siteUrl)?.snapshot(id) ??
      const _ChatThreadListSnapshot.empty();

  final Map<String, int> _lastOpenedChannelIds = {};

  late final ChatThreadMetadataOwner _threadMetadata = ChatThreadMetadataOwner(
    api: api,
    requests: _requests,
    store: _store,
    currentUserFor: _currentUserFor,
    channelFor: channel,
    events: _ChatThreadMetadataEvents(this, notifySafely),
  );

  final _readReceiptRetries = ChatReadReceiptRetries();

  final LinkedHashMap<String, _ChatConversationStream> _conversations =
      LinkedHashMap();

  /// Per site, message id to channel id for rows a delete hid from this
  /// reader. Their ids stay in held windows as paging slots with no record
  /// behind them, so only a record lost any other way is a hole.
  final Map<String, Map<int, int>> _hiddenDeletedMessageChannelIds = {};
  final Map<String, _AccountMessageWrites> _messageWriteOwners = {};
  final Map<({String siteUrl, int channelId}), Object> _messageQuoteWrites = {};
  final Map<String, _ChatChannelPins> _pinLists = {};
  final Map<String, _AccountChatReactions> _reactionOwners = {};
  final Map<String, int> _bookmarkVersions = {};
  final Map<String, FrameSafeValueNotifier<ChatComposerDraft?>>
  _composerDraftRefs = {};

  static String _targetKey(String siteUrl, ChatStreamTarget target) =>
      '$siteUrl~${target.storageKey}';
  static String _streamKey(String siteUrl, int id) =>
      _targetKey(siteUrl, ChatChannelTarget(id));
  static String _pinsKey(String siteUrl, int channelId) =>
      '$siteUrl~channel-$channelId-pins';

  _AccountChatReactions? _heldReactions(String siteUrl) {
    final held = _reactionOwners[siteUrl];
    return held != null && held.isCurrent ? held : null;
  }

  _AccountChatReactions _reactionsFor(String siteUrl) {
    final held = _heldReactions(siteUrl);
    if (held != null) return held;
    _reactionOwners.remove(siteUrl)?.retire();
    final owner = _AccountChatReactions(
      this,
      siteUrl,
      _requests.capture(siteUrl),
      onChanged: notifySafely,
    );
    _reactionOwners[siteUrl] = owner;
    return owner;
  }

  _AccountMessageWrites _messageWritesFor(String siteUrl) {
    final held = _messageWriteOwners[siteUrl];
    if (held != null && held.isCurrent) return held;
    if (held != null) {
      _messageWriteOwners.remove(siteUrl);
      held.retire();
    }
    final owner = _AccountMessageWrites(
      this,
      siteUrl,
      _requests.capture(siteUrl),
      onChanged: notifySafely,
    );
    _messageWriteOwners[siteUrl] = owner;
    return owner;
  }

  /// Rechecks ownership after credential awaits so stale account requests are
  /// never sent after disconnect, disposal, or generation replacement.
  bool _requestIsCurrent(PluginSiteLease lease, bool Function() ownsRequest) =>
      !isDisposed && lease.isCurrent && ownsRequest();

  late final ChatChannelListController channelListPreferences;
  final ChatInboxFilters inboxFilters = ChatInboxFilters();

  List<ChatChannel> channelList(
    String siteUrl,
    ChatChannelListSection section, {
    bool sidebar = true,
    int? activeChannelId,
  }) {
    final preferences = channelListPreferences.preferencesFor(siteUrl);
    if (!preferences.supportsSection(section)) {
      return switch ((section, sidebar)) {
        (ChatChannelListSection.channels, true) => unstarredPublicChannels(
          siteUrl,
        ),
        (ChatChannelListSection.channels, false) =>
          activitySortedPublicChannels(siteUrl),
        (ChatChannelListSection.starred, true) => starredChannels(siteUrl),
        (ChatChannelListSection.starred, false) =>
          activitySortedStarredChannels(siteUrl),
        (ChatChannelListSection.directMessages, true) =>
          unstarredDirectChannels(siteUrl),
        (ChatChannelListSection.directMessages, false) =>
          activitySortedDirectChannels(siteUrl).take(50).toList(),
      };
    }
    final source = switch (section) {
      ChatChannelListSection.channels => publicChannels(
        siteUrl,
      ).where((channel) => !sidebar || !channel.membership.starred),
      ChatChannelListSection.starred => starredChannels(siteUrl),
      ChatChannelListSection.directMessages => directChannels(
        siteUrl,
      ).where((channel) => !sidebar || !channel.membership.starred),
    };
    return _heldDirectory(siteUrl)?._preferenceChannelList(
          source.toList(),
          section: section,
          filter: channelListPreferences.bypassed(siteUrl, section)
              ? ChatChannelListFilter.all
              : preferences.filterFor(section),
          sort: preferences.sortFor(section),
          now: _clock(),
          activeChannelId: activeChannelId,
          sidebar: sidebar,
        ) ??
        const [];
  }

  List<ChatChannel> inboxConversations(
    String siteUrl,
    ChatInboxFilter filter,
  ) =>
      _heldDirectory(siteUrl)?._inboxConversations(
        filter,
        publicChannelsEnabled: siteConfigFor(
          siteUrl,
        ).chatSettings.publicChannelsEnabled,
      ) ??
      <ChatChannel>[];

  List<ChatChannel> publicChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.publicChannels() ?? [];

  List<ChatChannel> directChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.directChannels() ?? [];

  /// Unread messages across channels and DMs, including watched threads.
  /// Mentions overlap these counts; unread thread totals count threads, not messages.
  int unreadMessageCount(String siteUrl, {ChatChannelListSection? section}) {
    // Totals need membership filtering, not the lists' activity sorting.
    final channels = switch (section) {
      ChatChannelListSection.channels => publicChannels(siteUrl),
      ChatChannelListSection.directMessages => directChannels(siteUrl),
      _ => [...publicChannels(siteUrl), ...directChannels(siteUrl)],
    };
    return channels
        .where(
          (channel) => switch (section) {
            ChatChannelListSection.starred => channel.membership.starred,
            ChatChannelListSection.channels => !channel.membership.starred,
            ChatChannelListSection.directMessages =>
              !channel.membership.starred,
            null => true,
          },
        )
        .fold(
          0,
          (count, channel) =>
              count +
              channel.tracking.unreadCount +
              channel.tracking.watchedThreadsUnreadCount,
        );
  }

  /// Public channels in the unread-first activity order.
  List<ChatChannel> activitySortedPublicChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.activitySortedPublicChannels() ?? const [];

  /// Captures the account that owns a menu gesture or other synchronous UI action.
  PluginSiteLease captureAccount(String siteUrl) => _requests.capture(siteUrl);

  bool channelsLoaded(String siteUrl) =>
      _heldDirectory(siteUrl)?.channelsLoaded() ?? false;

  bool channelsLoading(String siteUrl) =>
      _heldDirectory(siteUrl)?.channelsLoading() ?? false;

  ChatComposerDraft? composerDraftFor(
    String siteUrl,
    ChatStreamTarget target,
  ) => _composerDraftRefs[_targetKey(siteUrl, target)]?.value;

  /// A target-scoped draft signal shared by every mounted presentation of the
  /// same channel or thread. A snapshot-only lookup would leave other mounted
  /// composers stale.
  ValueListenable<ChatComposerDraft?> composerDraftListenableFor(
    String siteUrl,
    ChatStreamTarget target,
  ) {
    final key = _targetKey(siteUrl, target);
    _rememberTarget(siteUrl, target);
    _enforceSiteRetention(siteUrl, keep: key);
    return _composerDraftRefs.putIfAbsent(
      key,
      () => FrameSafeValueNotifier<ChatComposerDraft?>(null),
    );
  }

  /// Retains local-only drafts while their view is absent.
  /// Empty documents are removed so a successfully sent message cannot return
  /// when the composer is mounted again.
  void retainComposerDraft(
    String siteUrl,
    ChatStreamTarget target, {
    required String raw,
    required Iterable<ComposerUploadResult> uploads,
    ChatReplyTo? replyTo,
  }) {
    if (isDisposed) return;
    final key = _targetKey(siteUrl, target);
    _rememberTarget(siteUrl, target);
    final retainedUploads = List<ComposerUploadResult>.unmodifiable(uploads);
    if (raw.isEmpty && retainedUploads.isEmpty && replyTo == null) {
      _preparedCooking?.cancel(('draft', key));
      _composerDraftRefs[key]?.value = null;
      if (_conversations[key]?._window == null &&
          _canEvictRetainedTarget(key)) {
        _evictRetainedTarget(key);
      }
      _enforceSiteRetention(siteUrl);
      return;
    }
    final next = ChatComposerDraft(
      raw: raw,
      uploads: retainedUploads,
      replyTo: replyTo,
    );
    _preparedCooking?.prepare(key: ('draft', key), siteUrl: siteUrl, raw: raw);
    _composerDraftRefs
            .putIfAbsent(
              key,
              () => FrameSafeValueNotifier<ChatComposerDraft?>(null),
            )
            .value =
        next;
    _enforceSiteRetention(siteUrl, keep: key);
  }

  bool hasThreads(String siteUrl) =>
      _heldThreadCatalog(siteUrl)?.hasThreads ?? false;

  bool channelStarWriteInFlight(String siteUrl, int channelId) =>
      _heldDirectory(siteUrl)?.channelStarWriteInFlight(channelId) ?? false;

  bool channelNotificationWriteInFlight(String siteUrl, int channelId) =>
      _heldDirectory(siteUrl)?.channelNotificationWriteInFlight(channelId) ??
      false;

  Future<String?> updateChannelStarred(
    String siteUrl,
    int channelId,
    bool starred,
  ) => isDisposed
      ? Future.value(appL10n.thisChannelCanNoLongerBeChanged)
      : _directory(siteUrl).updateChannelStarred(channelId, starred);

  /// Muting and push frequency are independent Discourse fields.
  Future<String?> updateChannelNotifications(
    String siteUrl,
    int channelId, {
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
  }) => isDisposed
      ? Future.value(appL10n.thisChannelCanNoLongerBeChanged)
      : _directory(siteUrl).updateChannelNotifications(
          channelId,
          muted: muted,
          notificationLevel: notificationLevel,
        );

  Future<ChatChannelMembersResult> fetchChannelMembers(
    String siteUrl,
    int channelId, {
    String username = '',
    int offset = 0,
    int limit = 20,
  }) => isDisposed
      ? Future.value((
          page: null,
          error: appL10n.thisMemberListIsNoLongerAvailable,
        ))
      : _directory(siteUrl).fetchChannelMembers(
          channelId,
          username: username,
          offset: offset,
          limit: limit,
        );

  Future<ChatChannelBrowseResult> fetchBrowseChannels(
    String siteUrl, {
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
  }) => isDisposed
      ? Future.value((
          page: null,
          error: appL10n.theChannelDirectoryIsNoLongerAvailable,
        ))
      : _directory(siteUrl).fetchBrowseChannels(
          filter: filter,
          status: status,
          offset: offset,
          limit: limit,
        );

  bool channelFollowWriteInFlight(String siteUrl, int channelId) =>
      _heldDirectory(siteUrl)?.channelFollowWriteInFlight(channelId) ?? false;

  bool channelSettingsWriteInFlight(String siteUrl, int channelId) =>
      _heldDirectory(siteUrl)?.channelSettingsWriteInFlight(channelId) ?? false;

  bool canEditChannelMetadata(String siteUrl, int channelId) => isDisposed
      ? false
      : _directory(siteUrl).canEditChannelMetadata(channelId);

  /// Omit unchanged fields; an empty description removes the existing value.
  Future<String?> updateChannelMetadata(
    String siteUrl,
    int channelId, {
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
  }) => isDisposed
      ? Future.value(appL10n.thisChannelCannotBeEdited)
      : _directory(siteUrl).updateChannelMetadata(
          channelId,
          name: name,
          slug: slug,
          description: description,
          threadingEnabled: threadingEnabled,
        );

  Future<String?> updateChannelThreading(
    String siteUrl,
    int channelId,
    bool enabled,
  ) => isDisposed
      ? Future.value(appL10n.searchThreadingCannotBeChanged)
      : _directory(siteUrl).updateChannelThreading(channelId, enabled);

  bool canChangeChannelStatus(String siteUrl, int channelId) => isDisposed
      ? false
      : _directory(siteUrl).canChangeChannelStatus(channelId);

  /// Discourse reserves read-only and archived transitions for its archive flow.
  Future<String?> setChannelClosed(
    String siteUrl,
    int channelId, {
    required bool closed,
  }) => isDisposed
      ? Future.value(appL10n.thisChannelSStatusCannotBeChanged)
      : _directory(siteUrl).setChannelClosed(channelId, closed: closed);

  /// Closing a direct message is Discourse's reversible membership follow write.
  Future<String?> updateChannelFollowing(
    String siteUrl,
    ChatChannel candidate,
    bool following,
  ) => isDisposed
      ? Future.value(appL10n.thisChannelCanNoLongerBeChanged)
      : _directory(siteUrl).updateChannelFollowing(candidate, following);

  List<ChatThread> myThreads(String siteUrl) => [
    for (final id
        in _threadList(siteUrl, _ChatThreadListId.mine).ids ?? const <int>[])
      ?_store.read<ChatThread>(siteUrl, id),
  ];

  bool myThreadsLoaded(String siteUrl) =>
      _threadList(siteUrl, _ChatThreadListId.mine).loaded;

  bool myThreadsLoadingMore(String siteUrl) {
    final state = _threadList(siteUrl, _ChatThreadListId.mine);
    return state.loading && state.loaded;
  }

  bool myThreadsHaveMore(String siteUrl) =>
      _threadList(siteUrl, _ChatThreadListId.mine).hasMore;

  String? myThreadsError(String siteUrl) =>
      _threadList(siteUrl, _ChatThreadListId.mine).error;

  List<ChatThread> channelThreads(String siteUrl, int channelId) =>
      _heldThreadCatalog(siteUrl)?.channelThreads(channelId) ??
      const <ChatThread>[];

  bool channelThreadsLoaded(String siteUrl, int channelId) =>
      _threadList(siteUrl, _ChannelChatThreadList(channelId)).loaded;

  bool channelThreadsLoading(String siteUrl, int channelId) {
    final state = _threadList(siteUrl, _ChannelChatThreadList(channelId));
    return state.loading && !state.loaded;
  }

  bool channelThreadsLoadingMore(String siteUrl, int channelId) {
    final state = _threadList(siteUrl, _ChannelChatThreadList(channelId));
    return state.loading && state.loaded;
  }

  bool channelThreadsHaveMore(String siteUrl, int channelId) =>
      _threadList(siteUrl, _ChannelChatThreadList(channelId)).hasMore;

  String? channelThreadsError(String siteUrl, int channelId) =>
      _threadList(siteUrl, _ChannelChatThreadList(channelId)).error;

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
  }) => isDisposed
      ? Future.value()
      : _directory(siteUrl).createDirectMessageChannel(
          usernames: usernames,
          groups: groups,
          name: name,
          upsert: upsert,
        );

  /// Adopts conversations omitted by the capped sidebar snapshot and discards
  /// results from a superseded account session.
  Future<ChatDirectMessageSearchResults> searchDirectMessages(
    String siteUrl,
    String term, {
    bool includeGroups = false,
    bool includeDirectMessageChannels = true,
    bool includeCategoryChannels = false,
  }) => isDisposed
      ? Future.value(ChatDirectMessageSearchResults(const []))
      : _directory(siteUrl).searchDirectMessages(
          term,
          includeGroups: includeGroups,
          includeDirectMessageChannels: includeDirectMessageChannels,
          includeCategoryChannels: includeCategoryChannels,
        );

  void _publishNotificationChange(
    String siteUrl,
    ChatChannel before,
    ChatChannel after,
  ) => _directory(siteUrl)._publishNotificationChange(before, after);

  void _insertLiveChannel(String siteUrl, ChatChannel incoming) =>
      _directory(siteUrl)._insertLiveChannel(incoming);

  Object? _beginLiveChannelFollow(String siteUrl, int channelId) =>
      _directory(siteUrl)._beginLiveChannelFollow(channelId);

  bool _ownsLiveChannelFollow(String siteUrl, int channelId, Object token) =>
      _heldDirectory(siteUrl)?._ownsLiveChannelFollow(channelId, token) ??
      false;

  void _endLiveChannelFollow(String siteUrl, int channelId, Object token) =>
      _heldDirectory(siteUrl)?._endLiveChannelFollow(channelId, token);

  /// Matches Discourse: starred public channels precede title-sorted starred DMs.
  List<ChatChannel> starredChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.starredChannels() ?? [];

  List<ChatChannel> unstarredPublicChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.unstarredPublicChannels() ?? [];

  List<ChatChannel> unstarredDirectChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.unstarredDirectChannels() ?? const [];

  /// All direct-message channels in the same activity order used by the web
  /// channel list, before its 50-row display limit is applied.
  List<ChatChannel> activitySortedDirectChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.activitySortedDirectChannels() ?? const [];

  /// Starred channel rows follow web's four buckets—active public, active DMs,
  /// read public, read DMs—with urgency and last activity inside each bucket.
  List<ChatChannel> activitySortedStarredChannels(String siteUrl) =>
      _heldDirectory(siteUrl)?.activitySortedStarredChannels() ?? const [];

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

    final urgent = all.fold(0, (count, channel) => count + channel.urgentCount);
    if (urgent > 0) return ChatHeaderIndicator.urgent(urgent);

    if (preference == ChatHeaderIndicatorPreference.allNew &&
        (public.any((channel) => channel.tracking.unreadCount > 0) ||
            all.any((channel) => channel.unreadThreadCount > 0))) {
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
    return activitySortedDirectChannels(siteUrl).firstOrNull ??
        publicChannels(siteUrl).firstOrNull;
  }

  ChatChannel? channel(String siteUrl, int channelId) =>
      _store.read<ChatChannel>(siteUrl, channelId);

  // Live and local mutations participate in an in-flight list refresh. Ordinary
  // HTTP hydration (including partial channel metadata) is not a newer mutation.
  void _putChannel(String siteUrl, ChatChannel next) =>
      _directory(siteUrl)._putChannel(next);

  void _updateChannel(
    String siteUrl,
    int channelId,
    ChatChannel Function(ChatChannel) change,
  ) => _directory(siteUrl)._updateChannel(channelId, change);

  /// Fetches membership absent from partial search hits outside the capped snapshot.
  Future<ChatChannel?> ensureChannel(String siteUrl, int channelId) =>
      isDisposed
      ? Future.value()
      : _directory(siteUrl).ensureChannel(channelId);

  ChatThread? thread(String siteUrl, int threadId) =>
      _store.read<ChatThread>(siteUrl, threadId);

  void _putThread(String siteUrl, ChatThread next) {
    final before = thread(siteUrl, next.id);
    _recordThreadChange(siteUrl, before, _store.put(siteUrl, next));
  }

  void _updateThread(
    String siteUrl,
    int threadId,
    ChatThread Function(ChatThread held) change,
  ) {
    final before = thread(siteUrl, threadId);
    if (before == null) return;
    _store.update<ChatThread>(siteUrl, threadId, change);
    if (thread(siteUrl, threadId) case final after?) {
      _recordThreadChange(siteUrl, before, after);
    }
  }

  void _recordThreadChange(
    String siteUrl,
    ChatThread? before,
    ChatThread after,
  ) {
    _heldThreadCatalog(siteUrl)?.recordThreadChange(before, after);
  }

  Ref<ChatThread> threadRef(String siteUrl, int threadId) =>
      _store.ref<ChatThread>(siteUrl, threadId);

  /// Advances core's `lastViewedAt`, which filters old thread overview entries.
  Object beginViewingChannel(String siteUrl, int channelId) {
    final target = ChatChannelTarget(channelId);
    final token = _liveSync.beginViewingChannel(siteUrl, channelId);
    if (isDisposed) return token;
    final key = _targetKey(siteUrl, target);
    _rememberTarget(siteUrl, target);
    _conversations[key]?.syncMessagePins();
    _enforceSiteRetention(siteUrl, keep: key);
    _advanceLastViewedAt(siteUrl, channelId);
    return token;
  }

  /// Ignores disposal from an older overlapping pane generation.
  void endViewingChannel(String siteUrl, int channelId, Object token) {
    _liveSync.endViewingChannel(siteUrl, channelId, token);
    final target = ChatChannelTarget(channelId);
    _conversations[_targetKey(siteUrl, target)]?.syncMessagePins();
    _enforceRetentionAfterViewEnds(siteUrl);
  }

  Object beginViewingThread(String siteUrl, ChatThreadTarget target) {
    final token = _liveSync.beginViewingThread(siteUrl, target);
    if (isDisposed) return token;
    final key = _targetKey(siteUrl, target);
    _rememberTarget(siteUrl, target);
    _conversations[key]?.syncMessagePins();
    _enforceSiteRetention(siteUrl, keep: key);
    return token;
  }

  void endViewingThread(String siteUrl, ChatThreadTarget target, Object token) {
    _liveSync.endViewingThread(siteUrl, target, token);
    _conversations[_targetKey(siteUrl, target)]?.syncMessagePins();
    _enforceRetentionAfterViewEnds(siteUrl);
  }

  void _enforceRetentionAfterViewEnds(String siteUrl) {
    scheduleMicrotask(() {
      if (!isDisposed) _enforceSiteRetention(siteUrl);
    });
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
    _putChannel(siteUrl, held.withLastViewedAt(viewedAt));
    if (notify) notifySafely();
  }

  Ref<ChatChannel> channelRef(String siteUrl, int channelId) =>
      _store.ref<ChatChannel>(siteUrl, channelId);

  Ref<ChatMessage> messageRef(String siteUrl, int messageId) =>
      _store.ref<ChatMessage>(siteUrl, messageId);

  ChatMessage? message(String siteUrl, int messageId) =>
      _store.read<ChatMessage>(siteUrl, messageId);

  _ChatChannelPins _pinsFor(String siteUrl, int channelId) =>
      _pinLists.putIfAbsent(
        _pinsKey(siteUrl, channelId),
        () => _ChatChannelPins(this, siteUrl, channelId),
      );

  ValueListenable<ChatPinsState> pinsListenable(
    String siteUrl,
    int channelId,
  ) => _pinsFor(siteUrl, channelId).ref;

  Future<void> loadPinnedMessages(
    String siteUrl,
    int channelId, {
    bool force = false,
  }) => _pinsFor(siteUrl, channelId).load(force: force);

  Future<void> markPinnedMessagesRead(String siteUrl, int channelId) async {
    final held = channel(siteUrl, channelId);
    if (held == null || !held.membership.following) return;
    final lease = _requests.capture(siteUrl);
    _putChannel(siteUrl, held.withPinsViewed(_clock().toUtc()));
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (isDisposed || !lease.isCurrent || apiKey == null) return;
      final clientId = requestCredentials.clientId;
      if (isDisposed || !lease.isCurrent) return;
      await requestCredentials.run(
        () => api.markChatPinsRead(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: channelId,
        ),
      );
    } catch (_) {}
  }

  /// Reads a linked message without replacing a channel/thread's visible window.
  Future<ChatMessage?> resolveBookmarkMessage(
    String siteUrl,
    ChatLink link,
  ) async {
    final messageId = link.messageId;
    final user = _currentUserFor(siteUrl);
    if (isDisposed ||
        messageId == null ||
        user == null ||
        user.hasChatEnabled == false ||
        user.canChat == false ||
        !siteConfigFor(siteUrl).chatSettings.chatEnabled) {
      return null;
    }
    final lease = _requests.capture(siteUrl);
    final version = _bookmarkVersion(siteUrl);
    await ensureChannel(siteUrl, link.route.channelId);
    final credentials = await _requests.credentialsFor(siteUrl);
    if (!lease.isCurrent || isDisposed || credentials.apiKey == null) {
      return null;
    }
    final read = _messageWritesFor(siteUrl).beginRead(link.route.channelId);
    try {
      final threadId = link.route.threadId;
      final page = threadId == null
          ? await credentials.run(
              () => api.chatMessages(
                siteUrl: siteUrl,
                channelId: link.route.channelId,
                targetMessageId: messageId,
                apiKey: credentials.apiKey,
                clientId: credentials.clientId,
              ),
            )
          : await credentials.run(
              () => api.chatThreadMessages(
                siteUrl: siteUrl,
                channelId: link.route.channelId,
                threadId: threadId,
                targetMessageId: messageId,
                apiKey: credentials.apiKey,
                clientId: credentials.clientId,
              ),
            );
      if (!lease.isCurrent ||
          isDisposed ||
          version != _bookmarkVersion(siteUrl)) {
        return null;
      }
      final resolved = read
          .projectPage(page)
          .messages
          .where(
            (message) =>
                message.id == messageId &&
                message.channelId == link.route.channelId &&
                (threadId == null || message.threadId == threadId),
          )
          .firstOrNull;
      if (resolved == null || !canBookmarkMessage(siteUrl, resolved)) {
        return null;
      }
      lease.commit(
        () => _putMessages(siteUrl, [
          resolved,
        ], bookmarkVersionAtDispatch: version),
      );
      return message(siteUrl, messageId);
    } finally {
      read.release();
    }
  }

  // Message rows redraw the per-message checks only when the channel's
  // `ChatChannel.messageAccess` or the account's `ChatAccountAccess` changes,
  // so every channel or account field one of them reads must be part of those.
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
        (message.raw.trim().isNotEmpty ||
            message.uploads.any((upload) => upload.id > 0)) &&
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
  }) => _messageWritesFor(siteUrl).flag(messageId, flagType, message: message);

  Future<String?> setMessagePinned(
    String siteUrl,
    int messageId, {
    required bool pinned,
  }) => _messageWritesFor(siteUrl).pin(messageId, pinned: pinned);

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

  Future<String?> deleteMessage(String siteUrl, int messageId) =>
      _messageWritesFor(siteUrl).setDeleted(messageId, deleted: true);

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
  ) => _messageWritesFor(siteUrl).deleteMany(channelId, messageIds);

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
          !message.isDeleted &&
          // The site moves every message sharing a selected message's thread,
          // so a reply would carry its original message and siblings along.
          (message.threadId == null ||
              message.thread?.threadId == message.threadId);
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
  ) => _messageWritesFor(
    siteUrl,
  ).move(channelId, destinationChannelId, messageIds);

  Future<String?> restoreMessage(String siteUrl, int messageId) =>
      _messageWritesFor(siteUrl).setDeleted(messageId, deleted: false);

  bool messageEditWriteInFlight(String siteUrl, int messageId) =>
      _messageWriteOwners[siteUrl]?.inFlight(
        messageId,
        _MessageWriteKind.edit,
      ) ??
      false;

  bool messageRebakeWriteInFlight(String siteUrl, int messageId) =>
      _messageWriteOwners[siteUrl]?.inFlight(
        messageId,
        _MessageWriteKind.rebake,
      ) ??
      false;

  Future<String?> rebakeMessage(String siteUrl, int messageId) =>
      _messageWritesFor(siteUrl).rebake(messageId);

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
      return (markdown: null, error: appL10n.selectAtLeastOneMessage);
    }
    for (final id in ids) {
      final held = _store.read<ChatMessage>(siteUrl, id);
      if (id <= 0 || held == null || held.channelId != channelId) {
        return (
          markdown: null,
          error: appL10n.oneOfThoseMessagesIsNoLongerAvailable,
        );
      }
    }

    final key = (siteUrl: siteUrl, channelId: channelId);
    if (_messageQuoteWrites.containsKey(key)) {
      return (markdown: null, error: appL10n.thatTranscriptIsStillBeingBuilt);
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
      final markdown = await requestCredentials.run(
        () => api.generateChatQuote(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: channelId,
          messageIds: ids,
        ),
      );
      return ownsRequest()
          ? (markdown: markdown, error: null)
          : (markdown: null, error: null);
    } on WriteException catch (error) {
      return (markdown: null, error: error.message);
    } catch (error) {
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
    Object? cookingOwner,
  }) => _messageWritesFor(
    siteUrl,
  ).edit(messageId, raw, uploads: uploads, cookingOwner: cookingOwner);

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
    for (final message in incoming) {
      _forgetHiddenDelete(siteUrl, message.id);
      _updateChannelMessagePreview(siteUrl, message);
    }
  }

  void _updateChannelMessagePreview(String siteUrl, ChatMessage message) {
    final held = channel(siteUrl, message.channelId);
    if (held == null || held.lastMessageId != message.id) return;
    final preview = chatMessageSummary(
      cooked: message.canonicalReceived ? message.cooked : null,
      raw: message.raw,
      deleted: message.isDeleted,
      hasUploads: message.uploads.isNotEmpty,
    );
    if (held.lastMessagePreview != preview ||
        held.lastMessageUserId != message.author.id ||
        held.lastMessageUsername != message.author.username) {
      _putChannel(
        siteUrl,
        held.withLastMessagePreview(
          preview,
          userId: message.author.id,
          username: message.author.username,
        ),
      );
    }
  }

  void _clearDeletedChannelPreview(
    String siteUrl,
    int? channelId,
    Iterable<int> messageIds,
  ) {
    final held = channelId == null ? null : channel(siteUrl, channelId);
    if (held != null && messageIds.contains(held.lastMessageId)) {
      _putChannel(siteUrl, held.withLastMessagePreview(appL10n.messageDeleted));
    }
  }

  /// Adding requires both message interaction permission and channel membership.
  bool canAddReactionToMessage(String siteUrl, ChatMessage message) =>
      _canInteractWithMessage(siteUrl, message, requireFollowing: true);

  bool canReplyToMessage(String siteUrl, ChatMessage message) =>
      _canInteractWithMessage(siteUrl, message, requireFollowing: true);

  /// Discourse permits removing a reaction after leaving the channel.
  bool canRemoveReactionFromMessage(String siteUrl, ChatMessage message) =>
      _canInteractWithMessage(siteUrl, message, requireFollowing: false);

  bool _canInteractWithMessage(
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
  }) => isDisposed
      ? Future.value()
      : _reactionsFor(siteUrl).set(messageId, emoji, reacted: reacted);

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
  }) => _heldReactions(
    siteUrl,
  )?.reactorsError(channelId, messageId, filter: filter);

  /// Uses chat's authenticated channel-scoped endpoint and retains the previous
  /// page while one request per exact filter refreshes it.
  Future<void> loadMessageReactors({
    required String siteUrl,
    required int channelId,
    required int messageId,
    String? filter,
  }) => isDisposed
      ? Future.value()
      : _reactionsFor(
          siteUrl,
        ).loadReactors(channelId, messageId, filter: filter);

  ChatStreamState stream(String siteUrl, int channelId) =>
      streamFor(siteUrl, ChatChannelTarget(channelId));

  ChatStreamState streamFor(String siteUrl, ChatStreamTarget target) =>
      _conversations[_targetKey(siteUrl, target)]?.snapshot ??
      const ChatStreamState();

  ValueListenable<ChatStreamState> streamListenable(
    String siteUrl,
    int channelId,
  ) => streamListenableFor(siteUrl, ChatChannelTarget(channelId));

  ValueListenable<ChatStreamState> streamListenableFor(
    String siteUrl,
    ChatStreamTarget target,
  ) {
    final key = _targetKey(siteUrl, target);
    _rememberTarget(siteUrl, target);
    _enforceSiteRetention(siteUrl, keep: key);
    return _conversations[key]!.listenable;
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
    _messageWriteOwners[siteUrl]?.retireChannelPins(channelId);
    _directory(siteUrl).revokeChannel(channelId);
    final key = _streamKey(siteUrl, channelId);
    final threadPrefix = '$siteUrl~channel-$channelId-thread-';
    _heldThreadCatalog(siteUrl)?.revokeChannel(channelId);
    _store.removeMatching<ChatThread>(
      siteUrl,
      (thread) => thread.channelId == channelId,
    );
    _store.removeMatching<ChatMessage>(
      siteUrl,
      (message) => message.channelId == channelId,
    );
    if (_hiddenDeletedMessageChannelIds[siteUrl] case final hidden?) {
      hidden.removeWhere((_, heldChannelId) => heldChannelId == channelId);
      if (hidden.isEmpty) _hiddenDeletedMessageChannelIds.remove(siteUrl);
    }
    _threadMetadata.revokeChannel(siteUrl, channelId);

    final unavailableStreams = _conversations.values
        .where(
          (owner) =>
              owner._window != null &&
              (owner.key == key || owner.key.startsWith(threadPrefix)),
        )
        .toList(growable: false);
    for (final owner in unavailableStreams) {
      final current = owner.snapshot;
      owner.abandonWindowWork();
      owner.publish(
        ChatStreamState(
          fetchedOnce: true,
          fetches: current.fetches,
          error: appL10n.youNoLongerHaveAccessToThisChannel,
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
    // Live events extend only a present window. An anchored window keeps its
    // gap and obtains the message through forward paging.
    final window = stream(siteUrl, channelId);
    if (window.fetchedOnce &&
        window.atPresent &&
        !window.messageIds.contains(canonical.id)) {
      _putLiveMessage(siteUrl, canonical, preservePersonalizedState: true);
      _setStream(
        siteUrl,
        ChatChannelTarget(channelId),
        window.copyWith(
          // Root and thread channels race to deliver this event; reduction
          // makes clock-skewed insertion deterministic in either order.
          messageIds: ChatMessageTimeline.admitLive(
            held: _timelineSnapshot(siteUrl, window.messageIds),
            message: canonical,
          ),
          localMessageIds: _retireCanonicalLocals(siteUrl, window, [canonical]),
        ),
        growth: _ChatWindowGrowth.future,
      );
    }
  }

  void _admitLiveMessage(
    String siteUrl,
    ChatStreamTarget target,
    ChatMessage message,
  ) {
    _conversations[_targetKey(siteUrl, target)]?.admitLive(message);
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

  void _putMessage(String siteUrl, ChatMessage message) {
    final previous = _store.read<ChatMessage>(siteUrl, message.id);
    _store.put(siteUrl, message);
    if (previous?.thread?.threadId != message.thread?.threadId ||
        (previous != null && _messageGroupingChanged(previous, message))) {
      _bumpStreamsHolding(siteUrl, message.id);
    }
  }

  static bool _messageGroupingChanged(ChatMessage before, ChatMessage after) =>
      before.isDeleted != after.isDeleted ||
      before.pinned != after.pinned ||
      before.isAction != after.isAction ||
      before.isWebhook != after.isWebhook ||
      before.firstOfResults != after.firstOfResults ||
      before.author.id != after.author.id ||
      before.createdAt != after.createdAt ||
      before.replyTo?.id != after.replyTo?.id;

  /// Invalidates ID-keyed projections when a live record changes rendered shape.
  void _putLiveMessage(
    String siteUrl,
    ChatMessage message, {
    bool preservePersonalizedState = false,
    bool fromRead = false,
  }) {
    if (message.canonicalReceived) _cancelMessageCooking(siteUrl, message.id);
    final replaced = _store.read<ChatMessage>(siteUrl, message.id);
    var effective = replaced == null
        ? message
        : preservePersonalizedState
        ? message.withPersonalizedStateOf(
            replaced,
            currentUserId: _currentUserFor(siteUrl)?.id,
          )
        : replaced.bookmark != null && message.bookmark == null
        ? message.withBookmarkOf(replaced)
        : message;
    // This is client pagination metadata, absent from live and pin payloads.
    if (replaced != null &&
        effective.firstOfResults != replaced.firstOfResults) {
      effective = effective.withFirstOfResults(replaced.firstOfResults);
    }
    _store.put(siteUrl, effective);
    if (!fromRead) {
      final writes = _messageWriteOwners[siteUrl];
      writes?.recordContent(effective);
      writes?.recordDeletion(effective.channelId, effective.id, effective);
    }
    _forgetHiddenDelete(siteUrl, message.id);
    _updateChannelMessagePreview(siteUrl, effective);
    if (replaced != null &&
        (_messageGroupingChanged(replaced, effective) ||
            replaced.thread?.threadId != effective.thread?.threadId)) {
      _bumpStreamsHolding(siteUrl, message.id);
    }
  }

  void _bumpStreamsHolding(String siteUrl, int messageId) {
    final stale = [
      for (final owner in _conversations.values)
        if (owner.siteUrl == siteUrl &&
            (owner._window?.messageIds.contains(messageId) ?? false))
          owner,
    ];
    for (final owner in stale) {
      final window = owner.snapshot;
      owner.publish(window.copyWith(revision: window.revision + 1));
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
    final resolvedChannelId =
        message?.channelId ?? channelId ?? jsonIntOrNull(data['channel_id']);
    final pins = resolvedChannelId == null
        ? null
        : _pinLists[_pinsKey(siteUrl, resolvedChannelId)];
    pins?.advanceLiveRevision();
    final pinned = data['type'] == 'pin';
    if (resolvedChannelId != null) {
      final writes = _messageWriteOwners[siteUrl];
      writes?.acceptPinEvent(
        resolvedChannelId,
        messageId,
        pinned: pinned,
        actorId: jsonIntOrNull(
          data[pinned ? 'pinned_by_id' : 'unpinned_by_id'],
        ),
      );
      if (jsonIntOrNull(data['pinned_message_count']) != null) {
        writes?.acceptPinCount(resolvedChannelId);
      }
    }
    var changed = false;
    if (message != null && message.pinned != pinned) {
      changed = true;
      _store.put(siteUrl, message.withPinned(pinned));
      _bumpStreamsHolding(siteUrl, messageId);
    }

    if (resolvedChannelId != null) {
      _updateChannel(siteUrl, resolvedChannelId, (channel) {
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

      pins?.applyLiveEvent(messageId, pinned: pinned);
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
    _clearDeletedChannelPreview(siteUrl, channelId, ids);
    final deletedAt = _clock().toUtc();
    final deletedById = _currentUserFor(siteUrl)?.id;
    for (final id in ids) {
      final latest = _store.read<ChatMessage>(siteUrl, id);
      if (latest == null || latest.isDeleted) continue;
      _store.put(
        siteUrl,
        latest.withDeletedAt(deletedAt, deletedById: deletedById),
      );
      _messageWriteOwners[siteUrl]?.recordDeletion(
        channelId,
        id,
        _store.read<ChatMessage>(siteUrl, id),
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
  /// the tombstone keeps the row; anyone else loses the record but keeps its
  /// paging slot until a restore stores it again. Answers the message as it
  /// was held, or null when it was not held at all.
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
      (_hiddenDeletedMessageChannelIds[siteUrl] ??= {})[deletedId] =
          message.channelId;
    }
    _messageWriteOwners[siteUrl]?.recordDeletion(
      message.channelId,
      deletedId,
      _store.read<ChatMessage>(siteUrl, deletedId),
    );
    if (!message.isDeleted) _bumpStreamsHolding(siteUrl, deletedId);
    return message;
  }

  void _forgetHiddenDelete(String siteUrl, int messageId) {
    final hidden = _hiddenDeletedMessageChannelIds[siteUrl];
    if (hidden == null || hidden.remove(messageId) == null) return;
    if (hidden.isEmpty) _hiddenDeletedMessageChannelIds.remove(siteUrl);
  }

  bool _holdsMessageSlot(String siteUrl, int messageId) =>
      _store.containsRecord<ChatMessage>(siteUrl, messageId) ||
      (_hiddenDeletedMessageChannelIds[siteUrl]?.containsKey(messageId) ??
          false);

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
    _clearDeletedChannelPreview(siteUrl, resolvedChannelId, [deletedId]);
    final heldChannel = resolvedChannelId == null
        ? null
        : channel(siteUrl, resolvedChannelId);
    if (heldChannel?.membership.lastReadMessageId == deletedId) {
      _putChannel(siteUrl, heldChannel!.withLastReadAfterDelete(latest));
    }
    if (thread == null) return;

    final membership = thread.membership;
    final movesReadCursor = membership?.lastReadMessageId == deletedId;
    final movesLastMessage = thread.lastMessageId == deletedId;
    if (!movesReadCursor && !movesLastMessage) return;
    _updateThread(siteUrl, thread.id, (current) {
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
    _clearDeletedChannelPreview(siteUrl, channelId, deletedIds);
    final heldChannel = channelId == null ? null : channel(siteUrl, channelId);
    if (heldChannel != null &&
        deletedIds.contains(heldChannel.membership.lastReadMessageId)) {
      _putChannel(siteUrl, heldChannel.withLastReadAfterDelete(null));
    }
    if (thread != null) {
      final movesRead = deletedIds.contains(
        thread.membership?.lastReadMessageId,
      );
      final movesLast = deletedIds.contains(thread.lastMessageId);
      if (movesRead || movesLast) {
        _updateThread(siteUrl, thread.id, (current) {
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
    _threadMetadata.recordOriginalDeleted(
      siteUrl,
      channelId,
      originalMessageId,
      clear ? null : deletedAt,
    );
    final candidateIds =
        _heldThreadCatalog(siteUrl)?.loadedIdsForChannel(channelId) ??
        const <int>{};
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
      _putThread(
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

  void _applyReactionEvent(String siteUrl, Map<String, dynamic> data) {
    if (!isDisposed) _reactionsFor(siteUrl).applyEvent(data);
  }

  void _scheduleThreadDetailRefresh(String siteUrl, ChatThreadTarget target) {
    // A refresh during the in-flight request dirties its answer and makes the
    // per-target drain fetch again before callers complete.
    unawaited(refreshThreadDetail(siteUrl, target));
  }

  void _setStream(
    String siteUrl,
    ChatStreamTarget target,
    ChatStreamState stream, {
    _ChatWindowGrowth? growth,
  }) => _conversationFor(siteUrl, target).publish(stream, growth: growth);

  _ChatConversationStream _conversationFor(
    String siteUrl,
    ChatStreamTarget target,
  ) {
    final key = _targetKey(siteUrl, target);
    return _conversations.putIfAbsent(
      key,
      () => _ChatConversationStream(this, siteUrl, target),
    );
  }

  void _rememberTarget(String siteUrl, ChatStreamTarget target) =>
      _rememberConversation(_conversationFor(siteUrl, target));

  void _rememberConversation(_ChatConversationStream owner) {
    if (!owner.isCurrent) return;
    _conversations.remove(owner.key);
    _conversations[owner.key] = owner;
  }

  /// The pinned-message snapshot key owned by a retained channel target.
  String? _retainedPinsKey(String key) {
    final identity = _conversations[key];
    if (identity == null || identity.target is! ChatChannelTarget) return null;
    return _pinsKey(identity.siteUrl, identity.target.channelId);
  }

  /// A window claims at least a page. A channel's pin snapshot claims a row
  /// per pin as well, since those messages occupy the same Store partition
  /// the budget is derived from; a pin also inside the window is counted
  /// twice, which can only evict sooner.
  int _retentionWeight(String key) {
    final messageCount = _conversations[key]?._window?.messageIds.length ?? 0;
    final windowWeight = messageCount < pageSize ? pageSize : messageCount;
    final pinsKey = _retainedPinsKey(key);
    final pinCount = pinsKey == null
        ? 0
        : _pinLists[pinsKey]?.ref.value.pins.length ?? 0;
    return windowWeight + pinCount;
  }

  void _enforceSiteRetention(String siteUrl, {String? keep}) {
    final budget = _maxRetainedCanonicalMessageIdsPerSite;
    if (budget == null) return;
    final candidates = [
      for (final entry in _conversations.entries)
        if (entry.value.siteUrl == siteUrl) entry.key,
    ];
    var retained = candidates.fold<int>(
      0,
      (total, key) => total + _retentionWeight(key),
    );
    if (retained <= budget) return;
    for (final key in candidates) {
      if (retained <= budget) break;
      if (key == keep || !_canEvictRetainedTarget(key)) continue;
      retained -= _retentionWeight(key);
      _evictRetainedTarget(key);
    }
  }

  bool _canEvictRetainedTarget(String key) {
    final identity = _conversations[key];
    if (identity == null) return false;
    final pinsKey = _retainedPinsKey(key);
    final target = identity.target;
    final metadataBusy =
        target is ChatThreadTarget &&
        _threadMetadata.preventsEviction(identity.siteUrl, target);
    if (_liveSync.isViewingTarget(identity.siteUrl, identity.target) ||
        (identity._ref?.hasListeners ?? false) ||
        identity.preventsEviction ||
        (pinsKey != null && (_pinLists[pinsKey]?.ref.hasListeners ?? false)) ||
        (_composerDraftRefs[key]?.hasListeners ?? false) ||
        _composerDraftRefs[key]?.value != null ||
        metadataBusy ||
        (identity.target is ChatChannelTarget &&
            _directory(identity.siteUrl).hasWrite(identity.target.channelId))) {
      return false;
    }
    return true;
  }

  void _evictRetainedTarget(String key) {
    _preparedCooking?.cancel(('draft', key));
    final pinsKey = _retainedPinsKey(key);
    if (pinsKey != null) {
      _pinLists.remove(pinsKey)?.retire(_ChatPinsRetirement.evicted);
    }
    final owner = _conversations.remove(key);
    owner?.retire();
    owner?.resetReference(dispose: true);
    final draftRef = _composerDraftRefs[key];
    if (draftRef != null && draftRef.value == null && !draftRef.hasListeners) {
      _composerDraftRefs.remove(key)?.dispose();
    }
  }

  void _showStreamNotice(
    String siteUrl,
    ChatStreamTarget target,
    String notice,
  ) => _conversationFor(siteUrl, target).showNotice(notice);

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

      _cancelMessageCooking(siteUrl, id);
      remaining ??= stream.localMessageIds.sublist(0, index);
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

  String? channelsError(String siteUrl) =>
      _heldDirectory(siteUrl)?.channelsError();

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
    if (target is! ChatThreadTarget) {
      // Core offers Join instead of a category channel's composer until the
      // reader follows it: the site refuses a message from a reader who never
      // joined, and one who left would post without rejoining. Posting to a
      // closed direct message re-follows it, so that stays sendable.
      return canModify &&
          (heldChannel == null ||
              !heldChannel.isCategoryChannel ||
              heldChannel.membership.following);
    }

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

  /// Whether one of this client's own messages to [target] is on the wire.
  ///
  /// Only a staged local row is ever `sending`, so this reads the local
  /// overlay alone: a composer asks on every stream change, and reading the
  /// canonical window would cost a record per held message each time.
  bool hasSendingMessage(String siteUrl, ChatStreamTarget target) {
    for (final id in streamFor(siteUrl, target).localMessageIds) {
      final local = _store.read<ChatMessage>(siteUrl, id);
      if (local?.delivery == ChatMessageDelivery.sending) return true;
    }
    return false;
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

  ChatSendHandle? retryMessage(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
  ) => _sendCoordinator.retryMessage(siteUrl, target, stagedId);

  ChatMessage? _outgoingMessage(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
  ) {
    for (final id in streamFor(siteUrl, target).localMessageIds) {
      final held = _store.read<ChatMessage>(siteUrl, id);
      if (held?.stagedId == stagedId) return held;
    }
    return null;
  }

  void _stageOutgoing(
    String siteUrl,
    ChatStreamTarget target,
    ChatMessage local,
  ) {
    final ready = _preparedCooking?.takeReady(
      key: ('draft', _targetKey(siteUrl, target)),
      raw: local.raw,
    );
    if (ready != null) local = local.withProvisionalCooked(ready);
    _store.put(siteUrl, local);
    final held = streamFor(siteUrl, target);
    _setStream(
      siteUrl,
      target,
      held.copyWith(
        localMessageIds: List.unmodifiable([...held.localMessageIds, local.id]),
        clearError: true,
      ),
    );
    if (ready == null) _cookMessage(siteUrl, local, target: target);
  }

  void _cancelMessageCooking(String siteUrl, int messageId) {
    _messageCookingTokens.remove((siteUrl, messageId));
    _preparedCooking?.cancel(('message', siteUrl, messageId));
  }

  /// Scheduling never assembles a snapshot or awaits the worker on the staging
  /// stack. Updates retain concurrent message state and cannot recreate a row.
  void _cookMessage(
    String siteUrl,
    ChatMessage message, {
    ChatStreamTarget? target,
    ChatMessage? author,
  }) {
    final cooking = _preparedCooking;
    if (cooking == null || isDisposed) return;
    final token = Object();
    final key = (siteUrl, message.id);
    final lease = _requests.capture(siteUrl);
    final localeRevision = _cookingLocaleRevisions[siteUrl] ?? 0;
    _messageCookingTokens[key] = token;
    bool isCurrent() {
      if (isDisposed ||
          !lease.isCurrent ||
          localeRevision != (_cookingLocaleRevisions[siteUrl] ?? 0) ||
          !identical(_messageCookingTokens[key], token)) {
        return false;
      }
      final current = _store.read<ChatMessage>(siteUrl, message.id);
      return current != null &&
          !current.canonicalReceived &&
          !current.isDeleted &&
          current.raw == message.raw &&
          current.stagedId == message.stagedId &&
          (target == null ||
              streamFor(siteUrl, target).localMessageIds.contains(message.id));
    }

    unawaited(
      cooking
          .cook(
            key: ('message', siteUrl, message.id),
            siteUrl: siteUrl,
            raw: message.raw,
            contextBuilder: () => _cookingContext(siteUrl, author: author),
            isCurrent: isCurrent,
          )
          .then((html) {
            if (html != null && isCurrent()) {
              _store.update<ChatMessage>(
                siteUrl,
                message.id,
                (held) => held.withProvisionalCooked(html),
              );
            }
            if (identical(_messageCookingTokens[key], token)) {
              _messageCookingTokens.remove(key);
            }
          }),
    );
  }

  ChatPreviewResult _projectPreview(
    String siteUrl,
    OutgoingChatMessage message,
  ) {
    if (_preparedCooking != null && message.trustedPreviewSeed == null) {
      return SourceFallback(message.raw, ChatPreviewFallbackReason.pending);
    }
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
              failure: failure,
              deliveryUncertain:
                  failure.failure == WriteFailure.unreachable &&
                  !failure.notSent,
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
    _cancelMessageCooking(siteUrl, localId);
    final key = _targetKey(siteUrl, target);
    final window = _conversations[key]?._window;
    if (window == null || !window.localMessageIds.contains(localId)) return;
    _setStream(
      siteUrl,
      target,
      window.copyWith(
        localMessageIds: List.unmodifiable(
          window.localMessageIds.where((id) => id != localId),
        ),
      ),
    );
    _sendCoordinator.releaseReconciliationIfSettled(siteUrl, target);
  }

  bool _hasUnsettledOutgoingMessages(String siteUrl, ChatStreamTarget target) {
    final window = streamFor(siteUrl, target);
    for (final id in window.localMessageIds) {
      final local = _store.read<ChatMessage>(siteUrl, id);
      if (local == null) continue;
      if (local.delivery == ChatMessageDelivery.sending ||
          local.deliveryUncertain ||
          local.sendRetryable ||
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
          userId: canonical.author.id,
          username: canonical.author.username,
          preview: chatMessageSummary(
            cooked: canonical.cooked,
            raw: canonical.raw,
            hasUploads: canonical.uploads.isNotEmpty,
          ),
          markRead: true,
          incrementUnread: false,
        );
        _putChannel(siteUrl, updated);
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

  /// Returning after [resumeResyncThreshold] revalidates every held channel
  /// list, whose snapshot replaces the cursors and presence the resumed poll
  /// could not catch up; live changes accepted during that read still win.
  /// Each viewed window at the present is re-read from its newest message.
  void setForeground(bool foreground) {
    if (isDisposed) return;
    if (!foreground) {
      _backgroundedAt ??= _clock();
      return;
    }
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null ||
        _clock().difference(backgroundedAt) < resumeResyncThreshold) {
      return;
    }
    for (final siteUrl
        in _directories.entries
            .where((entry) => entry.value.hasSnapshot)
            .map((entry) => entry.key)
            .toList()) {
      unawaited(loadChannels(siteUrl, revalidate: true));
    }
    for (final owner in _conversations.values.toList()) {
      _resyncViewedWindow(owner.siteUrl, owner.target);
    }
  }

  /// A window at the present extends itself with live arrivals, trusting the
  /// poll to carry on from its newest message. After an absence the resumed
  /// poll replays only what the trimmed backlog still holds, and appending
  /// that would bridge a gap neither paging direction could fill. The window
  /// is anchored behind the present instead, so replayed arrivals park until
  /// a forward page from its newest message closes the seam, and the reader
  /// keeps their place. A window no one is viewing is left to the fresh read
  /// its next open makes.
  void _resyncViewedWindow(String siteUrl, ChatStreamTarget target) {
    final key = _targetKey(siteUrl, target);
    final conversation = _conversations[key];
    final window = conversation?._window;
    if (window == null ||
        !window.fetchedOnce ||
        !window.atPresent ||
        window.error != null ||
        (_conversations[key]?._loading ?? false) ||
        !_liveSync.isViewingTarget(siteUrl, target)) {
      return;
    }
    if (window.newestId == null) {
      // With no edge to page from, a fresh read replaces nothing on screen.
      unawaited(
        conversation!.fetchWindow(fromLastRead: target.threadId == null),
      );
      return;
    }
    _setStream(siteUrl, target, window.copyWith(canLoadMoreFuture: true));
    unawaited(conversation!.loadNewer());
  }

  /// Shares one bounded initial sidebar load per site; live tracking keeps it
  /// fresh, while failure leaves the site without a chat section.
  ///
  /// [force] is reserved for an explicit retry or refresh by the reader.
  /// [revalidate] re-reads a held list in the background once live tracking
  /// can no longer vouch for it: it is not drawn as loading, and a failure
  /// leaves the held list as it was, without an error to retry.
  Future<void> loadChannels(
    String siteUrl, {
    bool force = false,
    bool revalidate = false,
  }) => isDisposed
      ? Future.value()
      : _directory(siteUrl).loadChannels(force: force, revalidate: revalidate);

  /// Uses the wire offset, not deduplicated row count, for core's thread pages.
  Future<void> loadMyThreads(
    String siteUrl, {
    bool more = false,
    bool force = false,
  }) => isDisposed
      ? Future.value()
      : _threadCatalog(
          siteUrl,
        ).load(_ChatThreadListId.mine, more: more, force: force);

  /// A [force]d load replaces a held list with its first page. [revalidate]
  /// instead refreshes that page into the held list, as the web list refetches
  /// on each visit: threads started since join the pages already read, and a
  /// failure leaves the held list as it was, without an error to retry.
  Future<void> loadChannelThreads(
    String siteUrl,
    int channelId, {
    bool more = false,
    bool force = false,
    bool revalidate = false,
    ChatChannel? directoryChannel,
  }) {
    if (isDisposed || channelId <= 0) return Future.value();
    var heldChannel = channel(siteUrl, channelId);
    if (heldChannel == null && directoryChannel?.id == channelId) {
      heldChannel = directoryChannel;
      _directory(siteUrl).hydratePartialIfMissing(directoryChannel!);
    }
    if (heldChannel?.threadingEnabled != true) return Future.value();
    return _threadCatalog(siteUrl).load(
      _ChannelChatThreadList(channelId),
      more: more,
      force: force,
      revalidate: revalidate,
    );
  }

  /// Retries the load behind [channelThreadsError]. A failed page leaves more
  /// to load, so a list with none left failed its first page or a forced
  /// refresh, and asking it for a next page would send nothing.
  Future<void> retryChannelThreads(
    String siteUrl,
    int channelId, {
    ChatChannel? directoryChannel,
  }) {
    final more = channelThreadsHaveMore(siteUrl, channelId);
    return loadChannelThreads(
      siteUrl,
      channelId,
      more: more,
      force: !more,
      directoryChannel: directoryChannel,
    );
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
    final held = streamFor(siteUrl, target);
    final backed = _canonicalWindowIsBacked(siteUrl, held);
    if (!force &&
        targetMessageId == null &&
        _windowAttemptedRecently(key) &&
        ((_conversations[key]?._loading ?? false) ||
            held.fetchedOnce && backed)) {
      return;
    }
    if (!backed) _discardStaleCanonicalWindow(siteUrl, target, held);
    final conversation = _conversationFor(siteUrl, target);
    await conversation.fetchWindow(
      fromLastRead: targetMessageId == null,
      targetMessageId: targetMessageId,
    );
  }

  bool _windowAttemptedRecently(String key) =>
      _conversations[key]?.attemptedRecently ?? false;

  bool _canonicalWindowIsBacked(String siteUrl, ChatStreamState stream) =>
      stream.messageIds.every((id) => _holdsMessageSlot(siteUrl, id));

  void _discardStaleCanonicalWindow(
    String siteUrl,
    ChatStreamTarget target,
    ChatStreamState stream,
  ) {
    _setStream(
      siteUrl,
      target,
      stream.copyWith(
        messageIds: const [],
        loadingOlder: false,
        loadingNewer: false,
        fetchedOnce: false,
        revision: stream.revision + 1,
      ),
    );
  }

  Future<void> openThread(
    String siteUrl,
    ChatThreadTarget target, {
    int? targetMessageId,
    bool force = false,
  }) async {
    if (isDisposed || target.channelId <= 0 || target.threadId <= 0) return;
    final key = _targetKey(siteUrl, target);
    final held = streamFor(siteUrl, target);
    final backed = _canonicalWindowIsBacked(siteUrl, held);
    if (!force &&
        targetMessageId == null &&
        _windowAttemptedRecently(key) &&
        ((_conversations[key]?._loading ?? false) ||
            held.fetchedOnce && backed)) {
      return;
    }
    if (!backed) _discardStaleCanonicalWindow(siteUrl, target, held);
    final conversation = _conversationFor(siteUrl, target);
    final detail = await refreshThreadDetail(siteUrl, target);
    if (detail == null || !conversation.isCurrent) return;
    _liveSync.ensureThreadSubscription(siteUrl, target);
    final result = await conversation.fetchWindow(
      fromLastRead: false,
      targetMessageId: targetMessageId,
    );
    if (result == _ChatWindowFetchResult.missingTarget &&
        targetMessageId != null) {
      final fallback = await conversation.fetchWindow(fromLastRead: false);
      if (fallback == _ChatWindowFetchResult.loaded) {
        conversation.showNotice(
          appL10n.thatMessageIsUnavailableShowingTheThreadInstead,
        );
      }
    }
  }

  Future<ChatThread?> refreshThreadDetail(
    String siteUrl,
    ChatThreadTarget target,
  ) => _threadMetadata.refreshThreadDetail(siteUrl, target);

  Future<ChatThread?> createThread(
    String siteUrl, {
    required int channelId,
    required int originalMessageId,
  }) => _threadMetadata.createThread(
    siteUrl,
    channelId: channelId,
    originalMessageId: originalMessageId,
  );

  bool canEditThreadTitle(String siteUrl, ChatThread? thread) =>
      _threadMetadata.canEditThreadTitle(siteUrl, thread);

  Future<bool> updateThreadTitle(
    String siteUrl,
    ChatThreadTarget target,
    String title,
  ) => _threadMetadata.updateThreadTitle(siteUrl, target, title);

  Future<bool> updateThreadNotificationLevel(
    String siteUrl,
    ChatThreadTarget target,
    ChatThreadNotificationLevel level,
  ) => _threadMetadata.updateThreadNotificationLevel(siteUrl, target, level);

  /// Fetches only when the held window is not already at the present.
  Future<void> showLatest(String siteUrl, int channelId) {
    return showLatestFor(siteUrl, ChatChannelTarget(channelId));
  }

  Future<void> showLatestFor(String siteUrl, ChatStreamTarget target) async {
    if (isDisposed || target.channelId <= 0) return;
    if (streamFor(siteUrl, target).atPresent) return;
    final conversation = _conversationFor(siteUrl, target);
    await conversation.fetchWindow(fromLastRead: false, anchorAtEnd: true);
  }

  Future<void> loadOlder(String siteUrl, int channelId) async {
    return loadOlderFor(siteUrl, ChatChannelTarget(channelId));
  }

  Future<void> loadOlderFor(String siteUrl, ChatStreamTarget target) {
    if (isDisposed || target.channelId <= 0) return Future.value();
    return _conversations[_targetKey(siteUrl, target)]?.loadOlder() ??
        Future.value();
  }

  Future<void> loadNewer(String siteUrl, int channelId) async {
    return loadNewerFor(siteUrl, ChatChannelTarget(channelId));
  }

  Future<void> loadNewerFor(String siteUrl, ChatStreamTarget target) {
    if (isDisposed || target.channelId <= 0) return Future.value();
    return _conversations[_targetKey(siteUrl, target)]?.loadNewer() ??
        Future.value();
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
    final admission = ChatReadReceiptOwner.admit(
      target,
      messageId,
      ChatReadReceiptSnapshot(
        lease: lease,
        channel: channel(siteUrl, target.channelId),
        thread: target.threadId == null
            ? null
            : thread(siteUrl, target.threadId!),
        isLocalMessage: window.localMessageIds.contains(messageId),
        atPresent: window.atPresent,
        newestMessageId: window.newestId,
      ),
      retryMessageId: _readReceiptRetries.pendingMessageId(siteUrl, target),
    );
    if (admission == null) return Future.value();
    return _conversationFor(siteUrl, target).readReceipts.markRead(admission);
  }

  void _publishRead(
    String siteUrl,
    ChatStreamTarget target,
    ChatReadAdmission admission,
    DateTime viewedAt,
  ) {
    switch (admission) {
      case ChatChannelRead():
        ChatChannel? updatedChannel;
        _updateChannel(siteUrl, target.channelId, (current) {
          final updated = admission.project(current, viewedAt);
          if (updated == null) return current;
          updatedChannel = updated;
          return updated;
        });
        if (updatedChannel case final updated?) {
          _publishNotificationChange(siteUrl, admission.before, updated);
        }
      case ChatThreadRead():
        _updateThread(siteUrl, target.threadId!, admission.project);
    }
    notifySafely();
  }

  void forget(String siteUrl) {
    _readReceiptRetries.forget(siteUrl);
    _messageWriteOwners.remove(siteUrl)?.retire();
    _reactionOwners.remove(siteUrl)?.retire();
    _directories.remove(siteUrl)?.retire();
    _preparedCooking?.forget(siteUrl);
    _cookingLocales.remove(siteUrl);
    _cookingLocaleRevisions.remove(siteUrl);
    _messageCookingTokens.removeWhere((key, _) => key.$1 == siteUrl);
    channelListPreferences.forget(siteUrl);
    inboxFilters.forget(siteUrl);
    _threadCatalogs.remove(siteUrl)?.retire();
    _liveSync.forget(siteUrl);
    final forgottenConversations = <_ChatConversationStream>[];
    _conversations.removeWhere((_, owner) {
      if (owner.siteUrl != siteUrl) return false;
      forgottenConversations.add(owner);
      return true;
    });
    for (final owner in forgottenConversations) {
      owner.retire();
    }
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
    _messageQuoteWrites.removeWhere((key, _) => key.siteUrl == siteUrl);
    final forgottenPins = <_ChatChannelPins>[];
    _pinLists.removeWhere((_, owner) {
      if (owner.siteUrl != siteUrl) return false;
      forgottenPins.add(owner);
      return true;
    });
    for (final owner in forgottenPins) {
      owner.retire(_ChatPinsRetirement.forgotten);
    }
    _bookmarkVersions.remove(siteUrl);
    _threadMetadata.forget(siteUrl);
    _hiddenDeletedMessageChannelIds.remove(siteUrl);
    for (final owner in forgottenConversations) {
      owner.resetReference();
    }
    _lastOpenedChannelIds.remove(siteUrl);
    _store.forget(siteUrl);
    notifySafely();
  }

  @override
  void dispose() {
    _readReceiptRetries.clear();
    final messageWriteOwners = _messageWriteOwners.values.toList(
      growable: false,
    );
    _messageWriteOwners.clear();
    for (final owner in messageWriteOwners) {
      owner.retire();
    }
    final reactions = _reactionOwners.values.toList(growable: false);
    _reactionOwners.clear();
    for (final owner in reactions) {
      owner.retire();
    }
    final directories = _directories.values.toList(growable: false);
    _directories.clear();
    for (final directory in directories) {
      directory.retire();
    }
    _preparedCooking?.dispose();
    _messageCookingTokens.clear();
    _cookingLocales.clear();
    _cookingLocaleRevisions.clear();
    channelListPreferences.dispose();
    inboxFilters.dispose();
    final catalogs = _threadCatalogs.values.toList(growable: false);
    _threadCatalogs.clear();
    for (final catalog in catalogs) {
      catalog.retire();
    }
    _liveSync.dispose();
    final conversations = _conversations.values.toList(growable: false);
    _conversations.clear();
    for (final owner in conversations) {
      owner.retire();
      owner.disposeReference();
    }
    _threadMetadata.dispose();
    _hiddenDeletedMessageChannelIds.clear();
    _messageQuoteWrites.clear();
    final pinLists = _pinLists.values.toList(growable: false);
    _pinLists.clear();
    for (final owner in pinLists) {
      owner.retire(_ChatPinsRetirement.disposed);
    }
    _bookmarkVersions.clear();
    for (final ref in _composerDraftRefs.values) {
      ref.dispose();
    }
    _composerDraftRefs.clear();
    super.dispose();
  }
}

final class _ChatThreadMetadataEvents implements ChatThreadMetadataEvents {
  _ChatThreadMetadataEvents(this._controller, this._onChanged);

  final ChatController _controller;
  final void Function() _onChanged;

  @override
  void detailLoading(String siteUrl, ChatThreadTarget target) {
    _controller._setStream(
      siteUrl,
      target,
      _controller
          .streamFor(siteUrl, target)
          .copyWith(clearError: true, threadUnavailable: false),
    );
  }

  @override
  void detailStored(
    String siteUrl,
    ChatThreadTarget target,
    ChatThread detail,
  ) {
    _controller._liveSync.adoptThreadCursor(
      siteUrl,
      target,
      detail.messageBusLastId,
    );
    final originalId = detail.originalMessage?.id;
    final preview = detail.preview;
    if (originalId != null && preview != null) {
      final original = _controller._store.read<ChatMessage>(
        siteUrl,
        originalId,
      );
      if (original != null && original.channelId == detail.channelId) {
        _controller._putMessage(siteUrl, original.withThreadPreview(preview));
      }
    }
    detailLoading(siteUrl, target);
  }

  @override
  void ensureThreadSubscription(String siteUrl, ChatThreadTarget target) =>
      _controller._liveSync.ensureThreadSubscription(siteUrl, target);

  @override
  void detailFailed(
    String siteUrl,
    ChatThreadTarget target, {
    required bool terminal,
  }) {
    final window = _controller.streamFor(siteUrl, target);
    _controller._setStream(
      siteUrl,
      target,
      window.copyWith(
        fetchedOnce: true,
        error: window.messageIds.isEmpty
            ? terminal
                  ? appL10n.thisThreadIsNoLongerAvailable
                  : appL10n.couldNotLoadThisThread
            : null,
        threadUnavailable: terminal,
      ),
    );
  }

  @override
  void threadCreated(
    String siteUrl,
    ChatThread created,
    int originalMessageId,
  ) {
    _controller._threadCatalog(siteUrl).insertCreated(created);
    final original = _controller._store.read<ChatMessage>(
      siteUrl,
      originalMessageId,
    );
    if (original != null && created.preview != null) {
      _controller._putMessage(
        siteUrl,
        original.withThreadPreview(created.preview),
      );
    }
    _onChanged();
  }

  @override
  void threadChanged(String siteUrl, ChatThread before, ChatThread after) =>
      _controller._recordThreadChange(siteUrl, before, after);

  @override
  void threadTitleStored(String siteUrl, int threadId) =>
      _controller._heldThreadCatalog(siteUrl)?.recordTitleChange(threadId);
}
