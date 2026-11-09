import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _topic = TopicDetail(id: 1, title: 'One', stream: [100], postsCount: 1);
const _post = Post(
  id: 100,
  postNumber: 1,
  username: 'sam',
  cooked: '<p>First</p>',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reconciling a visit leaves the review queue unseen, opening the list does not',
    () async {
      final api = _Api();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.example',
          ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
        ]),
        api: api,
        authenticator: FakeAuthenticator()
          ..keys['https://meta.example'] = 'api-key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.store
        ..put('https://meta.example', _topic)
        ..put('https://meta.example', _post);
      shell.pushContent(
        ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
      );
      await pumpEventQueue();
      final reader = shell.createTopicReader(
        shell.focusedTabContext,
        shell.currentContent!,
      );
      addTearDown(reader.close);

      api.unfilteredReads.clear();
      await reader.reconcileVisit();

      expect(api.unfilteredReads, isNotEmpty);
      expect(api.unfilteredReads, everyElement(isTrue));

      api.unfilteredReads.clear();
      await shell.loadNotifications('https://meta.example');

      expect(api.unfilteredReads, [false]);
    },
  );
}

final class _Api extends FakeDiscourseApi {
  /// Whether each unfiltered notification read was a background one.
  final unfilteredReads = <bool>[];

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    bool background = false,
    String? clientId,
  }) {
    if (filterByTypes.isEmpty) unfilteredReads.add(background);
    return super.notifications(
      siteUrl: siteUrl,
      apiKey: apiKey,
      limit: limit,
      filterByTypes: filterByTypes,
      background: background,
      clientId: clientId,
    );
  }
}
