import 'dart:async';

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

  late _EditApi api;
  late ShellController controller;

  setUp(() async {
    api = _EditApi(
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

  test(
    'an edit cannot adopt an account selected during write admission',
    () async {
      final post = controller.store
          .read<Post>(_siteUrl, 2)!
          .withRaw('Original reply body');
      controller.store.put(_siteUrl, post);
      controller.openEdit(post);
      final composer = controller.visibleComposer!;
      composer.text.text = 'Updated reply body';
      expect(composer.canSubmit, isTrue);
      var replaced = false;
      controller.addListener(() {
        if (replaced || !controller.postWriteInFlight(2)) return;
        replaced = true;
        _replaceWriteAccount(controller, 2);
      });

      await controller.submitComposer();

      expect(replaced, isTrue);
      expect(api.updated, isEmpty);
      expect(controller.postWriteInFlight(2), isTrue);
    },
  );

  test(
    'an old edit completion cannot release the new account post write',
    () async {
      final started = Completer<void>();
      final reply = Completer<void>();
      api.beforePostReply = () {
        started.complete();
        return reply.future;
      };
      final post = controller.store
          .read<Post>(_siteUrl, 2)!
          .withRaw('Original reply body');
      controller.store.put(_siteUrl, post);
      controller.openEdit(post);
      controller.visibleComposer!.text.text = 'Updated reply body';

      final saving = controller.submitComposer();
      await started.future;
      _replaceWriteAccount(controller, 2);
      reply.complete();
      await saving;

      expect(controller.postWriteInFlight(2), isTrue);
      expect(
        controller.store.read<Post>(_siteUrl, 2)!.raw,
        'Original reply body',
      );
    },
  );

  test(
    'an account change between metadata and body writes stops the edit',
    () async {
      final started = Completer<void>();
      final reply = Completer<void>();
      api.beforeTopicReply = () {
        started.complete();
        return reply.future;
      };
      final post = controller.store
          .read<Post>(_siteUrl, 1)!
          .withRaw('Original first post body');
      controller.store.put(_siteUrl, post);
      controller.openEdit(post);
      final composer = controller.visibleComposer!;
      composer.title.text = 'Updated topic title';
      composer.text.text = 'Updated first post body';
      expect(composer.canSubmit, isTrue);

      final saving = controller.submitComposer();
      await started.future;
      _replaceWriteAccount(controller, 1);
      reply.complete();
      await saving;

      expect(api.topicsUpdated, hasLength(1));
      expect(api.updated, isEmpty);
      expect(controller.store.read<TopicDetail>(_siteUrl, 7)!.title, 'Topic');
      expect(controller.postWriteInFlight(1), isTrue);
    },
  );

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

void _replaceWriteAccount(ShellController controller, int postId) {
  controller.lifecycle.invalidate(_siteUrl);
  controller.endPluginPostWrite(_siteUrl, postId);
  controller.beginPluginPostWrite(_siteUrl, postId);
}

final class _EditApi extends FakeDiscourseApi {
  _EditApi({required super.feeds, required super.postsById});

  Future<void> Function()? beforePostReply;
  Future<void> Function()? beforeTopicReply;

  @override
  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  }) async {
    final post = await super.updatePost(
      siteUrl: siteUrl,
      apiKey: apiKey,
      postId: postId,
      raw: raw,
      originalText: originalText,
      editReason: editReason,
      clientId: clientId,
    );
    await beforePostReply?.call();
    return post;
  }

  @override
  Future<void> updateTopic({
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
    await super.updateTopic(
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
    await beforeTopicReply?.call();
  }
}
