import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

const _support = TopicCategory(
  id: 5,
  name: 'Support',
  color: '0088CC',
  permission: 1,
  minimumRequiredTags: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ComposerController> compose({
    required bool staff,
    required bool canTagTopics,
  }) async {
    final user = DiscourseUser(
      id: 7,
      username: 'author',
      canCreateTopic: true,
      staff: staff,
    );
    final api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
      categoryPages: const {
        1: [_support],
      },
      composerCapabilities: TopicComposerCapabilities(
        canTagTopics: canTagTopics,
      ),
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
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.loadFeed('latest');
    await shell.loadCategories(_siteUrl);

    await shell.openNewTopicFromList();
    await pumpEventQueue();
    final composer = shell.visibleComposer!;
    await shell.changeComposerCategory(composer, 5);
    composer.title.text = 'A topic worth reading through';
    composer.text.text = 'With a body long enough to post.';
    return composer;
  }

  test('a member the site lets tag must meet the category minimum', () async {
    final composer = await compose(staff: false, canTagTopics: true);

    expect(
      composer.taxonomyValidationMessage,
      'Choose at least 1 tag for this category.',
    );
    expect(composer.canSubmit, isFalse);
  });

  test('a member the site does not let tag can still post', () async {
    final composer = await compose(staff: false, canTagTopics: false);

    expect(composer.taxonomyValidationMessage, isNull);
    expect(composer.canSubmit, isTrue);
  });

  test('staff can post without the category minimum', () async {
    final composer = await compose(staff: true, canTagTopics: true);

    expect(composer.taxonomyValidationMessage, isNull);
    expect(composer.canSubmit, isTrue);
  });
}
