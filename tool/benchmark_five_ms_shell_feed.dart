import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fakes.dart';

const _url = 'https://forum.example';
const _latency = Duration(milliseconds: 30);
const _reader = DiscourseUser(id: 1, username: 'reader');
const _connected = DiscourseInstance(url: _url, title: 'Forum', user: _reader);
const _baseRow = Topic(id: 1, title: 'A topic', slug: 'a-topic');
const _post = Post(
  id: 11,
  postNumber: 1,
  username: 'reader',
  cooked: '<p>One</p>',
);
const _detail = TopicDetail(
  id: 1,
  title: 'A topic',
  stream: [11],
  postsCount: 1,
);
final _visited = _baseRow.withPlugins(
  PluginData.none.withValue(
    const PluginDataKey<_VisitRecord>(owner: 'benchmark', name: 'visit'),
    const _VisitRecord(),
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    stdout.writeln(
      jsonEncode({
        'reconcile_reader_visit_and_source_feed': await _reconcileVisit(),
        'load_sidebar_on_connected_forum_selection': await _selectForum(),
      }),
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

ShellController _shell(_ShellApi api, List<DiscourseInstance> forums) =>
    ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: api,
      authenticator: FakeAuthenticator()..keys[_url] = 'test-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );

Future<double> _reconcileVisit() async {
  final api = _ShellApi();
  final shell = _shell(api, [_connected]);
  try {
    await shell.load();
    final list = ContentRoute.topicList(TopicListMode.latest);
    await shell.loadFeed(list.id);
    shell.store
      ..put(_url, _detail)
      ..put(_url, _post);
    shell.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'a-topic', title: 'A topic'),
    );
    final reader = shell.createTopicReader(
      shell.focusedTabContext,
      shell.currentContent!,
    );
    try {
      _check(
        reader.foreground && reader.isConnected,
        'active connected reader',
      );
      _check(
        shell.focusedTabContext.topicListContent?.id == list.id,
        'source list',
      );
      api.visit = true;
      final watch = Stopwatch()..start();
      await reader.reconcileVisit();
      watch.stop();
      _check(
        api.visitedFeeds == 1 && api.silentNotifications == 1,
        'both visit reads',
      );
      _check(
        shell.store.read<Topic>(_url, 1)?.readingPolicy.explicitReadState ==
            true,
        'source topic marked read',
      );
      return watch.elapsedMicroseconds.toDouble();
    } finally {
      reader.close();
    }
  } finally {
    shell.dispose();
  }
}

Future<double> _selectForum() async {
  final api = _ShellApi();
  final shell = _shell(api, [instance('other.example'), _connected]);
  try {
    await shell.load();
    final sidebarVisible = Completer<void>();
    void observe() {
      if (!sidebarVisible.isCompleted &&
          shell
              .customSidebarSectionsFor(_url)
              .any((row) => row.id == 'custom')) {
        sidebarVisible.complete();
      }
    }

    shell.addListener(observe);
    final watch = Stopwatch()..start();
    shell.selectInstance(1);
    await sidebarVisible.future.timeout(const Duration(seconds: 3));
    watch.stop();
    _check(
      shell.currentInstance?.url == _url &&
          api.sidebarCalls == 1 &&
          api.currentUserCalls == 1,
      'selected connected forum and loaded sidebar',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    shell.dispose();
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class _VisitRecord implements TopicReadingPolicyRecord {
  const _VisitRecord();

  @override
  TopicReadingPolicy get topicReadingPolicy =>
      const NonchronologicalTopicReadingPolicy(serverReadState: true);

  @override
  Object markTopicRead() => this;
}

final class _ShellApi extends FakeDiscourseApi {
  _ShellApi()
    : super(
        user: _reader,
        feeds: const {
          '/latest.json': [_baseRow],
        },
        postsById: const {11: _post},
        topics: const {
          1: (detail: _detail, posts: [_post]),
        },
      );

  var visit = false;
  var silentNotifications = 0;
  var visitedFeeds = 0;
  var currentUserCalls = 0;
  var sidebarCalls = 0;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (visit && siteUrl == _url && path == '/latest.json') {
      visitedFeeds++;
      await Future<void>.delayed(_latency);
      return TopicList(topics: [_visited]);
    }
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
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
    if (visit && siteUrl == _url && filterByTypes.isEmpty) {
      _check(background, 'visit must keep notifications silent');
      silentNotifications++;
      await Future<void>.delayed(_latency);
    }
    return const [];
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (siteUrl == _url) {
      currentUserCalls++;
      await Future<void>.delayed(_latency);
    }
    return _reader;
  }

  @override
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    if (siteUrl != _url) return const [];
    sidebarCalls++;
    await Future<void>.delayed(_latency);
    return const [
      SidebarSection(id: 'custom', title: 'Saved links', destinations: []),
    ];
  }
}
