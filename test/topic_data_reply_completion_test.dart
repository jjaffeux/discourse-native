import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reply completion cannot refresh a replacement account after notification',
    () async {
      final site = instance(
        'reply.example',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'author'));
      final api = _ActionApi();
      final controller = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: api,
        authenticator: FakeAuthenticator.signedIn([site], site: api),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.store.put(
        site.url,
        const TopicDetail(
          id: 7,
          title: 'Reply',
          stream: [1],
          postsCount: 1,
          canCreatePost: true,
        ),
      );
      controller.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'reply', title: 'Reply'),
      );
      controller.openReply();
      controller.visibleComposer!.text.text = 'An accepted reply';
      expect(controller.visibleComposer!.canSubmit, isTrue);
      var retired = false;
      int? readsAtRetirement;
      controller.addListener(() {
        if (retired ||
            controller.visibleComposer != null ||
            controller.store.read<Post>(site.url, 9001) == null) {
          return;
        }
        retired = true;
        readsAtRetirement = api.topicsOpened.length;
        controller.lifecycle.invalidate(site.url);
        controller.store.forget(site.url);
      });

      await controller.submitComposer();
      await pumpEventQueue();

      expect(api.created, hasLength(1));
      expect(retired, isTrue);
      expect(api.topicsOpened, hasLength(readsAtRetirement!));
      expect(controller.store.read<TopicDetail>(site.url, 7), isNull);
    },
  );
  for (final recovery in [false, true]) {
    test(
      '${recovery ? 'topic recovery' : 'mark unread'} cannot refresh an account replaced during publication',
      () async {
        final site = instance(
          'completion.example',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'author'));
        final api = _ActionApi();
        final controller = ShellController(
          instanceStore: FakeInstanceStore([site]),
          api: api,
          authenticator: FakeAuthenticator.signedIn([site], site: api),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        controller.store.put(
          site.url,
          TopicDetail(
            id: 7,
            title: 'Topic',
            stream: const [1, 2],
            postsCount: 2,
            highestPostNumber: 2,
            canRecoverTopic: recovery,
            deletedAt: recovery ? DateTime.utc(2026, 1, 1) : null,
          ),
        );
        controller.store.put(
          site.url,
          const Topic(id: 7, title: 'Topic', slug: 'topic'),
        );
        var retired = false;
        void retire() {
          if (retired) return;
          retired = true;
          controller.lifecycle.invalidate(site.url);
          controller.store.forget(site.url);
        }

        if (recovery) {
          controller.store.ref<TopicDetail>(site.url, 7).addListener(retire);
          expect(await controller.setTopicDeleted(site.url, 7, false), isNull);
        } else {
          controller.store.ref<Topic>(site.url, 7).addListener(retire);
          expect(await controller.markTopicUnread(site.url, 7), isNull);
        }
        await pumpEventQueue();
        expect(retired, isTrue);
        expect(api.topicsOpened, isEmpty);
        expect(controller.store.read<TopicDetail>(site.url, 7), isNull);
      },
    );
  }
}

final class _ActionApi extends FakeDiscourseApi {
  _ActionApi() : super(feeds: const {'/latest.json': []});

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async => {};
}
