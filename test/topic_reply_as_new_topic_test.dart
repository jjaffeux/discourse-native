import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShellController> shell({required bool canReplyAsNewTopic}) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      ]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': <Topic>[]},
        categoryList: const [
          TopicCategory(
            id: 5,
            name: 'Support',
            color: '0088CC',
            permission: 1,
            minimumRequiredTags: 1,
          ),
        ],
      ),
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await controller.load();
    await pumpEventQueue();
    controller.store.put(
      _siteUrl,
      TopicDetail(
        id: 7,
        title: 'A real topic',
        stream: const [1],
        categoryId: 5,
        canReplyAsNewTopic: canReplyAsNewTopic,
      ),
    );
    controller.store.put(
      _siteUrl,
      const Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>First post</p>',
      ),
    );
    controller.pushContent(
      ContentRoute.topic(
        topicId: 7,
        slug: 'a-real-topic',
        title: 'A real topic',
      ),
    );
    return controller;
  }

  test('opens a category-aware new-topic composer over its source', () async {
    final controller = await shell(canReplyAsNewTopic: true);
    addTearDown(controller.dispose);
    const continuation =
        'Continue the discussion from [A real topic](https://meta.discourse.org/t/a-real-topic/7)';

    await controller.openReplyAsNewTopic(continuation);

    final composer = controller.visibleComposer;
    expect(composer, isNotNull);
    expect(composer!.target.isNewTopic, isTrue);
    expect(composer.target.originTopicId, 7);
    expect(composer.categoryId, 5);
    expect(composer.canSubmit, isFalse);
    expect(composer.raw, continuation);
  });

  test('does nothing when the topic guardian withholds the action', () async {
    final controller = await shell(canReplyAsNewTopic: false);
    addTearDown(controller.dispose);

    await controller.openReplyAsNewTopic('Continue elsewhere');

    expect(controller.visibleComposer, isNull);
  });
}
