import 'dart:async';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/draft_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _replyTarget = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: _siteUrl,
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);
const _newTopicTarget = NewTopicComposerTarget(
  siteUrl: _siteUrl,
  topicTitle: 'New topic',
);
const _listedDraft = UserDraft(
  key: 'topic_7',
  sequence: 4,
  data: ComposerDraft(reply: 'Listed reply'),
);
const _listedTopicTarget = NewTopicComposerTarget(
  siteUrl: _siteUrl,
  topicTitle: 'New topic',
  draftKey: 'new_topic_1789070000000',
);
const _listedTopicDraft = UserDraft(
  key: 'new_topic_1789070000000',
  sequence: 4,
  data: ComposerDraft(
    reply: 'Listed topic body',
    title: 'Listed topic title',
    action: ComposerDraft.createTopicAction,
  ),
);

void main() {
  group('conflicting drafts', () {
    test(
      'keeps newer queued writing locally and never retries the server',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftGate: gate,
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'First writing';
        final saving = composer.flushDraft();
        await pumpEventQueue();
        composer.text.text = 'Newest writing';
        unawaited(composer.flushDraft());
        await pumpEventQueue();
        gate.complete();
        await saving;
        expect(harness.api.draftsSaved, hasLength(1));
        expect(harness.api.draftsSaved.single['sequence'], 4);
        expect(composer.draftConflict, isTrue);
        expect(composer.draftsGaveUp, isTrue);
        expect(composer.localDraftFailed, isFalse);
        var recovery = LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!;
        expect(recovery.draft.reply, 'Newest writing');
        expect(recovery.sequence, 4);
        expect(recovery.conflicted, isTrue);
        composer.text.text = 'Still newer writing';
        await composer.flushDraft();
        recovery = LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!;
        expect(recovery.draft.reply, 'Still newer writing');
        expect(recovery.conflicted, isTrue);
        expect(harness.api.draftsSaved, hasLength(1));
      },
    );

    for (final target in [_replyTarget, _listedTopicTarget]) {
      test(
        'restart retains local baseline and conflict for ${target.draftKey}',
        () async {
          final local = FakeDraftStore();
          await local.write(
            _siteUrl,
            target.draftKey,
            const LocalComposerDraft(
              draft: ComposerDraft(reply: 'Local version'),
              sequence: 4,
              conflicted: true,
            ).encode(),
          );

          for (var restart = 0; restart < 2; restart++) {
            final harness = _Harness(
              localStore: local,
              cachedSequence: 9,
            )..cachedDraft = const ComposerDraft(reply: 'Other device writing');
            addTearDown(harness.dispose);
            final composer = harness.open(target).composer;
            harness.coordinator.startRestore(
              composer,
              listedDraft: UserDraft(
                key: target.draftKey,
                sequence: 9,
                data: const ComposerDraft(reply: 'Other device writing'),
              ),
            );
            expect(await harness.coordinator.finishRestore(composer), isTrue);
            expect(
              composer.text.text,
              restart == 0 ? 'Local version' : 'Locally edited version',
            );
            expect(composer.draftSequence, 4);
            expect(composer.draftConflict, isTrue);
            await harness.coordinator.restoreListedDraft(
              composer,
              UserDraft(
                key: target.draftKey,
                sequence: 10,
                data: const ComposerDraft(reply: 'Newer other device writing'),
              ),
            );
            expect(composer.draftSequence, 4);
            composer.text.text = 'Locally edited version';
            await composer.flushDraft();
            harness.coordinator.preservePendingLocally(composer);
            await harness.coordinator.localWritesSettled();
            expect(harness.api.draftsSaved, isEmpty);
            expect(
              LocalComposerDraft.decode(local.saved.values.single)!.conflicted,
              isTrue,
            );
            harness.dispose();
          }
        },
      );
    }

    test(
      'a pre-conflict snapshot cannot adopt a newly observed baseline',
      () async {
        final local = FakeDraftStore();
        await local.write(
          _siteUrl,
          'topic_7',
          const LocalComposerDraft(
            draft: ComposerDraft(reply: 'Before conflict was persisted'),
            sequence: 4,
          ).encode(),
        );
        final harness = _Harness(localStore: local, cachedSequence: 9);
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        expect(await harness.coordinator.finishRestore(composer), isTrue);
        composer.text.text = 'Reopened edit';
        await composer.flushDraft();
        expect(composer.draftSequence, 4);
        expect(composer.draftConflict, isTrue);
        expect(harness.api.draftsSaved, isEmpty);
      },
    );

    test(
      'legacy recovery uses an unknown baseline rather than another device sequence',
      () async {
        final harness = _Harness(
          cachedSequence: 9,
          api: FakeDiscourseApi(
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        await harness.localStore.write(
          _siteUrl,
          'topic_7',
          const ComposerDraft(reply: 'Legacy writing').encodeLocal(),
        );
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        expect(await harness.coordinator.finishRestore(composer), isTrue);
        expect(composer.text.text, 'Legacy writing');
        composer.text.text = 'Edited legacy writing';
        await composer.flushDraft();
        expect(harness.api.draftsSaved.single['sequence'], 0);
        expect(composer.draftConflict, isTrue);
      },
    );

    for (final clearFirst in [false, true]) {
      test(
        'discard only removes local conflict recovery after clear=$clearFirst',
        () async {
          final harness = _Harness(
            cachedSequence: 4,
            serverDraftKnown: true,
            api: FakeDiscourseApi(
              draftFailure: const WriteException(WriteFailure.conflict),
            ),
          );
          addTearDown(harness.dispose);
          final composer = harness.open(_replyTarget).composer;
          harness.coordinator.startNewDraft(composer);
          composer.text.text = 'Local conflict';
          await composer.flushDraft();
          if (clearFirst) {
            composer.text.clear();
            await composer.flushDraft();
          }
          expect(await harness.coordinator.discard(composer), isNull);
          expect(harness.api.userDraftsDeleted, isEmpty);
          expect(harness.localStore.saved, isEmpty);
          expect(harness.destroyed, isEmpty);
        },
      );
    }

    test(
      'successful queued saves advance only their own accepted baseline',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(draftGate: gate),
        );
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'First writing';
        final saving = composer.flushDraft();
        await pumpEventQueue();
        composer.text.text = 'Second writing';
        unawaited(composer.flushDraft());
        harness.coordinator.rememberSequence(_replyTarget, 99);
        gate.complete();
        await saving;
        expect(harness.api.draftsSaved.map((save) => save['sequence']), [4, 5]);
        expect(composer.draftSequence, 6);
        expect(harness.coordinator.sequenceFor(_replyTarget), 99);
        expect(composer.draftConflict, isFalse);
      },
    );

    test(
      'protected draft repair uses an accepted save instead of a newer observation',
      () async {
        final harness = _Harness(cachedSequence: 4)
          ..cachedDraft = const ComposerDraft(reply: 'Protected original');
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'Replacement writing';
        harness.coordinator.startRestore(composer);
        expect(await harness.coordinator.finishRestore(composer), isTrue);
        expect(composer.hasUnappliedDraft, isTrue);
        await composer.flushDraft();
        harness.coordinator.rememberSequence(_replyTarget, 99);
        expect(await harness.coordinator.discard(composer), isNull);
        expect(harness.api.draftsSaved.map((save) => save['sequence']), [4, 5]);
        expect(
          ComposerDraft.decode(harness.api.draftsSaved.last['data'])!.reply,
          'Protected original',
        );
      },
    );

    test(
      'retired preservation cannot replace a new session recovery at the same address',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final retired = harness.open(_replyTarget).composer;
        retired.text.text = 'Older pending writing';
        harness.lifecycle.invalidate(_siteUrl);
        harness.coordinator.forgetSite(_siteUrl);
        harness.composers.remove(retired);
        final replacement = harness.open(_replyTarget);
        await replacement.session.stage(
          ComposerDraftSave(
            target: _replyTarget,
            draft: const ComposerDraft(reply: 'Replacement recovery'),
            sequence: 0,
            localOnly: true,
            isCurrent: () => true,
          ),
        );
        harness.coordinator.preservePendingLocally(retired);
        await harness.coordinator.localWritesSettled();
        expect(
          ComposerDraft.decodeLocal(
            harness.localStore.saved.values.single,
          )!.reply,
          'Replacement recovery',
        );
        retired.dispose();
      },
    );

    test(
      'retired conflict writing remains recoverable without a newer same-account writer',
      () async {
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'Original conflicting writing';
        await composer.flushDraft();
        composer.text.text = 'Pending conflicting writing';
        harness.lifecycle.invalidate(_siteUrl);
        harness.coordinator.forgetSite(_siteUrl);
        harness.coordinator.preservePendingLocally(composer);
        await harness.coordinator.localWritesSettled();
        final recovery = LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!;
        expect(recovery.draft.reply, 'Pending conflicting writing');
        expect(recovery.sequence, 4);
        expect(recovery.conflicted, isTrue);
      },
    );

    test(
      'a failed conflict marker reports local failure and the next edit repairs it',
      () async {
        final local = _FailingConflictMarkerStore();
        final harness = _Harness(
          localStore: local,
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'Original writing';
        await composer.flushDraft();
        expect(composer.draftConflict, isTrue);
        expect(composer.localDraftFailed, isTrue);
        expect(
          LocalComposerDraft.decode(local.saved.values.single)!.sequence,
          4,
        );
        composer.text.text = 'Repaired local writing';
        await composer.flushDraft();
        expect(composer.localDraftFailed, isFalse);
        expect(
          LocalComposerDraft.decode(local.saved.values.single)!.draft.reply,
          'Repaired local writing',
        );
        expect(
          LocalComposerDraft.decode(local.saved.values.single)!.conflicted,
          isTrue,
        );
        expect(harness.api.draftsSaved, hasLength(1));
      },
    );

    test(
      'a retired conflict protects the replacement composer newest writing',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftGate: gate,
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final retired = harness.open(_replyTarget).composer;
        retired.text.text = 'Older retired writing';
        final saving = retired.flushDraft();
        await pumpEventQueue();
        harness.coordinator.retire(retired);
        harness.composers.remove(retired);
        retired.dispose();
        final replacement = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(replacement);
        expect(await harness.coordinator.finishRestore(replacement), isTrue);
        replacement.text.text = 'Newest replacement writing';
        final replaced = replacement.flushDraft();
        await pumpEventQueue();
        gate.complete();
        await saving;
        await replaced;
        expect(harness.api.draftsSaved, hasLength(1));
        expect(replacement.draftConflict, isTrue);
        expect(replacement.draftStatus, DraftStatus.failing);
        final recovery = LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!;
        expect(recovery.draft.reply, 'Newest replacement writing');
        expect(recovery.sequence, 4);
        expect(recovery.conflicted, isTrue);
      },
    );

    test(
      'account retirement prevents a late conflict from touching the replacement',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftGate: gate,
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final retired = harness.open(_replyTarget).composer;
        retired.text.text = 'Old account writing';
        final saving = retired.flushDraft();
        await pumpEventQueue();
        harness.lifecycle.invalidate(_siteUrl);
        harness.coordinator.forgetSite(_siteUrl);
        harness.composers.remove(retired);
        retired.dispose();
        final replacement = harness.open(_replyTarget);
        await replacement.session.stage(
          ComposerDraftSave(
            target: _replyTarget,
            draft: const ComposerDraft(reply: 'New account recovery'),
            sequence: 4,
            localOnly: true,
            isCurrent: () => true,
          ),
        );
        gate.complete();
        await saving;
        expect(replacement.composer.draftConflict, isFalse);
        final recovery = LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!;
        expect(recovery.draft.reply, 'New account recovery');
        expect(recovery.conflicted, isFalse);
      },
    );

    test(
      'late conflict after accepted submission cannot recreate recovery',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftGate: gate,
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        composer.text.text = 'Submitted writing';
        final saving = composer.flushDraft();
        await pumpEventQueue();
        harness.coordinator.settleAfterSubmission(
          composer,
          harness.lifecycle.capture(_siteUrl),
        );
        gate.complete();
        await saving;
        expect(harness.localStore.saved, isEmpty);
        expect(composer.draftConflict, isFalse);
      },
    );

    test(
      'a late conflict in another tab cannot mark a submitted key conflicted',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftGate: gate,
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final submitted = harness.open(_replyTarget).composer;
        final other = harness.open(_replyTarget).composer;
        other.text.text = 'Other tab writing';
        final saving = other.flushDraft();
        await pumpEventQueue();
        expect(harness.api.draftsSaved, hasLength(1));
        harness.coordinator.settleAfterSubmission(
          submitted,
          harness.lifecycle.capture(_siteUrl),
        );
        gate.complete();
        await saving;
        harness.composers
          ..remove(submitted)
          ..remove(other);
        submitted.dispose();
        other.dispose();

        final reopened = harness.open(_replyTarget).composer;
        expect(reopened.draftConflict, isFalse);
        expect(harness.localStore.saved, isEmpty);
      },
    );

    test(
      'a stored conflict survives restart without a newer server sequence',
      () async {
        final harness = _Harness(cachedSequence: 4);
        addTearDown(harness.dispose);
        await harness.localStore.write(
          _siteUrl,
          'topic_7',
          const LocalComposerDraft(
            draft: ComposerDraft(reply: 'Conflicted writing'),
            sequence: 4,
            conflicted: true,
          ).encode(),
        );
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        expect(await harness.coordinator.finishRestore(composer), isTrue);
        expect(composer.text.text, 'Conflicted writing');
        expect(composer.draftConflict, isTrue);

        composer.text.text = 'Edited conflicted writing';
        await composer.flushDraft();
        expect(harness.api.draftsSaved, isEmpty);
      },
    );

    test(
      'a composer attached to a conflicted key shows the conflict',
      () async {
        final harness = _Harness(
          cachedSequence: 4,
          api: FakeDiscourseApi(
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final first = harness.open(_replyTarget).composer;
        first.text.text = 'Conflicting writing';
        await first.flushDraft();
        expect(first.draftConflict, isTrue);

        final second = harness.open(_replyTarget).composer;

        expect(second.draftConflict, isTrue);
      },
    );

    test(
      "discarding after another tab's conflict leaves the server copy",
      () async {
        final harness = _Harness(
          cachedSequence: 4,
          serverDraftKnown: true,
          api: FakeDiscourseApi(
            draftFailure: const WriteException(WriteFailure.conflict),
          ),
        );
        addTearDown(harness.dispose);
        final discarding = harness.open(_replyTarget).composer;
        harness.coordinator.startNewDraft(discarding);
        final other = harness.open(_replyTarget).composer;
        other.text.text = 'Other tab conflict';
        await other.flushDraft();
        expect(other.draftConflict, isTrue);
        expect(discarding.draftConflict, isFalse);

        expect(await harness.coordinator.discard(discarding), isNull);

        expect(discarding.isDisposed, isTrue);
        expect(harness.api.userDraftsDeleted, isEmpty);
        expect(harness.destroyed, isEmpty);
      },
    );
  });

  test(
    'draft save retains account scope and payload owner without migration header',
    () async {
      final api = _ScopedDraftApi();
      final harness = _Harness(api: api);
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;
      composer.text.text = 'Save this draft';
      await composer.flushDraft();
      expect(api.owner, 'client-id');
      expect(api.saves, 1);
      composer.text.clear();
      await composer.flushDraft();
      expect(api.deletes, 1);
    },
  );

  test('empty and metadata-only drafts are never saved', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final composer = harness.open(_newTopicTarget).composer;
    composer.title.text = '  ';
    composer.text.text = ' \n\t ';
    composer.setCategory(8);

    await composer.flushDraft();

    expect(harness.api.draftsSaved, isEmpty);
    expect(harness.api.userDraftsDeleted, isEmpty);
    expect(harness.localStore.saved, isEmpty);
    expect(
      harness.localStore.events.where((event) => event.startsWith('write:')),
      isEmpty,
    );
  });

  test(
    'clearing a saved draft deletes it instead of saving empty data',
    () async {
      final harness = _Harness(cachedSequence: 4, serverDraftKnown: true);
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;
      composer.text.text = 'Save before clearing';
      await composer.flushDraft();
      composer.text.text = ' \n ';

      await composer.flushDraft();

      expect(harness.api.draftsSaved, hasLength(1));
      expect(harness.api.userDraftsDeleted.single.sequence, 5);
      expect(harness.cachedDraft, isNull);
      expect(harness.localStore.saved, isEmpty);
      expect(
        harness.localStore.events.where((event) => event.startsWith('write:')),
        hasLength(1),
      );
      expect(composer.isDisposed, isFalse);
    },
  );

  test('an empty queued revision deletes after an in-flight save', () async {
    final gate = Completer<void>();
    final harness = _Harness(api: FakeDiscourseApi(draftGate: gate));
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      harness.dispose();
    });
    final composer = harness.open(_replyTarget).composer;
    composer.text.text = 'In-flight body';
    final saving = composer.flushDraft();
    await pumpEventQueue();
    expect(harness.api.draftsSaved, hasLength(1));
    composer.text.clear();
    final clearing = composer.flushDraft();
    await pumpEventQueue();
    expect(harness.localStore.saved, isEmpty);

    gate.complete();
    await saving;
    await clearing;

    expect(harness.api.draftsSaved, hasLength(1));
    expect(harness.api.userDraftsDeleted.single.sequence, 1);
    expect(harness.cachedDraft, isNull);
    expect(harness.localStore.saved, isEmpty);
    expect(
      harness.localStore.events.where((event) => event.startsWith('write:')),
      hasLength(1),
    );
  });

  test('empty local-only saves and disposal clear the local copy', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final (:composer, :session) = harness.open(_replyTarget);
    await harness.localStore.write(
      _siteUrl,
      _replyTarget.draftKey,
      const ComposerDraft(reply: 'Old local copy').encode(),
    );

    await session.save(
      ComposerDraftSave(
        target: _replyTarget,
        draft: const ComposerDraft(reply: ' '),
        sequence: 0,
        localOnly: true,
        isCurrent: () => true,
      ),
    );
    expect(harness.localStore.saved, isEmpty);
    expect(harness.api.draftsSaved, isEmpty);

    composer.text.text = 'Typed and removed';
    composer.text.clear();
    harness.coordinator.preservePendingLocally(composer);
    await pumpEventQueue();
    expect(harness.localStore.saved, isEmpty);
    expect(
      harness.localStore.events.where((event) => event.startsWith('write:')),
      hasLength(1),
    );
  });

  test('title-only drafts are saved', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final composer = harness.open(_newTopicTarget).composer;
    composer.title.text = 'A title to finish later';

    await composer.flushDraft();

    expect(
      ComposerDraft.decode(
        harness.api.draftsSaved.single['data'] as String,
      )?.title,
      'A title to finish later',
    );
  });

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

  group('listed topic drafts', () {
    test(
      'restores the selected draft without touching the legacy local draft',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        const unrelated = ComposerDraft(
          reply: 'Another unfinished topic',
          title: 'Legacy local draft',
          action: ComposerDraft.createTopicAction,
        );
        await harness.localStore.write(
          _siteUrl,
          ComposerDraft.newTopicDraftKey,
          unrelated.encode(),
        );
        final composer = harness.open(_listedTopicTarget).composer;

        harness.coordinator.startRestore(
          composer,
          listedDraft: _listedTopicDraft,
        );
        expect(await harness.coordinator.finishRestore(composer), isTrue);

        expect(composer.text.text, _listedTopicDraft.data!.reply);
        expect(composer.title.text, _listedTopicDraft.data!.title);
        expect(composer.draftSequence, 4);
        expect(
          await harness.localStore.read(
            _siteUrl,
            ComposerDraft.newTopicDraftKey,
          ),
          unrelated.encode(),
        );
      },
    );

    for (final local in [false, true]) {
      test(
        'prefers newer ${local ? 'local' : 'server'} text to the list',
        () async {
          const newer = ComposerDraft(
            reply: 'Newer topic body',
            title: 'Newer topic title',
            action: ComposerDraft.createTopicAction,
            categoryId: 8,
          );
          final api = FakeDiscourseApi(
            draftToRestore: const (draft: newer, sequence: 9),
          );
          final harness = _Harness(api: api);
          addTearDown(harness.dispose);
          if (local) {
            await harness.localStore.write(
              _siteUrl,
              _listedTopicDraft.key,
              newer.encode(),
            );
          }
          final composer = harness.open(_listedTopicTarget).composer;

          harness.coordinator.startRestore(
            composer,
            listedDraft: _listedTopicDraft,
          );
          expect(await harness.coordinator.finishRestore(composer), isTrue);

          expect(composer.text.text, newer.reply);
          expect(composer.title.text, newer.title);
          expect(composer.categoryId, 8);
          expect(composer.draftSequence, local ? 0 : 9);
          expect(
            api.draftsRequested.map((request) => request.draftKey),
            local ? isEmpty : [_listedTopicDraft.key],
          );
        },
      );
    }

    test(
      'does not apply the list snapshot over changes during restoration',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(api: FakeDiscourseApi(draftRestoreGate: gate));
        addTearDown(harness.dispose);
        final composer = harness.open(_listedTopicTarget).composer;
        harness.coordinator.startRestore(
          composer,
          listedDraft: _listedTopicDraft,
        );
        await pumpEventQueue();
        composer.setCategory(8);

        gate.complete();
        expect(await harness.coordinator.finishRestore(composer), isTrue);

        expect(composer.text.text, isEmpty);
        expect(composer.title.text, isEmpty);
        expect(composer.categoryId, 8);
        expect(composer.draftSequence, 4);
      },
    );

    test(
      'does not resurrect a listed draft deleted during restoration',
      () async {
        final localStore = _GatedReadStore();
        final harness = _Harness(localStore: localStore);
        addTearDown(harness.dispose);
        final composer = harness.open(_listedTopicTarget).composer;
        harness.coordinator.startRestore(
          composer,
          listedDraft: _listedTopicDraft,
        );
        await localStore.started.future;

        await harness.coordinator.deleteListedDraft(
          _siteUrl,
          _listedTopicDraft,
          () => true,
        );
        localStore.gate.complete();
        expect(await harness.coordinator.finishRestore(composer), isTrue);

        expect(composer.text.text, isEmpty);
        expect(composer.title.text, isEmpty);
      },
    );
  });

  group('listed reply drafts', () {
    test(
      'an open composer settles its own restore before taking the row',
      () async {
        const newer = ComposerDraft(reply: 'Newer local reply');
        final localStore = _GatedReadStore();
        await localStore.write(_siteUrl, _listedDraft.key, newer.encode());
        final harness = _Harness(cachedSequence: 2, localStore: localStore);
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        await localStore.started.future;

        final offered = harness.coordinator.restoreListedDraft(
          composer,
          _listedDraft,
        );
        localStore.gate.complete();
        await offered;

        expect(composer.text.text, newer.reply);
        expect(composer.draftSequence, 0);
      },
    );

    test(
      'an open composer that cannot read its local copy withholds the row',
      () async {
        final harness = _Harness(
          cachedSequence: 2,
          localStore: _FailingReadStore(),
        );
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);

        await harness.coordinator.restoreListedDraft(composer, _listedDraft);

        expect(composer.text.text, isEmpty);
        expect(
          composer.notice,
          "Couldn't check for an existing draft. Try again.",
        );
      },
    );

    for (final (label, postNumber, username) in [
      ('another post', 3, 'sam'),
      ('the topic', null, null),
    ]) {
      test('a newer local copy replying to $label keeps its target', () async {
        const listed = UserDraft(
          key: 'topic_7',
          sequence: 4,
          data: ComposerDraft(
            reply: 'Listed reply',
            replyToPostNumber: 5,
            replyToUsername: 'alex',
          ),
        );
        final newer = ComposerDraft(
          reply: 'Newer local reply',
          replyToPostNumber: postNumber,
          replyToUsername: username,
        );
        final harness = _Harness(cachedSequence: 2);
        addTearDown(harness.dispose);
        await harness.localStore.write(_siteUrl, listed.key, newer.encode());
        final composer = harness
            .open(_replyTarget.replyingTo(5, 'alex'))
            .composer;

        harness.coordinator.startRestore(composer, listedDraft: listed);
        expect(await harness.coordinator.finishRestore(composer), isTrue);

        expect(composer.text.text, newer.reply);
        expect(composer.target.replyToPostNumber, postNumber);
        expect(composer.target.replyToUsername, username);
        expect(composer.draftPersistencePending, isFalse);
      });
    }

    test('a newer copy replying to the row\'s whisper keeps it one', () async {
      const listed = UserDraft(
        key: 'topic_7',
        sequence: 4,
        data: ComposerDraft(
          reply: 'Listed reply',
          replyToPostNumber: 5,
          replyToUsername: 'alex',
          whisper: true,
        ),
      );
      const newer = ComposerDraft(
        reply: 'Newer local reply',
        replyToPostNumber: 5,
        replyToUsername: 'alex',
        whisper: true,
      );
      final harness = _Harness(cachedSequence: 2);
      addTearDown(harness.dispose);
      await harness.localStore.write(_siteUrl, listed.key, newer.encode());
      final composer = harness
          .open(_replyTarget.replyingTo(5, 'alex', replyingToWhisper: true))
          .composer;

      harness.coordinator.startRestore(composer, listedDraft: listed);
      expect(await harness.coordinator.finishRestore(composer), isTrue);

      expect(composer.text.text, newer.reply);
      expect(composer.target.replyToPostNumber, 5);
      expect(composer.target.replyingToWhisper, isTrue);
      expect(composer.whisper, isTrue);
    });

    test('a row saved under another key is not restored', () async {
      const otherTopic = UserDraft(
        key: 'topic_8',
        sequence: 6,
        data: ComposerDraft(reply: 'Reply to another topic'),
      );
      final harness = _Harness(cachedSequence: 2);
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;

      harness.coordinator.startRestore(composer, listedDraft: otherTopic);
      expect(await harness.coordinator.finishRestore(composer), isTrue);

      expect(composer.text.text, isEmpty);
      expect(composer.draftSequence, 2);
    });

    test('the cached topic draft outranks an older row', () async {
      final harness = _Harness(cachedSequence: 6)
        ..cachedDraft = const ComposerDraft(reply: 'Cached newer reply');
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;

      harness.coordinator.startRestore(composer, listedDraft: _listedDraft);
      expect(await harness.coordinator.finishRestore(composer), isTrue);

      expect(composer.text.text, 'Cached newer reply');
      expect(composer.draftSequence, 6);
    });

    test(
      'a row offered before the account changes is not applied after it',
      () async {
        final localStore = _GatedReadStore();
        final harness = _Harness(cachedSequence: 2, localStore: localStore);
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        await localStore.started.future;

        final offered = harness.coordinator.restoreListedDraft(
          composer,
          _listedDraft,
        );
        harness.lifecycle.invalidate(_siteUrl);
        localStore.gate.complete();
        await offered;

        expect(composer.text.text, isEmpty);
        expect(composer.draftSequence, 2);
      },
    );

    test(
      'an open composer that keeps its own writing still learns the row sequence',
      () async {
        final harness = _Harness(cachedSequence: 2);
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        expect(await harness.coordinator.finishRestore(composer), isTrue);
        composer.text.text = 'Writing in progress';

        await harness.coordinator.restoreListedDraft(composer, _listedDraft);

        expect(composer.text.text, 'Writing in progress');
        expect(harness.coordinator.sequenceFor(_replyTarget), 4);
      },
    );
  });

  group('retargeting while the draft is restored', () {
    const offline = ComposerDraft(
      reply: 'Written offline',
      replyToPostNumber: 3,
      replyToUsername: 'sam',
    );

    test('restores the local text under the newer reply target', () async {
      final localStore = _GatedReadStore();
      await localStore.write(_siteUrl, 'topic_7', offline.encode());
      final harness = _Harness(cachedSequence: 2, localStore: localStore);
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;
      harness.coordinator.startRestore(composer);
      await localStore.started.future;

      composer.retarget(replyToPostNumber: 5, replyToUsername: 'alex');
      localStore.gate.complete();
      expect(await harness.coordinator.finishRestore(composer), isTrue);

      expect(composer.text.text, offline.reply);
      expect(composer.target.replyToPostNumber, 5);
      expect(composer.target.replyToUsername, 'alex');
      expect(composer.draftPersistencePending, isFalse);
      expect(await localStore.read(_siteUrl, 'topic_7'), offline.encode());

      await composer.flushDraft();
      final saved = ComposerDraft.decode(
        harness.api.draftsSaved.single['data'],
      );
      expect(saved?.reply, offline.reply);
      expect(saved?.replyToPostNumber, 5);
    });

    test(
      'a composer replaced before the copy is read leaves it alone',
      () async {
        final localStore = _GatedReadStore();
        await localStore.write(_siteUrl, 'topic_7', offline.encode());
        final harness = _Harness(cachedSequence: 2, localStore: localStore);
        addTearDown(harness.dispose);
        final replaced = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(replaced);
        await localStore.started.future;

        replaced.retarget(replyToPostNumber: 5, replyToUsername: 'alex');
        harness.coordinator.retire(replaced);
        replaced.dispose();
        harness.composers.remove(replaced);
        final other = harness
            .open(
              const ReplyComposerTarget(
                privateMessageTopic: false,
                siteUrl: _siteUrl,
                topicId: 8,
                slug: 'another-topic',
                topicTitle: 'Another topic',
              ),
            )
            .composer;
        harness.coordinator.startRestore(other);
        localStore.gate.complete();
        expect(await harness.coordinator.finishRestore(other), isTrue);
        await pumpEventQueue();

        expect(other.text.text, isEmpty);
        expect(harness.api.draftsSaved, isEmpty);
        expect(await localStore.read(_siteUrl, 'topic_7'), offline.encode());
      },
    );

    test('a composer opened on a post keeps it over the copy', () async {
      final harness = _Harness(cachedSequence: 2);
      addTearDown(harness.dispose);
      await harness.localStore.write(_siteUrl, 'topic_7', offline.encode());
      final composer = harness
          .open(_replyTarget.replyingTo(5, 'alex'))
          .composer;

      harness.coordinator.startRestore(composer);
      expect(await harness.coordinator.finishRestore(composer), isTrue);

      expect(composer.text.text, offline.reply);
      expect(composer.target.replyToPostNumber, 5);
      expect(composer.target.replyToUsername, 'alex');
    });
  });

  test('forgetting a site releases coordinator-owned sequence state', () {
    final harness = _Harness(cachedSequence: 4);
    addTearDown(harness.dispose);
    harness.coordinator.rememberSequence(_replyTarget, 9);
    expect(harness.coordinator.sequenceFor(_replyTarget), 9);

    harness.coordinator.forgetSite(_siteUrl);

    expect(harness.coordinator.sequenceFor(_replyTarget), 4);
  });

  test('a forgotten save cannot clear a replacement recovery copy', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final harness = _Harness(
      cachedSequence: 4,
      api: FakeDiscourseApi(draftGate: gate),
    );
    addTearDown(harness.dispose);
    final first = harness.open(_replyTarget);
    final saving = first.session.save(
      ComposerDraftSave(
        target: _replyTarget,
        draft: const ComposerDraft(reply: 'Earlier save'),
        sequence: 4,
        localOnly: false,
        isCurrent: () => true,
      ),
    );
    await pumpEventQueue();
    expect(harness.api.draftsSaved, hasLength(1));

    harness.coordinator.forgetSite(_siteUrl);
    final replacement = harness.open(_replyTarget);
    await replacement.session.save(
      ComposerDraftSave(
        target: _replyTarget,
        draft: const ComposerDraft(reply: 'Replacement recovery'),
        sequence: 4,
        localOnly: true,
        isCurrent: () => true,
      ),
    );
    gate.complete();
    expect(await saving, 5);

    expect(harness.cachedDraft, isNull);
    expect(harness.coordinator.sequenceFor(_replyTarget), 5);
    expect(
      ComposerDraft.decode(
        await harness.localStore.read(_siteUrl, 'topic_7'),
      )?.reply,
      'Replacement recovery',
    );
  });

  for (final restored in [false, true]) {
    test(
      'repeated saves preserve cached-count accounting for a ${restored ? 'restored' : 'new'} draft',
      () async {
        final harness = _Harness(cachedSequence: 4)
          ..cachedDraft = restored ? _listedDraft.data : null;
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        expect(await harness.coordinator.finishRestore(composer), isTrue);

        composer.text.text = 'First saved edit';
        await composer.flushDraft();
        composer.text.text = 'Second saved edit';
        await composer.flushDraft();
        composer.text.clear();
        await composer.flushDraft();

        expect(harness.api.draftsSaved, hasLength(2));
        expect(harness.api.userDraftsDeleted, hasLength(1));
        expect(harness.destroyed, [
          (siteUrl: _siteUrl, draftKey: 'topic_7', knownToExist: restored),
        ]);
      },
    );
  }

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

  test(
    "a replacement waits out a retired save and survives that save's failure",
    () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final harness = _Harness(
        api: FakeDiscourseApi(
          draftGate: gate,
          draftFailure: const WriteException(WriteFailure.unreachable),
        ),
      );
      addTearDown(harness.dispose);
      final retired = harness.open(_replyTarget).composer;
      retired.text.text = 'Retired reply';
      unawaited(retired.flushDraft());
      await pumpEventQueue();
      expect(harness.api.draftsSaved, hasLength(1));
      harness.coordinator.retire(retired);
      harness.composers.remove(retired);
      retired.dispose();

      final replacement = harness.open(_replyTarget).composer;
      var settled = false;
      final waiting = harness.coordinator
          .finishRetiredSaves(replacement)
          .then((_) => settled = true);
      await pumpEventQueue();
      expect(settled, isFalse);

      gate.complete();
      await waiting;
      expect(settled, isTrue);
    },
  );

  test(
    "a retired composer's late save cannot replace its replacement's local copy",
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final retired = harness.open(_replyTarget);
      harness.composers.remove(retired.composer);
      retired.composer.dispose();
      final replacement = harness.open(_replyTarget);

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

      await save(replacement.session, 'Replacement writing');
      await save(retired.session, 'Retired writing');

      expect(
        ComposerDraft.decode(harness.localStore.saved.values.single)?.reply,
        'Replacement writing',
      );
    },
  );

  test(
    "a replacement's save reaches the site after a retired composer's last save",
    () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final harness = _Harness(api: FakeDiscourseApi(draftGate: gate));
      addTearDown(harness.dispose);
      final retired = harness.open(_replyTarget).composer;
      addTearDown(retired.dispose);
      retired.text.text = 'Retired first';
      final saving = retired.flushDraft();
      await pumpEventQueue();
      expect(harness.api.draftsSaved, hasLength(1));
      retired.text.text = 'Retired second';
      harness.coordinator.retire(retired);
      harness.composers.remove(retired);

      final replacement = harness.open(_replyTarget).composer;
      replacement.text.text = 'Replacement';
      final replaced = replacement.flushDraft();
      await pumpEventQueue();
      gate.complete();
      await saving;
      await replaced;
      await harness.coordinator.finishRetiredSaves(replacement);

      expect(
        harness.api.draftsSaved.map(
          (save) => ComposerDraft.decode(save['data'])!.reply,
        ),
        ['Retired first', 'Retired second', 'Replacement'],
      );
    },
  );

  test(
    'submitting a restored draft that was never saved again clears its recovery',
    () async {
      final harness = _Harness(cachedSequence: 4);
      addTearDown(harness.dispose);
      await harness.localStore.write(
        _siteUrl,
        'topic_7',
        const LocalComposerDraft(
          draft: ComposerDraft(reply: 'Recovered reply'),
          sequence: 4,
        ).encode(),
      );
      final composer = harness.open(_replyTarget).composer;
      harness.coordinator.startRestore(composer);
      expect(await harness.coordinator.finishRestore(composer), isTrue);
      expect(composer.text.text, 'Recovered reply');

      harness.coordinator.settleAfterSubmission(
        composer,
        harness.lifecycle.capture(_siteUrl),
        sequence: 5,
      );
      await pumpEventQueue();

      expect(harness.localStore.saved, isEmpty);
      expect(composer.draftSequence, 5);
    },
  );

  test(
    'a submission settled after the account changed leaves recovery alone',
    () async {
      final harness = _Harness(cachedSequence: 4);
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;
      final lease = harness.lifecycle.capture(_siteUrl);
      harness.lifecycle.invalidate(_siteUrl);
      await harness.localStore.write(
        _siteUrl,
        'topic_7',
        const LocalComposerDraft(
          draft: ComposerDraft(reply: 'Next account recovery'),
          sequence: 0,
        ).encode(),
      );

      harness.coordinator.settleAfterSubmission(composer, lease);
      await pumpEventQueue();

      expect(
        LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!.draft.reply,
        'Next account recovery',
      );
    },
  );

  test(
    'a preserved write still pending at submission does not recreate recovery',
    () async {
      final localStore = _GatedWriteStore();
      final harness = _Harness(cachedSequence: 4, localStore: localStore);
      addTearDown(harness.dispose);
      final composer = harness.open(_replyTarget).composer;
      composer.text.text = 'Submitted writing';
      harness.coordinator.preservePendingLocally(composer);
      await localStore.started.future;

      harness.coordinator.settleAfterSubmission(
        composer,
        harness.lifecycle.capture(_siteUrl),
      );
      localStore.gate.complete();
      await harness.coordinator.localWritesSettled();

      expect(harness.localStore.saved, isEmpty);
    },
  );

  for (final restored in [false, true]) {
    test(
      'discarding a saved ${restored ? 'restored' : 'new'} draft preserves cached-count accounting',
      () async {
        final harness = _Harness(cachedSequence: 4)
          ..cachedDraft = restored ? _listedDraft.data : null;
        addTearDown(harness.dispose);
        final composer = harness.open(_replyTarget).composer;
        harness.coordinator.startRestore(composer);
        expect(await harness.coordinator.finishRestore(composer), isTrue);
        composer.text.text = 'Saved before discarding';
        await composer.flushDraft();

        expect(await harness.coordinator.discard(composer), isNull);

        expect(harness.api.userDraftsDeleted, hasLength(1));
        expect(harness.destroyed, [
          (siteUrl: _siteUrl, draftKey: 'topic_7', knownToExist: restored),
        ]);
      },
    );
  }

  test(
    'discarding over a protected local copy puts it back after a failed save',
    () async {
      final harness = _Harness(
        cachedSequence: 4,
        api: FakeDiscourseApi(
          draftFailure: const WriteException(WriteFailure.unreachable),
        ),
      );
      addTearDown(harness.dispose);
      await harness.localStore.write(
        _siteUrl,
        'topic_7',
        const LocalComposerDraft(
          draft: ComposerDraft(reply: 'Protected local copy'),
          sequence: 4,
        ).encode(),
      );
      final composer = harness.open(_replyTarget).composer;
      composer.text.text = 'Replacement writing';
      harness.coordinator.startRestore(composer);
      expect(await harness.coordinator.finishRestore(composer), isTrue);
      expect(composer.hasUnappliedDraft, isTrue);
      await composer.flushDraft();
      expect(
        LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!.draft.reply,
        'Replacement writing',
      );

      expect(await harness.coordinator.discard(composer), isNull);

      expect(composer.isDisposed, isTrue);
      expect(harness.api.userDraftsDeleted, isEmpty);
      expect(
        LocalComposerDraft.decode(
          harness.localStore.saved.values.single,
        )!.draft.reply,
        'Protected local copy',
      );
    },
  );

  test('a local copy exactly at the storage limit restores', () async {
    final overhead = const ComposerDraft(reply: '').encode().length;
    final reply = 'x' * (ComposerDraft.maximumLocalEncodedCodeUnits - overhead);
    final encoded = ComposerDraft(reply: reply).encodeLocal();
    expect(encoded, hasLength(ComposerDraft.maximumLocalEncodedCodeUnits));
    final harness = _Harness(cachedSequence: 2);
    addTearDown(harness.dispose);
    await harness.localStore.write(_siteUrl, 'topic_7', encoded);
    final composer = harness.open(_replyTarget).composer;

    harness.coordinator.startRestore(composer);
    expect(await harness.coordinator.finishRestore(composer), isTrue);

    expect(composer.text.text == reply, isTrue);
  });
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
        ComposerDraft.decodeLocal(
          await localStore.read(_siteUrl, _listedDraft.key),
        ),
        replacement,
      );
      localStore.gate.complete();
      await deletion;
      await save;
      expect(
        ComposerDraft.decodeLocal(
          await localStore.read(_siteUrl, _listedDraft.key),
        ),
        replacement,
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

    test('a row older than the cached topic draft is not deleted', () async {
      const newer = ComposerDraft(reply: 'Newer cached reply');
      final harness = _Harness(cachedSequence: 6)..cachedDraft = newer;
      addTearDown(harness.dispose);
      await harness.localStore.write(_siteUrl, _listedDraft.key, 'recovery');

      await expectLater(
        harness.coordinator.deleteListedDraft(
          _siteUrl,
          _listedDraft,
          () => true,
        ),
        throwsA(isA<WriteException>()),
      );

      expect(harness.api.userDraftsDeleted, isEmpty);
      expect(harness.cachedDraft, newer);
      expect(
        await harness.localStore.read(_siteUrl, _listedDraft.key),
        'recovery',
      );
    });

    for (final staged in [false, true]) {
      test(
        'a retired ${staged ? 'stage' : 'save'} still writing locally cannot '
        'recreate a deleted generation',
        () async {
          final deleteGate = Completer<void>();
          final localStore = _GatedWriteStore();
          final harness = _Harness(
            cachedSequence: 4,
            localStore: localStore,
            api: FakeDiscourseApi(draftDeleteGate: deleteGate),
          );
          addTearDown(harness.dispose);
          final retired = harness.open(_replyTarget);
          harness.composers.remove(retired.composer);
          retired.composer.dispose();
          final deletion = harness.coordinator.deleteListedDraft(
            _siteUrl,
            _listedDraft,
            () => true,
          );
          await pumpEventQueue();
          expect(harness.api.userDraftsDeleted, hasLength(1));

          final save = ComposerDraftSave(
            target: _replyTarget,
            draft: _listedDraft.data!,
            sequence: 4,
            localOnly: true,
            isCurrent: () => true,
          );
          final writing = staged
              ? retired.session.stage(save)
              : retired.session.save(save);
          await localStore.started.future;
          deleteGate.complete();
          await deletion;
          localStore.gate.complete();
          await writing;

          expect(harness.localStore.saved, isEmpty);
        },
      );
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
      credentials: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
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

final class _FailingReadStore extends FakeDraftStore {
  @override
  Future<String?> read(String siteUrl, String draftKey) =>
      Future.error(const DraftWriteException());
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

final class _ScopedDraftApi extends FakeDiscourseApi {
  String? owner;
  int saves = 0;
  int deletes = 0;

  void validate(String siteUrl, String apiKey, String? clientId) {
    expect(AccountRequestScope.current, isNotNull);
    AccountRequestScope.current!.validate(siteUrl, apiKey, clientId);
    expect(clientId, isNull);
  }

  @override
  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  }) {
    validate(siteUrl, apiKey, clientId);
    this.owner = owner;
    saves++;
    return super.saveDraft(
      siteUrl: siteUrl,
      apiKey: apiKey,
      draftKey: draftKey,
      sequence: sequence,
      data: data,
      owner: owner,
      clientId: clientId,
    );
  }

  @override
  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  }) {
    validate(siteUrl, apiKey, clientId);
    deletes++;
    return super.deleteUserDraft(
      siteUrl: siteUrl,
      apiKey: apiKey,
      draftKey: draftKey,
      sequence: sequence,
      clientId: clientId,
    );
  }
}

final class _FailingConflictMarkerStore extends FakeDraftStore {
  bool fail = true;

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (fail && LocalComposerDraft.decode(data)?.conflicted == true) {
      fail = false;
      throw const DraftWriteException();
    }
    await super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}
