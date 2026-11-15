import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/profile_avatar_transactions.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://avatars.example';
const _reader = DiscourseInstance(
  url: _site,
  title: 'Avatars',
  user: DiscourseUser(id: 7, username: 'Reader'),
);
const _other = DiscourseInstance(
  url: _site,
  title: 'Avatars',
  user: DiscourseUser(id: 8, username: 'other'),
);

ComposerUploadFile _file([String name = 'me.png']) => ComposerUploadFile(
  name: name,
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);

final class _AvatarApi implements UserAvatarApi {
  final List<String> calls = [];
  Future<int> Function(Future<void> abortTrigger)? onUpload;
  Future<void> Function(int? uploadId)? onPick;

  @override
  Future<int> uploadAvatar({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required Future<void> abortTrigger,
    String? clientId,
  }) async {
    calls.add('upload ${file.name} $apiKey $clientId');
    return await onUpload?.call(abortTrigger) ?? 91;
  }

  @override
  Future<void> pickAvatar({
    required String siteUrl,
    required String apiKey,
    required String username,
    required int? uploadId,
    String? clientId,
  }) async {
    calls.add('pick $username $uploadId');
    await onPick?.call(uploadId);
  }
}

final class _Credentials implements ApiCredentialReader {
  String? key = 'api-key';

  @override
  Future<String?> apiKeyFor(String siteUrl) async => key;

  @override
  Future<String> clientId() async => 'client';
}

final class _Harness {
  _Harness() {
    avatars = ProfileAvatarTransactions(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      refreshCurrentUser: (siteUrl, apiKey, lease) async {
        refreshes.add(siteUrl);
        await onRefresh?.call();
        return fresh;
      },
      onChanged: (instance, uploadId) =>
          changes.add((instance.user!.username, uploadId)),
      onReplaced:
          (
            siteUrl,
            lease, {
            required username,
            required previous,
            required current,
          }) => replaced.add((username, previous, current)),
    )..addListener(() => states.add(avatars.stateFor(_site)));
    addTearDown(avatars.dispose);
  }

  final api = _AvatarApi();
  final credentials = _Credentials();
  final lifecycle = SiteLifecycle();
  final refreshes = <String>[];
  final changes = <(String, int?)>[];
  final replaced = <(String, String?, String?)>[];
  DiscourseUser? fresh;
  final states = <ProfileAvatarState>[];
  Future<void> Function()? onRefresh;
  late final ProfileAvatarTransactions avatars;

  ProfileAvatarState get state => avatars.stateFor(_site);
}

void main() {
  test('an upload is stored, picked, then read back before it rests', () async {
    final h = _Harness();

    expect(await h.avatars.upload(_reader, _file()), isTrue);

    expect(h.api.calls, ['upload me.png api-key client', 'pick Reader 91']);
    expect(h.changes, [('Reader', 91)]);
    expect(h.refreshes, [_site]);
    expect(h.states.map((state) => state.runtimeType), [
      ProfileAvatarUploading,
      ProfileAvatarSaving,
      ProfileAvatarIdle,
    ]);
  });

  test('the read-back says which picture the new one replaced', () async {
    final h = _Harness()
      ..fresh = const DiscourseUser(
        id: 7,
        username: 'Reader',
        avatarTemplate: '/user_avatar/avatars.example/reader/{size}/91_2.png',
      );
    const before = DiscourseInstance(
      url: _site,
      title: 'Avatars',
      user: DiscourseUser(
        id: 7,
        username: 'Reader',
        avatarTemplate: '/letter_avatar_proxy/v4/letter/r/a587f6/{size}.png',
      ),
    );

    expect(await h.avatars.upload(before, _file()), isTrue);

    expect(h.replaced, [
      (
        'Reader',
        '/letter_avatar_proxy/v4/letter/r/a587f6/{size}.png',
        '/user_avatar/avatars.example/reader/{size}/91_2.png',
      ),
    ]);
  });

  test('a read-back that was dropped replaces nothing', () async {
    final h = _Harness();

    expect(await h.avatars.upload(_reader, _file()), isTrue);

    expect(h.refreshes, [_site]);
    expect(h.replaced, isEmpty);
  });

  test('a read-back for a retired session replaces nothing', () async {
    final h = _Harness()
      ..fresh = const DiscourseUser(id: 7, username: 'Reader');
    h.onRefresh = () async => h.lifecycle.invalidate(_site);

    expect(await h.avatars.upload(_reader, _file()), isFalse);

    expect(h.replaced, isEmpty);
  });

  test('the default picture is picked with no upload', () async {
    final h = _Harness();

    expect(await h.avatars.useDefault(_reader), isTrue);

    expect(h.api.calls, ['pick Reader null']);
    expect(h.changes, [('Reader', null)]);
    expect(h.refreshes, [_site]);
    expect(h.states.first, isA<ProfileAvatarSaving>());
    expect(h.state, isA<ProfileAvatarIdle>());
  });

  test('a refused upload says why and picks nothing', () async {
    final h = _Harness();
    h.api.onUpload = (_) async => throw const ComposerUploadException(
      'Sorry, that image is too big.',
      statusCode: 422,
    );

    expect(await h.avatars.upload(_reader, _file()), isFalse);

    expect(
      h.state,
      isA<ProfileAvatarFailed>().having(
        (state) => state.message,
        'message',
        'Sorry, that image is too big.',
      ),
    );
    expect(h.api.calls, hasLength(1));
    expect(h.changes, isEmpty);
    expect(h.refreshes, isEmpty);
  });

  test('a refused pick surfaces the site message, or a plain one', () async {
    final h = _Harness();
    h.api.onPick = (_) async => throw const WriteException(
      WriteFailure.validation,
      errors: ['The avatar is missing.'],
    );
    expect(await h.avatars.upload(_reader, _file()), isFalse);
    expect((h.state as ProfileAvatarFailed).message, 'The avatar is missing.');

    h.api.onPick = (_) async =>
        throw const WriteException(WriteFailure.unreachable, statusCode: 422);
    expect(await h.avatars.useDefault(_reader), isFalse);
    expect(
      (h.state as ProfileAvatarFailed).message,
      "This site didn't accept that picture.",
    );
    expect(h.changes, isEmpty);

    h.api.onPick = null;
    expect(await h.avatars.useDefault(_reader), isTrue);
    expect(h.state, isA<ProfileAvatarIdle>());
  });

  test('an account with no key is told to reconnect', () async {
    final h = _Harness()..credentials.key = null;

    expect(await h.avatars.upload(_reader, _file()), isFalse);

    expect(h.state, isA<ProfileAvatarFailed>());
    expect(h.api.calls, isEmpty);
  });

  test('a second change waits for the first to settle', () async {
    final h = _Harness();
    final pick = Completer<void>();
    h.api.onPick = (_) => pick.future;

    final first = h.avatars.upload(_reader, _file());
    await pumpEventQueue();
    expect(h.state, isA<ProfileAvatarSaving>());
    expect(await h.avatars.useDefault(_reader), isFalse);
    expect(h.state, isA<ProfileAvatarSaving>());

    pick.complete();
    expect(await first, isTrue);
    expect(h.api.calls, ['upload me.png api-key client', 'pick Reader 91']);
  });

  test('a retired session aborts its upload and ignores the answer', () async {
    final h = _Harness();
    final upload = Completer<int>();
    var aborted = false;
    h.api.onUpload = (abortTrigger) {
      unawaited(abortTrigger.then((_) => aborted = true));
      return upload.future;
    };

    final pending = h.avatars.upload(_reader, _file());
    await pumpEventQueue();
    expect(h.state, isA<ProfileAvatarUploading>());

    h.lifecycle.invalidate(_site);
    await pumpEventQueue();
    expect(aborted, isTrue);
    expect(h.state, isA<ProfileAvatarIdle>());

    upload.complete(91);
    expect(await pending, isFalse);
    expect(h.api.calls, hasLength(1));
    expect(h.changes, isEmpty);
    expect(h.refreshes, isEmpty);
    expect(h.state, isA<ProfileAvatarIdle>());
  });

  test(
    'an answer for the retired account cannot settle the next account\'s change',
    () async {
      final h = _Harness();
      final stalePick = Completer<void>();
      final freshUpload = Completer<int>();
      h.api.onPick = (_) => stalePick.future;

      final stale = h.avatars.useDefault(_reader);
      await pumpEventQueue();
      h.lifecycle.invalidate(_site);
      h.api
        ..onPick = null
        ..onUpload = (_) => freshUpload.future;
      final fresh = h.avatars.upload(_other, _file('new.png'));
      await pumpEventQueue();
      expect(h.state, isA<ProfileAvatarUploading>());

      stalePick.completeError(const WriteException(WriteFailure.unreachable));
      expect(await stale, isFalse);
      expect(h.state, isA<ProfileAvatarUploading>());
      expect(h.changes, isEmpty);

      freshUpload.complete(12);
      expect(await fresh, isTrue);
      expect(h.changes, [('other', 12)]);
      expect(h.state, isA<ProfileAvatarIdle>());
    },
  );

  test('forgetting the site mid-save drops the outcome', () async {
    final h = _Harness();
    final pick = Completer<void>();
    h.api.onPick = (_) => pick.future;

    final pending = h.avatars.useDefault(_reader);
    await pumpEventQueue();
    h.avatars.forget(_site);
    expect(h.state, isA<ProfileAvatarIdle>());

    pick.complete();
    expect(await pending, isFalse);
    expect(h.changes, isEmpty);
    expect(h.refreshes, isEmpty);
  });

  test(
    'a picture the site took still rests when the read-back fails',
    () async {
      final h = _Harness()..onRefresh = () async => throw StateError('offline');

      expect(await h.avatars.upload(_reader, _file()), isTrue);

      expect(h.changes, [('Reader', 91)]);
      expect(h.state, isA<ProfileAvatarIdle>());
    },
  );

  test('a disposed owner starts nothing and tolerates a late answer', () async {
    final h = _Harness();
    final pick = Completer<void>();
    h.api.onPick = (_) => pick.future;
    final pending = h.avatars.useDefault(_reader);
    await pumpEventQueue();

    h.avatars.dispose();
    pick.complete();

    expect(await pending, isFalse);
    expect(await h.avatars.upload(_reader, _file()), isFalse);
    expect(h.changes, isEmpty);
  });
}
