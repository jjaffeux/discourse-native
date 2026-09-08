import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_draft_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _replyTarget = ComposerTarget(
  siteUrl: _siteUrl,
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);
const _newTopicTarget = ComposerTarget(
  siteUrl: _siteUrl,
  topicId: 0,
  slug: '',
  topicTitle: 'New topic',
  mode: ComposerMode.newTopic,
);
const _listedDraft = UserDraft(
  key: 'topic_7',
  sequence: 4,
  data: ComposerDraft(reply: 'Listed reply'),
);

void main() {
  test(
    'saves locally before committing the server sequence and cache',
    () async {
      final harness = _Harness(cachedSequence: 4);
      addTearDown(harness.dispose);
      final (:composer, :session) = harness.open(_replyTarget);
      const draft = ComposerDraft(reply: 'A durable reply');

      final sequence = await session.save(
        ComposerDraftSave(
          target: _replyTarget,
          draft: draft,
          sequence: composer.draftSequence,
          localOnly: false,
          isCurrent: () => true,
        ),
      );

      expect(sequence, 5);
      expect(harness.api.draftsSaved.single['sequence'], 4);
      expect(harness.localStore.events.first, startsWith('write:'));
      expect(harness.localStore.events.last, 'clear');
      expect(harness.localStore.saved, isEmpty);
      expect(harness.cachedDraft, draft);
      expect(harness.cachedSequence, 5);
      expect(harness.coordinator.sequenceFor(_replyTarget), 5);
    },
  );

  test('restores a remote new-topic draft and adopts its sequence', () async {
    const draft = ComposerDraft(
      reply: 'Body from another client',
      title: 'Remote title',
      action: ComposerDraft.createTopicAction,
    );
    final harness = _Harness(
      cachedSequence: 0,
      api: FakeDiscourseApi(draftToRestore: const (draft: draft, sequence: 7)),
    );
    addTearDown(harness.dispose);
    final composer = harness.open(_newTopicTarget).composer;

    harness.coordinator.startRestore(composer);
    expect(await harness.coordinator.finishRestore(composer), isTrue);

    expect(composer.text.text, 'Body from another client');
    expect(composer.title.text, 'Remote title');
    expect(composer.draftSequence, 7);
    expect(harness.coordinator.sequenceFor(_newTopicTarget), 7);
  });

  test(
    'discard deletes through the injected ports and closes via callback',
    () async {
      final harness = _Harness(cachedSequence: 4, serverDraftKnown: true);
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;

      expect(await harness.coordinator.discard(composer), isNull);

      expect(harness.api.userDraftsDeleted, const [
        (siteUrl: _siteUrl, draftKey: 'topic_7', sequence: 4),
      ]);
      expect(harness.destroyed, const [
        (siteUrl: _siteUrl, draftKey: 'topic_7', knownToExist: true),
      ]);
      expect(harness.cachedDraft, isNull);
      expect(harness.activeComposer, isNull);
      expect(composer.isDisposed, isTrue);
    },
  );

  test('forgetting a site releases coordinator-owned sequence state', () {
    final harness = _Harness(cachedSequence: 4);
    addTearDown(harness.dispose);
    harness.coordinator.rememberSequence(_replyTarget, 9);
    expect(harness.coordinator.sequenceFor(_replyTarget), 9);

    harness.coordinator.forgetSite(_siteUrl);

    expect(harness.coordinator.sequenceFor(_replyTarget), 4);
  });

  test(
    'a retained older composer can save the shared draft key again',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = harness.open(_replyTarget);
      final second = harness.open(_replyTarget);

      Future<int?> save(ComposerDraftSession session, String text) =>
          session.save(
            ComposerDraftSave(
              target: _replyTarget,
              draft: ComposerDraft(reply: text),
              sequence: 0,
              localOnly: true,
              isCurrent: () => true,
            ),
          );

      await save(first.session, 'First tab');
      await save(second.session, 'Second tab');
      await save(first.session, 'First tab edited again');

      expect(
        ComposerDraft.decode(harness.localStore.saved.values.single)?.reply,
        'First tab edited again',
      );
    },
  );

  group('list deletion', () {
    test(
      'a superseded save is still skipped after a slow local write',
      () async {
        final localStore = _GatedWriteStore();
        final harness = _Harness(cachedSequence: 4, localStore: localStore);
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'Superseded edit';
        final save = composer.flushDraft();
        await localStore.started.future;
        composer.text.text = 'Current edit';
        localStore.gate.complete();
        await save;
        expect(harness.api.draftsSaved, isEmpty);
        await composer.flushDraft();
        expect(
          harness.api.draftsSaved.single['data'],
          contains('Current edit'),
        );
      },
    );

    test('a newer topic snapshot retains its draft and sequence', () async {
      final gate = Completer<void>();
      final harness = _Harness(
        cachedSequence: 4,
        api: FakeDiscourseApi(draftDeleteGate: gate),
      )..cachedDraft = _listedDraft.data;
      addTearDown(harness.dispose);
      final deletion = harness.coordinator.deleteListedDraft(
        _siteUrl,
        _listedDraft,
        () => true,
      );
      await pumpEventQueue();
      expect(harness.api.userDraftsDeleted, hasLength(1));
      harness
        ..cachedSequence = 6
        ..cachedDraft = const ComposerDraft(reply: 'New topic snapshot');
      gate.complete();
      await deletion;
      expect(harness.cachedDraft?.reply, 'New topic snapshot');
      expect(harness.coordinator.sequenceFor(_replyTarget), 6);
    });

    test('a retired writer cannot recreate a deleted generation', () async {
      final harness = _Harness(cachedSequence: 4)
        ..cachedDraft = _listedDraft.data;
      addTearDown(harness.dispose);
      final retired = harness.open(_replyTarget);
      harness.composers.remove(retired.composer);
      retired.composer.dispose();
      await harness.coordinator.deleteListedDraft(
        _siteUrl,
        _listedDraft,
        () => true,
      );

      final save = ComposerDraftSave(
        target: _replyTarget,
        draft: _listedDraft.data!,
        sequence: 4,
        localOnly: false,
        isCurrent: () => true,
      );
      await retired.session.stage(save);
      await retired.session.save(save);
      expect(harness.api.draftsSaved, isEmpty);
      expect(harness.localStore.saved, isEmpty);
      expect(harness.cachedDraft, isNull);

      final replacement = harness.open(_replyTarget).composer;
      replacement.text.text = 'A later reply';
      await replacement.flushDraft();
      expect(harness.api.draftsSaved.single['sequence'], 4);
      expect(harness.cachedDraft?.reply, 'A later reply');
    });

    test(
      'a local read already in flight cannot restore deleted text',
      () async {
        final localStore = _GatedReadStore();
        final harness = _Harness(cachedSequence: 4, localStore: localStore)
          ..cachedDraft = _listedDraft.data;
        addTearDown(harness.dispose);
        await localStore.write(
          _siteUrl,
          _listedDraft.key,
          _listedDraft.data!.encode(),
        );
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        await localStore.started.future;

        await harness.coordinator.deleteListedDraft(
          _siteUrl,
          _listedDraft,
          () => true,
        );
        localStore.gate.complete();
        expect(await harness.coordinator.finishRestore(composer), isTrue);
        expect(composer.text.text, isEmpty);
        expect(harness.cachedDraft, isNull);
      },
    );

    test(
      'a slow local write reserves its save before a stale list DELETE',
      () async {
        final localStore = _GatedWriteStore();
        final harness = _Harness(cachedSequence: 4, localStore: localStore)
          ..cachedDraft = _listedDraft.data;
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'Newer save';
        final save = composer.flushDraft();
        await localStore.started.future;
        final deletion = harness.coordinator.deleteListedDraft(
          _siteUrl,
          _listedDraft,
          () => true,
        );
        final rejected = expectLater(deletion, throwsA(isA<WriteException>()));
        await pumpEventQueue();
        expect(harness.api.userDraftsDeleted, isEmpty);

        localStore.gate.complete();
        await save;
        await rejected;
        expect(harness.api.userDraftsDeleted, isEmpty);
        expect(harness.cachedDraft?.reply, 'Newer save');
        expect(harness.cachedSequence, 5);
      },
    );

    test('a delayed clear preserves a newer local-only generation', () async {
      final localStore = _GatedClearStore();
      final harness = _Harness(cachedSequence: 4, localStore: localStore)
        ..cachedDraft = _listedDraft.data;
      addTearDown(harness.dispose);
      final opened = harness.open(_replyTarget);
      final deletion = harness.coordinator.deleteListedDraft(
        _siteUrl,
        _listedDraft,
        () => true,
      );
      await localStore.started.future;

      const replacement = ComposerDraft(reply: 'New local revision');
      final save = opened.session.save(
        ComposerDraftSave(
          target: _replyTarget,
          draft: replacement,
          sequence: 4,
          localOnly: true,
          isCurrent: () => true,
        ),
      );
      await pumpEventQueue();
      expect(
        await localStore.read(_siteUrl, _listedDraft.key),
        replacement.encode(),
      );
      localStore.gate.complete();
      await deletion;
      await save;
      expect(
        await localStore.read(_siteUrl, _listedDraft.key),
        replacement.encode(),
      );
      expect(harness.cachedDraft, isNull);
      expect(harness.api.draftsSaved, isEmpty);
    });

    test('failed local cleanup keeps recovery and permits a retry', () async {
      final localStore = _FailingClearStore();
      final harness = _Harness(cachedSequence: 4, localStore: localStore)
        ..cachedDraft = _listedDraft.data;
      addTearDown(harness.dispose);
      await localStore.write(
        _siteUrl,
        _listedDraft.key,
        _listedDraft.data!.encode(),
      );

      await expectLater(
        harness.coordinator.deleteListedDraft(
          _siteUrl,
          _listedDraft,
          () => true,
        ),
        throwsA(isA<DraftWriteException>()),
      );
      expect(harness.cachedDraft, _listedDraft.data);
      expect(
        await localStore.read(_siteUrl, _listedDraft.key),
        _listedDraft.data!.encode(),
      );
      localStore.fail = false;
      await harness.coordinator.deleteListedDraft(
        _siteUrl,
        _listedDraft,
        () => true,
      );
      expect(harness.cachedDraft, isNull);
      expect(await localStore.read(_siteUrl, _listedDraft.key), isNull);
    });

    for (final key in [
      'new_topic',
      'new_private_message',
      'new_topic_voice_7',
      'edit_topic_7',
    ]) {
      test('deleting $key leaves the topic reply cache alone', () async {
        final harness = _Harness(cachedSequence: 4)
          ..cachedDraft = _listedDraft.data;
        addTearDown(harness.dispose);
        await harness.localStore.write(
          _siteUrl,
          key,
          _listedDraft.data!.encode(),
        );
        await harness.coordinator.deleteListedDraft(
          _siteUrl,
          UserDraft(key: key, sequence: 4, data: _listedDraft.data, topicId: 7),
          () => true,
        );
        expect(await harness.localStore.read(_siteUrl, key), isNull);
        expect(harness.cachedDraft, _listedDraft.data);
        expect(harness.api.userDraftsDeleted.single.draftKey, key);
      });
    }
  });
}

final class _Harness {
  _Harness({
    this.cachedSequence = 0,
    this.serverDraftKnown = false,
    FakeDiscourseApi? api,
    FakeDraftStore? localStore,
  }) : api = api ?? FakeDiscourseApi(),
       localStore = localStore ?? FakeDraftStore() {
    coordinator = ComposerDraftCoordinator(
      localStore: this.localStore,
      persistence: this.api,
      draftsApi: this.api,
      lifecycle: lifecycle,
      readCredential: (_) async => (apiKey: 'api-key', failure: null),
      readClientId: () async => 'client-id',
      isDisposed: () => disposed,
      isCurrentComposer: composers.contains,
      readCachedDraft: (_) => cachedDraft,
      readCachedSequence: (_) => cachedSequence,
      writeCachedDraft: (_, draft, sequence) {
        cachedDraft = draft;
        cachedSequence = sequence;
      },
      minimumRequiredTagsFor: (_, _) => 0,
      isServerDraftKnown: (_) => serverDraftKnown,
      recordDraftDestroyed: (siteUrl, draftKey, {required knownToExist}) {
        destroyed.add((
          siteUrl: siteUrl,
          draftKey: draftKey,
          knownToExist: knownToExist,
        ));
      },
      onComposerClosed: (composer) {
        composers.remove(composer);
        if (identical(activeComposer, composer)) activeComposer = null;
      },
      reportError: (error, stackTrace, operation) {
        errors.add((error: error, operation: operation));
      },
    );
  }

  final FakeDiscourseApi api;
  final FakeDraftStore localStore;
  final SiteLifecycle lifecycle = SiteLifecycle();
  final bool serverDraftKnown;
  late final ComposerDraftCoordinator coordinator;
  final List<({String siteUrl, String draftKey, bool knownToExist})> destroyed =
      [];
  final List<({Object error, String operation})> errors = [];
  ComposerController? activeComposer;
  final Set<ComposerController> composers = {};
  ComposerDraft? cachedDraft;
  int cachedSequence;
  bool disposed = false;

  ({ComposerController composer, ComposerDraftSession session}) open(
    ComposerTarget target,
  ) {
    final session = coordinator.openSession(target);
    final composer = ComposerController(
      target,
      onSaveDraft: session.save,
      onStageDraft: session.stage,
    );
    activeComposer = composer;
    composers.add(composer);
    coordinator.attach(session, composer);
    return (composer: composer, session: session);
  }

  void dispose() {
    disposed = true;
    for (final composer in composers) {
      if (!composer.isDisposed) composer.dispose();
    }
    composers.clear();
    activeComposer = null;
  }
}

final class _GatedReadStore extends FakeDraftStore {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<DraftStoreRead> readChecked(String siteUrl, String draftKey) async {
    final snapshot = await super.readChecked(siteUrl, draftKey);
    if (!started.isCompleted) {
      started.complete();
      await gate.future;
    }
    return snapshot;
  }
}

final class _GatedWriteStore extends FakeDraftStore {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await gate.future;
    }
    await super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}

final class _GatedClearStore extends FakeDraftStore {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<bool> clearChecked(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    started.complete();
    await gate.future;
    return super.clearChecked(siteUrl, draftKey, ifCurrent: ifCurrent);
  }
}

final class _FailingClearStore extends FakeDraftStore {
  bool fail = true;

  @override
  Future<bool> clearChecked(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async => fail
      ? false
      : super.clearChecked(siteUrl, draftKey, ifCurrent: ifCurrent);
}
