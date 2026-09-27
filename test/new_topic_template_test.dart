import 'dart:async';

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _bugTemplate = '### Steps to reproduce\n\n### Expected behaviour\n';
const _featureTemplate = '### What problem does this solve?\n';
const _untouchedTemplateMessage =
    'Please add details and specifics to your topic by editing the topic '
    'template.';

const _bugs = TopicCategory(
  id: 5,
  name: 'Bug reports',
  slug: 'bugs',
  color: 'E45735',
  permission: 1,
  topicTemplate: _bugTemplate,
);
const _features = TopicCategory(
  id: 6,
  name: 'Feature requests',
  slug: 'features',
  color: '0088CC',
  permission: 1,
  topicTemplate: _featureTemplate,
);
const _general = TopicCategory(
  id: 7,
  name: 'General',
  slug: 'general',
  color: '25AAE2',
  permission: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({ShellController shell, FakeDiscourseApi api})> start({
    Completer<void>? draftRestoreGate,
    ({ComposerDraft? draft, int sequence}) draftToRestore = const (
      draft: null,
      sequence: 0,
    ),
    SiteConfig? siteConfig,
  }) async {
    const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
    final api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': [], '/c/bugs/5.json': []},
      creatableFeedPaths: const {'/latest.json', '/c/bugs/5.json'},
      categoryList: const [_bugs, _features, _general],
      draftRestoreGate: draftRestoreGate,
      draftToRestore: draftToRestore,
      siteConfigs: {_siteUrl: ?siteConfig},
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
    if (siteConfig != null) await shell.resolveSiteConfig(_siteUrl);
    await shell.loadFeed('latest');
    return (shell: shell, api: api);
  }

  Future<ComposerController> openInBugs(ShellController shell) async {
    shell.browseTopicCategory(_bugs);
    await pumpEventQueue();
    await shell.openNewTopicFromList();
    // The template follows the composer's draft restore, which opening does
    // not wait for.
    await pumpEventQueue();
    return shell.visibleComposer!;
  }

  test(
    'a new topic opened in a templated category starts from its template',
    () async {
      final (:shell, :api) = await start();

      final composer = await openInBugs(shell);

      expect(composer.categoryId, _bugs.id);
      expect(composer.text.text, _bugTemplate);
      expect(composer.hasChanges, isFalse);
      expect(await shell.prepareComposerForClose(composer), isTrue);
      expect(api.draftsSaved, isEmpty);
    },
  );

  test(
    'choosing a category swaps an untouched template and keeps an edited one',
    () async {
      final (:shell, api: _) = await start();
      await shell.openNewTopic();
      final composer = shell.visibleComposer!;
      expect(composer.text.text, isEmpty);

      await shell.changeComposerCategory(composer, _bugs.id);
      expect(composer.text.text, _bugTemplate);
      await shell.changeComposerCategory(composer, _features.id);
      expect(composer.text.text, _featureTemplate);
      await shell.changeComposerCategory(composer, _general.id);
      expect(composer.text.text, isEmpty);

      await shell.changeComposerCategory(composer, _bugs.id);
      const edited = '${_bugTemplate}It crashes on launch.';
      composer.text.text = edited;
      await shell.changeComposerCategory(composer, _features.id);
      expect(composer.text.text, edited);
      await shell.changeComposerCategory(composer, _general.id);
      expect(composer.text.text, edited);
    },
  );

  for (final reply in ['I wrote this myself', '']) {
    test(
      'a restored draft body "$reply" is never replaced by its template',
      () async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final draft = ComposerDraft(
          action: ComposerDraft.createTopicAction,
          title: 'Crash on launch',
          reply: reply,
          categoryId: _bugs.id,
        );
        final (:shell, api: _) = await start(
          draftRestoreGate: gate,
          draftToRestore: (draft: draft, sequence: 3),
        );

        final opening = shell.resumeDraft(
          _siteUrl,
          UserDraft(key: 'new_topic_1', sequence: 3, data: draft),
        );
        await pumpEventQueue();
        final composer = shell.visibleComposer!;
        expect(composer.text.text, isEmpty);

        gate.complete();
        await opening;
        expect(await shell.finishComposerDraftRestore(composer), isTrue);
        await pumpEventQueue();

        expect(composer.categoryId, _bugs.id);
        expect(composer.title.text, 'Crash on launch');
        expect(composer.text.text, reply);
        if (reply.isNotEmpty) {
          await shell.changeComposerCategory(composer, _features.id);
          expect(composer.text.text, reply);
        }
      },
    );
  }

  test(
    'submitting an untouched template is refused with the core message',
    () async {
      final (:shell, :api) = await start();
      final composer = await openInBugs(shell);
      composer.title.text = 'Crash on launch';
      expect(composer.canSubmit, isTrue);

      for (final body in [_bugTemplate, '\n$_bugTemplate\n\n']) {
        composer.text.text = body;
        await shell.submitComposer();

        expect(api.topicsCreated, isEmpty);
        expect(composer.state, ComposerState.editing);
        expect(composer.error?.message, _untouchedTemplateMessage);
      }

      const edited = '${_bugTemplate}It crashes on launch.';
      composer.text.text = edited;
      await shell.submitComposer();

      expect(api.topicsCreated.single['raw'], edited);
      expect(api.topicsCreated.single['categoryId'], _bugs.id);
    },
  );

  test(
    'a site with templates requires a category before it asks the site',
    () async {
      final (:shell, :api) = await start();
      await shell.openNewTopic();
      final composer = shell.visibleComposer!;
      composer.title.text = 'A question';
      composer.text.text = 'Where does this go?';

      await shell.submitComposer();

      expect(api.topicsCreated, isEmpty);
      expect(composer.error?.message, 'You must choose a category.');

      await shell.changeComposerCategory(composer, _general.id);
      await shell.submitComposer();

      expect(api.topicsCreated.single['categoryId'], _general.id);
    },
  );

  test(
    'uncategorized topics stay allowed where the site allows them',
    () async {
      final (:shell, :api) = await start(
        siteConfig: const SiteConfig(allowUncategorizedTopics: true),
      );
      await shell.openNewTopic();
      final composer = shell.visibleComposer!;
      composer.title.text = 'A question';
      composer.text.text = 'Where does this go?';

      await shell.submitComposer();

      expect(api.topicsCreated.single['categoryId'], isNull);
    },
  );

  test('a reply in a templated category neither takes nor checks it', () async {
    final (:shell, :api) = await start();
    shell.store.put(
      _siteUrl,
      const TopicDetail(
        id: 9,
        title: 'A bug',
        stream: [],
        categoryId: 5,
        canCreatePost: true,
      ),
    );
    shell.pushContent(
      ContentRoute.topic(topicId: 9, slug: 'a-bug', title: 'A bug'),
    );
    shell.openReply();
    final composer = shell.visibleComposer!;
    expect(await shell.finishComposerDraftRestore(composer), isTrue);
    expect(composer.text.text, isEmpty);

    await shell.changeComposerCategory(composer, _features.id);
    expect(composer.text.text, isEmpty);
    composer.text.text = _bugTemplate;
    await shell.submitComposer();

    expect(api.created.single['raw'], _bugTemplate.trim());
  });
}
