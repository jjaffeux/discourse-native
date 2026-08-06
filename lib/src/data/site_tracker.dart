import 'package:message_bus_client/message_bus_client.dart';

import '../models/incoming_topics.dart';
import '../models/notification_totals.dart';
import 'discourse_api.dart';

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
  }) : _signedIn = apiKey != null,
       _bus = MessageBusClient(
         baseUrl: Uri.parse(siteUrl),
         config: MessageBusConfig(headers: _headers(apiKey, clientId)),
         shouldLongPoll: shouldLongPoll,
       ) {
    _subscribe();
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
  final MessageBusClient _bus;

  final IncomingTopics incoming = IncomingTopics();

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
    if (userId case final userId?) {
      _bus.subscribe('/notification/$userId', _onNotification);
      _bus.subscribe('/reviewable_counts/$userId', _onReviewableCounts);
    }
  }

  void _onTopicMessage(Object? data, int globalId, int messageId) {
    if (incoming.notify(data)) onIncomingTopics();
  }

  void _onNotification(Object? data, int globalId, int messageId) =>
      onNotifications(data);

  void _onReviewableCounts(Object? data, int globalId, int messageId) =>
      onReviewableCounts(data);

  /// Resumes polling for this site.
  ///
  /// Cursors survive [stop], so a site returned to is asked for what it
  /// published while it was off screen rather than starting over.
  void start() => _bus.start();

  /// Stops polling, for a site that is no longer the one being read.
  ///
  /// Only one long poll is held open at a time — the same as the web, where
  /// there is only ever one site.
  void stop() => _bus.stop();

  /// Polls at once instead of waiting out a backoff. For an app coming back to
  /// the foreground, where the connection has usually been dead for a while.
  void pollNow() => _bus.pollNow();

  Future<void> dispose() => _bus.close();

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
