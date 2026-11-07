import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _post = Post(
  id: 22,
  postNumber: 2,
  username: 'author',
  cooked: '<p>Original</p>',
  likeCount: 2,
  canLike: true,
);

void main() {
  test('credential lookup cannot repeat an already canonical like', () async {
    final api = FakeDiscourseApi();
    final auth = _Auth()..keys[_site] = 'api-key';
    final shell = await _shell(api, auth);
    final credentials = Completer<String?>();
    auth.nextRead = credentials;
    final write = shell.toggleLike(_post, siteUrl: _site);
    expect(auth.nextRead, isNull);
    final canonical = _post.copyWith(
      liked: true,
      likeCount: 9,
      canLike: false,
      canUnlike: true,
    );
    shell.store.put(_site, canonical);
    credentials.complete('api-key');
    expect(await write, isNull);
    expect(api.liked, isEmpty);
    expect(shell.store.read<Post>(_site, 22), canonical);
  });

  test(
    'failure restores latest admitted like fields and preserves edits',
    () async {
      final response = Completer<void>();
      final api = FakeDiscourseApi(
        likeGate: response,
        likeFailure: const WriteException(WriteFailure.forbidden),
      );
      final auth = _Auth()..keys[_site] = 'api-key';
      final shell = await _shell(api, auth);
      final credentials = Completer<String?>();
      auth.nextRead = credentials;
      final write = shell.toggleLike(_post, siteUrl: _site);
      final latest = _post.copyWith(likeCount: 5, canLike: false);
      shell.store.put(_site, latest);
      credentials.complete('api-key');
      await pumpEventQueue();
      expect(api.liked, [22]);
      final optimistic = shell.store.read<Post>(_site, 22)!;
      expect(optimistic.likeCount, 6);
      shell.store.put(_site, optimistic.copyWith(cooked: '<p>Edited</p>'));
      response.complete();
      expect(await write, isNotNull);
      expect(
        shell.store.read<Post>(_site, 22),
        latest.copyWith(cooked: '<p>Edited</p>'),
      );
      expect(shell.postWriteInFlight(22, siteUrl: _site), isFalse);
    },
  );

  test('retired like failure cannot change its successor account', () async {
    final response = Completer<void>();
    final api = FakeDiscourseApi(
      likeGate: response,
      likeFailure: const WriteException(WriteFailure.forbidden),
    );
    final shell = await _shell(api, _Auth()..keys[_site] = 'api-key');
    final write = shell.toggleLike(_post, siteUrl: _site);
    await pumpEventQueue();
    expect(api.liked, [22]);
    shell.lifecycle.invalidate(_site);
    final successor = _post.copyWith(liked: true, likeCount: 12);
    shell.store.put(_site, successor);
    response.complete();
    await write;
    expect(shell.store.read<Post>(_site, 22), successor);
  });

  test(
    'failed like cannot roll back a newer canonical like snapshot',
    () async {
      final response = Completer<void>();
      final api = FakeDiscourseApi(
        likeGate: response,
        likeFailure: const WriteException(WriteFailure.forbidden),
      );
      final shell = await _shell(api, _Auth()..keys[_site] = 'api-key');
      final write = shell.toggleLike(_post, siteUrl: _site);
      await pumpEventQueue();
      expect(api.liked, [22]);
      final canonical = _post.copyWith(
        liked: true,
        likeCount: 9,
        canLike: false,
        canUnlike: true,
      );
      shell.store.put(_site, canonical);
      response.complete();
      expect(await write, isNotNull);
      expect(shell.store.read<Post>(_site, 22), canonical);
    },
  );
}

Future<ShellController> _shell(FakeDiscourseApi api, _Auth auth) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
    ]),
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  shell.store.put(_site, _post);
  return shell;
}

class _Auth extends FakeAuthenticator {
  Completer<String?>? nextRead;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    final held = nextRead;
    if (held == null) return super.apiKeyFor(siteUrl);
    nextRead = null;
    return held.future;
  }
}
