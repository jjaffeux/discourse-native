import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
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
}

final class _Harness {
  _Harness({
    this.cachedSequence = 0,
    this.serverDraftKnown = false,
    FakeDiscourseApi? api,
  }) : api = api ?? FakeDiscourseApi() {
    coordinator = ComposerDraftCoordinator(
      localStore: localStore,
      persistence: this.api,
      draftsApi: this.api,
      lifecycle: lifecycle,
      readCredential: (_) async => (apiKey: 'api-key', failure: null),
      readClientId: () async => 'client-id',
      isDisposed: () => disposed,
      isCurrentComposer: (composer) => identical(activeComposer, composer),
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
        if (identical(activeComposer, composer)) activeComposer = null;
      },
      reportError: (error, stackTrace, operation) {
        errors.add((error: error, operation: operation));
      },
    );
  }

  final FakeDiscourseApi api;
  final FakeDraftStore localStore = FakeDraftStore();
  final SiteLifecycle lifecycle = SiteLifecycle();
  final bool serverDraftKnown;
  late final ComposerDraftCoordinator coordinator;
  final List<({String siteUrl, String draftKey, bool knownToExist})> destroyed =
      [];
  final List<({Object error, String operation})> errors = [];
  ComposerController? activeComposer;
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
    coordinator.attach(session, composer);
    return (composer: composer, session: session);
  }

  void dispose() {
    disposed = true;
    final composer = activeComposer;
    if (composer != null && !composer.isDisposed) composer.dispose();
    activeComposer = null;
  }
}
