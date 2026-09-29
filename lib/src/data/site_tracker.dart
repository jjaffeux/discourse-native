import 'dart:async';
import 'dart:math';

import 'package:discourse_native/l10n/strings.dart';
import 'package:http/http.dart' as http;
import 'package:message_bus_client/message_bus_client.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../foundation/bounded_lru_cache.dart';
import '../models/incoming_topics.dart';
import '../plugin_api/live_channels.dart';
import '../plugin_api/plugin_manifest.dart';
import 'discourse_api.dart';
import 'http_transport.dart';

typedef SiteTrackerFactory =
    SiteTracker Function({
      required String siteUrl,
      required void Function() onIncomingTopics,
      required void Function(Object? data) onNotifications,
      required void Function(Object? data) onReviewableCounts,
      bool Function(Object? data)? admitIncoming,
      int? userId,
      String? apiKey,
      String? clientId,
      bool Function()? shouldLongPoll,
      Map<String, int?> initialLastIds,
    });

abstract interface class SiteMessageBusSession {
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  });

  void start();

  void stop();

  void pollNow();

  Future<void> close();
}

abstract interface class SiteMessageBusErrorSource {
  Stream<Object> get errors;
}

abstract interface class SiteMessageBusSubscription {
  /// The channel position this subscription has read to: the last message it
  /// received, or the head its first poll reported when it started from new
  /// messages only. Null before that first poll and once cancelled.
  int? get lastId;

  void cancel();
}

class SiteTracker {
  /// Registers the core channels without polling. The owner adds every other
  /// channel it needs and then calls [start], so the first request already
  /// carries all of them: a channel added after a poll is sent makes that poll
  /// stale, and the client aborts it and polls again.
  SiteTracker({
    required this.siteUrl,
    required this.onIncomingTopics,
    required this.onNotifications,
    required this.onReviewableCounts,
    this.admitIncoming,
    this.userId,
    String? apiKey,
    String? clientId,
    bool Function()? shouldLongPoll,
    Map<String, int?> initialLastIds = const {},
    http.Client? httpClient,
    SiteMessageBusSession? messageBus,
  }) : _signedIn = apiKey != null,
       _initialLastIds = Map.unmodifiable(initialLastIds) {
    final Uri baseUrl;
    try {
      baseUrl = requireSafeHttpUrl(Uri.parse(siteUrl));
    } on UnsafeHttpTransportException {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    final transport = httpClient == null
        ? SafeHttpClient.create()
        : SafeHttpClient.borrowed(httpClient);
    final SiteMessageBusSession bus;
    try {
      bus =
          messageBus ??
          _createMessageBus(
            baseUrl: baseUrl,
            headers: _headers(apiKey, clientId),
            shouldLongPoll: shouldLongPoll,
            httpClient: transport,
          );
    } catch (_) {
      transport.close();
      rethrow;
    }
    _http = transport;
    _bus = bus;
    try {
      _listenForErrors();
      _subscribe();
    } catch (_) {
      dispose().ignore();
      rethrow;
    }
  }

  final String siteUrl;

  final void Function() onIncomingTopics;

  final void Function(Object? data) onNotifications;

  final void Function(Object? data) onReviewableCounts;

  /// Decides whether a `/latest` or `/new` message may count toward
  /// [incoming]. Core drops an arrival the reader's list will not return,
  /// such as a topic in a muted category, and only the owner knows the
  /// reader's preferences. Absent, every arrival counts.
  final bool Function(Object? data)? admitIncoming;

  final int? userId;

  final bool _signedIn;
  final Map<String, int?> _initialLastIds;
  late final SafeHttpClient _http;
  late final SiteMessageBusSession _bus;
  StreamSubscription<Object>? _errorSubscription;

  bool _polling = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  final IncomingTopics incoming = IncomingTopics();
  void Function(Object? data)? _onTopicTrackingState;

  void _listenForErrors() {
    final bus = _bus;
    if (bus is! SiteMessageBusErrorSource) return;
    _errorSubscription = (bus as SiteMessageBusErrorSource).errors.listen(
      _onMessageBusError,
    );
  }

  void _onMessageBusError(Object error) {
    if (_disposed) return;
    final (
      Object safeError,
      StackTrace stackTrace,
      String operation,
    ) = switch (error) {
      MessageBusHttpException(:final statusCode, :final retryAfter) => (
        StateError(
          'Message bus HTTP $statusCode'
          '${retryAfter == null ? '' : appL10n.retryAfter((retryAfter).toString())}',
        ),
        StackTrace.current,
        'messageBus.poll',
      ),
      MessageBusTransportException(:final cause, :final stackTrace) => (
        cause,
        stackTrace ?? StackTrace.current,
        'messageBus.poll',
      ),
      MessageBusTimeoutException(:final timeout) => (
        TimeoutException(appL10n.messageBusPollTimedOut, timeout),
        StackTrace.current,
        'messageBus.poll',
      ),
      MessageBusProtocolException(:final message) => (
        FormatException(message),
        StackTrace.current,
        'messageBus.poll',
      ),
      MessageBusCallbackException(
        :final channel,
        :final cause,
        :final stackTrace,
      ) =>
        (
          // Preserve the original exception type so the central privacy
          // boundary can strip fields such as FormatException.source. Never
          // interpolate a callback exception into a wrapper string: it may
          // retain the message-bus payload it was parsing.
          cause,
          stackTrace ?? StackTrace.current,
          'messageBus.callback $channel',
        ),
      _ => (error, StackTrace.current, 'messageBus.poll'),
    };
    DiagnosticsSink.current.reportError(
      safeError,
      stackTrace,
      operation: operation,
      source: 'message_bus',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  void _subscribe() {
    // `/latest` is public, while `/new` is meaningful only to a signed-in user.
    // Authenticated startup supplies core's preloaded positions; anonymous and
    // older sites retain MessageBus's new-messages default.
    _subscribeChannel('/latest', (data, _) => _onTopicMessage(data));
    if (_signedIn) {
      _subscribeChannel('/new', (data, _) => _onTopicMessage(data));
    }

    // Discourse additionally scopes this named channel with `user_ids: [id]`;
    // the channel name itself is not the account isolation boundary.
    if ((_signedIn, userId) case (true, final userId?)) {
      _subscribeChannel(
        '/notification/$userId',
        (data, _) => _onNotification(data),
      );
      _subscribeChannel(
        '/reviewable_counts/$userId',
        (data, _) => _onReviewableCounts(data),
      );
    }
  }

  SiteMessageBusSubscription _subscribeChannel(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) => _bus.subscribe(
    channel,
    onMessage,
    lastId: lastId ?? _initialLastIds[channel],
  );

  /// How many left topic channels keep their read position. Each visible
  /// topic has a core channel and a few plugin ones, so this covers the last
  /// few dozen topics a reader moved between.
  static const int retainedTopicPositionCapacity = 128;

  final Map<String, SiteMessageBusSubscription> _topicSubscriptions = {};

  /// Where each recently left topic channel was read to. MessageBus positions
  /// belong to this session, so they live and die with the tracker.
  final BoundedLruCache<String, int> _topicPositions = BoundedLruCache(
    retainedTopicPositionCapacity,
  );
  void Function(String channel, Object? data)? _onWatchedTopicMessage;
  int? _watchedTopic;

  int? get watchedTopic => _watchedTopic;

  /// Makes [channels] the watched topic channels. A channel already watched
  /// keeps its subscription and position and only adopts [onMessage]; a
  /// channel that was watched before in this session resumes where it was
  /// left, or from its [lastIds] snapshot when that is newer. Re-subscribing
  /// a kept channel from its snapshot would replay what it already delivered,
  /// and starting a left one from new messages only would drop what was
  /// published while it was away.
  void watchTopic(
    int topicId,
    List<String> channels,
    void Function(String channel, Object? data) onMessage, {
    Map<String, int?> lastIds = const {},
  }) {
    _ensureActive();
    _watchedTopic = topicId;
    _onWatchedTopicMessage = onMessage;
    final wanted = channels.toSet();
    for (final channel in [..._topicSubscriptions.keys]) {
      if (!wanted.contains(channel)) _leaveTopicChannel(channel);
    }
    try {
      for (final channel in wanted) {
        if (_topicSubscriptions.containsKey(channel)) continue;
        _topicSubscriptions[channel] = _subscribeTopicChannel(
          channel,
          _newerPosition(lastIds[channel], _topicPositions.read(channel)),
        );
      }
    } catch (_) {
      unwatchTopic();
      rethrow;
    }
  }

  void unwatchTopic() {
    _watchedTopic = null;
    _onWatchedTopicMessage = null;
    for (final channel in [..._topicSubscriptions.keys]) {
      _leaveTopicChannel(channel);
    }
  }

  SiteMessageBusSubscription _subscribeTopicChannel(
    String channel,
    int? lastId,
  ) {
    final gate = _MessageBusCallbackGate();
    final subscription = _bus.subscribe(channel, (data, _) {
      // A kept channel reports to whichever watch last asked for it.
      if (_disposed || !gate.isOpen) return;
      _onWatchedTopicMessage?.call(channel, data);
    }, lastId: lastId);
    return _LifecycleBoundMessageBusSubscription(subscription, gate);
  }

  void _leaveTopicChannel(String channel) {
    // Removed before cancelling: a cancellation can re-enter disposal.
    final subscription = _topicSubscriptions.remove(channel);
    if (subscription == null) return;
    // A cancelled handle no longer reports its position.
    final position = subscription.lastId;
    if (position != null) _topicPositions.put(channel, position);
    try {
      subscription.cancel();
    } catch (error, stackTrace) {
      if (!_disposed) {
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'messageBus.unsubscribeTopic',
          source: 'message_bus',
          severity: DiagnosticSeverity.warning,
          handled: true,
          degraded: true,
        );
      }
      // The bus close is the final cleanup boundary. One broken channel
      // handle must not retain every later subscription or prevent close.
    }
  }

  static int? _newerPosition(int? snapshot, int? retained) {
    if (snapshot == null) return retained;
    if (retained == null) return snapshot;
    return max(snapshot, retained);
  }

  void watchTopicTrackingState(
    int accountId,
    void Function(Object? data) onMessage, {
    Map<String, int?> lastIds = const {},
  }) {
    _ensureActive();
    if (!_signedIn || _onTopicTrackingState != null) return;
    _onTopicTrackingState = onMessage;
    for (final channel in [
      '/unread',
      '/unread/$accountId',
      '/delete',
      '/recover',
      '/destroy',
    ]) {
      _subscribeChannel(
        channel,
        channel == '/delete'
            ? (data, _) => _onDeleteMessage(data)
            : (data, _) => _emitTopicTrackingState(data),
        lastId: lastIds[channel],
      );
    }
  }

  SiteMessageBusSubscription watchPluginChannel(
    String channel,
    void Function(Object? data) onMessage, {
    int? lastId,
  }) => watchPluginChannelWithPosition(
    channel,
    (data, _) => onMessage(data),
    lastId: lastId,
  );

  SiteMessageBusSubscription watchPluginChannelWithPosition(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    _ensureActive();
    final gate = _MessageBusCallbackGate();
    final subscription = _subscribeChannel(channel, (data, messageId) {
      // A transport can already have copied this callback into its delivery
      // queue when the channel is cancelled or the site is forgotten. Keep
      // the tracker as the lifecycle boundary instead of requiring every
      // plugin to independently defend against a retained message.
      if (!_disposed && gate.isOpen) onMessage(data, messageId);
    }, lastId: lastId);
    return _LifecycleBoundMessageBusSubscription(subscription, gate);
  }

  void _onTopicMessage(Object? data) {
    if (_disposed) return;
    _emitTopicTrackingState(data);
    if (_disposed || !(admitIncoming?.call(data) ?? true)) return;
    if (incoming.notify(data)) onIncomingTopics();
  }

  void _onDeleteMessage(Object? data) {
    if (_disposed) return;
    _emitTopicTrackingState(data);
    if (_disposed) return;
    if (incoming.notifyDeleted(data)) onIncomingTopics();
  }

  void _emitTopicTrackingState(Object? data) {
    if (!_disposed) _onTopicTrackingState?.call(data);
  }

  void _onNotification(Object? data) {
    if (!_disposed) onNotifications(data);
  }

  void _onReviewableCounts(Object? data) {
    if (!_disposed) onReviewableCounts(data);
  }

  void start() {
    _ensureActive();
    if (_polling) return;
    _bus.start();
    _polling = true;
  }

  void stop() {
    if (_disposed || !_polling) return;
    _bus.stop();
    _polling = false;
  }

  void pollNow() {
    if (!_disposed && _polling) _bus.pollNow();
  }

  Future<void> dispose() {
    final pending = _disposeFuture;
    if (pending != null) return pending;

    final completion = Completer<void>();
    _disposeFuture = completion.future;
    _disposed = true;
    _polling = false;
    unwatchTopic();
    _topicPositions.clear();
    incoming.resetAll();
    completion.complete(_close());
    return completion.future;
  }

  Future<void> _close() async {
    // Start closing the bus before the first asynchronous suspension, so a
    // started client cannot send a poll it had already scheduled. Test
    // sessions likewise promise that [close] is invoked synchronously,
    // including when construction fails part-way through subscribing.
    try {
      // Both futures need error handlers immediately. Awaiting cancellation
      // first leaves an early bus-close failure unhandled while it is pending.
      await Future.wait<void>([
        _cancelErrorSubscription(),
        Future<void>.sync(_bus.close),
      ], eagerError: true);
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'messageBus.close',
        source: 'message_bus',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      rethrow;
    } finally {
      _http.close();
    }
  }

  Future<void> _cancelErrorSubscription() async {
    try {
      await _errorSubscription?.cancel();
    } catch (_) {
      // The bus close remains the authoritative cleanup boundary.
    } finally {
      _errorSubscription = null;
    }
  }

  void _ensureActive() {
    if (_disposed) throw StateError('This SiteTracker has been disposed.');
  }

  static Map<String, String> _headers(String? apiKey, String? clientId) => {
    'User-Agent': DiscourseApi.userAgent,
    'User-Api-Key': ?apiKey,
    if (clientId case final id? when id.isNotEmpty) 'User-Api-Client-Id': id,
  };
}

extension SiteTrackerPluginLiveChannels on SiteTracker {
  PluginLiveChannelHandle pluginLiveChannels(
    Iterable<PluginLiveChannelScope> scopes,
  ) => _ScopedPluginLiveChannelHandle(this, List.unmodifiable(scopes));
}

const _coreLiveChannelScopes = <String>[
  '/latest',
  '/new',
  '/notification',
  '/reviewable_counts',
  '/user-status',
  '/do-not-disturb',
  '/topic',
];

bool _isWithinChannelScope(String channel, String scope) =>
    channel == scope || channel.startsWith('$scope/');

bool _isCoreLiveChannel(String channel) => _coreLiveChannelScopes.any(
  (scope) => _isWithinChannelScope(channel, scope),
);

final class _ScopedPluginLiveChannelHandle implements PluginLiveChannelHandle {
  const _ScopedPluginLiveChannelHandle(this._tracker, this._scopes);

  final SiteTracker _tracker;
  final List<PluginLiveChannelScope> _scopes;

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    if (_isCoreLiveChannel(channel) ||
        !_scopes.any((scope) => scope.allows(channel))) {
      throw ArgumentError.value(
        channel,
        'channel',
        'The channel is outside this plugin live-channel scope.',
      );
    }
    return _PluginLiveChannelSubscription(
      _tracker.watchPluginChannelWithPosition(
        channel,
        onMessage,
        lastId: lastId,
      ),
    );
  }
}

final class _PluginLiveChannelSubscription
    implements PluginLiveChannelSubscription {
  const _PluginLiveChannelSubscription(this._subscription);

  final SiteMessageBusSubscription _subscription;

  @override
  void cancel() => _subscription.cancel();
}

SiteMessageBusSession _createMessageBus({
  required Uri baseUrl,
  required Map<String, String> headers,
  required http.Client httpClient,
  bool Function()? shouldLongPoll,
}) => _MessageBusSession(
  MessageBusClient(
    baseUrl: baseUrl,
    config: MessageBusConfig(headers: headers),
    shouldLongPoll: shouldLongPoll,
    httpClient: httpClient,
  ),
);

final class _MessageBusSession
    implements SiteMessageBusSession, SiteMessageBusErrorSource {
  _MessageBusSession(this._client) {
    // `subscribe` starts a client that was never started or stopped. Stopping
    // it first leaves [SiteTracker.start] as the only way polling begins.
    _client.stop();
  }

  final MessageBusClient _client;

  @override
  Stream<Object> get errors => _client.errors;

  @override
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) => _MessageBusSubscription(
    _client.subscribe(
      channel,
      (data, globalId, messageId) => onMessage(data, messageId),
      lastId: lastId ?? MessageBusPosition.newMessages,
    ),
  );

  @override
  void start() => _client.start();

  @override
  void stop() => _client.stop();

  @override
  void pollNow() => _client.pollNow();

  @override
  Future<void> close() => _client.close();
}

final class _MessageBusSubscription implements SiteMessageBusSubscription {
  _MessageBusSubscription(this._subscription);

  final MessageBusSubscription _subscription;

  /// The client reports `-1` both before its baseline and once cancelled.
  @override
  int? get lastId {
    final position = _subscription.lastId;
    return position < 0 ? null : position;
  }

  @override
  void cancel() => _subscription.cancel();
}

final class _MessageBusCallbackGate {
  bool isOpen = true;

  void close() => isOpen = false;
}

final class _LifecycleBoundMessageBusSubscription
    implements SiteMessageBusSubscription {
  _LifecycleBoundMessageBusSubscription(this._subscription, this._gate);

  final SiteMessageBusSubscription _subscription;
  final _MessageBusCallbackGate _gate;
  bool _cancelled = false;

  @override
  int? get lastId => _subscription.lastId;

  @override
  void cancel() {
    _gate.close();
    if (_cancelled) return;
    _subscription.cancel();
    _cancelled = true;
  }
}
