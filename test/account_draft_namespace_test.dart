import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/private_storage.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/draft_coordinator.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _a = DiscourseUser(id: 1, username: 'writer-a', canCreateTopic: true);
const _b = DiscourseUser(id: 2, username: 'writer-b', canCreateTopic: true);
const _original = DiscourseInstance(url: _site, title: 'Forum', user: _a);
const _key = 'new_topic_saved';
const _writing = ComposerDraft(reply: 'Only on this device', title: 'My draft');
const _row = UserDraft(
  key: _key,
  sequence: 1,
  data: ComposerDraft(reply: 'Remote placeholder', title: 'Remote title'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;
  late DraftStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('account-draft-scope-');
    file = File('${directory.path}/drafts.json');
    store = DraftStore(
      persistence: AppleFileDraftPersistence(
        file: file,
        legacyStorage: _EmptyLegacy(),
      ),
    );
  });

  tearDown(() async => directory.delete(recursive: true));

  final liveShells = <ShellController>{};

  void disposeShell(ShellController shell) {
    if (liveShells.remove(shell)) shell.dispose();
  }

  Future<ShellController> shellFor(DiscourseInstance instance) async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance]),
      api: FakeDiscourseApi(
        user: instance.user!,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      drafts: store,
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
    );
    liveShells.add(shell);
    addTearDown(() => disposeShell(shell));
    await shell.load();
    await shell.loadFeed('latest');
    return shell;
  }

  test(
    'shell restores only the original account writing after restart',
    () async {
      await store.write(_site, _key, _writing.encode());
      final replacement = _original.copyWith(user: _b);
      final bShell = await shellFor(replacement);
      await bShell.resumeDraft(_site, _row);
      expect(
        await bShell.finishComposerDraftRestore(bShell.visibleComposer!),
        isTrue,
      );
      expect(bShell.visibleComposer!.text.text, 'Remote placeholder');
      disposeShell(bShell);

      final expired = DiscourseInstance.fromJson(
        replacement.copyWith(clearUser: true).toJson(),
      );
      final aShell = await shellFor(expired.copyWith(user: _a));
      await aShell.resumeDraft(_site, _row);
      expect(
        await aShell.finishComposerDraftRestore(aShell.visibleComposer!),
        isTrue,
      );
      expect(aShell.visibleComposer!.text.text, _writing.reply);
      expect(await store.read(_site, _key), _writing.encode());
    },
  );

  test(
    'unknown signed-out provenance never grants flat drafts to a new login',
    () async {
      await store.write(_site, _key, _writing.encode());
      const unknown = DiscourseInstance(url: _site, title: 'Forum');
      final signedIn = DiscourseInstance.fromJson(
        unknown.copyWith(user: _b).toJson(),
      );
      expect(signedIn.draftOwner, '');
      final shell = await shellFor(signedIn);
      await shell.resumeDraft(_site, _row);
      expect(
        await shell.finishComposerDraftRestore(shell.visibleComposer!),
        isTrue,
      );
      expect(shell.visibleComposer!.text.text, 'Remote placeholder');
      expect(await store.read(_site, _key), _writing.encode());
    },
  );

  test(
    'a verified new ID cannot inherit username-only legacy writing',
    () async {
      await store.write(_site, _key, _writing.encode());
      const old = DiscourseInstance(
        url: _site,
        title: 'Forum',
        user: DiscourseUser(username: 'writer-a', canCreateTopic: true),
      );
      final signedIn = old.copyWith(clearUser: true).copyWith(user: _a);
      expect(signedIn.localDraftAccount, 'id:1');
      final shell = await shellFor(signedIn);
      await shell.resumeDraft(_site, _row);
      expect(
        await shell.finishComposerDraftRestore(shell.visibleComposer!),
        isTrue,
      );
      expect(shell.visibleComposer!.text.text, 'Remote placeholder');
      expect(await store.read(_site, _key), _writing.encode());
    },
  );

  test('scoped storage cannot alias an arbitrary legacy draft key', () async {
    final bSite = DraftStore.accountSiteKey(_site, 'id:2');
    const adversarial = 'account:id:2::topic_42';
    await store.write(_site, adversarial, 'A private writing');
    await store.write(bSite, 'topic_42', 'B private writing');
    expect(await store.read(_site, adversarial), 'A private writing');
    expect(await store.read(bSite, 'topic_42'), 'B private writing');
    await store.clear(bSite, 'topic_42');
    expect(await store.read(_site, adversarial), 'A private writing');
  });

  test(
    'retired composer preservation keeps its captured local account',
    () async {
      var localSite = DraftStore.accountSiteKey(_site, 'id:2');
      final originalSite = localSite;
      final lifecycle = SiteLifecycle();
      final api = FakeDiscourseApi();
      final composers = <ComposerController>{};
      final coordinator = ComposerDraftCoordinator(
        localStore: store,
        localDraftSite: (_) => localSite,
        persistence: api,
        draftsApi: api,
        lifecycle: lifecycle,
        credentials: FakeAuthenticator()..keys[_site] = 'key',
        readClientId: () async => 'client',
        isDisposed: () => false,
        isCurrentComposer: composers.contains,
        readCachedDraft: (_) => null,
        readCachedSequence: (_) => 0,
        writeCachedDraft: (_, _, _) {},
        minimumRequiredTagsFor: (_, _) => 0,
        isServerDraftKnown: (_) => false,
        recordDraftDestroyed: (_, _, {required knownToExist}) {},
        onComposerClosed: composers.remove,
      );
      const target = NewTopicComposerTarget(
        siteUrl: _site,
        topicTitle: 'Topic',
      );
      final session = coordinator.openSession(target);
      final composer = ComposerController(
        target,
        onSaveDraft: session.save,
        onStageDraft: session.stage,
      );
      composers.add(composer);
      coordinator.attach(session, composer);
      coordinator.startNewDraft(composer);
      composer.text.text = 'Original account pending text';
      lifecycle.invalidate(_site);
      localSite = DraftStore.accountSiteKey(_site, 'id:3');
      coordinator.preservePendingLocally(composer);
      await pumpEventQueue();
      expect(
        ComposerDraft.decode(
          await store.read(originalSite, target.draftKey),
        )?.reply,
        'Original account pending text',
      );
      expect(await store.read(localSite, target.draftKey), isNull);
      composer.dispose();
    },
  );

  for (final scopedActive in [false, true]) {
    for (final failingDelete in [1, 2]) {
      test(
        'cleanup failure $failingDelete keeps active ${scopedActive ? 'scoped' : 'flat'} text',
        () async {
          final backend = _ControlledPersistence();
          final drafts = DraftStore(persistence: backend);
          final activeSite = scopedActive
              ? DraftStore.accountSiteKey(_site, 'id:2')
              : _site;
          await drafts.write(activeSite, 'topic_42', 'Active account writing');
          backend.failingDelete = failingDelete;
          await expectLater(drafts.clearSite(activeSite), throwsStateError);
          expect(
            await drafts.read(activeSite, 'topic_42'),
            'Active account writing',
          );
        },
      );
    }
  }

  test(
    'cleanup rechecks ownership between separate persistence roots',
    () async {
      final backend = _ControlledPersistence()..deleteGate = Completer<void>();
      final drafts = DraftStore(persistence: backend);
      await drafts.write(_site, 'topic_42', 'Original account writing');
      var current = true;
      final clearing = drafts.clearSite(_site, ifCurrent: () => current);
      await backend.deletionStarted.future;
      current = false;
      backend.deleteGate!.complete();
      await clearing;
      expect(backend.deleteCount, 1);
      expect(await drafts.read(_site, 'topic_42'), 'Original account writing');
    },
  );

  test(
    'account cleanup does not erase replacement writes queued after it',
    () async {
      final backend = _ControlledPersistence()..deleteGate = Completer<void>();
      final drafts = DraftStore(persistence: backend);
      var current = true;
      final clearing = drafts.clearSite(_site, ifCurrent: () => current);
      await backend.deletionStarted.future;
      current = false;
      final bSite = DraftStore.accountSiteKey(_site, 'id:2');
      final writing = drafts.write(bSite, 'topic_42', 'New account writing');
      backend.deleteGate!.complete();
      await clearing;
      await writing;
      expect(await drafts.read(bSite, 'topic_42'), 'New account writing');
    },
  );

  test(
    'account roots keep delimiter-containing forum paths separate',
    () async {
      final first = DraftStore.accountSiteKey(
        'https://example.com/forum',
        'id:2',
      );
      final second = DraftStore.accountSiteKey(
        'https://example.com/forum::subfolder',
        'id:2',
      );
      await store.write(first, 'topic_42', 'First forum');
      await store.write(second, 'topic_42', 'Second forum');
      await store.clearSite(first);
      expect(await store.read(second, 'topic_42'), 'Second forum');
    },
  );

  test('account namespaces and retirement share the real site queue', () async {
    final backend = _ControlledPersistence()..writeGate = Completer<void>();
    final drafts = DraftStore(persistence: backend);
    final scopedSite = DraftStore.accountSiteKey(_site, 'id:2');
    final writing = drafts.write(scopedSite, 'topic_42', 'Pending writing');
    await backend.writingStarted.future;
    final clearing = drafts.clearSite(_site);
    await pumpEventQueue();
    expect(backend.deleteCount, 0);
    backend.writeGate!.complete();
    await writing;
    await clearing;
    expect(await drafts.read(scopedSite, 'topic_42'), isNull);
  });
}

final class _EmptyLegacy implements PrivateStorage {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

final class _ControlledPersistence implements DraftPersistence {
  final values = <String, String>{};
  final deletionStarted = Completer<void>();
  final writingStarted = Completer<void>();
  Completer<void>? deleteGate;
  Completer<void>? writeGate;
  int? failingDelete;
  int deleteCount = 0;

  @override
  Future<DraftPersistenceRead> read(String key) async =>
      (value: values[key], allowPreferenceFallback: false);

  @override
  Future<void> write(String key, String value) async {
    if (!writingStarted.isCompleted) writingStarted.complete();
    await writeGate?.future;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    deleteCount++;
    if (!deletionStarted.isCompleted) deletionStarted.complete();
    await deleteGate?.future;
    if (deleteCount == failingDelete) throw StateError('storage failed');
    values.removeWhere((key, _) => key.startsWith(prefix));
  }
}
