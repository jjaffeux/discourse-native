import 'dart:async';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_checklist.dart';
import 'package:discourse_native/src/shell/checklist_transactions.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://checklist.example';
const _raw = '[ ] One';
const _cooked =
    '<p><span class="chcklst-box" data-chk-src="0:0"></span> One</p>';
const _checked =
    '<p><span class="chcklst-box checked" data-chk-src="0:0"></span> One</p>';
Post _post() => Post(
  id: 22,
  postNumber: 2,
  username: 'author',
  raw: _raw,
  cooked: _cooked,
  canEdit: true,
  version: 1,
  updatedAt: DateTime.utc(2026, 10, 24),
);

final class _Credentials extends FakeAuthenticator {
  Completer<String?>? gate;
  bool fail = false;
  int reads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    reads++;
    if (fail) throw StateError('Storage unavailable');
    return gate == null ? 'key' : gate!.future;
  }
}

final class _Api extends FakeDiscourseApi {
  Completer<List<Post>>? readGate;
  Completer<void>? saveGate;
  int reads = 0;
  final saves =
      <({String raw, DateTime updatedAt, String id, Object session})>[];
  final readSessions = <Object>[];

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    reads++;
    final scope = AccountRequestScope.current!;
    scope.validate(siteUrl, apiKey, clientId);
    readSessions.add(scope.session);
    expect(includeRaw, isTrue);
    return readGate == null ? [_post()] : readGate!.future;
  }

  @override
  Future<PostChecklistUpdate> togglePostChecklist({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required List<Map<String, Object?>> toggles,
    required String expectedRaw,
    required DateTime expectedUpdatedAt,
    required String mutationId,
    String? clientId,
  }) async {
    final scope = AccountRequestScope.current!;
    scope.validate(siteUrl, apiKey, clientId);
    saves.add((
      raw: expectedRaw,
      updatedAt: expectedUpdatedAt,
      id: mutationId,
      session: scope.session,
    ));
    expect(toggles.single['checked'], isTrue);
    await saveGate?.future;
    return PostChecklistUpdate(
      raw: '[x] One',
      cooked: _checked,
      updatedAt: expectedUpdatedAt.add(const Duration(seconds: 1)),
      version: 2,
    );
  }
}

final class _Fixture {
  _Fixture() {
    data = TopicDataOwner(
      content: api,
      feeds: api,
      models: api.models,
      store: store,
      credentials: credentials,
      lifecycle: lifecycle,
      changed: () => changes++,
      liveChanged: (_) {},
      published: (_, _) => false,
      prepareCategories: (_, _) async {},
      loadTimeout: const Duration(seconds: 5),
      bookmarkReads: (_, _) => throw StateError('Unexpected bookmark read'),
    );
    owner = ChecklistTransactions(
      api: api,
      store: store,
      credentials: credentials,
      lifecycle: lifecycle,
      isConnected: (_) => true,
      topicData: (siteUrl, lease) {
        bindings++;
        return data.forLease(siteUrl, lease);
      },
      bookmarkWriting: (_, _, _) => false,
    );
    store.put(_site, _post());
    addTearDown(data.dispose);
    addTearDown(owner.dispose);
  }

  final store = Store();
  final lifecycle = SiteLifecycle();
  final credentials = _Credentials();
  final api = _Api();
  late final TopicDataOwner data;
  late final ChecklistTransactions owner;
  int bindings = 0;
  int changes = 0;

  bool get checked => PostChecklistDocument(
    store.read<Post>(_site, 22)!.cooked,
  ).targets.single.checked;

  Future<String?> toggle() {
    final post = store.read<Post>(_site, 22)!;
    return owner.toggle(
      siteUrl: _site,
      topicId: 7,
      post: post,
      target: PostChecklistDocument(post.cooked).targets.single,
      checked: true,
    );
  }
}

void main() {
  test('headless construction and activity reads do not bind accounts', () {
    final f = _Fixture();
    expect(f.bindings, 0);
    expect(f.owner.isWriting(_site, 22), isFalse);
    expect(f.bindings, 0);
    expect(f.credentials.reads, 0);
    expect(f.changes, 0);
  });

  test(
    'transport retains the original lease and exact concurrency baseline',
    () async {
      final f = _Fixture();
      final lease = f.lifecycle.capture(_site);
      expect(await f.toggle(), isNull);
      expect(f.api.readSessions.single, same(lease.session));
      final saved = f.api.saves.single;
      expect(saved.session, same(lease.session));
      expect(saved.raw, _raw);
      expect(saved.updatedAt, _post().updatedAt);
      expect(f.store.read<Post>(_site, 22)!.raw, '[x] One');
      expect(f.owner.isWriting(_site, 22), isFalse);
      expect(f.data.forSite(_site).postWriting(22), isFalse);
    },
  );

  test(
    'an exclusive post action refuses checklist admission before projection',
    () async {
      final f = _Fixture();
      final data = f.data.forSite(_site);
      expect(data.beginPluginWrite(22), isTrue);
      expect(await f.toggle(), isNotNull);
      expect(f.checked, isFalse);
      expect(f.owner.isWriting(_site, 22), isFalse);
      expect(f.credentials.reads, 0);
      expect(f.api.reads, 0);
      expect(f.api.saves, isEmpty);
      expect(data.postWriting(22), isTrue);
      data.endPluginWrite(22);
      expect(data.postWriting(22), isFalse);
    },
  );

  for (final missing in [false, true]) {
    test(
      'credential ${missing ? 'absence' : 'failure'} rolls back and releases',
      () async {
        final f = _Fixture();
        if (missing) {
          f.credentials.gate = Completer<String?>()..complete(null);
        } else {
          f.credentials.fail = true;
        }
        final pending = f.toggle();
        expect(f.checked, isTrue);
        expect(await pending, isNotNull);
        expect(f.checked, isFalse);
        expect(f.api.reads, 0);
        expect(f.api.saves, isEmpty);
        expect(f.owner.isWriting(_site, 22), isFalse);
        expect(f.data.forSite(_site).postWriting(22), isFalse);
      },
    );
  }

  for (final stage in ['credential', 'load', 'save']) {
    test('retiring during $stage keeps a successor write owned', () async {
      final f = _Fixture();
      final oldCredential = stage == 'credential' ? Completer<String?>() : null;
      final oldLoad = stage == 'load' ? Completer<List<Post>>() : null;
      final oldSave = stage == 'save' ? Completer<void>() : null;
      f.credentials.gate = oldCredential;
      f.api.readGate = oldLoad;
      f.api.saveGate = oldSave;
      final oldLease = f.lifecycle.capture(_site);
      final old = f.toggle();
      await pumpEventQueue();
      expect(f.owner.isWriting(_site, 22), isTrue);
      f.lifecycle.invalidate(_site);
      expect(f.owner.isWriting(_site, 22), isFalse);

      f.credentials.gate = null;
      f.api.readGate = null;
      final successorSave = Completer<void>();
      f.api.saveGate = successorSave;
      f.store.put(_site, _post());
      final successorLease = f.lifecycle.capture(_site);
      final successor = f.toggle();
      await pumpEventQueue();
      final requests = f.api.saves.length;
      oldCredential?.complete('retired-key');
      oldLoad?.complete([_post()]);
      oldSave?.complete();
      expect(await old, isNull);
      expect(f.owner.isWriting(_site, 22), isTrue);
      expect(f.data.forSite(_site).postWriting(22), isTrue);
      expect(f.checked, isTrue);
      await f.toggle();
      expect(f.api.saves, hasLength(requests));
      expect(f.api.saves.last.session, same(successorLease.session));
      expect(f.api.saves.last.session, isNot(same(oldLease.session)));

      successorSave.complete();
      expect(await successor, isNull);
      expect(f.owner.isWriting(_site, 22), isFalse);
      expect(f.data.forSite(_site).postWriting(22), isFalse);
      expect(f.api.saves.map((save) => save.id).toSet(), hasLength(requests));
    });
  }

  test(
    'repeated forget and dispose retire metadata and stop pending dispatch',
    () async {
      final f = _Fixture();
      final credential = Completer<String?>();
      f.credentials.gate = credential;
      final pending = f.toggle();
      f.owner.forget(_site);
      f.owner.forget(_site);
      f.owner.dispose();
      f.owner.dispose();
      expect(f.owner.isWriting(_site, 22), isFalse);
      credential.complete('key');
      expect(await pending, isNull);
      expect(f.api.reads, 0);
      expect(f.api.saves, isEmpty);
      expect(f.data.forSite(_site).postWriting(22), isFalse);
    },
  );
}
