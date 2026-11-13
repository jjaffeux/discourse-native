import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/account_activity_api.dart';
import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_content_api.dart';
import 'package:discourse_native/src/data/topic_feeds_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/assign/assign_notifications.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';

const _site = DiscourseInstance(
  url: 'https://example.test',
  title: 'Example',
  user: DiscourseUser(username: 'reader'),
);
const _latency = Duration(milliseconds: 30);
const _credentials = _Credentials();

Future<void> main() async {
  try {
    stdout.writeln(
      jsonEncode({
        'restore_four_evicted_topic_summaries': await _restoreVisibleRows(),
        'reconcile_create_against_three_same_title_topics':
            await _reconcileTopic(),
        'dismiss_assignment_notifications_and_refresh':
            await _dismissAssignmentNotifications(),
      }),
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<double> _restoreVisibleRows() async {
  final api = _Api();
  final store = Store();
  final controller = TopicFeedController(
    api: api,
    credentials: _credentials,
    lifecycle: SiteLifecycle(),
    store: store,
  );
  try {
    await controller.load(
      instance: _site,
      destinationId: 'latest',
      path: '/latest.json',
      incoming: null,
    );
    for (var id = 1; id <= 4; id++) {
      store.remove<Topic>(_site.url, id);
    }
    api.requests.clear();
    final watch = Stopwatch()..start();
    await controller.ensureRange(
      instance: _site,
      destinationId: 'latest',
      firstRow: 0,
      lastRow: 9,
    );
    watch.stop();
    final feed = controller.feedFor(_site.url, 'latest')!;
    _check(feed.error == null && feed.rowCount == 30, 'topic range');
    for (var id = 1; id <= 10; id++) {
      _check(feed.topicIdAt(id - 1) == id, 'visible topic identity');
      _check(
        store.read<Topic>(_site.url, id)?.title == 'Topic $id',
        'restored topic',
      );
    }
    _checkRequests(api, ['summary:1', 'summary:2', 'summary:3', 'summary:4']);
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    controller.dispose();
  }
}

Future<double> _reconcileTopic() async {
  final api = _Api();
  final lifecycle = SiteLifecycle();
  final owner = TopicDataOwner(
    content: api,
    feeds: api,
    models: const DiscourseModelCodec.core(),
    store: Store(),
    credentials: _credentials,
    lifecycle: lifecycle,
    changed: () {},
    liveChanged: (_) {},
    published: (_, _) => true,
    prepareCategories: (_, _) async {},
    loadTimeout: const Duration(seconds: 5),
    bookmarkReads: (_, _) => const _Bookmarks(),
  );
  try {
    final session = owner.forSite(_site.url);
    final auth = await AccountRequestSession(
      _site.url,
      lifecycle.capture(_site.url),
    ).keyCredentials(_credentials);
    final watch = Stopwatch()..start();
    final match = await session.findCreatedTopic(
      username: 'reader',
      title: 'Weekly update',
      raw: 'A newly submitted weekly update.',
      privateMessage: false,
      credential: auth,
    );
    watch.stop();
    _check(
      match ==
          (topicId: 101, slug: 'weekly-update-101', title: 'Weekly update'),
      'uniquely reconciled topic',
    );
    _checkRequests(api, [
      'list:/topics/created-by/reader.json',
      for (var id = 101; id <= 103; id++) ...['topic:$id', 'posts:$id'],
    ]);
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    owner.dispose();
  }
}

Future<double> _dismissAssignmentNotifications() async {
  final api = _Api();
  final controller = AccountActivityController(
    api: api,
    credentials: _credentials,
    lifecycle: SiteLifecycle(),
  );
  final source = assignNotificationFeed;
  try {
    await controller.loadPluginNotifications(_site, source);
    _check(
      controller
          .pluginNotificationsFor(source.id, _site.url)
          .notifications
          .single
          .isUnread,
      'unread fixture',
    );
    api.requests.clear();
    final watch = Stopwatch()..start();
    await controller.dismissPluginNotifications(_site, source);
    watch.stop();
    final feed = controller.pluginNotificationsFor(source.id, _site.url);
    _check(
      feed.error == null && feed.notifications.single.read,
      'dismissed notification',
    );
    _check(
      controller.totalsFor(_site.url)?.unreadNotifications == 0,
      'updated totals',
    );
    _checkRequests(api, ['dismiss', 'notifications', 'totals']);
    _check(api.requests.first == 'dismiss', 'write before refresh');
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    controller.dispose();
  }
}

void _checkRequests(_Api api, List<String> expected) {
  _check(
    api.requests.length == expected.length &&
        api.requests.toSet().containsAll(expected),
    'requests ${api.requests}',
  );
}

void _check(bool success, String state) {
  if (!success) throw StateError(state);
}

final class _Credentials implements ApiCredentialReader {
  const _Credentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'test-key';

  @override
  Future<String> clientId() async => 'test-client';
}

final class _Api implements TopicContentApi, TopicFeedsApi, AccountActivityApi {
  final requests = <String>[];
  var dismissed = false;

  Future<void> _request(String key) {
    requests.add(key);
    return Future.delayed(_latency);
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    await _request('list:$path');
    return TopicList(
      topics: [
        if (path == '/latest.json')
          for (var id = 1; id <= 30; id++) _summary(id)
        else
          for (var id = 101; id <= 103; id++)
            Topic(id: id, title: 'Weekly update', slug: 'weekly-update-$id'),
      ],
    );
  }

  Topic _summary(int id) =>
      Topic(id: id, title: 'Topic $id', slug: 'topic-$id');

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    await _request('summary:$id');
    return _summary(id);
  }

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    await _request('topic:$id');
    return (
      detail: TopicDetail(id: id, title: 'Weekly update', stream: [id + 1000]),
      posts: const <Post>[],
    );
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    _check(includeRaw && ids.single == topicId + 1000, 'raw post request');
    await _request('posts:$topicId');
    return [
      Post(
        id: ids.single,
        postNumber: 1,
        username: 'reader',
        cooked: '',
        raw: topicId == 101
            ? 'A newly submitted weekly update.'
            : 'Older update.',
      ),
    ];
  }

  @override
  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  }) async {
    _check(types.isNotEmpty, 'assignment notification type filters');
    await _request('dismiss');
    dismissed = true;
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    bool background = false,
    String? clientId,
  }) async {
    await _request('notifications');
    return [
      DiscourseNotification(
        id: 1,
        typeId: const NotificationTypeId(34),
        read: dismissed,
      ),
    ];
  }

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    await _request('totals');
    return NotificationTotals(unreadNotifications: dismissed ? 0 : 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Bookmarks implements BookmarkReadProjection {
  const _Bookmarks();

  @override
  int get epoch => 0;

  @override
  int revision(int topicId) => 0;

  @override
  bool Function() guard(int topicId) =>
      () => true;

  @override
  Post postFromRead(int topicId, int version, Post incoming) => incoming;

  @override
  Post preservePost(Post incoming) => incoming;

  @override
  TopicDetail detailFromRead(int version, TopicDetail incoming) => incoming;

  @override
  Topic prepareRow(Topic incoming, int? versionAtDispatch) => incoming;

  @override
  Topic projectTopicRow(Topic incoming) => incoming;
}
