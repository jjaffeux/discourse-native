import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDiscourseApi api;
  late ShellController controller;

  setUp(() async {
    // Neither post carries its raw, and the fetch that should supply it
    // answers without one — the shape of an edit whose body never arrived.
    api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: const {
        1: Post(
          id: 1,
          postNumber: 1,
          username: 'author',
          cooked: '<p>First post body</p>',
          canEdit: true,
        ),
        2: Post(
          id: 2,
          postNumber: 2,
          username: 'author',
          cooked: '<p>Reply body</p>',
          canEdit: true,
        ),
      },
    );
    controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    controller.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    controller.store.put(
      _siteUrl,
      const TopicDetail(
        id: 7,
        title: 'Topic',
        stream: [1, 2],
        postsCount: 2,
        canCreatePost: true,
        canEdit: true,
      ),
    );
    for (final post in api.postsById.values) {
      controller.store.put(_siteUrl, post);
    }
  });

  test('a post edit whose body never loaded cannot replace the post', () async {
    controller.openEdit(controller.store.read<Post>(_siteUrl, 2)!);
    await pumpEventQueue();

    final composer = controller.visibleComposer!;
    expect(composer.loadingBody, isFalse);
    expect(composer.originalRaw, isNull);

    composer.text.text = 'oops';
    expect(composer.canSubmit, isFalse);
    await controller.submitComposer();

    expect(api.updated, isEmpty);
    expect(controller.visibleComposer, same(composer));
    expect(composer.raw, 'oops');
  });

  test('a topic edit whose body never loaded cannot blank the first '
      'post', () async {
    controller.openEdit(controller.store.read<Post>(_siteUrl, 1)!);
    await pumpEventQueue();

    final composer = controller.visibleComposer!;
    expect(composer.loadingBody, isFalse);
    expect(composer.originalRaw, isNull);

    composer.title.text = 'Changed title';
    expect(composer.metadataChanged, isTrue);
    expect(composer.canSubmit, isFalse);
    await controller.submitComposer();

    expect(api.updated, isEmpty);
    expect(api.topicsUpdated, isEmpty);
    expect(controller.visibleComposer, same(composer));
  });
}
