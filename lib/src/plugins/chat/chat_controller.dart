import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import '../../data/site_tracker.dart';
import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../models/discourse_user.dart';
import '../../models/json.dart';
import '../../models/site_config.dart';
import 'chat_channel.dart';
import 'chat_message.dart';
import 'chat_preview.dart';

/// What Discourse's chat shortcut paints over its comment icon.
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

/// What the main region knows about one channel, at one moment.
///
/// The sibling of `TopicFeed`, and ids rather than messages for the same
/// reason: the messages themselves are in the [Store], where one copy is shared
/// by the row drawing it and anything else that names it, so this is only the
/// order they go in.
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
    this.fetchedOnce = false,
    this.fetches = 0,
    this.lastReadOnOpen,
    this.error,
  });

  /// Oldest first, and **contiguous** — there is never a hole in the middle.
  /// That is the invariant paging depends on: [ChatController.loadOlder] pages
  /// before the first of these and [ChatController.loadNewer] after the last,
  /// so a gap anywhere between them could never be filled.
  final List<int> messageIds;

  /// Optimistic outgoing rows, oldest first, after the canonical window.
  ///
  /// These ids are negative and local. Keeping them out of [messageIds] is
  /// load-bearing: that list is a contiguous server window used as the cursor
  /// for paging and read receipts, while a message authored from an anchored
  /// window may be separated from it by an arbitrarily large unread gap.
  final List<int> localMessageIds;

  /// A first page is on its way and there is nothing to show behind it.
  final bool loading;

  /// A page of history is on its way, under what is already on screen.
  final bool loadingOlder;

  /// A page towards the present is on its way, over what is already on screen.
  final bool loadingNewer;

  final bool canLoadMorePast;

  /// Whether there are messages between the newest one held and the present.
  ///
  /// False for a stream fetched at the live edge, which is most of them. True
  /// only while the reader is anchored back where they left off with a backlog
  /// in front of them — which is what [ChatController.openChannel] does, and
  /// the reason [ChatController.loadNewer] exists at all.
  final bool canLoadMoreFuture;

  /// Whether the site has answered at all, which is what tells an empty channel
  /// apart from one that has not been read yet.
  final bool fetchedOnce;

  /// How many times this stream has been *replaced* — opened, or jumped to the
  /// present — as opposed to paged into.
  ///
  /// The view's cue to position itself: a fresh window means the scroll offset
  /// it is holding describes messages that are no longer there, so it has to
  /// land somewhere deliberately rather than inherit it. Paging changes the
  /// list without changing where the reader is, and leaves this alone.
  final int fetches;

  /// Where the reader had got to when this stream was fetched, which is what
  /// the unread divider is drawn from.
  ///
  /// A snapshot rather than the membership's live answer, and that is the
  /// whole point of it: [ChatController.markRead] moves the membership as the
  /// reader scrolls, so a divider that watched it would slide down the screen
  /// ahead of them and then vanish. Discourse pins the same line to a
  /// `newestMessage` captured at fetch time, for the same reason. It moves
  /// when the stream is replaced — a re-open — and not before.
  final int? lastReadOnOpen;

  final String? error;

  bool get isEmpty =>
      fetchedOnce &&
      error == null &&
      messageIds.isEmpty &&
      localMessageIds.isEmpty;

  /// The message to page before. Null on an empty stream, where there is
  /// nothing to page from.
  int? get oldestId => messageIds.firstOrNull;

  /// The message to page after, and the one the reader is caught up to when
  /// there is nothing in front of it.
  int? get newestId => messageIds.lastOrNull;

  /// Whether the newest message held is the newest there is.
  bool get atPresent => !canLoadMoreFuture;

  ChatStreamState copyWith({
    List<int>? messageIds,
    List<int>? localMessageIds,
    bool? loading,
    bool? loadingOlder,
    bool? loadingNewer,
    bool? canLoadMorePast,
    bool? canLoadMoreFuture,
    bool? fetchedOnce,
    String? error,
    bool clearError = false,
  }) => ChatStreamState(
    messageIds: messageIds ?? this.messageIds,
    localMessageIds: localMessageIds ?? this.localMessageIds,
    loading: loading ?? this.loading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    loadingNewer: loadingNewer ?? this.loadingNewer,
    canLoadMorePast: canLoadMorePast ?? this.canLoadMorePast,
    canLoadMoreFuture: canLoadMoreFuture ?? this.canLoadMoreFuture,
    fetchedOnce: fetchedOnce ?? this.fetchedOnce,
    // Carried rather than settable: both belong to the fetch that built this
    // window, and every copy of one is the same window still.
    fetches: fetches,
    lastReadOnOpen: lastReadOnOpen,
    error: clearError ? null : (error ?? this.error),
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
          other.fetchedOnce == fetchedOnce &&
          other.fetches == fetches &&
          other.lastReadOnOpen == lastReadOnOpen &&
          other.error == error;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(messageIds),
    Object.hashAll(localMessageIds),
    loading,
    loadingOlder,
    loadingNewer,
    canLoadMorePast,
    canLoadMoreFuture,
    fetchedOnce,
    fetches,
    lastReadOnOpen,
    error,
  );
}

/// Which channels a site has, and which messages are in the one on screen.
///
/// Its own notifier rather than more state on `ShellController`, the way
/// `ReactionsController` and `UpdateController` are. The sidebar navigation and
/// active channel listen directly; individual messages use their store refs.
/// Chat traffic therefore redraws the regions it can change without notifying
/// every shell dependent.
///
/// Only the *asking* and the *ordering* live here. The channels and the
/// messages go in the [Store] under their own ids, so the sidebar row and the
/// screen it opens are drawing one record rather than two copies.
class ChatController extends FrameSafeNotifier {
  ChatController({
    required this.api,
    required this.credentials,
    required this.store,
    SiteLifecycle? lifecycle,
    DiscourseUser? Function(String siteUrl)? currentUserFor,
    SiteConfig Function(String siteUrl)? siteConfigFor,
    ChatPreviewEngine? previewEngine,
    this.minimumWindowRefreshInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : assert(minimumWindowRefreshInterval >= Duration.zero),
       lifecycle = lifecycle ?? SiteLifecycle(),
       _currentUserFor = currentUserFor ?? _noCurrentUser,
       _siteConfigFor = siteConfigFor ?? _unknownSiteConfig,
       _previewEngine = previewEngine ?? ChatPreviewEngine(),
       _clock = clock ?? DateTime.now;

  final ChatApi api;
  final ApiCredentialReader credentials;
  final Store store;
  final SiteLifecycle lifecycle;
  final Duration minimumWindowRefreshInterval;
  final DiscourseUser? Function(String siteUrl) _currentUserFor;
  final SiteConfig Function(String siteUrl) _siteConfigFor;
  final ChatPreviewEngine _previewEngine;
  final DateTime Function() _clock;

  static DiscourseUser? _noCurrentUser(String _) => null;
  static SiteConfig _unknownSiteConfig(String _) => const SiteConfig.unknown();

  void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool degraded = true,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'chat',
      severity: severity,
      handled: true,
      degraded: degraded,
    );
  }

  /// How many messages to ask for. The site caps it at 50 and Discourse's own
  /// client sends exactly that.
  static const int pageSize = 50;

  /// How many times a site's channel list is worth asking for.
  ///
  /// Bounded like `_ensureCustomEmojis`: nothing on screen asks for this again,
  /// so a failure that could only be retried by an event which will not happen
  /// would be a dead end for the life of the session.
  static const int maxChannelAttempts = 3;

  /// Facts about requests rather than about records, which is why they are here
  /// and not in the [Store]: a channel that has never been fetched has nowhere
  /// to hold them.
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};
  final Map<String, int> _attempts = {};
  final Map<String, Future<void>> _channelRequests = {};
  final Map<String, Object> _channelRuns = {};

  /// Channel ids in the order the sidebar draws them. The channels themselves
  /// are in the [Store]; these two lists are the orderings, which no record
  /// holds.
  final Map<String, List<int>> _publicIds = {};
  final Map<String, List<int>> _directIds = {};
  final Map<String, int> _lastOpenedChannelIds = {};

  /// The channel panes currently mounted, with a generation token so disposal
  /// of an older overlapping pane cannot deactivate its replacement.
  final Map<String, Object> _activeChannelViews = {};

  /// The HTTP presence snapshot, its row-scoped listenable and the live
  /// subscription that advances it. A tracker can arrive before or after the
  /// channel list, so both halves are retained and [_syncPresence] joins them
  /// whenever the second one appears.
  final Map<String, ChatPresence> _presence = {};
  final Map<String, FrameSafeValueNotifier<Set<int>>> _presenceRefs = {};
  final Map<String, SiteTracker> _presenceTrackers = {};
  final Map<String, SiteMessageBusSubscription> _presenceSubscriptions = {};

  /// Persistent activity subscriptions for every channel in the latest HTTP
  /// snapshot. Separate from [_sendSubscriptions], which temporarily watches
  /// `/chat/{id}` only to reconcile this client's staged sends.
  final Map<String, Map<int, int?>> _newMessageCursors = {};
  final Map<String, SiteMessageBusSubscription> _newMessageSubscriptions = {};
  final Map<String, int?> _newChannelCursors = {};
  final Map<String, SiteMessageBusSubscription> _newChannelSubscriptions = {};
  final Map<String, int?> _userTrackingCursors = {};
  final Map<String, List<SiteMessageBusSubscription>>
  _userTrackingSubscriptions = {};
  final Set<String> _newChannelsAwaitingFirstMessage = {};

  /// One channel's stream, keyed `'$siteUrl~$channelId'`.
  final Map<String, ChatStreamState> _streams = {};
  final Map<String, FrameSafeValueNotifier<ChatStreamState>> _streamRefs = {};
  final Map<String, Object> _streamGenerations = {};
  final Map<String, DateTime> _windowAttemptedAt = {};
  final Map<String, Object> _pageRequests = {};
  final Map<
    String,
    ({String siteUrl, int channelId, int messageId, SiteLease lease})
  >
  _queuedReadReceipts = {};
  final Map<String, Future<void>> _readReceiptTasks = {};
  final Map<String, Object> _readReceiptRuns = {};
  final Map<String, _ChatSendQueue> _sendQueues = {};
  final Map<String, SiteMessageBusSubscription> _sendSubscriptions = {};
  final Set<({String siteUrl, int channelId})> _sendSubscriptionChannels = {};
  int _nextLocalMessageId = -1;
  int _nextStagedSequence = 0;

  static String _channelsKey(String siteUrl) => '$siteUrl~channels';
  static String _streamKey(String siteUrl, int id) => '$siteUrl~$id';
  static String _olderKey(String siteUrl, int id) => '$siteUrl~$id~past';
  static String _newerKey(String siteUrl, int id) => '$siteUrl~$id~future';

  /// Whether an asynchronous operation still belongs to this controller, site
  /// session, and request generation.
  ///
  /// Credential storage is asynchronous on every platform and can be visibly
  /// slow on macOS. A site can be disconnected, the controller disposed, or a
  /// stream replaced during either await. Response guards are too late for
  /// those cases: they prevent stale state commits but still send an old
  /// account request. Chat operations prove ownership with this predicate
  /// after each credential await and immediately before delegation.
  bool _requestIsCurrent(SiteLease lease, bool Function() ownsRequest) =>
      !isDisposed && lease.isCurrent && ownsRequest();

  // --- reads -------------------------------------------------------------

  /// The public channels this account follows, in sidebar order. Empty before
  /// the site has answered, which is also what a site with none looks like —
  /// deliberately, since nothing is drawn for either.
  List<ChatChannel> publicChannels(String siteUrl) =>
      _resolve(siteUrl, _publicIds[siteUrl]);

  List<ChatChannel> directChannels(String siteUrl) =>
      _resolve(siteUrl, _directIds[siteUrl]);

  /// Starred public channels followed by starred direct messages, matching
  /// Discourse's desktop sidebar. Public channels already arrive slug-sorted;
  /// direct messages need a separate title sort because their ordinary section
  /// stays in the server's activity order.
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

  /// Core's `compareDirectMessageChannelsByActivity`, for the unstarred DM
  /// section this app mirrors. Starred conversations live in their own
  /// alphabetical section and never enter this comparator.
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

  /// The header's aggregate signal, following ChatHeaderIconUnreadIndicator.
  ///
  /// Urgent means every direct-message unread, every mention and every watched
  /// thread unread. Ordinary public-channel activity and unread untracked
  /// threads are the quieter dot, shown only for the `all_new` preference.
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

  /// Where the shortcut lands: the channel most recently opened in this app,
  /// then the server's last channel when it is still in the account's followed
  /// lists, then the newest direct message, then the first public channel. The
  /// latter two are the native fallback for core's browse screen, which this
  /// client does not have yet.
  ChatChannel? shortcutChannel(String siteUrl, {int? lastChannelId}) {
    final preferredId = _lastOpenedChannelIds[siteUrl] ?? lastChannelId;
    if (preferredId != null) {
      final last = channel(siteUrl, preferredId);
      if (last != null) return last;
    }
    return _sortDirectMessageActivity(
          directChannels(siteUrl).toList(),
        ).firstOrNull ??
        publicChannels(siteUrl).firstOrNull;
  }

  List<ChatChannel> _resolve(String siteUrl, List<int>? ids) => [
    for (final id in ids ?? const <int>[])
      ?store.read<ChatChannel>(siteUrl, id),
  ];

  ChatChannel? channel(String siteUrl, int channelId) =>
      store.read<ChatChannel>(siteUrl, channelId);

  /// Marks one mounted channel pane active and returns its generation token.
  ///
  /// Core advances `lastViewedAt` when the pane opens. That timestamp filters
  /// old thread overview entries out of both sidebar ordering and its badge.
  Object beginViewingChannel(String siteUrl, int channelId) {
    final token = Object();
    if (isDisposed) return token;
    final key = _streamKey(siteUrl, channelId);
    _activeChannelViews[key] = token;
    _advanceLastViewedAt(siteUrl, channelId);
    return token;
  }

  /// Releases a pane only if it is still the active generation for its route.
  void endViewingChannel(String siteUrl, int channelId, Object token) {
    final key = _streamKey(siteUrl, channelId);
    if (identical(_activeChannelViews[key], token)) {
      _activeChannelViews.remove(key);
    }
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
    store.put(siteUrl, held.withLastViewedAt(viewedAt));
    if (notify) notifySafely();
  }

  /// A channel to watch rather than to read, so a row redraws itself when its
  /// record changes without anything above it rebuilding.
  Ref<ChatChannel> channelRef(String siteUrl, int channelId) =>
      store.ref<ChatChannel>(siteUrl, channelId);

  Ref<ChatMessage> messageRef(String siteUrl, int messageId) =>
      store.ref<ChatMessage>(siteUrl, messageId);

  ChatStreamState stream(String siteUrl, int channelId) =>
      _streams[_streamKey(siteUrl, channelId)] ?? const ChatStreamState();

  ValueListenable<ChatStreamState> streamListenable(
    String siteUrl,
    int channelId,
  ) {
    final key = _streamKey(siteUrl, channelId);
    return _streamRefs.putIfAbsent(
      key,
      () => FrameSafeValueNotifier(_streams[key] ?? const ChatStreamState()),
    );
  }

  /// Whether [userId] is currently in Discourse's global chat presence.
  bool isOnline(String siteUrl, int userId) =>
      _presence[siteUrl]?.contains(userId) ?? false;

  /// The smallest live surface a message avatar can watch.
  ///
  /// Returning the set, rather than the controller itself, means a presence
  /// event rebuilds visible chat avatars without also rebuilding channel
  /// navigation, composer state or the rest of the shell.
  ValueListenable<Set<int>> onlineUserIdsListenable(String siteUrl) =>
      _presenceRefs.putIfAbsent(
        siteUrl,
        () => FrameSafeValueNotifier(_presence[siteUrl]?.userIds ?? const {}),
      );

  /// Gives chat access to the selected site's already-owned MessageBus.
  ///
  /// [ShellController] remains responsible for the tracker lifetime; this
  /// controller owns only the presence channel registration made through it.
  void attachTracker(String siteUrl, SiteTracker tracker) {
    if (!identical(_presenceTrackers[siteUrl], tracker)) {
      _cancelPresence(siteUrl);
      _cancelLiveChatSubscriptions(siteUrl);
      _cancelSendSubscriptions(siteUrl, forgetTargets: false);
    }
    _presenceTrackers[siteUrl] = tracker;
    _syncPresence(siteUrl);
    _syncNewMessageSubscriptions(siteUrl);
    for (final target in _sendSubscriptionChannels) {
      if (target.siteUrl == siteUrl) {
        _ensureSendSubscription(target.siteUrl, target.channelId);
      }
    }
  }

  void _syncPresence(String siteUrl) {
    if (_presenceSubscriptions.containsKey(siteUrl)) return;
    final tracker = _presenceTrackers[siteUrl];
    final presence = _presence[siteUrl];
    if (tracker == null || presence == null) return;

    try {
      _presenceSubscriptions[siteUrl] = tracker.watchPluginChannel(
        '/presence/chat/online',
        (data) => _applyPresenceMessage(siteUrl, data),
        lastId: presence.lastMessageId,
      );
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        'chat.presence.subscribe',
        severity: DiagnosticSeverity.warning,
      );
      // Presence is decoration. A rejected live channel must not turn a valid
      // channel list into a failed chat sidebar.
    }
  }

  void _replacePresence(String siteUrl, ChatPresence presence) {
    _cancelPresence(siteUrl);
    _presence[siteUrl] = presence;
    _presenceRefs[siteUrl]?.value = presence.userIds;
    _syncPresence(siteUrl);
  }

  void _cancelPresence(String siteUrl) {
    try {
      _presenceSubscriptions.remove(siteUrl)?.cancel();
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        'chat.presence.unsubscribe',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  void _cancelSendSubscriptions(String siteUrl, {bool forgetTargets = true}) {
    final cancelled = <SiteMessageBusSubscription>[];
    _sendSubscriptions.removeWhere((key, subscription) {
      if (!key.startsWith('$siteUrl~')) return false;
      cancelled.add(subscription);
      return true;
    });
    if (forgetTargets) {
      _sendSubscriptionChannels.removeWhere(
        (target) => target.siteUrl == siteUrl,
      );
    }
    for (final subscription in cancelled) {
      try {
        subscription.cancel();
      } catch (error, stackTrace) {
        _report(
          error,
          stackTrace,
          'chat.sendMessage.unsubscribe',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
  }

  void _replaceLiveChatChannels(String siteUrl, ChatChannels channels) {
    _cancelLiveChatSubscriptions(siteUrl);
    _newMessageCursors[siteUrl] = {
      for (final channel in [...channels.public, ...channels.direct])
        if (!channel.membership.muted)
          channel.id: channels.newMessageBusLastIds[channel.id],
    };
    _newChannelCursors[siteUrl] = channels.newChannelBusLastId;
    _userTrackingCursors[siteUrl] = channels.userTrackingBusLastId;
    _newChannelsAwaitingFirstMessage.removeWhere(
      (key) => key.startsWith('$siteUrl~'),
    );
    _syncNewMessageSubscriptions(siteUrl);
  }

  void _syncNewMessageSubscriptions(String siteUrl) {
    final tracker = _presenceTrackers[siteUrl];
    final cursors = _newMessageCursors[siteUrl];
    if (tracker == null || cursors == null) return;

    final currentUserId = _currentUserFor(siteUrl)?.id;
    if (currentUserId != null &&
        _newChannelCursors.containsKey(siteUrl) &&
        !_newChannelSubscriptions.containsKey(siteUrl)) {
      try {
        _newChannelSubscriptions[siteUrl] = tracker.watchPluginChannel(
          '/chat/new-channel',
          (data) => _applyNewChannel(siteUrl, data),
          lastId: _newChannelCursors[siteUrl],
        );
      } catch (error, stackTrace) {
        _report(
          error,
          stackTrace,
          'chat.newChannel.subscribe',
          severity: DiagnosticSeverity.warning,
        );
      }
    }

    if (currentUserId != null &&
        _userTrackingCursors.containsKey(siteUrl) &&
        !_userTrackingSubscriptions.containsKey(siteUrl)) {
      final subscriptions = <SiteMessageBusSubscription>[];
      try {
        final cursor = _userTrackingCursors[siteUrl];
        subscriptions.add(
          tracker.watchPluginChannel(
            '/chat/user-tracking-state/$currentUserId',
            (data) => _applyUserTrackingState(siteUrl, data),
            lastId: cursor,
          ),
        );
        subscriptions.add(
          tracker.watchPluginChannel(
            '/chat/bulk-user-tracking-state/$currentUserId',
            (data) => _applyBulkUserTrackingState(siteUrl, data),
            lastId: cursor,
          ),
        );
        _userTrackingSubscriptions[siteUrl] = subscriptions;
      } catch (error, stackTrace) {
        for (final subscription in subscriptions) {
          try {
            subscription.cancel();
          } catch (_) {
            // The failed registration remains isolated from later channels.
          }
        }
        _report(
          error,
          stackTrace,
          'chat.userTracking.subscribe',
          severity: DiagnosticSeverity.warning,
        );
      }
    }

    for (final entry in cursors.entries) {
      final key = _streamKey(siteUrl, entry.key);
      if (_newMessageSubscriptions.containsKey(key)) continue;
      try {
        _newMessageSubscriptions[key] = tracker.watchPluginChannel(
          '/chat/${entry.key}/new-messages',
          (data) => _applyNewMessage(siteUrl, entry.key, data),
          lastId: entry.value,
        );
      } catch (error, stackTrace) {
        _report(
          error,
          stackTrace,
          'chat.newMessages.subscribe',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
  }

  void _cancelLiveChatSubscriptions(String siteUrl) {
    final cancelled = <SiteMessageBusSubscription>[];
    _newMessageSubscriptions.removeWhere((key, subscription) {
      if (!key.startsWith('$siteUrl~')) return false;
      cancelled.add(subscription);
      return true;
    });
    final newChannel = _newChannelSubscriptions.remove(siteUrl);
    if (newChannel != null) cancelled.add(newChannel);
    cancelled.addAll(_userTrackingSubscriptions.remove(siteUrl) ?? const []);
    for (final subscription in cancelled) {
      try {
        subscription.cancel();
      } catch (error, stackTrace) {
        _report(
          error,
          stackTrace,
          'chat.live.unsubscribe',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
  }

  void _applyNewChannel(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    final payload = data['channel'];
    if (payload is! Map<String, dynamic>) return;

    final incoming = ChatChannel.fromJson(payload, siteUrl);
    if (incoming.id <= 0 ||
        !incoming.membership.following ||
        !incoming.isDirectMessage && !incoming.isCategoryChannel) {
      return;
    }

    final wasListed =
        (_directIds[siteUrl]?.contains(incoming.id) ?? false) ||
        (_publicIds[siteUrl]?.contains(incoming.id) ?? false);
    // The global cursor belongs to the last HTTP snapshot. Replacing a tracker
    // can replay channel-creation events from that point; an already-listed
    // channel is discovery we have applied, not a newer channel snapshot.
    if (wasListed) return;

    store.put(siteUrl, incoming);
    if (_activeChannelViews.containsKey(_streamKey(siteUrl, incoming.id))) {
      _advanceLastViewedAt(siteUrl, incoming.id, notify: false);
    }

    if (incoming.isDirectMessage) {
      final ids = _directIds.putIfAbsent(siteUrl, () => []);
      if (!ids.contains(incoming.id)) ids.add(incoming.id);
    } else if (incoming.isCategoryChannel) {
      final ids = _publicIds.putIfAbsent(siteUrl, () => []);
      if (!ids.contains(incoming.id)) ids.add(incoming.id);
      ids.sort((a, b) {
        final aChannel = channel(siteUrl, a);
        final bChannel = channel(siteUrl, b);
        return (aChannel?.slug ?? aChannel?.title ?? '')
            .toLowerCase()
            .compareTo((bChannel?.slug ?? bChannel?.title ?? '').toLowerCase());
      });
    }

    final cursor = jsonIntOrNull(
      jsonObject(
        jsonObject(payload['meta'])['message_bus_last_ids'],
      )['new_messages'],
    );
    if (!incoming.membership.muted) {
      (_newMessageCursors[siteUrl] ??= {})[incoming.id] = cursor;
      if (incoming.lastMessageId != null) {
        _newChannelsAwaitingFirstMessage.add(_streamKey(siteUrl, incoming.id));
      }
      _syncNewMessageSubscriptions(siteUrl);
    }
    notifySafely();
  }

  void _applyUserTrackingState(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    final channelId = jsonIntOrNull(data['channel_id']);
    if (channelId == null) return;
    _applyTrackingState(siteUrl, channelId, data);
  }

  void _applyBulkUserTrackingState(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    for (final entry in data.entries) {
      final channelId = int.tryParse(entry.key);
      final tracking = entry.value;
      if (channelId != null && tracking is Map<String, dynamic>) {
        _applyTrackingState(siteUrl, channelId, tracking, notify: false);
      }
    }
    notifySafely();
  }

  void _applyTrackingState(
    String siteUrl,
    int channelId,
    Map<String, dynamic> data, {
    bool notify = true,
  }) {
    final held = channel(siteUrl, channelId);
    if (held == null) return;

    // A read is projected locally before its request crosses the network. The
    // unread event which prompted it can still be waiting in MessageBus and
    // must not move that projection backwards when it finally arrives. Newer
    // unread state remains safe: its last-read position is at least the one
    // already held, and the eager /new-messages path has accounted for it too.
    final isChannelState = jsonIntOrNull(data['thread_id']) == null;
    final hasLastRead = data.containsKey('last_read_message_id');
    final incomingLastRead = jsonIntOrNull(data['last_read_message_id']) ?? 0;
    final heldLastRead = held.membership.lastReadMessageId ?? 0;
    if (isChannelState && hasLastRead && incomingLastRead < heldLastRead) {
      return;
    }

    Map<int, DateTime>? threadOverview;
    if (data.containsKey('unread_thread_overview')) {
      threadOverview = {};
      for (final entry in jsonObject(data['unread_thread_overview']).entries) {
        final threadId = int.tryParse(entry.key);
        final createdAt = jsonDate(entry.value);
        if (threadId != null && threadId > 0 && createdAt != null) {
          threadOverview[threadId] = createdAt;
        }
      }
      threadOverview = Map.unmodifiable(threadOverview);
    }

    final updated = held.withTrackingState(
      tracking: ChatTracking(
        unreadCount: jsonInt(data['unread_count']),
        mentionCount: jsonInt(data['mention_count']),
        watchedThreadsUnreadCount: jsonInt(
          data['watched_threads_unread_count'],
        ),
      ),
      lastReadMessageId: isChannelState
          ? jsonIntOrNull(data['last_read_message_id'])
          : null,
      unreadThreadOverview: threadOverview,
    );
    if (updated == held) return;
    store.put(siteUrl, updated);
    if (notify) notifySafely();
  }

  void _applyNewMessage(String siteUrl, int channelId, Object? data) {
    if (data is! Map<String, dynamic>) return;
    if (data['type'] != 'channel' && data['type'] != 'thread') return;
    if (jsonIntOrNull(data['channel_id']) != channelId) return;
    final payload = data['message'];
    if (payload is! Map<String, dynamic>) return;

    final messageId = jsonIntOrNull(payload['id']);
    final payloadChannelId = jsonIntOrNull(payload['chat_channel_id']);
    final createdAt = jsonDate(payload['created_at']);
    if (messageId == null ||
        messageId <= 0 ||
        payloadChannelId != channelId ||
        createdAt == null) {
      return;
    }

    final held = channel(siteUrl, channelId);
    if (held == null) return;
    final key = _streamKey(siteUrl, channelId);
    final awaitingFirst = _newChannelsAwaitingFirstMessage.contains(key);
    final repeatsSnapshot = awaitingFirst && held.lastMessageId == messageId;
    if (!repeatsSnapshot &&
        held.lastMessageId != null &&
        messageId <= held.lastMessageId!) {
      return;
    }
    if (awaitingFirst) _newChannelsAwaitingFirstMessage.remove(key);

    final currentUser = _currentUserFor(siteUrl);
    final author = jsonObject(payload['user']);
    final authorId = jsonIntOrNull(author['id']);
    final authorUsername = jsonText(author['username']);
    final fromSelf = currentUser?.id != null && authorId == currentUser?.id;
    final fromIgnored =
        authorUsername != null &&
        currentUser?.ignoredUsernames.contains(authorUsername) == true;
    var markRead = false;
    var incrementUnread = false;
    if (data['type'] == 'channel') {
      if (fromSelf || fromIgnored) {
        markRead = true;
      } else if (currentUser?.id != null &&
          messageId > (held.membership.lastReadMessageId ?? 0)) {
        incrementUnread = true;
      }
    }
    // A reply normally has type `thread`, but core also publishes a
    // channel-shaped event carrying a thread id when it cannot publish to the
    // thread stream. Both paths update the unread-thread projection.
    final threadId = jsonIntOrNull(data['thread_id']);
    final markThreadUnread =
        threadId != null &&
        currentUser?.id != null &&
        !fromSelf &&
        !fromIgnored;

    var updated = held.withNewMessage(
      messageId,
      createdAt,
      markRead: markRead,
      incrementUnread: incrementUnread,
      threadId: threadId,
      markThreadUnread: markThreadUnread,
      markThreadRead: threadId != null && (fromSelf || fromIgnored),
    );
    if (markThreadUnread && _activeChannelViews.containsKey(key)) {
      final viewedAt = _clock().toUtc();
      final previous = updated.membership.lastViewedAt;
      if (previous == null || viewedAt.isAfter(previous)) {
        updated = updated.withLastViewedAt(viewedAt);
      }
    }

    store.put(siteUrl, updated);

    // The per-channel event is also the live message transport. Keeping only
    // its tracking half leaves an open pane one row behind its own sidebar:
    // the row says unread, but scrolling to the visible bottom can never reach
    // the message that would clear it. A window already at the present can
    // extend contiguously; an anchored window keeps its gap and will obtain the
    // message through forward paging instead.
    final window = stream(siteUrl, channelId);
    if (data['type'] == 'channel' &&
        window.fetchedOnce &&
        window.atPresent &&
        !window.messageIds.contains(messageId)) {
      final canonical = ChatMessage.fromJson(payload, siteUrl);
      store.put(siteUrl, canonical);
      _setStream(
        key,
        window.copyWith(
          messageIds: List.unmodifiable([...window.messageIds, messageId]),
          localMessageIds: _retireCanonicalLocals(siteUrl, window, [canonical]),
        ),
      );
    }
    notifySafely();
  }

  void _applyPresenceMessage(String siteUrl, Object? data) {
    final held = _presence[siteUrl];
    if (held == null) return;
    final updated = held.withMessage(data);
    if (identical(updated, held)) return;
    _presence[siteUrl] = updated;
    _presenceRefs[siteUrl]?.value = updated.userIds;
  }

  void _setStream(String key, ChatStreamState stream) {
    _streams[key] = stream;
    _streamRefs[key]?.value = stream;
  }

  /// Drops optimistic overlays once an ordinary page contains their server id.
  ///
  /// Returning the held list when nothing landed preserves its identity, which
  /// lets the view skip an otherwise unnecessary whole-window projection.
  List<int> _retireCanonicalLocals(
    String siteUrl,
    ChatStreamState stream,
    Iterable<ChatMessage> canonical,
  ) {
    if (stream.localMessageIds.isEmpty) return stream.localMessageIds;
    final arrived = {for (final message in canonical) message.id};
    if (arrived.isEmpty) return stream.localMessageIds;

    List<int>? remaining;
    for (var index = 0; index < stream.localMessageIds.length; index++) {
      final id = stream.localMessageIds[index];
      final local = store.read<ChatMessage>(siteUrl, id);
      if (local?.serverId == null || !arrived.contains(local!.serverId)) {
        remaining?.add(id);
        continue;
      }

      remaining ??= stream.localMessageIds.sublist(0, index);
      store.remove<ChatMessage>(siteUrl, id);
    }
    return remaining == null
        ? stream.localMessageIds
        : List.unmodifiable(remaining);
  }

  /// The messages of one channel, oldest first, as far as they are held.
  List<ChatMessage> messages(String siteUrl, int channelId) {
    final held = stream(siteUrl, channelId);
    return [
      for (final id in [...held.messageIds, ...held.localMessageIds])
        ?store.read<ChatMessage>(siteUrl, id),
    ];
  }

  String? channelsError(String siteUrl) => _errors[_channelsKey(siteUrl)];

  // --- writes ------------------------------------------------------------

  /// Whether a new staged row can be accepted synchronously.
  ///
  /// Network serialization happens below the optimistic boundary, so an
  /// in-flight message never makes the composer busy.
  bool canSendMessage(String siteUrl, int channelId) => !isDisposed;

  /// Stages and sends one message.
  ///
  /// This method does all visible work before its first await: the local row is
  /// in the stream when it returns, which lets the composer clear immediately.
  /// The POST carries the web client's same `staged_id` correlation token and
  /// MessageBus later replaces the raw projection with canonical cooked data.
  /// This workflow issues no newest-page GET at all, awaited or in the
  /// background. Full-window reads remain exclusive to ordinary open/paging.
  ChatSendHandle? sendMessage(
    String siteUrl,
    int channelId,
    OutgoingChatMessage message,
  ) {
    final text = message.raw;
    if (text.trim().isEmpty || isDisposed) return null;
    final key = _streamKey(siteUrl, channelId);

    final createdAt = _clock().toUtc();
    final stagedId =
        'native-${createdAt.microsecondsSinceEpoch}-${_nextStagedSequence++}';
    final user = _currentUserFor(siteUrl);
    final preview = _projectPreview(siteUrl, message);
    final local = ChatMessage.optimistic(
      id: _nextLocalMessageId--,
      channelId: channelId,
      raw: text,
      stagedId: stagedId,
      preview: preview,
      author: ChatMessageAuthor(
        id: user?.id ?? 0,
        username: user?.username ?? '',
        name: user?.name,
        avatarUrl: user?.avatarUrl,
        isStaff: user?.staff ?? false,
      ),
      createdAt: createdAt,
    );
    store.put(siteUrl, local);
    final held = stream(siteUrl, channelId);
    _setStream(
      key,
      held.copyWith(
        localMessageIds: List.unmodifiable([...held.localMessageIds, local.id]),
        clearError: true,
      ),
    );

    final target = (siteUrl: siteUrl, channelId: channelId);
    _sendSubscriptionChannels.add(target);
    _ensureSendSubscription(siteUrl, channelId);

    final settlement = Completer<ChatSendResult>();
    final handle = ChatSendHandle.internal(
      localId: local.id,
      stagedId: stagedId,
      settled: settlement.future,
    );
    final queue = _sendQueues.putIfAbsent(
      key,
      () => _ChatSendQueue(siteUrl: siteUrl, channelId: channelId, key: key),
    );
    queue.pending.add(
      _QueuedChatSend(
        local: local,
        settlement: settlement,
        lease: lifecycle.capture(siteUrl),
      ),
    );
    _scheduleSendQueue(queue);
    return handle;
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

  void _scheduleSendQueue(_ChatSendQueue queue) {
    if (queue.scheduled || queue.cancelled) return;
    queue.scheduled = true;
    scheduleMicrotask(() {
      queue.scheduled = false;
      _pumpSendQueue(queue);
    });
  }

  void _pumpSendQueue(_ChatSendQueue queue) {
    if (queue.active != null || queue.cancelled) return;
    if (!identical(_sendQueues[queue.key], queue) || isDisposed) {
      _cancelSendQueue(queue);
      return;
    }
    if (queue.pending.isEmpty) {
      _sendQueues.remove(queue.key);
      return;
    }

    final item = queue.pending.removeFirst();
    queue.active = item;
    unawaited(
      _guardSendQueued(queue, item).whenComplete(() {
        if (identical(queue.active, item)) queue.active = null;
        _scheduleSendQueue(queue);
      }),
    );
  }

  Future<void> _guardSendQueued(
    _ChatSendQueue queue,
    _QueuedChatSend item,
  ) async {
    try {
      await _sendQueued(queue, item);
    } catch (error, stackTrace) {
      item.complete(
        _ownsSend(queue, item)
            ? ChatSendResult.failed
            : ChatSendResult.cancelled,
      );
      try {
        _report(error, stackTrace, 'chat.sendMessage');
      } catch (_) {
        // Settlement and queue progress are stronger guarantees than
        // diagnostics: neither may be lost if the diagnostic sink is broken.
      }
    }
  }

  bool _ownsSend(_ChatSendQueue queue, _QueuedChatSend item) =>
      !queue.cancelled &&
      identical(_sendQueues[queue.key], queue) &&
      identical(queue.active, item);

  Future<void> _sendQueued(_ChatSendQueue queue, _QueuedChatSend item) async {
    final siteUrl = queue.siteUrl;
    final channelId = queue.channelId;
    final local = item.local;
    bool ownsRequest() => _ownsSend(queue, item);

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_requestIsCurrent(item.lease, ownsRequest)) {
        item.complete(ChatSendResult.cancelled);
        return;
      }
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final clientId = await credentials.clientId();
      if (!_requestIsCurrent(item.lease, ownsRequest)) {
        item.complete(ChatSendResult.cancelled);
        return;
      }
      final serverId = await api.sendChatMessage(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: channelId,
        message: local.optimisticRaw!,
        stagedId: local.stagedId,
        clientCreatedAt: local.createdAt,
      );
      if (!_requestIsCurrent(item.lease, ownsRequest)) {
        item.complete(ChatSendResult.cancelled);
        return;
      }
      item.lease.commit(() {
        final localId = _updateOutgoing(
          siteUrl,
          channelId,
          local.stagedId!,
          (held) => held.withSendState(
            delivery: ChatMessageDelivery.sent,
            serverId: serverId,
          ),
        );
        if (serverId != null &&
            localId != null &&
            stream(siteUrl, channelId).messageIds.contains(serverId)) {
          _removeLocalMessage(siteUrl, channelId, localId);
        }
      });
      item.complete(ChatSendResult.sent);
    } catch (error, stackTrace) {
      if (_requestIsCurrent(item.lease, ownsRequest)) {
        final failure = error is WriteException
            ? error
            : const WriteException(WriteFailure.unreachable);
        var canonicalAlreadyArrived = false;
        item.lease.commit(
          () => _updateOutgoing(siteUrl, channelId, local.stagedId!, (held) {
            canonicalAlreadyArrived = held.serverId != null;
            return canonicalAlreadyArrived
                ? held
                : held.withSendState(
                    delivery: ChatMessageDelivery.failed,
                    error: failure.message,
                    deliveryUncertain:
                        failure.failure == WriteFailure.unreachable,
                  );
          }),
        );
        item.lease.commit(
          () => _releaseSendSubscriptionIfSettled(siteUrl, channelId),
        );
        _report(error, stackTrace, 'chat.sendMessage');
        item.complete(
          canonicalAlreadyArrived ? ChatSendResult.sent : ChatSendResult.failed,
        );
      } else {
        item.complete(ChatSendResult.cancelled);
      }
    }
  }

  void _cancelSendQueue(_ChatSendQueue queue) {
    if (queue.cancelled) return;
    queue.cancelled = true;
    queue.active?.complete(ChatSendResult.cancelled);
    while (queue.pending.isNotEmpty) {
      queue.pending.removeFirst().complete(ChatSendResult.cancelled);
    }
  }

  void _cancelSendQueues({String? siteUrl}) {
    final queues = _sendQueues.values
        .where((queue) => siteUrl == null || queue.siteUrl == siteUrl)
        .toList(growable: false);
    for (final queue in queues) {
      _sendQueues.remove(queue.key);
      _cancelSendQueue(queue);
    }
  }

  int? _updateOutgoing(
    String siteUrl,
    int channelId,
    String stagedId,
    ChatMessage Function(ChatMessage held) update,
  ) {
    final window = stream(siteUrl, channelId);
    for (final id in window.localMessageIds) {
      final held = store.read<ChatMessage>(siteUrl, id);
      if (held?.stagedId != stagedId) continue;
      store.put(siteUrl, update(held!));
      return id;
    }
    return null;
  }

  void _removeLocalMessage(String siteUrl, int channelId, int localId) {
    final key = _streamKey(siteUrl, channelId);
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
    store.remove<ChatMessage>(siteUrl, localId);
    _releaseSendSubscriptionIfSettled(siteUrl, channelId);
  }

  void _releaseSendSubscriptionIfSettled(String siteUrl, int channelId) {
    final window = stream(siteUrl, channelId);
    for (final id in window.localMessageIds) {
      final local = store.read<ChatMessage>(siteUrl, id);
      if (local == null) continue;
      if (local.delivery == ChatMessageDelivery.sending ||
          local.deliveryUncertain ||
          local.delivery == ChatMessageDelivery.sent &&
              !local.canonicalReceived) {
        return;
      }
    }

    final key = _streamKey(siteUrl, channelId);
    _sendSubscriptionChannels.remove((siteUrl: siteUrl, channelId: channelId));
    final subscription = _sendSubscriptions.remove(key);
    if (subscription == null) return;
    try {
      subscription.cancel();
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        'chat.sendMessage.unsubscribe',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  void _ensureSendSubscription(String siteUrl, int channelId) {
    final key = _streamKey(siteUrl, channelId);
    if (_sendSubscriptions.containsKey(key)) return;
    final tracker = _presenceTrackers[siteUrl];
    if (tracker == null) return;

    try {
      _sendSubscriptions[key] = tracker.watchPluginChannel(
        '/chat/$channelId',
        (data) => _applySendMessage(siteUrl, channelId, data),
      );
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        'chat.sendMessage.subscribe',
        severity: DiagnosticSeverity.warning,
      );
      // The POST response still marks the staged row sent. A later ordinary
      // channel fetch supplies the canonical cooked record.
    }
  }

  void _applySendMessage(String siteUrl, int channelId, Object? data) {
    if (data is! Map<String, dynamic>) return;
    if (data['type'] != 'sent' || data['staged_id'] is! String) return;
    final stagedId = data['staged_id'] as String;
    final window = stream(siteUrl, channelId);
    for (final id in window.localMessageIds) {
      final local = store.read<ChatMessage>(siteUrl, id);
      if (local?.stagedId != stagedId) continue;

      // Do not deserialize every event in every channel ever sent to. This
      // listener exists solely to reconcile one of our still-local rows.
      final payload = data['chat_message'];
      if (payload is! Map<String, dynamic>) return;
      final canonical = ChatMessage.fromJson(payload, siteUrl);
      if (canonical.id <= 0 || canonical.channelId != channelId) return;
      final currentUserId = _currentUserFor(siteUrl)?.id;
      if (currentUserId != null && canonical.author.id != currentUserId) return;

      store.put(siteUrl, canonical);
      if (window.messageIds.contains(canonical.id)) {
        _removeLocalMessage(siteUrl, channelId, id);
      } else {
        store.put(siteUrl, local!.withCanonical(canonical));
        _releaseSendSubscriptionIfSettled(siteUrl, channelId);
      }
      return;
    }
  }

  /// Fetches the channels this account follows on [siteUrl].
  ///
  /// Once per site rather than on every open, unlike the reactor lists: this
  /// decides what is in the sidebar, and a sidebar that re-fetched whenever a
  /// widget rebuilt would flicker. Keeping it fresh afterwards is what step 2's
  /// live tracking is for.
  ///
  /// Failure is silent and bounded. There is nothing on screen to put an error
  /// on — no chat section exists yet to hold one — and a site that will not
  /// answer is simply a site drawn without chat, which is the same argument
  /// `SiteConfig` makes for having no error state.
  Future<void> loadChannels(String siteUrl, {bool force = false}) {
    if (isDisposed) return Future.value();
    final key = _channelsKey(siteUrl);
    if (!force && _publicIds.containsKey(siteUrl)) return Future.value();
    if ((_attempts[key] ?? 0) >= maxChannelAttempts) return Future.value();

    // Unlike a caller that merely wants the sidebar to redraw eventually, the
    // shortcut needs to wait for the same in-flight answer before choosing its
    // destination. Share the task as well as the HTTP request.
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

    final lease = lifecycle.capture(siteUrl);
    bool ownsRequest() => identical(_channelRuns[key], run);
    _attempts[key] = (_attempts[key] ?? 0) + 1;

    try {
      // Inside the guard, not before it: an unsigned macOS build's keychain can
      // throw rather than answer, and reading it outside would leave this key
      // stranded in `_loading` for the life of the app.
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = await credentials.clientId();
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final channels = await api.chatChannels(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        store.putAll(siteUrl, channels.public);
        store.putAll(siteUrl, channels.direct);
        for (final channel in [...channels.public, ...channels.direct]) {
          if (_activeChannelViews.containsKey(
            _streamKey(siteUrl, channel.id),
          )) {
            _advanceLastViewedAt(siteUrl, channel.id, notify: false);
          }
        }
        _publicIds[siteUrl] = [for (final c in channels.public) c.id];
        _directIds[siteUrl] = [for (final c in channels.direct) c.id];
        _replaceLiveChatChannels(siteUrl, channels);
        _replacePresence(siteUrl, channels.presence);
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

  /// Puts a channel on screen where the reader left off.
  ///
  /// Anchored rather than at the live edge, which is what Discourse's own
  /// client does — `fetchMessages({fetch_from_last_read: true})` — and the
  /// reason matters more here than it does there, because [markRead] is
  /// watching: landing on the newest message means the newest message is on
  /// screen, and a reader three hundred messages behind would have all three
  /// hundred credited to them in the half second before they could scroll.
  /// Anchoring is what makes reading a thing the reader does rather than a
  /// thing that happens to them.
  ///
  /// A reader with no last-read is answered with the newest page, by the
  /// server, for free — the target resolves to nil and the query takes its
  /// no-target branch. So a channel opened for the first time still starts at
  /// the present, without this having to ask a different question.
  ///
  /// A normal open refreshes an old window, but reuses one attempted in the last
  /// [minimumWindowRefreshInterval]. Site and tab activation can remount this
  /// view several times in one navigation; those mounts do not make the answer
  /// meaningfully fresher. Explicit reloads and post-mutation reconciliations
  /// pass [force], while paging remains independent. Whatever was fetched last
  /// time stays on screen while an allowed answer is on its way.
  ///
  /// The answer **replaces** the stream rather than merging into it. Contiguity
  /// is what [loadOlder] and [loadNewer] depend on, and merging a window fetched
  /// around one message into a window around another would leave a hole in the
  /// middle that nothing could ever fill.
  Future<void> openChannel(
    String siteUrl,
    int channelId, {
    bool force = false,
  }) {
    if (isDisposed || channelId <= 0) return Future.value();
    _lastOpenedChannelIds[siteUrl] = channelId;
    final key = _streamKey(siteUrl, channelId);
    if (!force && _windowAttemptedRecently(key)) return Future.value();
    return DiagnosticsSink.runOperation(
      'chat.loadWindow',
      () => _fetchWindow(siteUrl, channelId, fromLastRead: true),
    );
  }

  bool _windowAttemptedRecently(String key) {
    final attemptedAt = _windowAttemptedAt[key];
    return attemptedAt != null &&
        _clock().difference(attemptedAt) < minimumWindowRefreshInterval;
  }

  /// Puts the newest page on screen, wherever the reader was.
  ///
  /// The way out of an anchored stream, and the same two-step Discourse's
  /// `scrollToLatestMessage` makes: when there is nothing in front of what is
  /// held, the present is already on screen and this is a scroll rather than a
  /// fetch — which is the view's half of it, so this simply does nothing.
  Future<void> showLatest(String siteUrl, int channelId) {
    if (isDisposed || channelId <= 0) return Future.value();
    if (stream(siteUrl, channelId).atPresent) return Future.value();
    return DiagnosticsSink.runOperation(
      'chat.loadLatest',
      () => _fetchWindow(siteUrl, channelId, fromLastRead: false),
    );
  }

  Future<void> _fetchWindow(
    String siteUrl,
    int channelId, {
    required bool fromLastRead,
  }) async {
    final key = _streamKey(siteUrl, channelId);
    if (!_loading.add(key)) return;
    _windowAttemptedAt[key] = _clock();

    final lease = lifecycle.capture(siteUrl);
    final generation = Object();
    _streamGenerations[key] = generation;
    bool ownsRequest() => identical(_streamGenerations[key], generation);
    _pageRequests.remove(_olderKey(siteUrl, channelId));
    _pageRequests.remove(_newerKey(siteUrl, channelId));
    final held = stream(siteUrl, channelId);
    _setStream(
      key,
      held.copyWith(
        // Only a stream with nothing in it gets to show a loading placeholder
        // in place of content; a re-open refreshes underneath what is already
        // there.
        loading: held.messageIds.isEmpty,
        loadingOlder: false,
        loadingNewer: false,
        clearError: true,
      ),
    );

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = await credentials.clientId();
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        fromLastRead: fromLastRead,
        pageSize: pageSize,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation)) return;
        store.putAll(siteUrl, page.messages);
        final current = _streams[key] ?? held;
        _setStream(
          key,
          ChatStreamState(
            messageIds: _sortedIds(siteUrl, page.messages),
            localMessageIds: _retireCanonicalLocals(
              siteUrl,
              current,
              page.messages,
            ),
            canLoadMorePast: page.canLoadMorePast,
            canLoadMoreFuture: page.canLoadMoreFuture,
            fetchedOnce: true,
            fetches: held.fetches + 1,
            lastReadOnOpen: channel(
              siteUrl,
              channelId,
            )?.membership.lastReadMessageId,
          ),
        );
        _releaseSendSubscriptionIfSettled(siteUrl, channelId);
      });
    } catch (error, stackTrace) {
      if (!_requestIsCurrent(lease, ownsRequest)) {
        return;
      }
      _report(error, stackTrace, 'chat.loadWindow', degraded: false);
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation)) return;
        final current = _streams[key] ?? const ChatStreamState();
        _setStream(
          key,
          current.copyWith(
            fetchedOnce: true,
            error: current.messageIds.isEmpty && current.localMessageIds.isEmpty
                ? 'Could not load this channel.'
                : null,
          ),
        );
      });
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

  /// Prepends the page immediately before the oldest message held.
  ///
  /// Does nothing when the site has said there is no more, when a page is
  /// already on its way, or before there is an oldest message to page from —
  /// each of which the view can and does ask for anyway, because the cheapest
  /// place to answer "no" is here.
  Future<void> loadOlder(String siteUrl, int channelId) async {
    if (isDisposed || channelId <= 0) return;
    final key = _streamKey(siteUrl, channelId);
    final held = stream(siteUrl, channelId);
    final before = held.oldestId;
    if (!held.canLoadMorePast || before == null) return;

    final guard = _olderKey(siteUrl, channelId);
    if (_loading.contains(key) || _pageRequests.containsKey(guard)) return;

    final lease = lifecycle.capture(siteUrl);
    final generation = _streamGenerations.putIfAbsent(key, Object.new);
    final request = Object();
    _pageRequests[guard] = request;
    bool ownsRequest() =>
        identical(_streamGenerations[key], generation) &&
        identical(_pageRequests[guard], request);
    _setStream(key, held.copyWith(loadingOlder: true));

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = await credentials.clientId();
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
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
        store.putAll(siteUrl, page.messages);
        final current = _streams[key] ?? const ChatStreamState();
        final merged = _sortedIds(
          siteUrl,
          page.messages,
          held: current.messageIds,
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
        _releaseSendSubscriptionIfSettled(siteUrl, channelId);
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
      // History that would not load is not worth an error state: what is on
      // screen is still true, and scrolling up again asks again.
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

  /// Appends the page immediately after the newest message held.
  ///
  /// [loadOlder] read forwards, and every argument it makes applies mirrored —
  /// including the "brought nothing new" override, which is safe for the same
  /// reason: `direction=future` answers with ids strictly above the newest held
  /// one, so anything it returns is new by construction.
  ///
  /// Only ever does anything on a stream [openChannel] anchored behind the
  /// present. On a stream fetched at the live edge `canLoadMoreFuture` is
  /// false, and this is the cheapest place to say so.
  Future<void> loadNewer(String siteUrl, int channelId) async {
    if (isDisposed || channelId <= 0) return;
    final key = _streamKey(siteUrl, channelId);
    final held = stream(siteUrl, channelId);
    final after = held.newestId;
    if (!held.canLoadMoreFuture || after == null) return;

    final guard = _newerKey(siteUrl, channelId);
    if (_loading.contains(key) || _pageRequests.containsKey(guard)) return;

    final lease = lifecycle.capture(siteUrl);
    final generation = _streamGenerations.putIfAbsent(key, Object.new);
    final request = Object();
    _pageRequests[guard] = request;
    bool ownsRequest() =>
        identical(_streamGenerations[key], generation) &&
        identical(_pageRequests[guard], request);
    _setStream(key, held.copyWith(loadingNewer: true));

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = await credentials.clientId();
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
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
        store.putAll(siteUrl, page.messages);
        final current = _streams[key] ?? const ChatStreamState();
        final merged = _sortedIds(
          siteUrl,
          page.messages,
          held: current.messageIds,
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
            canLoadMoreFuture:
                merged.length > current.messageIds.length &&
                page.canLoadMoreFuture,
            fetchedOnce: true,
          ),
        );
        _releaseSendSubscriptionIfSettled(siteUrl, channelId);
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
      // Same as [loadOlder]: what is on screen is still true, and scrolling
      // down again asks again.
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

  /// Credits the reader with everything in a channel up to [messageId].
  ///
  /// Called from the view as the reader scrolls, debounced there — the same
  /// division Discourse draws, where the component watches the viewport and
  /// `chatApi.markChannelAsRead` is the thing it calls. What lives here is
  /// every rule about *whether* the write happens.
  ///
  /// Optimistic, and deliberately not undone when the write fails. There is
  /// nothing to tell the reader — this is not an action they took — and the
  /// site is the one keeping score: the next fetch of the channel list brings
  /// its answer, which corrects anything this got wrong. Putting a badge back
  /// under a reader who has visibly read the messages would be the worse lie.
  Future<void> markRead(String siteUrl, int channelId, int messageId) {
    if (isDisposed) return Future.value();
    final held = channel(siteUrl, channelId);
    if (held == null) return Future.value();
    final lease = lifecycle.capture(siteUrl);
    final window = stream(siteUrl, channelId);

    // Optimistic rows are an outgoing overlay, not part of the contiguous
    // server window. In particular a first-ever local id is negative and must
    // never become a site's `last_read_message_id`.
    if (messageId <= 0 || window.localMessageIds.contains(messageId)) {
      return Future.value();
    }

    // Only a followed channel has a membership row to move. The site is blunt
    // about the rest — `find_for_user(following: true)` misses, and the answer
    // is a 404 — and this app only ever draws followed channels anyway.
    if (!held.membership.following) return Future.value();

    // Never backwards, which is both the site's rule and the reader's: paging
    // into the past must not undo what they have already seen. This also
    // de-duplicates the common second viewport tick for the same message.
    final lastRead = held.membership.lastReadMessageId;
    if (lastRead != null && lastRead >= messageId) return Future.value();

    // Both halves are load-bearing since the stream can be anchored behind the
    // present: the reader is caught up only if this is the last message held
    // *and* there is nothing in front of it. Discourse asks its loader the same
    // two questions — `!canLoadMoreFuture && firstMessage.id === last.id`.
    final caughtUp =
        window.atPresent &&
        window.newestId == messageId &&
        (held.lastMessageId == null || held.lastMessageId! <= messageId);

    // Before credential storage, not after: the await below is a gap two scroll
    // ticks can both arrive in, and the guard above is only a guard once the
    // answer it reads has been written.
    final viewedAt = _clock().toUtc();
    store.update<ChatChannel>(siteUrl, channelId, (current) {
      var updated = current.withLastRead(messageId, caughtUp: caughtUp);
      final previous = updated.membership.lastViewedAt;
      if (previous == null || viewedAt.isAfter(previous)) {
        updated = updated.withLastViewedAt(viewedAt);
      }
      return updated;
    });
    notifySafely();

    return _queueReadReceipt(
      siteUrl: siteUrl,
      channelId: channelId,
      messageId: messageId,
      lease: lease,
    );
  }

  Future<void> _queueReadReceipt({
    required String siteUrl,
    required int channelId,
    required int messageId,
    required SiteLease lease,
  }) {
    final key = _streamKey(siteUrl, channelId);
    // Only one write per channel runs at once. While it does, every viewport
    // tick supersedes the previous queued position: sending an intermediate
    // read marker has no value once the reader is already farther ahead.
    _queuedReadReceipts[key] = (
      siteUrl: siteUrl,
      channelId: channelId,
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
      // Forgetting a site removes this run synchronously. Without checking
      // before the dequeue, its next loop could steal a receipt queued by a
      // new account session using the same site and channel key.
      if (!identical(_readReceiptRuns[key], run)) return;
      final receipt = _queuedReadReceipts.remove(key);
      if (receipt == null) {
        // Cleared in the same synchronous turn that observed an empty queue,
        // so a new caller cannot attach work to a task that has already ended.
        // Identity keeps an invalidated old session from clearing a new run.
        if (identical(_readReceiptRuns[key], run)) {
          _readReceiptRuns.remove(key);
          final _ = _readReceiptTasks.remove(key);
        }
        return;
      }
      bool ownsRequest() => identical(_readReceiptRuns[key], run);
      try {
        final apiKey = await credentials.apiKeyFor(receipt.siteUrl);
        if (!_requestIsCurrent(receipt.lease, ownsRequest)) continue;
        // A channel on screen belongs to a connected site, so this is the
        // unsigned-macOS-keychain case rather than a reader without a key. The
        // guess stands; nothing else can be done with it.
        if (apiKey == null) continue;

        final clientId = await credentials.clientId();
        if (!_requestIsCurrent(receipt.lease, ownsRequest)) continue;
        await api.markChatChannelRead(
          siteUrl: receipt.siteUrl,
          apiKey: apiKey,
          channelId: receipt.channelId,
          messageId: receipt.messageId,
          clientId: clientId,
        );
      } catch (error, stackTrace) {
        if (_requestIsCurrent(receipt.lease, ownsRequest)) {
          _report(
            error,
            stackTrace,
            'chat.markRead',
            severity: DiagnosticSeverity.warning,
          );
        }
        // There is nobody to tell, and nothing to put back. A newer queued
        // position must still be attempted after this one fails.
      }
    }
  }

  /// Forgets a disconnected site.
  ///
  /// More than `ReactionsController.forget` drops, because more than the
  /// questions belong to this class: the two channel lists and every stream are
  /// orderings, and no record holds those. The channels and the messages
  /// themselves are the [Store]'s to forget.
  void forget(String siteUrl) {
    _cancelSendQueues(siteUrl: siteUrl);
    _cancelPresence(siteUrl);
    _cancelSendSubscriptions(siteUrl);
    _cancelLiveChatSubscriptions(siteUrl);
    _presenceTrackers.remove(siteUrl);
    _presence.remove(siteUrl);
    _newMessageCursors.remove(siteUrl);
    _newChannelCursors.remove(siteUrl);
    _userTrackingCursors.remove(siteUrl);
    _newChannelsAwaitingFirstMessage.removeWhere(
      (key) => key.startsWith('$siteUrl~'),
    );
    _activeChannelViews.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    final presenceRef = _presenceRefs.remove(siteUrl);
    if (presenceRef != null) presenceRef.value = const {};
    _loading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _channelRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _channelRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _errors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _attempts.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _streams.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _streamGenerations.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _windowAttemptedAt.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _pageRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _queuedReadReceipts.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _readReceiptTasks.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _readReceiptRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    final forgottenRefs = <FrameSafeValueNotifier<ChatStreamState>>[];
    _streamRefs.removeWhere((key, ref) {
      if (!key.startsWith('$siteUrl~')) return false;
      forgottenRefs.add(ref);
      return true;
    });
    // Detach before notifying. A listener can synchronously look up a stream,
    // and that new session must receive a new ref rather than putting the old
    // account's notifier back into this map. The detached ref is not disposed:
    // a widget may still be listening during the frame that removes it.
    for (final ref in forgottenRefs) {
      ref.value = const ChatStreamState();
    }
    _publicIds.remove(siteUrl);
    _directIds.remove(siteUrl);
    _lastOpenedChannelIds.remove(siteUrl);
    notifySafely();
  }

  /// Union by id, ordered by `(createdAt, id)`.
  ///
  /// Deduping by id and not by identity, because the same message arrives twice
  /// whenever a page overlaps a boundary; the store has already merged the two
  /// copies into one record, and the list must not name it twice or the row is
  /// built twice.
  ///
  /// The tiebreak is load-bearing rather than tidy. `created_at` is serialised
  /// as iso8601, so two messages written in the same second carry equal dates
  /// on the wire; Dart's sort is unstable, so a date-only comparator lets those
  /// two swap places every time a page is merged and the list visibly
  /// reshuffles under the reader. The merge also has to be idempotent — folding
  /// a page that overlaps one already held must give the identical list — and a
  /// comparator that can return zero cannot promise that. `(created_at, id)` is
  /// the site's own `ORDER BY`.
  List<int> _sortedIds(
    String siteUrl,
    Iterable<ChatMessage> arrived, {
    List<int> held = const [],
  }) {
    final dates = <int, DateTime>{
      for (final id in held)
        if (store.read<ChatMessage>(siteUrl, id) case final message?)
          id: message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      for (final message in arrived)
        message.id: message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    };

    return dates.keys.toList()..sort((a, b) {
      final byDate = dates[a]!.compareTo(dates[b]!);
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  }

  @override
  void dispose() {
    _cancelSendQueues();
    for (final siteUrl in _presenceSubscriptions.keys.toList()) {
      _cancelPresence(siteUrl);
    }
    _presenceTrackers.clear();
    _presence.clear();
    for (final subscription in _newMessageSubscriptions.values) {
      try {
        subscription.cancel();
      } catch (_) {
        // Disposal continues through every independent subscription.
      }
    }
    _newMessageSubscriptions.clear();
    _newMessageCursors.clear();
    for (final subscription in _newChannelSubscriptions.values) {
      try {
        subscription.cancel();
      } catch (_) {
        // Disposal continues through every independent subscription.
      }
    }
    _newChannelSubscriptions.clear();
    _newChannelCursors.clear();
    for (final subscriptions in _userTrackingSubscriptions.values) {
      for (final subscription in subscriptions) {
        try {
          subscription.cancel();
        } catch (_) {
          // Disposal continues through every independent subscription.
        }
      }
    }
    _userTrackingSubscriptions.clear();
    _userTrackingCursors.clear();
    _newChannelsAwaitingFirstMessage.clear();
    _activeChannelViews.clear();
    for (final ref in _presenceRefs.values) {
      ref.dispose();
    }
    _presenceRefs.clear();
    _windowAttemptedAt.clear();
    _queuedReadReceipts.clear();
    _readReceiptTasks.clear();
    _readReceiptRuns.clear();
    for (final subscription in _sendSubscriptions.values) {
      try {
        subscription.cancel();
      } catch (_) {
        // The tracker is being torn down at the same boundary. Best effort is
        // enough, and disposal must continue through every remaining ref.
      }
    }
    _sendSubscriptions.clear();
    _sendSubscriptionChannels.clear();
    for (final ref in _streamRefs.values) {
      ref.dispose();
    }
    _streamRefs.clear();
    super.dispose();
  }
}

final class _ChatSendQueue {
  _ChatSendQueue({
    required this.siteUrl,
    required this.channelId,
    required this.key,
  });

  final String siteUrl;
  final int channelId;
  final String key;
  final ListQueue<_QueuedChatSend> pending = ListQueue<_QueuedChatSend>();
  _QueuedChatSend? active;
  bool scheduled = false;
  bool cancelled = false;
}

final class _QueuedChatSend {
  _QueuedChatSend({
    required this.local,
    required this.settlement,
    required this.lease,
  });

  final ChatMessage local;
  final Completer<ChatSendResult> settlement;
  final SiteLease lease;

  void complete(ChatSendResult result) {
    if (!settlement.isCompleted) settlement.complete(result);
  }
}
