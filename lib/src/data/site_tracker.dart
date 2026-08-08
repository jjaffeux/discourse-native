import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:message_bus_client/message_bus_client.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../models/incoming_topics.dart';
import '../models/notification_totals.dart';
import 'discourse_api.dart';
import 'http_transport.dart';

/// How a shell gets its trackers.
///
/// Injectable for the same reason [DiscourseApi] takes a client: a tracker
/// holds a connection open, and a test that builds a shell should not be
/// dialling out to do it. `SiteTracker.new` is the real one.
typedef SiteTrackerFactory =
    SiteTracker Function({
      required String siteUrl,
      required void Function() onIncomingTopics,
      required void Function(Object? data) onNotifications,
      required void Function(Object? data) onReviewableCounts,
      int? userId,
      String? apiKey,
      String? clientId,
      bool Function()? shouldLongPoll,
    });

/// The package-neutral message-bus surface owned by one [SiteTracker].
abstract interface class SiteMessageBusSession {
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data) onMessage, {
    int? lastId,
  });

  void start();

  void stop();

  void pollNow();

  Future<void> close();
}

/// Optional error stream implemented by the production message-bus adapter.
/// Kept separate so small test fakes and alternate transports need not grow an
/// error controller merely to satisfy [SiteMessageBusSession].
abstract interface class SiteMessageBusErrorSource {
  Stream<Object> get errors;
}

/// A cancellable channel registration from [SiteMessageBusSession].
abstract interface class SiteMessageBusSubscription {
  void cancel();
}

/// One site's live connection: everything it pushes at us without being asked.
///
/// One of these per site, and only the site on screen is polling — see [start]
/// and [stop]. Every channel rides the same poll, which is the reason this is
/// one object rather than one per concern: message_bus multiplexes, so a second
/// client would mean a second connection held open for the same site.
///
/// The channels and their starting positions mirror core's
/// `TopicTrackingState.establishChannels` and its
/// `subscribe-user-notifications` initializer.
class SiteTracker {
  SiteTracker({
    required this.siteUrl,
    required this.onIncomingTopics,
    required this.onNotifications,
    required this.onReviewableCounts,
    this.userId,
    String? apiKey,
    String? clientId,
    bool Function()? shouldLongPoll,
    http.Client? httpClient,
    SiteMessageBusSession? messageBus,
  }) : _signedIn = apiKey != null {
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
      start();
    } catch (_) {
      dispose().ignore();
      rethrow;
    }
  }

  final String siteUrl;

  /// Called when the incoming-topic count changed and the list should redraw.
  /// Never called for the messages that change nothing, which is most of them.
  final void Function() onIncomingTopics;

  /// One `/notification/{id}` payload, to be folded onto the totals the shell
  /// holds — see [NotificationTotals.withNotification].
  final void Function(Object? data) onNotifications;

  /// One `/reviewable_counts/{id}` payload. Only staff ever get one.
  final void Function(Object? data) onReviewableCounts;

  /// The account the counter channels are named after, or null when it is not
  /// known — signed out, or a site connected before this app stored it.
  final int? userId;

  final bool _signedIn;
  late final SafeHttpClient _http;
  late final SiteMessageBusSession _bus;
  StreamSubscription<Object>? _errorSubscription;

  bool _polling = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  final IncomingTopics incoming = IncomingTopics();

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
          '${retryAfter == null ? '' : ' (retry after $retryAfter)'}',
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
        TimeoutException('Message bus poll timed out', timeout),
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
    // Everything starts at [MessageBusPosition.newMessages], core's
    // `messageBusDefaultNewMessageId`: what matters is what has changed since
    // the lists and counters on screen were fetched, and anything older is
    // already in them. Core does better for notifications — it subscribes from
    // the `notification_channel_position` its page preloaded — which is a
    // window this app does not have, since nothing here is server-rendered.
    //
    // Topic messages carry the id of a topic and a `message_type` saying what
    // happened to it; see `TopicTrackingState.publish_new` and
    // `publish_latest` server side for the payloads.
    //
    // `/latest` is public, so it works signed out. `/new` is not subscribed to
    // without a key — core gates it on there being a current user, and a
    // reader with no account has no "new".
    _bus.subscribe('/latest', _onTopicMessage);
    if (_signedIn) _bus.subscribe('/new', _onTopicMessage);

    // The counts behind the rail badge, the user menu tabs and the dot on the
    // avatar. Named after the user because that is how Discourse scopes them,
    // and published with `user_ids: [id]` on top of that — so a channel name
    // is not what keeps one account's counts away from another's.
    if ((_signedIn, userId) case (true, final userId?)) {
      _bus.subscribe('/notification/$userId', _onNotification);
      _bus.subscribe('/reviewable_counts/$userId', _onReviewableCounts);
    }
  }

  /// Channels only worth listening to while one topic is open.
  ///
  /// Site-wide channels are subscribed to once, in the constructor, and never
  /// change. These come and go with what is on screen — a topic's own updates
  /// are of no use once the reader has left it, and a site with a thousand
  /// topics cannot be subscribed to all of them.
  final List<SiteMessageBusSubscription> _topicSubscriptions = [];
  int? _watchedTopic;
  int _topicWatchRevision = 0;

  int? get watchedTopic => _watchedTopic;

  /// Listens to [channels] for as long as [topicId] is the topic being read.
  ///
  /// Only one topic at a time: opening another cancels the last, because only
  /// one is ever on screen. Asking for the topic already being watched does
  /// nothing, so a rebuild does not churn the subscriptions.
  void watchTopic(
    int topicId,
    List<String> channels,
    void Function(String channel, Object? data) onMessage,
  ) {
    _ensureActive();
    if (_watchedTopic == topicId) return;
    unwatchTopic();
    _watchedTopic = topicId;
    final revision = _topicWatchRevision;
    try {
      for (final channel in channels.toSet()) {
        _topicSubscriptions.add(
          _bus.subscribe(channel, (data) {
            if (_disposed || revision != _topicWatchRevision) return;
            onMessage(channel, data);
          }),
        );
      }
    } catch (_) {
      unwatchTopic();
      rethrow;
    }
  }

  void unwatchTopic() {
    _topicWatchRevision += 1;
    final subscriptions = List.of(_topicSubscriptions);
    _topicSubscriptions.clear();
    _watchedTopic = null;
    for (final subscription in subscriptions) {
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
  }

  /// A cancellable plugin-owned channel, optionally starting at the snapshot
  /// cursor returned by the HTTP endpoint that preceded it.
  SiteMessageBusSubscription watchPluginChannel(
    String channel,
    void Function(Object? data) onMessage, {
    int? lastId,
  }) {
    _ensureActive();
    return _bus.subscribe(channel, onMessage, lastId: lastId);
  }

  void _onTopicMessage(Object? data) {
    if (_disposed) return;
    if (incoming.notify(data)) onIncomingTopics();
  }

  void _onNotification(Object? data) {
    if (!_disposed) onNotifications(data);
  }

  void _onReviewableCounts(Object? data) {
    if (!_disposed) onReviewableCounts(data);
  }

  /// Resumes polling for this site.
  ///
  /// Cursors survive [stop], so a site returned to is asked for what it
  /// published while it was off screen rather than starting over.
  void start() {
    _ensureActive();
    if (_polling) return;
    _bus.start();
    _polling = true;
  }

  /// Stops polling, for a site that is no longer the one being read.
  ///
  /// Only one long poll is held open at a time — the same as the web, where
  /// there is only ever one site.
  void stop() {
    if (_disposed || !_polling) return;
    _bus.stop();
    _polling = false;
  }

  /// Polls at once instead of waiting out a backoff. For an app coming back to
  /// the foreground, where the connection has usually been dead for a while.
  void pollNow() {
    if (!_disposed && _polling) _bus.pollNow();
  }

  Future<void> dispose() {
    final pending = _disposeFuture;
    if (pending != null) return pending;

    _disposed = true;
    _polling = false;
    unwatchTopic();
    incoming.resetAll();
    final closing = _close();
    _disposeFuture = closing;
    return closing;
  }

  Future<void> _close() async {
    // Start closing the bus before the first asynchronous suspension. This is
    // important when construction fails part-way through subscribing: a real
    // message-bus client may already have scheduled its next poll, and test
    // sessions likewise promise that [close] is invoked synchronously.
    Future<void>? cancellingErrors;
    try {
      cancellingErrors = _errorSubscription?.cancel();
    } catch (_) {
      // The bus close below remains the authoritative cleanup boundary.
    }

    final Future<void> closingBus;
    try {
      closingBus = _bus.close();
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
      _http.close();
      Error.throwWithStackTrace(error, stackTrace);
    }

    try {
      try {
        await cancellingErrors;
      } catch (_) {
        // The bus close below remains the authoritative cleanup boundary.
      }
      await closingBus;
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

  void _ensureActive() {
    if (_disposed) throw StateError('This SiteTracker has been disposed.');
  }

  /// What the poll carries beyond what the client sets for itself.
  ///
  /// Deliberately not [DiscourseApi.authHeaders], which is right for the API
  /// and wrong here twice over: it sends `Dont-Chunk`, which would switch off
  /// the streaming this transport exists for, and a `Content-Type` the bus
  /// client owns — the poll body is form-encoded, not JSON.
  ///
  /// The key is what makes the poll authenticated, and Discourse's message_bus
  /// route is inside the `notifications` scope this app already asks for
  /// (`UserApiKeyScope::SCOPES`), so no new consent is involved.
  static Map<String, String> _headers(String? apiKey, String? clientId) => {
    'User-Agent': DiscourseApi.userAgent,
    'User-Api-Key': ?apiKey,
    'User-Api-Client-Id': ?clientId,
  };
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
    _client.stop();
  }

  final MessageBusClient _client;

  @override
  Stream<Object> get errors => _client.errors;

  @override
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data) onMessage, {
    int? lastId,
  }) => _MessageBusSubscription(
    _client.subscribe(
      channel,
      (data, globalId, messageId) => onMessage(data),
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

  @override
  void cancel() => _subscription.cancel();
}
