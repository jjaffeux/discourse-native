import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _template = '### Steps to reproduce\n\n### Expected behaviour\n';

/// The category as core's category list serializes it
/// (`BasicCategorySerializer`).
const _bugs = <String, dynamic>{
  'id': 5,
  'name': 'Bug reports',
  'slug': 'bugs',
  'color': 'E45735',
  'text_color': 'FFFFFF',
  'style_type': 'square',
  'read_restricted': false,
  'permission': 1,
  'minimum_required_tags': 1,
  'topic_count': 12,
  'description_excerpt': 'Something is broken.',
  'position': 2,
  'notification_level': 2,
  'topic_template': _template,
};

/// The same category as a topic list embeds it on a site that lazy-loads
/// categories (`CategoryBadgeSerializer`).
const _bugsBadge = <String, dynamic>{
  'id': 5,
  'name': 'Bug reports',
  'slug': 'bugs',
  'color': 'E45735',
  'text_color': 'FFFFFF',
  'style_type': 'square',
  'icon': null,
  'emoji': null,
  'read_restricted': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({ShellController shell, FakeDiscourseApi api})> start({
    Map<String, dynamic> badge = _bugsBadge,
  }) async {
    const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
    final api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': [], '/c/bugs/5.json': []},
      creatableFeedPaths: const {'/latest.json', '/c/bugs/5.json'},
      categoryPages: {
        1: [TopicCategory.fromJson(_bugs)],
      },
      feedCategoriesByPath: {
        '/c/bugs/5.json': TopicList.fromJson({
          'topic_list': {
            'topics': const <Object?>[],
            'categories': [badge],
          },
        }, _siteUrl).categories,
      },
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      initialRootMode: ShellRootMode.forum,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1789070000000),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.loadFeed('latest');
    await shell.loadCategories(_siteUrl);
    expect(shell.categoryFor(5, siteUrl: _siteUrl)?.topicTemplate, _template);
    return (shell: shell, api: api);
  }

  /// Opens the category's own list, whose payload embeds its badge.
  Future<void> browseBugs(ShellController shell, FakeDiscourseApi api) async {
    shell.browseTopicCategory(shell.categoryFor(5, siteUrl: _siteUrl)!);
    await pumpEventQueue();
    expect(api.feedPaths.last, '/c/bugs/5.json');
  }

  test(
    'a topic list keeps the category details the composer depends on',
    () async {
      final (:shell, :api) = await start(
        badge: {..._bugsBadge, 'name': 'Bugs', 'color': 'BF1E2E'},
      );

      await browseBugs(shell, api);

      final held = shell.categoryFor(5, siteUrl: _siteUrl)!;
      expect(held.name, 'Bugs');
      expect(held.color, 'BF1E2E');
      expect(held.topicTemplate, _template);
      expect(held.minimumRequiredTags, 1);
      expect(held.descriptionExcerpt, 'Something is broken.');
      expect(held.topicCount, 12);
      expect(held.position, 2);
      expect(held.notificationLevel, CategoryNotificationLevel.tracking);
      expect(
        shell
            .topicComposerCategories(_siteUrl)
            .where((category) => category.canCreateTopic)
            .map((category) => (category.id, category.name)),
        [(5, 'Bugs')],
      );

      await shell.openNewTopicFromList();
      await pumpEventQueue();
      final composer = shell.visibleComposer!;

      expect(composer.categoryId, 5);
      expect(composer.text.text, _template);
      expect(
        composer.taxonomyValidationMessage,
        'Choose at least 1 tag for this category.',
      );
    },
  );

  test(
    'a category reload that drops the template and tag minimum clears them',
    () async {
      final (:shell, :api) = await start();
      await browseBugs(shell, api);

      final cleared = {
        ..._bugs,
        'minimum_required_tags': 0,
        'topic_template': null,
      };
      api.categoryPages[1] = [TopicCategory.fromJson(cleared)];
      await shell.loadCategories(_siteUrl, force: true);

      final held = shell.categoryFor(5, siteUrl: _siteUrl)!;
      expect(held.topicTemplate, isNull);
      expect(held.minimumRequiredTags, 0);
      expect(held.canCreateTopic, isTrue);

      await shell.openNewTopicFromList();
      await pumpEventQueue();
      final composer = shell.visibleComposer!;

      expect(composer.categoryId, 5);
      expect(composer.text.text, isEmpty);
      expect(composer.taxonomyValidationMessage, isNull);
    },
  );
}
