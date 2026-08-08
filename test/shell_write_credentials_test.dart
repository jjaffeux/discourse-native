import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthenticator authenticator;
  late FakeDiscourseApi api;
  late ShellController controller;

  setUp(() async {
    authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    api = FakeDiscourseApi(feeds: const {'/latest.json': []});
    controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
      ]),
      api: api,
      authenticator: authenticator,
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
        stream: [1],
        postsCount: 1,
        canCreatePost: true,
      ),
    );
    controller.store.put(
      _siteUrl,
      const Post(
        id: 1,
        postNumber: 1,
        username: 'author',
        cooked: '<p>Body</p>',
        canDelete: true,
        canLike: true,
      ),
    );
  });

  test(
    'post actions translate a keychain failure and release their guard',
    () async {
      final post = controller.store.read<Post>(_siteUrl, 1)!;
      authenticator.apiKeyFailure = StateError('keychain unavailable');

      expect(
        await controller.toggleLike(post, siteUrl: _siteUrl),
        const WriteException(WriteFailure.unreachable).message,
      );
      expect(
        await controller.toggleLike(post, siteUrl: _siteUrl),
        const WriteException(WriteFailure.unreachable).message,
      );
      expect(
        await controller.deletePost(post),
        const WriteException(WriteFailure.unreachable).message,
      );

      expect(api.liked, isEmpty);
      expect(api.deleted, isEmpty);
      expect(controller.store.read<Post>(_siteUrl, 1), same(post));
    },
  );

  test(
    'a keychain failure returns a composer to an editable error state',
    () async {
      controller.openReply();
      final composer = controller.visibleComposer!;
      composer.text.text = 'A reply that should remain local';
      authenticator.apiKeyFailure = StateError('keychain unavailable');

      await controller.submitComposer();

      expect(composer.submitting, isFalse);
      expect(composer.error?.failure, WriteFailure.unreachable);
      expect(composer.raw, 'A reply that should remain local');
      expect(api.created, isEmpty);
    },
  );
}
