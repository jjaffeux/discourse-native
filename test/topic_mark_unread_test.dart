import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
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
  test(
    'pending reset suppresses observations and duplicate reset requests',
    () async {
      final api = _Api()..holdDeletes = true;
      final shell = await _fixture(api);
      addTearDown(shell.dispose);
      final reset = shell.markTopicUnread(site, 7);
      await pumpEventQueue();
      expect(api.deletes, hasLength(1));
      await shell.markTopicRead(site, 7, 3, caughtUp: true);
      await shell.markTopicUnread(site, 7);
      expect(api.events, ['DELETE /t/7/timings.json?last=1']);
      expect(shell.topicUnreadWriteInFlight(site, 7), isTrue);
      api.deletes.single.complete();
      await reset;
      expect(shell.topicUnreadWriteInFlight(site, 7), isFalse);
    },
  );

  for (final failure in [
    const WriteException(WriteFailure.forbidden),
    StateError('offline'),
  ]) {
    test('failed reset reopens read admission for $failure', () async {
      final api = _Api()..resetFailure = failure;
      api.readGate.complete();
      final shell = await _fixture(api);
      addTearDown(shell.dispose);
      final result = await shell.markTopicUnread(site, 7);
      expect(
        result,
        failure is WriteException
            ? failure.message
            : const WriteException(WriteFailure.unreachable).message,
      );
      expect(shell.topicUnreadWriteInFlight(site, 7), isFalse);
      expect(shell.currentContent?.topicId, 7);
      await shell.markTopicRead(site, 7, 2, caughtUp: false);
      expect(api.events, ['DELETE /t/7/timings.json?last=1', 'read']);
      api.resetFailure = null;
      expect(await shell.markTopicUnread(site, 7), isNull);
    });
  }

  test('suppression covers reentrant projection and pending refresh', () async {
    final api = _Api();
    final shell = await _fixture(api);
    addTearDown(shell.dispose);
    shell.store.put(
      site,
      const Topic(id: 7, title: 'Topic', slug: 'topic', highestPostNumber: 3),
    );
    var projected = false;
    final row = shell.store.ref<Topic>(site, 7);
    void observeProjection() {
      if (projected || row.value?.unreadPosts != 1) return;
      projected = true;
      expect(shell.topicUnreadWriteInFlight(site, 7), isTrue);
      unawaited(shell.markTopicRead(site, 7, 3, caughtUp: true));
    }

    row.addListener(observeProjection);
    addTearDown(() => row.removeListener(observeProjection));
    api.refreshGate = Completer<void>();
    final reset = shell.markTopicUnread(site, 7);
    await pumpEventQueue();
    expect(projected, isTrue);
    expect(shell.store.read<Topic>(site, 7)?.lastReadPostNumber, 2);
    expect(shell.topicUnreadWriteInFlight(site, 7), isTrue);
    await shell.markTopicRead(site, 7, 3, caughtUp: true);
    expect(api.events, ['DELETE /t/7/timings.json?last=1']);
    api.refreshGate!.complete();
    await reset;
    expect(shell.topicUnreadWriteInFlight(site, 7), isFalse);
  });

  test('retired completion cannot release a replacement reset', () async {
    final api = _Api()..holdDeletes = true;
    final shell = await _fixture(api);
    addTearDown(shell.dispose);
    final oldReset = shell.markTopicUnread(site, 7);
    await pumpEventQueue();
    expect(api.deletes, hasLength(1));
    await shell.disconnectCurrentInstance();
    await shell.connectCurrentInstance();
    await shell.loadTopic(7, 'topic');
    final replacementReset = shell.markTopicUnread(site, 7);
    await pumpEventQueue();
    expect(api.deletes, hasLength(2));
    api.deletes.first.complete();
    await oldReset;
    expect(shell.topicUnreadWriteInFlight(site, 7), isTrue);
    await shell.markTopicRead(site, 7, 3, caughtUp: true);
    expect(api.events.where((event) => event == 'read'), isEmpty);
    api.deletes.last.complete();
    await replacementReset;
    expect(shell.topicUnreadWriteInFlight(site, 7), isFalse);
  });
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
        user: const DiscourseUser(username: 'reader'),
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
  final deletes = <Completer<void>>[];
  bool holdDeletes = false;
  Completer<void>? refreshGate;
  @override
  Completer<void>? get topicGate => refreshGate;
  Object? resetFailure;
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
    if (!readStarted.isCompleted) readStarted.complete();
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
    final response = Completer<void>();
    deletes.add(response);
    if (holdDeletes) await response.future;
    if (resetFailure case final failure?) throw failure;
    return {};
  }
}
