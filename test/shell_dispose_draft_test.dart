import 'dart:async';

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disposing preserves a debounced draft locally without remote sync',
    () async {
      final drafts = _GatedDraftStore();
      final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
      final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: drafts,
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      var disposed = false;
      addTearDown(() {
        if (!drafts.release.isCompleted) drafts.release.complete();
        if (!disposed) shell.dispose();
      });

      await shell.load();
      await pumpEventQueue();
      shell.store.put(
        _siteUrl,
        const TopicDetail(
          id: 7,
          title: 'A topic',
          stream: [],
          canCreatePost: true,
        ),
      );
      shell.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
      );
      shell.openReply();
      shell.visibleComposer!.text.text = 'Keep the newest thought';

      shell.dispose();
      disposed = true;
      await drafts.started.future;
      drafts.release.complete();
      await drafts.completed.future;

      expect(
        ComposerDraft.decode(drafts.saved['$_siteUrl::topic_7'])?.reply,
        'Keep the newest thought',
      );
      expect(api.draftsSaved, isEmpty);
    },
  );
}

final class _GatedDraftStore extends FakeDraftStore {
  final started = Completer<void>();
  final release = Completer<void>();
  final completed = Completer<void>();

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
    if (!completed.isCompleted) completed.complete();
  }
}
