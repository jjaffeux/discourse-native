import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _reader = DiscourseUser(username: 'reader', canSendPrivateMessages: true);
const _message = TopicDetail(
  id: 7,
  title: 'Question',
  stream: [],
  privateMessage: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an older topic read cannot undo a completed archive write', () async {
    final api = _ArchiveApi();
    final shell = await _shell(api);
    final staleRead = shell.loadTopic(7, 'question', force: true);
    await api.started.future;
    expect(await shell.updateMessageArchived(_site, 7, true), isNull);
    api.response.complete((detail: _message, posts: <Post>[]));
    await staleRead;
    expect(shell.store.read<TopicDetail>(_site, 7)!.messageArchived, isTrue);
    expect(shell.store.read<TopicDetail>(_site, 7)!.archived, isFalse);
  });

  test(
    'ordinary topics and accounts without PM permission cannot archive messages',
    () async {
      final api = FakeDiscourseApi();
      final shell = await _shell(api);
      shell.store.put(_site, _message.copyWith(privateMessage: false));
      expect(await shell.updateMessageArchived(_site, 7, true), isNotNull);
      final denied = await _shell(
        api,
        user: const DiscourseUser(username: 'reader'),
      );
      expect(await denied.updateMessageArchived(_site, 7, true), isNotNull);
      expect(api.messagesArchived, isEmpty);
    },
  );
}

Future<ShellController> _shell(
  FakeDiscourseApi api, {
  DiscourseUser user = _reader,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(shell.dispose);
  await shell.load();
  shell.store.put(_site, _message);
  return shell;
}

class _ArchiveApi extends FakeDiscourseApi {
  final started = Completer<void>();
  final response = Completer<TopicPayload>();

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}
