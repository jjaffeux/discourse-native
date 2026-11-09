import 'dart:async';

import '../data/site_lifecycle.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../models/json.dart';
import '../models/live_refresh_id.dart';
import '../models/post.dart';
import '../plugin_api/plugin_registry.dart';
import 'topic_data_owner.dart';
import 'topic_tracking_directory.dart';

typedef TopicReaderEvent = ({
  String siteUrl,
  Object account,
  int topicId,
  Object? data,
});

typedef _CoreInvalidation = ({
  bool stream,
  int? post,
  bool deletion,
  ({int id, int? postNumber, String? username})? created,
});

/// Applies what arrives on the visible topics' message-bus channels to the
/// account that opened the watch.
///
/// The reader event is delivered synchronously and every plugin hook can
/// re-enter the shell, so any step may retire that account while one message
/// is being routed. Ownership is read again after each step that can do so.
final class TopicChannelRouter {
  const TopicChannelRouter({
    required this._trackerFor,
    required this._tracking,
    required this._observeTopicMessage,
    required this._topics,
    required this._store,
    required this._lifecycle,
    required this._plugins,
    required this._publishReaderEvent,
    required this._isDisposed,
  });

  final SiteTracker? Function(String siteUrl) _trackerFor;
  final TopicTrackingDirectory _tracking;
  final void Function(String siteUrl, int topicId, Object? data, SiteLease)
  _observeTopicMessage;
  final TopicDataOwner _topics;
  final Store _store;
  final SiteLifecycle _lifecycle;
  final PluginRegistry _plugins;
  final void Function(TopicReaderEvent event) _publishReaderEvent;
  final bool Function() _isDisposed;

  /// Subscribes [tracker] to the channels of each topic in [slugsByTopic].
  void watch(
    String siteUrl,
    SiteTracker tracker,
    Map<int, String> slugsByTopic,
  ) {
    final channelsByTopic = {
      for (final topicId in slugsByTopic.keys)
        topicId: ['/topic/$topicId', ..._plugins.topicChannels(topicId)],
    };
    final lease = _lifecycle.capture(siteUrl);
    final tracking = _tracking.capture(siteUrl, lease: lease);
    if (tracking == null) return;
    bool ownsTopic() =>
        !_isDisposed() &&
        tracking.isCurrent &&
        identical(_trackerFor(siteUrl), tracker);
    tracker.watchTopic(
      slugsByTopic.keys.first,
      channelsByTopic.values.expand((channels) => channels).toSet().toList(),
      (channel, data) {
        if (!ownsTopic()) {
          return;
        }
        for (final entry in channelsByTopic.entries) {
          if (!ownsTopic()) return;
          if (!entry.value.contains(channel)) continue;
          final topicId = entry.key;
          final coreChannel = '/topic/$topicId';
          if (channel == coreChannel) {
            _publishReaderEvent((
              siteUrl: siteUrl,
              account: lease.session,
              topicId: topicId,
              data: data,
            ));
            _observeTopicMessage(siteUrl, topicId, data, lease);
            if (!ownsTopic()) return;
            _applyStats(siteUrl, topicId, data, lease);
            if (!ownsTopic()) return;
          }
          final core = channel == coreChannel
              ? _coreInvalidation(siteUrl, data)
              : _noCoreInvalidation;
          if ((core.stream && !_topics.forSite(siteUrl).usesReader(topicId)) ||
              _plugins.staleTopic(topicId, channel, data)) {
            unawaited(
              _topics
                  .forSite(siteUrl)
                  .refresh(topicId, slug: slugsByTopic[topicId] ?? ''),
            );
          } else if (core.created case final created?
              when !_topics.forSite(siteUrl).usesReader(topicId)) {
            _topics
                .forSite(siteUrl)
                .acceptCreatedPost(
                  topicId,
                  created.id,
                  slug: slugsByTopic[topicId] ?? '',
                  postNumber: created.postNumber,
                  username: created.username,
                );
          }
          final stale = {
            ..._plugins.stalePosts(channel, data),
            ..._plugins.staleHeldPosts(
              topicId,
              channel,
              data,
              _heldPosts(siteUrl, topicId),
            ),
          };
          if (stale.isNotEmpty) {
            _topics.forSite(siteUrl).invalidatePosts(topicId, stale);
          }
          if (core.post case final id?) {
            _topics.forSite(siteUrl).invalidatePosts(topicId, {
              id,
            }, deletion: core.deletion);
          }
        }
      },
      // Each visible conversation resumes from its own HTTP snapshot cursor.
      lastIds: {
        for (final topicId in slugsByTopic.keys)
          '/topic/$topicId': _store
              .read<TopicDetail>(siteUrl, topicId)
              ?.messageBusLastId,
      },
    );
  }

  Iterable<Post> _heldPosts(String siteUrl, int topicId) sync* {
    final stream = _store.read<TopicDetail>(siteUrl, topicId)?.stream;
    for (final id in stream ?? const <int>[]) {
      if (_store.read<Post>(siteUrl, id) case final post?) yield post;
    }
  }

  /// `Post#publish_change_to_clients!` types, each naming one post by `id`.
  static const _corePostMessageTypes = {
    'revised',
    'rebaked',
    'acted',
    'liked',
    'unliked',
    'deleted',
    'destroyed',
    'recovered',
  };

  static const _CoreInvalidation _noCoreInvalidation = (
    stream: false,
    post: null,
    deletion: false,
    created: null,
  );

  static const _CoreInvalidation _streamInvalidation = (
    stream: true,
    post: null,
    deletion: false,
    created: null,
  );

  /// Whether a core `/topic/{id}` message changes the stream, adds one post to
  /// it, or changes only the one post it names. A named post is re-read only
  /// while held, so an edit, like or deletion reaches a reader who is looking
  /// at it, including one whose cached topic is replayed from
  /// `messageBusLastId`. `deletion` marks the messages after which a re-read
  /// that omits the post means it is gone.
  _CoreInvalidation _coreInvalidation(String siteUrl, Object? data) {
    if (data is! Map) return _noCoreInvalidation;
    final type = data['type'];
    // As on the web client, a reload replaces the message's per-post handling.
    // An inbox move names no post, and only a topic read carries its state.
    if (type == 'archived' ||
        type == 'move_to_inbox' ||
        data['reload_topic'] == true) {
      return _streamInvalidation;
    }
    if (type == 'created') {
      final id = liveRefreshId(data['id']);
      if (id == null) return _streamInvalidation;
      return (
        stream: false,
        post: null,
        deletion: false,
        created: (
          id: id,
          postNumber: jsonIntOrNull(data['post_number']),
          username: jsonText(data['username']),
        ),
      );
    }
    final postId = _corePostMessageTypes.contains(type)
        ? liveRefreshId(data['id'])
        : null;
    if (postId == null) return _noCoreInvalidation;
    // A reader who could not see the deleted post no longer holds it, and its
    // recovery has to put it back at its place in the stream.
    if (type == 'recovered' && _store.read<Post>(siteUrl, postId) == null) {
      return _streamInvalidation;
    }
    return (
      stream: false,
      post: postId,
      deletion: type == 'deleted' || type == 'destroyed',
      created: null,
    );
  }

  void _applyStats(String siteUrl, int topicId, Object? data, SiteLease lease) {
    if (!lease.isCurrent || _isDisposed()) return;
    if (data is! Map || data['type'] != 'stats') return;
    int? total(Object? value) => value is int && value >= 0 ? value : null;
    _topics
        .forLease(siteUrl, lease)
        ?.acceptTotals(
          topicId,
          likeCount: total(data['like_count']),
          postsCount: total(data['posts_count']),
        );
  }
}
