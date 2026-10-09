import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const site = 'https://meta.example';
void main() {
  test(
    'Mark unread drains existing timings and suppresses new ones before DELETE',
    () async {
      final api = _Api();
      final shell = await _fixture(api);
      addTearDown(shell.dispose);
      final reading = shell.markTopicRead(site, 7, 2, caughtUp: false);
      await api.readStarted.future;
      final reset = shell.markTopicUnread(site, 7);
      await shell.markTopicRead(site, 7, 3, caughtUp: true);
      expect(api.events, ['read']);
      api.readGate.complete();
      await reading;
      await reset;
      expect(api.events, ['read', 'DELETE /t/7/timings.json?last=1']);
      expect(shell.topicUnreadWriteInFlight(site, 7), isFalse);
      expect(shell.currentContent?.topicId, isNot(7));
    },
  );
  test(
    'retiring the account while timing finishes prevents the reset',
    () async {
      final api = _Api();
      final shell = await _fixture(api);
      addTearDown(shell.dispose);
      final reading = shell.markTopicRead(site, 7, 2, caughtUp: false);
      await api.readStarted.future;
      final reset = shell.markTopicUnread(site, 7);
      await shell.disconnectCurrentInstance();
      api.readGate.complete();
      await reading;
      await reset;
      expect(api.events, ['read']);
    },
  );
}

Future<ShellController> _fixture(_Api api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(username: 'reader')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    initialRootMode: ShellRootMode.forum,
  );
  await shell.load();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await shell.loadTopic(7, 'topic');
  return shell;
}

class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        topics: {
          7: (
            detail: const TopicDetail(
              id: 7,
              title: 'Topic',
              stream: [1, 2, 3],
              highestPostNumber: 3,
            ),
            posts: const [
              Post(
                id: 2,
                postNumber: 2,
                username: 'sam',
                cooked: '<p>Reply</p>',
              ),
            ],
          ),
        },
      );
  final readStarted = Completer<void>();
  final readGate = Completer<void>();
  final events = <String>[];
  @override
  Future<void> recordTopicReads({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postNumbers,
    int milliseconds = 500,
    String? clientId,
  }) async {
    events.add('read');
    readStarted.complete();
    await readGate.future;
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    events.add('$method $path');
    return {};
  }
}
