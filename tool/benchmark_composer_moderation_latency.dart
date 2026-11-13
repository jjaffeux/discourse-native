import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_mutation_outcome.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fakes.dart';

const _url = 'https://forum.example';
const _latency = Duration(milliseconds: 30);
const _user = DiscourseUser(id: 1, username: 'reader', canCreateTopic: true);
const _category = TopicCategory(
  id: 7,
  name: 'Support',
  color: 'dd6600',
  minimumRequiredTags: 2,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    stdout.writeln(
      jsonEncode({
        'open_composer_in_uncached_category': await _openComposer(),
        'reconcile_whole_topic_moderation': await _repairTopic(),
      }),
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<double> _openComposer() async {
  final api = _Api();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('forum.example', user: _user)]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_url] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  try {
    await shell.load();
    _check(await shell.openInAppLink('$_url/c/support/7'), 'category route');
    await shell.loadFeed(shell.currentFeedId!);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!shell.canCreateTopicFromList && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    _check(
      shell.canCreateTopicFromList,
      'category permits composer: ${shell.currentFeedId} ${api.feedPaths}',
    );
    api.measureComposer = true;
    final watch = Stopwatch()..start();
    await shell.openNewTopicFromList();
    watch.stop();
    final composer = shell.visibleComposer;
    _check(
      composer?.categoryId == 7 &&
          composer?.taxonomyValidationMessage ==
              'Choose at least 2 tags for this category.',
      'category and minimum tags resolved',
    );
    _check(
      api.capabilityReads == 1 && api.categoryIdsRequested.single.single == 7,
      'exactly one capability and category read',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    shell.dispose();
  }
}

Future<double> _repairTopic() async {
  final api = _Api();
  final store = Store();
  final owner = TopicDataOwner(
    content: api,
    feeds: api,
    models: const DiscourseModelCodec.core(),
    store: store,
    credentials: FakeApiCredentialReader(),
    lifecycle: SiteLifecycle(),
    changed: () {},
    liveChanged: (_) {},
    published: (_, _) => true,
    prepareCategories: (_, _) async {},
    loadTimeout: const Duration(seconds: 5),
    bookmarkReads: (_, _) => const _Bookmarks(),
  );
  try {
    final ids = [for (var id = 1; id <= 41; id++) id];
    store.put(_url, TopicDetail(id: 23, title: 'Topic', stream: ids));
    store.putAll(_url, [
      for (final id in ids)
        Post(id: id, postNumber: id, username: 'reader', cooked: '<p>Old</p>'),
    ]);
    api.topics[23] = (
      detail: TopicDetail(id: 23, title: 'Updated topic', stream: ids),
      posts: const [],
    );
    final session = owner.forSite(_url);
    final watch = Stopwatch()..start();
    final outcome = await session.reconcileUncertainMutation(
      23,
      ids,
      'key',
      wholeTopic: true,
      alreadyHeld: false,
    );
    watch.stop();
    _check(
      outcome.projection == PostProjectionFreshness.fresh &&
          api.repairPages.length == 3 &&
          api.topicsOpened.single == 23,
      'three completed repair batches',
    );
    _check(
      api.repairPages.expand((page) => page).toList().join(',') ==
          ids.join(','),
      'complete requested coverage',
    );
    _check(
      store.read<TopicDetail>(_url, 23)?.title == 'Updated topic',
      'topic detail published',
    );
    for (final id in ids) {
      _check(
        store.read<Post>(_url, id)?.cooked == '<p>Updated $id</p>',
        'repaired post $id',
      );
    }
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    owner.dispose();
  }
}

void _check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

final class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        topics: {},
        feeds: const {'/c/support/7.json': [], '/c/7.json': []},
        creatableFeedPaths: const {'/c/support/7.json', '/c/7.json'},
        categoryFindResults: const [_category],
      );

  var measureComposer = false;
  var capabilityReads = 0;
  final repairPages = <List<int>>[];

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (measureComposer) {
      capabilityReads++;
      await Future<void>.delayed(_latency);
    }
    return const TopicComposerCapabilities(canTagTopics: true);
  }

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    await Future<void>.delayed(_latency);
    return super.findCategories(
      siteUrl: siteUrl,
      ids: ids,
      apiKey: apiKey,
      clientId: clientId,
    );
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
    await Future<void>.delayed(_latency);
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
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
    _check(
      topicId == 23 && apiKey == 'key',
      'captured moderation key and topic',
    );
    repairPages.add(ids);
    await Future<void>.delayed(_latency);
    return [
      for (final id in ids)
        Post(
          id: id,
          postNumber: id,
          username: 'reader',
          cooked: '<p>Updated $id</p>',
        ),
    ];
  }
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
