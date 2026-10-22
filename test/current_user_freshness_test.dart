import 'dart:async';

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', draftCount: 9);

final class _GatedFreshnessApi extends FakeDiscourseApi {
  _GatedFreshnessApi()
    : super(
        user: _user,
        feeds: const {'/latest.json': []},
        topics: {
          for (var id = 1; id <= 5; id++)
            id: topicPayload(
              id: id,
              title: 'Draft topic $id',
              canCreatePost: true,
              draft: const ComposerDraft(reply: 'Previously saved reply'),
              draftSequence: 4,
            ),
        },
      );

  final started = List.generate(3, (_) => Completer<void>());
  final responses = List.generate(3, (_) => Completer<DiscourseUser>());

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    final index = currentUserRequests.length;
    currentUserRequests.add(siteUrl);
    started[index].complete();
    return responses[index].future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'unlisted draft discards share a freshness replay and publish its count',
    () async {
      final api = _GatedFreshnessApi();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: _user),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'account-key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        initialRootMode: ShellRootMode.forum,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await api.started[0].future;

      Future<void> discard(int id) async {
        shell.pushContent(
          ContentRoute.topic(
            topicId: id,
            slug: 'draft-$id',
            title: 'Draft topic $id',
          ),
        );
        await shell.loadTopic(id, 'draft-$id');
        shell.openReply();
        final composer = shell.visibleComposer!;
        expect(await shell.finishComposerDraftRestore(composer), isTrue);
        expect(await shell.discardComposer(composer), isNull);
        await Future<void>.delayed(Duration.zero);
      }

      for (var id = 1; id <= 3; id++) {
        await discard(id);
      }
      expect(api.currentUserRequests, hasLength(1));
      expect(shell.draftList.feedFor(_site).loaded, isFalse);
      api.responses[0].complete(_user);
      await api.started[1].future;
      expect(api.currentUserRequests, hasLength(2));

      await discard(4);
      await discard(5);
      api.responses[1].complete(_user.withDraftCount(6));
      await api.started[2].future;
      expect(api.currentUserRequests, hasLength(3));
      api.responses[2].complete(_user.withDraftCount(2));
      await Future<void>.delayed(Duration.zero);
      expect(api.userDraftsDeleted, hasLength(5));
      expect(shell.currentInstance?.user?.draftCount, 2);
      expect(shell.draftCountFor(_site), 2);
      expect(api.currentUserRequests, hasLength(3));
    },
  );
}
