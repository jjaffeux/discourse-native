import 'package:flutter/foundation.dart';

import 'json.dart';

/// What a notification is about.
///
/// The numbers are Discourse's own `Notification.types`, which are written into
/// the database rather than derived, so they are stable: new kinds are appended
/// and plugins claim their own ranges. Anything unrecognised arrives as
/// [unknown] instead of being dropped — a row we cannot phrase is still a row,
/// and it still points at the topic it came from.
///
/// [wireName] is the name that goes with the number, which is also how
/// Discourse names the icon for each kind (`notification.replied`), so the two
/// are kept together here rather than in a second table.
enum NotificationKind {
  mentioned(1, 'mentioned'),
  replied(2, 'replied'),
  quoted(3, 'quoted'),
  edited(4, 'edited'),
  liked(5, 'liked'),
  privateMessage(6, 'private_message'),
  invitedToPrivateMessage(7, 'invited_to_private_message'),
  inviteeAccepted(8, 'invitee_accepted'),
  posted(9, 'posted'),
  movedPost(10, 'moved_post'),
  linked(11, 'linked'),
  grantedBadge(12, 'granted_badge'),
  invitedToTopic(13, 'invited_to_topic'),
  custom(14, 'custom'),
  groupMentioned(15, 'group_mentioned'),
  groupMessageSummary(16, 'group_message_summary'),
  watchingFirstPost(17, 'watching_first_post'),
  topicReminder(18, 'topic_reminder'),
  likedConsolidated(19, 'liked_consolidated'),
  postApproved(20, 'post_approved'),
  membershipRequestAccepted(22, 'membership_request_accepted'),
  membershipRequestConsolidated(23, 'membership_request_consolidated'),
  bookmarkReminder(24, 'bookmark_reminder'),
  reaction(25, 'reaction'),
  votesReleased(26, 'votes_released'),
  chatMention(29, 'chat_mention'),
  chatMessage(30, 'chat_message'),
  chatInvitation(31, 'chat_invitation'),
  chatQuoted(33, 'chat_quoted'),
  assigned(34, 'assigned'),
  watchingCategoryOrTag(36, 'watching_category_or_tag'),
  newFeatures(37, 'new_features'),
  adminProblems(38, 'admin_problems'),
  linkedConsolidated(39, 'linked_consolidated'),
  chatWatchedThread(40, 'chat_watched_thread'),
  followingCreatedTopic(801, 'following_created_topic'),
  followingReplied(802, 'following_replied'),

  /// A kind this app has not been taught, from a plugin or a newer Discourse.
  unknown(-1, 'unknown');

  const NotificationKind(this.id, this.wireName);

  /// Discourse's number for this kind.
  final int id;

  /// Discourse's name for it, in the snake case its payloads and icon names
  /// are written in.
  final String wireName;

  static final Map<int, NotificationKind> _byId = {
    for (final kind in values) kind.id: kind,
  };

  static NotificationKind fromId(int id) => _byId[id] ?? unknown;
}

/// The notification kinds Discourse groups into the user menu's Replies tab.
///
/// Keep the order in sync with core's `CORE_TOP_TABS`: the names are sent to
/// `/notifications` as one `filter_by_types` value.
const userMenuReplyNotificationKinds = <NotificationKind>[
  NotificationKind.mentioned,
  NotificationKind.groupMentioned,
  NotificationKind.posted,
  NotificationKind.quoted,
  NotificationKind.replied,
];

/// One row of the notifications tab.
///
/// Flattened out of the envelope Discourse sends: the interesting parts of a
/// notification live in a free-form `data` object whose keys depend on the
/// kind, and reading them at the edge keeps the widgets from having to know
/// which kind puts the group name where.
@immutable
class DiscourseNotification {
  const DiscourseNotification({
    required this.id,
    required this.kind,
    this.read = false,
    this.createdAt,
    this.topicId,
    this.postNumber,
    this.slug = '',
    this.title = '',
    this.actor,
    this.count = 0,
    this.badgeName,
    this.groupName,
    this.channelTitle,
    this.path,
  });

  factory DiscourseNotification.fromJson(Map<String, dynamic> json) {
    final data = jsonObject(json['data']);
    final kind = NotificationKind.fromId(jsonInt(json['notification_type']));
    final topicId = json['topic_id'] == null ? null : jsonInt(json['topic_id']);
    final postNumber = json['post_number'] == null
        ? null
        : jsonInt(json['post_number']);
    final slug = jsonString(json['slug']);

    return DiscourseNotification(
      id: jsonInt(json['id']),
      kind: kind,
      read: json['read'] == true,
      createdAt: jsonDate(json['created_at']),
      topicId: topicId,
      postNumber: postNumber,
      slug: slug,
      // `data.topic_title` already is plain, which is why it is handed first.
      title: jsonTitle(data['topic_title'], json['fancy_title']),
      path: _path(
        kind,
        data,
        topicId: topicId,
        slug: slug,
        postNumber: postNumber,
      ),
      // `display_username` is who acted, and is set for every kind that has
      // an actor; the consolidated kinds carry `username` instead.
      actor: jsonText(
        data['display_username'] ??
            data['username'] ??
            data['original_username'],
      ),
      // Consolidated kinds count what they folded together; a group summary
      // counts the inbox it is summarising.
      count: jsonInt(data['count'] ?? data['inbox_count']),
      badgeName: jsonText(data['badge_name']),
      groupName: jsonText(data['group_name']),
      channelTitle: jsonText(data['chat_channel_title']),
    );
  }

  /// Where clicking it leads, following Discourse's own `linkHref` for each
  /// kind, so a row goes where the same row goes on the web.
  ///
  /// Resolved here rather than by whoever opens it because every kind builds
  /// its link out of different keys of its own payload, which is exactly the
  /// per-kind knowledge the rest of the app should not have to carry.
  ///
  /// The routes that mean "the signed-in user's own page" are written as
  /// `/my/...`, which Discourse redirects to whoever is signed in: the payload
  /// does not say who that is, and a browser following the link may be signed
  /// in as somebody else anyway.
  static String? _path(
    NotificationKind kind,
    Map<String, dynamic> data, {
    int? topicId,
    String? slug,
    int? postNumber,
  }) {
    if (_ownPath(kind, data) case final path?) return path;
    if (_topicPath(topicId, slug, postNumber) case final path?) return path;

    // What is left is what Discourse falls back to for a notification with no
    // topic: the bookmarked thing itself, or the group inbox it arrived in.
    if (data['bookmarkable_url'] case final String url when url.isNotEmpty) {
      return url;
    }
    if (data['group_id'] != null) {
      final username = jsonText(data['username']);
      final group = jsonText(data['group_name']);
      if (username != null && group != null) {
        // The group inbox lives under `/messages/group/…` — the shape
        // `groupMessageSummary` builds above, not the shorter one a first
        // reading of the route might guess.
        return '/u/$username/messages/group/$group';
      }
    }
    return null;
  }

  /// The kinds that point at a page of their own rather than at a post.
  static String? _ownPath(NotificationKind kind, Map<String, dynamic> data) {
    final username = jsonText(data['username']);
    final group = jsonText(data['group_name']);

    return switch (kind) {
      NotificationKind.grantedBadge => _badgePath(data),
      NotificationKind.groupMessageSummary
          when username != null && group != null =>
        '/u/$username/messages/group/$group',
      NotificationKind.membershipRequestAccepted when group != null =>
        '/g/$group',
      NotificationKind.membershipRequestConsolidated => '/my/messages',
      NotificationKind.likedConsolidated =>
        '/my/notifications/likes-received${_actingUsername(username)}',
      NotificationKind.linkedConsolidated =>
        '/my/notifications/links${_actingUsername(username)}',
      NotificationKind.inviteeAccepted
          when data['display_username'] is String =>
        '/u/${data['display_username']}',
      NotificationKind.newFeatures => '/admin/whats-new',
      NotificationKind.adminProblems => '/admin',
      NotificationKind.chatMention ||
      NotificationKind.chatMessage ||
      NotificationKind.chatInvitation ||
      NotificationKind.chatQuoted ||
      NotificationKind.chatWatchedThread => _chatPath(data),
      _ => null,
    };
  }

  /// Discourse's own `postUrl`: the slug is decorative — `topic` stands in when
  /// there is none — and the post number is left off the first post.
  static String? _topicPath(int? topicId, String? slug, int? postNumber) {
    if (topicId == null) return null;

    final path = '/t/${slug == null || slug.isEmpty ? 'topic' : slug}/$topicId';
    return (postNumber ?? 0) > 1 ? '$path/$postNumber' : path;
  }

  /// The channel, and the message or thread within it. The slug segment is
  /// decorative here too, and Discourse takes `-` in its place.
  static String? _chatPath(Map<String, dynamic> data) {
    final channel = data['chat_channel_id'];
    if (channel == null) return null;

    final buffer = StringBuffer('/chat/c/-/${jsonInt(channel)}');
    if (data['chat_thread_id'] case final thread?) {
      buffer.write('/t/${jsonInt(thread)}');
    }
    if (data['chat_message_id'] case final message?) {
      buffer.write('/${jsonInt(message)}');
    }
    return buffer.toString();
  }

  static String? _badgePath(Map<String, dynamic> data) {
    final id = data['badge_id'];
    if (id == null) return null;

    // Discourse slugifies the name itself when the payload carries no slug.
    final slug =
        jsonText(data['badge_slug']) ??
        jsonString(
          data['badge_name'],
        ).replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '-').toLowerCase();
    final username = jsonText(data['username']);
    final query = username == null
        ? ''
        : '?username=${Uri.encodeQueryComponent(username.toLowerCase())}';

    if (slug.isEmpty) return '/badges/${jsonInt(id)}$query';
    return '/badges/${jsonInt(id)}/$slug$query';
  }

  static String _actingUsername(String? username) => username == null
      ? ''
      : '?acting_username=${Uri.encodeQueryComponent(username)}';

  final int id;
  final NotificationKind kind;
  final bool read;
  final DateTime? createdAt;

  /// Where it points, when it points at a topic. Badges, group memberships and
  /// chat messages have no topic, and there is nowhere in this app to send
  /// them yet.
  final int? topicId;
  final int? postNumber;
  final String slug;

  /// The topic's title, or empty when the kind has no topic.
  final String title;

  /// Who did it, where somebody did.
  final String? actor;

  /// How many things a consolidated notification stands for.
  final int count;

  final String? badgeName;
  final String? groupName;
  final String? channelTitle;

  /// Where it points, site-relative — `/t/a-topic/12/4`, `/badges/7/nice-reply`,
  /// `/chat/c/-/9/44`, `/admin`. Null when the payload gave us no way to reach
  /// whatever it is about.
  final String? path;

  bool get isUnread => !read;

  DiscourseNotification asRead() => read
      ? this
      : DiscourseNotification(
          id: id,
          kind: kind,
          read: true,
          createdAt: createdAt,
          topicId: topicId,
          postNumber: postNumber,
          slug: slug,
          title: title,
          actor: actor,
          count: count,
          badgeName: badgeName,
          groupName: groupName,
          channelTitle: channelTitle,
          path: path,
        );
}
