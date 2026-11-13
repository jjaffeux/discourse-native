import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fakes.dart';

const _url = 'https://forum.example';
const _latency = Duration(milliseconds: 30);
const _user = DiscourseUser(id: 1, username: 'reader', canCreateTopic: true);
const _tags = [
  TopicTag(id: 1, name: 'design'),
  TopicTag(id: 2, name: 'mobile'),
  TopicTag(id: 3, name: 'bug'),
];
const _kept = [_tagsFirst, _tagsLast];
const _tagsFirst = TopicTag(id: 1, name: 'design');
const _tagsLast = TopicTag(id: 3, name: 'bug');
const _category = TopicCategory(
  id: 7,
  name: 'Support',
  color: 'dd6600',
  minimumRequiredTags: 1,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    stdout.writeln(
      jsonEncode({
        'refresh_three_retained_filtered_feeds': await _refreshFeeds(),
        'change_draft_category_and_validate_three_tags': await _changeDraft(),
        'save_topic_category_after_three_tag_checks': await _saveCategory(),
      }),
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<double> _refreshFeeds() async {
  final api = _Api();
  final lifecycle = SiteLifecycle();
  final forum = instance('forum.example', user: _user);
  final controller = TopicFeedController(
    api: api,
    credentials: FakeApiCredentialReader()..keys[_url] = 'key',
    lifecycle: lifecycle,
    store: Store(),
  );
  try {
    for (var i = 1; i <= 3; i++) {
      await controller.load(
        instance: forum,
        destinationId: 'filtered-$i',
        path: '/filter.json?q=in%3Abookmarked+category%3A$i',
        incoming: null,
      );
    }
    api.refreshFeeds = true;
    final watch = Stopwatch()..start();
    final updated = await controller.refreshRetained(
      instance: forum,
      lease: lifecycle.capture(_url),
      wherePath: (path) => path.startsWith('/filter.json?'),
    );
    watch.stop();
    _check(updated && api.feedReads == 3, 'three feed refreshes completed');
    for (var i = 1; i <= 3; i++) {
      final feed = controller.feedFor(_url, 'filtered-$i');
      _check(
        feed?.topicIds.single == 100 + i && feed?.loading == false,
        'refreshed feed $i',
      );
    }
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    controller.dispose();
  }
}

Future<double> _changeDraft() async {
  final api = _Api();
  final shell = await _shell(api);
  try {
    await shell.loadFeed('latest');
    await shell.loadCategories(_url);
    await shell.openNewTopicFromList();
    final composer = shell.visibleComposer!;
    composer.setTags(_tags);
    final watch = Stopwatch()..start();
    await shell.changeComposerCategory(composer, 7);
    watch.stop();
    _check(
      composer.categoryId == 7 && _tagNames(composer.tags) == _tagNames(_kept),
      'draft selected category and allowed tags',
    );
    _check(
      api.tagTerms.join(',') == 'design,mobile,bug',
      'three draft tag lookups',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    shell.dispose();
  }
}

Future<double> _saveCategory() async {
  final api = _Api();
  final shell = await _shell(api);
  try {
    shell.store.put(
      _url,
      const TopicDetail(
        id: 23,
        title: 'Topic',
        categoryId: 5,
        stream: [],
        tags: _tags,
        canEdit: true,
      ),
    );
    final watch = Stopwatch()..start();
    final error = await shell.saveTopicCategory(
      siteUrl: _url,
      topicId: 23,
      categoryId: 7,
    );
    watch.stop();
    final detail = shell.store.read<TopicDetail>(_url, 23);
    _check(
      error == null &&
          detail?.categoryId == 7 &&
          _tagNames(detail!.tags) == _tagNames(_kept),
      'saved topic category and allowed tags',
    );
    _check(
      api.tagTerms.join(',') == 'design,mobile,bug' &&
          api.topicsUpdated.length == 1,
      'three topic tag lookups and accepted update',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    shell.dispose();
  }
}

String _tagNames(Iterable<TopicTag> tags) =>
    tags.map((tag) => tag.name).join(',');

Future<ShellController> _shell(_Api api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('forum.example', user: _user)]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_url] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  return shell;
}

void _check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

final class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        user: _user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
        categoryPages: const {
          1: [_category],
        },
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
      );

  var refreshFeeds = false;
  var feedReads = 0;
  final tagTerms = <String>[];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (!path.startsWith('/filter.json?')) {
      return super.topicList(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    final id = int.parse(path.substring(path.length - 1));
    if (refreshFeeds) {
      feedReads++;
      await Future<void>.delayed(_latency);
    }
    return TopicList(
      topics: [
        Topic(id: id + (refreshFeeds ? 100 : 0), title: 'Topic', slug: 'topic'),
      ],
    );
  }

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  }) async {
    _check(
      categoryId == 7 && _tags.any((tag) => tag.name == term),
      'category tag query',
    );
    tagTerms.add(term);
    await Future<void>.delayed(_latency);
    final tag = _tags.firstWhere((tag) => tag.name == term);
    return TopicTagSearch(tags: [tag], forbidden: term == 'mobile');
  }

  @override
  Future<TopicUpdate> updateTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String title,
    required String originalTitle,
    Iterable<TopicTag>? tags,
    Iterable<TopicTag>? originalTags,
    int? categoryId,
    String? clientId,
  }) async {
    _check(
      tagTerms.length == 3 &&
          _tagNames(tags ?? []) == _tagNames(_kept) &&
          _tagNames(originalTags ?? []) == _tagNames(_tags),
      'authoritative tag update',
    );
    await Future<void>.delayed(_latency);
    return super.updateTopic(
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      title: title,
      originalTitle: originalTitle,
      tags: tags,
      originalTags: originalTags,
      categoryId: categoryId,
      clientId: clientId,
    );
  }
}
