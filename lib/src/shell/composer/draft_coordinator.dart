// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';

import '../../data/account_request_session.dart';
import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/draft_store.dart';
import '../../data/site_lifecycle.dart';
import '../../models/composer_draft.dart';
import '../../models/user_draft.dart';
import 'controller.dart';

typedef _DraftCredential = ({
  AccountRequestCredentials? request,
  WriteException? failure,
});
typedef ComposerDraftCacheReader =
    ComposerDraft? Function(ComposerTarget target);
typedef ComposerDraftSequenceReader = int Function(ComposerTarget target);
typedef ComposerDraftCacheWriter =
    void Function(ComposerTarget target, ComposerDraft? draft, int sequence);
typedef ComposerDraftDestroyedCallback =
    void Function(
      String siteUrl,
      String draftKey, {
      required bool knownToExist,
    });

typedef _DraftSessionKey = ({String siteUrl, String draftKey, Object session});

enum _DraftServerPresence { unknown, createdAfterCachedCount, observed }

final class _DraftKeyState {
  int? latestGeneration;
  _RetiredDraftSaves? retiredSaves;
  Object? saveRequest;
  Future<void>? operationTail;
  Future<void>? listedDeletion;
  int? deletedGeneration;
  _DraftServerPresence _serverPresence = _DraftServerPresence.unknown;

  bool get knownOnServer => _serverPresence != _DraftServerPresence.unknown;
  bool get createdAfterCachedCount =>
      _serverPresence == _DraftServerPresence.createdAfterCachedCount;

  void observeServerDraft() {
    _serverPresence = _DraftServerPresence.observed;
  }

  void savedOnServer() {
    if (_serverPresence == _DraftServerPresence.unknown) {
      _serverPresence = _DraftServerPresence.createdAfterCachedCount;
    }
  }

  void forgetServerDraft() {
    _serverPresence = _DraftServerPresence.unknown;
  }
}

/// Owns the persistence lifecycle for composer drafts.
///
/// Navigation and presentation remain in the shell. This coordinator receives
/// narrow callbacks for the shell-owned cache and active composer so draft
/// ordering can be tested without coupling persistence to the whole shell.
final class ComposerDraftCoordinator {
  ComposerDraftCoordinator({
    required DraftStore localStore,
    String Function(String siteUrl)? localDraftSite,
    required ComposerPersistenceApi persistence,
    required DraftsApi draftsApi,
    required SiteLifecycle lifecycle,
    required SiteApiKeyReader credentials,
    required Future<String> Function() readClientId,
    required bool Function() isDisposed,
    required bool Function(ComposerController composer) isCurrentComposer,
    required ComposerDraftCacheReader readCachedDraft,
    required ComposerDraftSequenceReader readCachedSequence,
    required ComposerDraftCacheWriter writeCachedDraft,
    required int Function(String siteUrl, int? categoryId)
    minimumRequiredTagsFor,
    required bool Function(ComposerTarget target) isServerDraftKnown,
    required ComposerDraftDestroyedCallback recordDraftDestroyed,
    required void Function(ComposerController composer) onComposerClosed,
  }) : _localStore = localStore,
       _localDraftSite = localDraftSite ?? ((siteUrl) => siteUrl),
       _persistence = persistence,
       _draftsApi = draftsApi,
       _lifecycle = lifecycle,
       _credentials = credentials,
       _readClientId = readClientId,
       _isDisposed = isDisposed,
       _isCurrentComposer = isCurrentComposer,
       _readCachedDraft = readCachedDraft,
       _readCachedSequence = readCachedSequence,
       _writeCachedDraft = writeCachedDraft,
       _minimumRequiredTagsFor = minimumRequiredTagsFor,
       _isServerDraftKnown = isServerDraftKnown,
       _recordDraftDestroyed = recordDraftDestroyed,
       _onComposerClosed = onComposerClosed;

  final DraftStore _localStore;
  final String Function(String siteUrl) _localDraftSite;
  final ComposerPersistenceApi _persistence;
  final DraftsApi _draftsApi;
  final SiteLifecycle _lifecycle;
  final SiteApiKeyReader _credentials;
  final Future<String> Function() _readClientId;
  final bool Function() _isDisposed;
  final bool Function(ComposerController composer) _isCurrentComposer;
  final ComposerDraftCacheReader _readCachedDraft;
  final ComposerDraftSequenceReader _readCachedSequence;
  final ComposerDraftCacheWriter _writeCachedDraft;
  final int Function(String siteUrl, int? categoryId) _minimumRequiredTagsFor;
  final bool Function(ComposerTarget target) _isServerDraftKnown;
  final ComposerDraftDestroyedCallback _recordDraftDestroyed;
  final void Function(ComposerController composer) _onComposerClosed;

  final Expando<ComposerDraftSession> _sessions = Expando();
  final Expando<Future<bool>> _restoreTasks = Expando();
  final Map<ComposerController, Future<String?>> _discardTasks = {};
  final Map<_DraftSessionKey, _DraftKeyState> _draftStates = {};
  final Map<String, int> _sequences = {};
  int _generation = 0;

  /// Local copies still being written. Each settles without an error: the
  /// save or stage that started it owns the failure.
  final Set<Future<void>> _localWrites = {};

  ComposerDraftSession openSession(ComposerTarget target) =>
      ComposerDraftSession._(
        this,
        _lifecycle.capture(target.siteUrl),
        ++_generation,
        _localDraftSite(target.siteUrl),
      );

  void attach(ComposerDraftSession session, ComposerController composer) {
    _sessions[composer] = session;
    session._composer = composer;
    composer.draftSequence = sequenceFor(composer.target);
  }

  int sequenceFor(ComposerTarget target) =>
      _sequences[_sequenceKey(target.siteUrl, target.draftKey)] ??
      _readCachedSequence(target);

  void rememberSequence(ComposerTarget target, int sequence) {
    _sequences[_sequenceKey(target.siteUrl, target.draftKey)] = sequence;
  }

  /// Offers a list row to a composer that was already open under its key. A
  /// composer opened for the row takes it through [startRestore] instead.
  Future<void> restoreListedDraft(
    ComposerController composer,
    UserDraft draft,
  ) async {
    final target = composer.target;
    final data = draft.data;
    if (data == null ||
        !composer.canSaveDraft ||
        target.draftKey != draft.key) {
      return;
    }
    final lease = _lifecycle.capture(target.siteUrl);
    // The row can predate a save this composer has already committed.
    composer.draftSequence = _commitSequence(
      target,
      draft.sequence,
      fallback: composer.draftSequence,
    );
    // A restore still reading the local or cached copy ranks that copy above
    // the row, but gives it up if the row's text lands first. One that could
    // not read the local copy cannot rule it out, so the row is withheld, as
    // it is from a composer opened for it.
    if (!await finishRestore(composer) ||
        !lease.isCurrent ||
        composer.discarding ||
        composer.closing) {
      return;
    }
    composer.restore(data);
  }

  Future<bool>? restoreTaskFor(ComposerController composer) =>
      _restoreTasks[composer];

  Future<void> deleteListedDraft(
    String siteUrl,
    UserDraft draft,
    bool Function() requestIsCurrent,
  ) {
    final lease = _lifecycle.capture(siteUrl);
    final localSite = _localDraftSite(siteUrl);
    final key = (siteUrl: siteUrl, draftKey: draft.key, session: lease.session);
    final generation = _generation;
    final recoveryGeneration = _draftStates[key]?.latestGeneration;
    bool isCurrent() => !_isDisposed() && lease.isCurrent && requestIsCurrent();
    bool ownsRecovery() =>
        isCurrent() &&
        _draftStates[key]?.latestGeneration == recoveryGeneration;

    final task = () async {
      // A retired controller may still have a second save to enqueue. Drain
      // it before joining the same queue, without holding up its own saves.
      await _draftStates[key]?.retiredSaves?.task;
      if (!isCurrent()) return;
      await _serialize<void>(key, () async {
        if (!isCurrent()) return;
        final credential = await _readCredential(siteUrl, lease);
        if (!isCurrent()) return;
        if (credential.failure case final failure?) throw failure;

        final topicId = draft.key.startsWith('topic_')
            ? int.tryParse(draft.key.substring('topic_'.length))
            : null;
        final target = topicId != null && draft.key == 'topic_$topicId'
            ? ReplyComposerTarget(
                privateMessageTopic: false,
                siteUrl: siteUrl,
                topicId: topicId,
                slug: '',
                topicTitle: '',
              )
            : null;
        final sequenceKey = _sequenceKey(siteUrl, draft.key);
        final sequence = _sequences[sequenceKey] ?? 0;
        if (sequence > draft.sequence ||
            (target != null && _readCachedSequence(target) > draft.sequence)) {
          throw const WriteException(WriteFailure.validation);
        }
        await credential.request!.run(
          () => _draftsApi.deleteUserDraft(
            siteUrl: siteUrl,
            apiKey: credential.request!.apiKey!,
            draftKey: draft.key,
            sequence: draft.sequence,
          ),
        );
        if (!isCurrent()) return;
        final cleared = await _localStore.clearChecked(
          localSite,
          draft.key,
          ifCurrent: ownsRecovery,
        );
        if (!isCurrent()) return;
        if (!cleared && ownsRecovery()) throw const DraftWriteException();

        if (target != null && _readCachedSequence(target) <= draft.sequence) {
          _writeCachedDraft(target, null, draft.sequence);
        }
        if (!isCurrent()) return;
        _sequences.update(
          sequenceKey,
          (sequence) => sequence > draft.sequence ? sequence : draft.sequence,
          ifAbsent: () => draft.sequence,
        );
        if (target != null) {
          _commitSequence(target, _readCachedSequence(target));
        }
        _draftStates[key]?.forgetServerDraft();
        // Saves which had not reached the queue must not recreate this
        // snapshot. A current composer can claim a newer generation as usual.
        _stateFor(key).deletedGeneration = generation;
        if (ownsRecovery()) _stateFor(key).latestGeneration = ++_generation;
      });
    }();
    _stateFor(key).listedDeletion = task;
    void finished() {
      final state = _draftStates[key];
      if (identical(state?.listedDeletion, task)) {
        state!.listedDeletion = null;
      }
    }

    unawaited(
      task.then(
        (_) => finished(),
        onError: (Object _, StackTrace _) => finished(),
      ),
    );
    return task;
  }

  void startRestore(ComposerController composer, {UserDraft? listedDraft}) {
    // A list row stands in only for the draft saved under its own key.
    if (listedDraft?.key != composer.target.draftKey) listedDraft = null;
    final restore = _restoreDraft(composer, listedDraft: listedDraft);
    _restoreTasks[composer] = restore;
    unawaited(restore);
  }

  void startNewDraft(ComposerController composer) {
    // A newly allocated key has no saved snapshot, including when closing it.
    _restoreTasks[composer] = Future<bool>.value(true);
  }

  Future<bool> finishRestore(ComposerController composer) async {
    if (!_isCurrent(composer)) return false;
    var restore = _restoreTasks[composer];
    if (restore == null && composer.canSaveDraft) {
      restore = _restoreDraft(composer);
      _restoreTasks[composer] = restore;
      unawaited(restore);
    }
    var restored = true;
    if (restore != null) {
      try {
        restored = await restore;
      } catch (_) {
        restored = false;
      }
    }
    if (!restored && _isCurrent(composer) && !composer.isDisposed) {
      if (identical(_restoreTasks[composer], restore)) {
        _restoreTasks[composer] = null;
      }
      composer.showNotice(appL10n.couldnTCheckForAnExistingDraftTryAgain);
    }
    return restored && _isCurrent(composer) && !composer.isDisposed;
  }

  void retire(ComposerController composer) {
    if (!composer.canSaveDraft || !composer.draftPersistencePending) return;
    final session = _sessions[composer];
    if (session == null) return;
    final key = session._keyFor(composer.target);
    final previous = _draftStates[key]?.retiredSaves;
    final drain = composer.finishDraftSaves();
    final retired = _RetiredDraftSaves(
      owner: session._owner,
      previous: previous,
    );
    retired.task = () async {
      if (previous != null) {
        try {
          await previous.task;
        } catch (_) {}
      }
      try {
        await drain;
      } catch (_) {}
    }();
    _stateFor(key).retiredSaves = retired;
    unawaited(
      retired.task.then((_) {
        final state = _draftStates[key];
        if (identical(state?.retiredSaves, retired)) {
          state!.retiredSaves = null;
        }
      }),
    );
  }

  /// Completes once every save a replaced composer left in flight for this
  /// composer's draft key has settled. Never throws: retired saves absorb
  /// their own failures, and each is bounded by its request's timeout.
  Future<void> finishRetiredSaves(ComposerController composer) async {
    final session = _sessions[composer];
    if (session == null) return;
    await _waitForRetiredSaves(composer.target, session);
  }

  void detach(ComposerController composer) {
    _restoreTasks[composer] = null;
  }

  Future<String?> discard(ComposerController composer) {
    final running = _discardTasks[composer];
    if (running != null) return running;

    final task = _discard(composer);
    _discardTasks[composer] = task;
    unawaited(
      task.then<void>(
        (_) => _removeDiscardTask(composer, task),
        onError: (Object _, StackTrace _) => _removeDiscardTask(composer, task),
      ),
    );
    return task;
  }

  /// Persists the opened snapshot before replacing any live editor content.
  /// A successful caller may animate then close this exact composer/revision.
  Future<({int? revision, String? error})> rollbackSavedDraft(
    ComposerController composer, {
    required int confirmedRevision,
  }) async {
    final saved = composer.savedDraft;
    final session = _sessions[composer];
    if (saved == null ||
        session == null ||
        !composer.canSaveDraft ||
        composer.draftRevision != confirmedRevision ||
        composer.hasActiveUploads ||
        composer.loadingBody ||
        composer.submitting ||
        composer.closing ||
        composer.state == ComposerState.checking) {
      return (revision: null, error: _draftChanged);
    }
    final revision = composer.beginDiscard();
    if (revision == null) return (revision: null, error: _discardFailure);
    final target = composer.target;
    bool current() =>
        session._lease.isCurrent &&
        _isCurrent(composer) &&
        !composer.isDisposed;
    bool unchanged() =>
        current() && composer.discardRevisionIsCurrent(revision);
    ComposerDraftSave request(ComposerDraft value) => ComposerDraftSave(
      target: target,
      draft: value,
      sequence: composer.draftSequence,
      localOnly: composer.draftsGaveUp,
      isCurrent: unchanged,
    );
    try {
      await composer.finishInFlightDraftSaveForDiscard();
      if (!current()) return (revision: null, error: null);
      if (!unchanged()) {
        await composer.flushDraft();
        return (revision: null, error: _draftChanged);
      }
      final sequence = await _save(request(saved), session);
      if (!current()) return (revision: null, error: null);
      if (sequence != null) composer.draftSequence = sequence;
      if (!unchanged()) {
        await composer.flushDraft();
        return (revision: null, error: _draftChanged);
      }
      final restoredRevision = composer.applySavedDraftRollback(revision);
      if (restoredRevision == null) {
        return (revision: null, error: _draftChanged);
      }
      composer.setMinimumRequiredTags(
        _minimumRequiredTagsFor(target.siteUrl, composer.categoryId),
      );
      return (revision: restoredRevision, error: null);
    } catch (error) {
      if (!current()) return (revision: null, error: null);

      // A failed remote write may have staged the candidate locally. Put the
      // unchanged live edits back so reopening cannot silently discard them.
      var localFailed = false;
      try {
        final liveRevision = composer.draftRevision;
        await _stage(
          ComposerDraftSave(
            target: composer.target,
            draft: composer.draft,
            sequence: composer.draftSequence,
            localOnly: true,
            isCurrent: () =>
                current() && composer.discardRevisionIsCurrent(liveRevision),
          ),
          session,
        );
      } catch (_) {
        localFailed = true;
      }
      if (current()) {
        composer.draftRollbackWriteFailed(localFailed: localFailed);
      }
      return (
        revision: null,
        error: appL10n.thisDraftCouldNotBeSavedYetPleaseTryAgain,
      );
    } finally {
      if (!composer.isDisposed) composer.finishDiscard();
    }
  }

  void settleAfterSubmission(
    ComposerController composer,
    SiteLease lease, {
    int? sequence,
  }) {
    forgetKnownServerDraft(composer);
    composer.draftSettled();
    final target = composer.target;
    final localSite =
        _sessions[composer]?._localSite ?? _localDraftSite(target.siteUrl);
    unawaited(
      _localStore.clear(
        localSite,
        target.draftKey,
        ifCurrent: () => lease.commit(() {}),
      ),
    );
    if (sequence != null) {
      rememberSequence(target, sequence);
      composer.draftSequence = sequence;
    }
  }

  void forgetKnownServerDraft(ComposerController composer) {
    final session = _sessions[composer];
    if (session == null) return;
    final key = session._keyFor(composer.target);
    _draftStates[key]?.forgetServerDraft();
  }

  void forgetSite(String siteUrl) {
    _draftStates.removeWhere((key, _) => key.siteUrl == siteUrl);
    _sequences.removeWhere((key, _) => key.startsWith('$siteUrl#'));
  }

  /// Completes once every local draft write already started has settled,
  /// without waiting for the site. The local copy is what a relaunch
  /// restores, so a quit need not outlast the network. Never throws.
  Future<void> localWritesSettled() async {
    await Future.wait(List.of(_localWrites));
  }

  Future<T> _trackLocalWrite<T>(Future<T> write) {
    final settled = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _localWrites.add(settled);
    unawaited(settled.whenComplete(() => _localWrites.remove(settled)));
    return write;
  }

  void preservePendingLocally(ComposerController? composer) {
    if (composer == null || !composer.draftPersistencePending) return;
    final session = _sessions[composer];
    if (session == null) return;
    final target = composer.target;
    final draft = composer.draft;
    Future<void>.sync(
      () => draft.isEmpty
          ? _localStore.clear(session._localSite, target.draftKey)
          : _localStore.write(
              session._localSite,
              target.draftKey,
              draft.encodeLocal(),
            ),
    ).ignore();
  }

  void _removeDiscardTask(ComposerController composer, Future<String?> task) {
    if (identical(_discardTasks[composer], task)) {
      final _ = _discardTasks.remove(composer);
    }
  }

  Future<String?> _discard(ComposerController composer) async {
    if (!await finishRestore(composer)) return null;

    if (composer.hasUnappliedDraft) {
      return _discardWithProtectedDraft(composer);
    }
    return _discardCurrentDraft(composer);
  }

  Future<String?> _discardWithProtectedDraft(
    ComposerController composer,
  ) async {
    final revision = composer.beginDiscard();
    if (revision == null) return _discardFailure;
    final target = composer.target;
    final session = _sessions[composer];
    bool isCurrent() =>
        session != null &&
        session._lease.isCurrent &&
        _isCurrent(composer) &&
        !composer.isDisposed;
    String failAndResaveCurrentDraft() {
      if (isCurrent()) unawaited(composer.flushDraft());
      return _discardFailure;
    }

    try {
      final preserved = composer.unappliedDraft;
      if (!isCurrent()) return null;
      if (session == null || preserved == null) {
        return failAndResaveCurrentDraft();
      }
      await composer.finishInFlightDraftSaveForDiscard();
      if (!isCurrent()) return null;
      if (!composer.discardRevisionIsCurrent(revision)) {
        unawaited(composer.flushDraft());
        return _draftChanged;
      }

      final overwritten = composer.unappliedDraftOverwritten;
      if (overwritten || composer.unappliedDraftWasLocal) {
        // An in-flight replacement save can complete after Discard was
        // pressed. Put the protected snapshot back on-device before repairing
        // the server so a process exit between those operations cannot lose
        // both versions.
        await _localStore.write(
          session._localSite,
          target.draftKey,
          preserved.encodeLocal(),
          ifCurrent: () =>
              isCurrent() && composer.discardRevisionIsCurrent(revision),
        );
      }
      if (!isCurrent()) return null;
      if (!composer.discardRevisionIsCurrent(revision)) {
        unawaited(composer.flushDraft());
        return _draftChanged;
      }

      if (overwritten) {
        final credential = await _readCredential(
          target.siteUrl,
          session._lease,
        );
        if (!isCurrent()) return null;
        if (credential.failure != null) return failAndResaveCurrentDraft();
        final clientId = await _readClientId();
        if (!isCurrent()) return null;
        await _waitForRetiredSaves(target, session);
        if (!isCurrent()) return null;
        if (!composer.discardRevisionIsCurrent(revision)) {
          unawaited(composer.flushDraft());
          return _draftChanged;
        }

        final key = session._keyFor(target);
        final restored = await _serialize<bool>(key, () async {
          if (!isCurrent() || !composer.discardRevisionIsCurrent(revision)) {
            return false;
          }
          final sequence = sequenceFor(target);
          if (composer.unappliedDraftWasLocal) {
            await credential.request!.run(
              () => _draftsApi.deleteUserDraft(
                siteUrl: target.siteUrl,
                apiKey: credential.request!.apiKey!,
                draftKey: target.draftKey,
                sequence: sequence,
              ),
            );
            session._lease.commit(() {
              _draftStates[key]?.forgetServerDraft();
            });
            if (!isCurrent() || !composer.discardRevisionIsCurrent(revision)) {
              return false;
            }
          } else {
            final nextSequence = await credential.request!.run(
              () => _persistence.saveDraft(
                siteUrl: target.siteUrl,
                apiKey: credential.request!.apiKey!,
                draftKey: target.draftKey,
                sequence: sequence,
                data: preserved.encode(),
                owner: clientId,
              ),
            );
            session._lease.commit(() {
              if (nextSequence != null) {
                final committedSequence = _commitSequence(target, nextSequence);
                composer.draftSequence = committedSequence;
              }
              _stateFor(key).observeServerDraft();
            });
            if (!isCurrent() || !composer.discardRevisionIsCurrent(revision)) {
              return false;
            }
          }
          return true;
        });
        if (!restored) {
          if (!isCurrent()) return null;
          unawaited(composer.flushDraft());
          return _draftChanged;
        }
      }

      if (!composer.unappliedDraftWasLocal) {
        final cleared = await _localStore.clearChecked(
          session._localSite,
          target.draftKey,
          ifCurrent: () =>
              isCurrent() && composer.discardRevisionIsCurrent(revision),
        );
        if (!cleared &&
            isCurrent() &&
            composer.discardRevisionIsCurrent(revision)) {
          return failAndResaveCurrentDraft();
        }
      }
      if (!isCurrent()) return null;
      if (!composer.discardRevisionIsCurrent(revision)) {
        unawaited(composer.flushDraft());
        return _draftChanged;
      }
      _close(composer);
      return null;
    } catch (error) {
      if (isCurrent()) {
        return failAndResaveCurrentDraft();
      }
      return null;
    } finally {
      if (!composer.isDisposed) composer.finishDiscard();
    }
  }

  Future<String?> _discardCurrentDraft(ComposerController composer) async {
    final revision = composer.beginDiscard();
    if (revision == null) return _discardFailure;

    final target = composer.target;
    final lease = _lifecycle.capture(target.siteUrl);
    bool isCurrent() =>
        lease.isCurrent && _isCurrent(composer) && !composer.isDisposed;

    try {
      if (composer.canSaveDraft) {
        final credential = await _readCredential(target.siteUrl, lease);
        if (!isCurrent()) return null;
        if (credential.failure != null) return _discardFailure;

        await composer.finishInFlightDraftSaveForDiscard();
        if (!isCurrent()) return null;
        if (!composer.discardRevisionIsCurrent(revision)) {
          unawaited(composer.flushDraft());
          return _draftChanged;
        }
        final session = _sessions[composer];
        if (session == null) return _discardFailure;
        await _waitForRetiredSaves(target, session);
        if (!isCurrent()) return null;
        if (!composer.discardRevisionIsCurrent(revision)) {
          unawaited(composer.flushDraft());
          return _draftChanged;
        }

        final key = session._keyFor(target);
        final discarded = await _serialize<bool>(key, () async {
          if (!isCurrent() || !composer.discardRevisionIsCurrent(revision)) {
            return false;
          }
          final sequence = sequenceFor(target);
          final draftWasKnown =
              (_draftStates[key]?.knownOnServer ?? false) ||
              _isServerDraftKnown(target);
          await credential.request!.run(
            () => _draftsApi.deleteUserDraft(
              siteUrl: target.siteUrl,
              apiKey: credential.request!.apiKey!,
              draftKey: target.draftKey,
              sequence: sequence,
            ),
          );
          final localCleared = await _localStore.clearChecked(
            session._localSite,
            target.draftKey,
            ifCurrent: () =>
                isCurrent() && composer.discardRevisionIsCurrent(revision),
          );
          if (!localCleared) {
            if (!isCurrent() || !composer.discardRevisionIsCurrent(revision)) {
              return false;
            }
            throw const DraftWriteException();
          }
          if (!isCurrent() || !composer.discardRevisionIsCurrent(revision)) {
            return false;
          }
          if (!target.createsTopic) {
            _writeCachedDraft(target, null, sequence);
          }
          _recordDraftDestroyed(
            target.siteUrl,
            target.draftKey,
            knownToExist:
                draftWasKnown &&
                _draftStates[key]?.createdAfterCachedCount != true,
          );
          _draftStates[key]?.forgetServerDraft();
          composer.draftSettled();
          _close(composer);
          return true;
        });
        if (discarded) return null;
        if (!isCurrent()) return null;
        await composer.flushDraft();
        return _draftChanged;
      }

      if (!isCurrent()) return null;
      _close(composer);
      return null;
    } catch (error) {
      if (isCurrent()) {
        if (composer.canSaveDraft) unawaited(composer.flushDraft());
        return _discardFailure;
      }
      return null;
    } finally {
      if (!composer.isDisposed) composer.finishDiscard();
    }
  }

  void _close(ComposerController composer) {
    composer.dispose();
    _restoreTasks[composer] = null;
    _onComposerClosed(composer);
  }

  Future<void> _stage(ComposerDraftSave save, ComposerDraftSession session) {
    final key = session._keyFor(save.target);
    final generation = _claimGeneration(key, session);
    return _trackLocalWrite(
      _writeLocalDraft(
        save,
        session,
        ifCurrent: () =>
            save.isCurrent() &&
            session._lease.isCurrent &&
            generation > (_draftStates[key]?.deletedGeneration ?? -1) &&
            _draftStates[key]?.latestGeneration == generation,
      ),
    );
  }

  Future<void> _writeLocalDraft(
    ComposerDraftSave save,
    ComposerDraftSession session, {
    required bool Function() ifCurrent,
  }) async {
    final target = save.target;
    if (!save.draft.isEmpty) {
      await _localStore.write(
        session._localSite,
        target.draftKey,
        save.draft.encodeLocal(),
        ifCurrent: ifCurrent,
      );
    } else if (!await _localStore.clearChecked(
          session._localSite,
          target.draftKey,
          ifCurrent: ifCurrent,
        ) &&
        ifCurrent()) {
      throw const DraftWriteException();
    }
  }

  Future<int?> _save(
    ComposerDraftSave save,
    ComposerDraftSession session,
  ) async {
    final target = save.target;
    final lease = session._lease;
    final key = session._keyFor(target);
    final generation = _claimGeneration(key, session);
    bool ownsLatestGeneration() =>
        _draftStates[key]?.latestGeneration == generation;
    bool wasDeleted() =>
        generation <= (_draftStates[key]?.deletedGeneration ?? -1);

    // Preserve the local-first durability guarantee even when an older
    // controller is still draining. Its later queued writes are generation
    // guarded, so they cannot overwrite this newer composer's local copy.
    final localWrite = _trackLocalWrite(() async {
      DraftWriteException? failure;
      try {
        await _writeLocalDraft(
          save,
          session,
          ifCurrent: () =>
              save.isCurrent() &&
              !wasDeleted() &&
              ownsLatestGeneration() &&
              lease.commit(() {}),
        );
      } on DraftWriteException catch (error) {
        failure = error;
      } catch (error) {
        failure = DraftWriteException(error);
      }
      return failure;
    }());

    await _waitForRetiredSaves(target, session);
    if (!lease.isCurrent || !save.isCurrent()) return null;

    final request = Object();
    _stateFor(key).saveRequest = request;

    return _serialize<int?>(key, () async {
      try {
        // Reserve this save's place before a slow local write completes, so
        // deleting an older list row cannot overtake it.
        final localFailure = await localWrite;
        if (!lease.commit(() {}) || !save.isCurrent() || wasDeleted()) {
          return null;
        }

        // After the sync has given up, the local copy above is the whole save:
        // the site is not asked again, and the copy is not cleared.
        if (save.localOnly) {
          if (localFailure != null) throw localFailure;
          return null;
        }

        try {
          final credential = await _readCredential(target.siteUrl, lease);
          if (!lease.isCurrent) return null;
          if (credential.failure case final failure?) throw failure;
          final apiKey = credential.request!.apiKey!;
          if (save.draft.isEmpty) {
            final requestSequence = sequenceFor(target);
            final draftWasKnown =
                (_draftStates[key]?.knownOnServer ?? false) ||
                _isServerDraftKnown(target);
            if (draftWasKnown) {
              await credential.request!.run(
                () => _draftsApi.deleteUserDraft(
                  siteUrl: target.siteUrl,
                  apiKey: apiKey,
                  draftKey: target.draftKey,
                  sequence: requestSequence,
                ),
              );
            }
            lease.commit(() {
              if (draftWasKnown) {
                session._composer?.unappliedDraftWasOverwritten();
              }
              if (save.isCurrent() &&
                  identical(_draftStates[key]?.saveRequest, request)) {
                if (!target.createsTopic) {
                  _writeCachedDraft(target, null, requestSequence);
                }
                _recordDraftDestroyed(
                  target.siteUrl,
                  target.draftKey,
                  knownToExist:
                      draftWasKnown &&
                      _draftStates[key]?.createdAfterCachedCount != true,
                );
              }
              _draftStates[key]?.forgetServerDraft();
            });
            if (localFailure != null) throw localFailure;
            return null;
          }
          final clientId = await _readClientId();
          if (!lease.isCurrent) return null;

          final requestSequence = sequenceFor(target);
          final sequence = await credential.request!.run(
            () => _persistence.saveDraft(
              siteUrl: target.siteUrl,
              apiKey: apiKey,
              draftKey: target.draftKey,
              sequence: requestSequence,
              data: save.draft.encode(),
              // Discourse uses this to distinguish another writer from this
              // client returning to its own draft.
              owner: clientId,
            ),
          );

          var clearLocal = false;
          var committedSequence = sequence;
          lease.commit(() {
            if (sequence != null) {
              committedSequence = _commitSequence(target, sequence);
            }
            session._composer?.unappliedDraftWasOverwritten();
            _stateFor(key).savedOnServer();
            if (!save.isCurrent() ||
                !identical(_draftStates[key]?.saveRequest, request)) {
              return;
            }

            if (!target.createsTopic) {
              _writeCachedDraft(
                target,
                save.draft,
                committedSequence ?? requestSequence,
              );
            }
            if (!ownsLatestGeneration()) return;
            clearLocal = true;
          });
          if (clearLocal) {
            await _localStore.clear(
              session._localSite,
              target.draftKey,
              ifCurrent: () =>
                  save.isCurrent() &&
                  ownsLatestGeneration() &&
                  identical(_draftStates[key]?.saveRequest, request) &&
                  lease.commit(() {}),
            );
          }

          return committedSequence;
        } catch (_) {
          if (localFailure != null) throw localFailure;
          rethrow;
        }
      } finally {
        final state = _draftStates[key];
        if (identical(state?.saveRequest, request)) {
          state!.saveRequest = null;
        }
      }
    });
  }

  Future<bool> _restoreDraft(
    ComposerController composer, {
    int? startingRevision,
    ComposerTarget? startingTarget,
    UserDraft? listedDraft,
  }) async {
    // A retarget keeps the draft key, so this names the same draft throughout.
    final target = startingTarget ?? composer.target;
    final lease = _lifecycle.capture(target.siteUrl);
    startingRevision ??= composer.draftRevision;
    final session = _sessions[composer];
    final key = session?._keyFor(target);
    final localSite = session?._localSite ?? _localDraftSite(target.siteUrl);

    bool isCurrent() => lease.isCurrent && _isCurrent(composer);

    final deletion = _draftStates[key]?.listedDeletion;
    if (deletion != null) {
      try {
        await deletion;
        listedDraft = null;
      } catch (_) {}
      if (!isCurrent()) return true;
    }
    final deletedGeneration = _draftStates[key]?.deletedGeneration;
    if (listedDraft != null) {
      composer.draftSequence = _commitSequence(
        target,
        listedDraft.sequence,
        fallback: composer.draftSequence,
      );
    }

    // The local copy exists only while the site does not have the text, so if
    // there is one it is the newer of the two by construction.
    var localRead = await _localStore.readChecked(localSite, target.draftKey);
    if (!localRead.succeeded ||
        (localRead.value?.length ?? 0) >
            ComposerDraft.maximumLocalEncodedCodeUnits) {
      return false;
    }
    var local = ComposerDraft.decodeLocal(localRead.value);
    if (!isCurrent()) return true;
    if (local == null) {
      final session = _sessions[composer];
      if (session != null) {
        await _waitForRetiredSaves(target, session);
        if (!isCurrent()) return true;
        // A retired controller may have failed its first local write and then
        // completed a remote save while this composer was opening.
        localRead = await _localStore.readChecked(localSite, target.draftKey);
        if (!localRead.succeeded ||
            (localRead.value?.length ?? 0) >
                ComposerDraft.maximumLocalEncodedCodeUnits) {
          return false;
        }
        local = ComposerDraft.decodeLocal(localRead.value);
        if (!isCurrent()) return true;
      }
    }
    ComposerDraft? remote;
    var remoteSequence = 0;
    if (local == null && target.createsTopic) {
      try {
        final credential = await _readCurrent(
          lease,
          () => _readCredential(target.siteUrl, lease),
        );
        if (credential == null || !isCurrent()) return true;
        if (credential.failure != null) return false;
        final found = await credential.request!.run(
          () => _persistence.draft(
            siteUrl: target.siteUrl,
            apiKey: credential.request!.apiKey!,
            draftKey: target.draftKey,
          ),
        );
        remote = found.draft;
        remoteSequence = found.sequence;
      } catch (_) {
        return false;
      }
    }
    if (!isCurrent()) return true;
    if (_draftStates[key]?.listedDeletion != null ||
        _draftStates[key]?.deletedGeneration != deletedGeneration) {
      return _restoreDraft(
        composer,
        startingRevision: startingRevision,
        startingTarget: target,
      );
    }
    lease.commit(() {
      if (!_isCurrentComposer(composer)) return;
      if (target.createsTopic && remoteSequence > 0) {
        final currentSequence = _commitSequence(
          target,
          remoteSequence,
          fallback: composer.draftSequence,
        );
        composer.draftSequence = currentSequence;
      }
      final cached = target.createsTopic ? null : _readCachedDraft(target);
      final draft = local ?? remote ?? cached ?? listedDraft?.data;
      if (draft == null) return;
      final session = _sessions[composer];
      if (session != null &&
          (remote != null || cached != null || listedDraft != null)) {
        final key = session._keyFor(target);
        _stateFor(key).observeServerDraft();
      }
      if (!composer.canRestoreDraft(draft)) {
        composer.protectUnappliedDraft(draft, wasLocal: local != null);
        return;
      }

      // Body, title, category, tags and whisper all advance this revision.
      // Never restore an older snapshot over a choice made during the lookup.
      if (composer.draftRevision != startingRevision) return;
      // A reply target chosen during the lookup does not advance it, because
      // the composer held no draft yet. The snapshot's text is still wanted,
      // but its target is older than that choice.
      final retargeted =
          composer.target.replyToPostNumber != target.replyToPostNumber ||
          composer.target.replyToUsername != target.replyToUsername;

      if (!composer.restore(draft)) {
        composer.protectUnappliedDraft(draft, wasLocal: local != null);
        return;
      }
      composer.setMinimumRequiredTags(
        _minimumRequiredTagsFor(target.siteUrl, composer.categoryId),
      );
      // The snapshot's reply target comes with its text unless the composer
      // was opened on a post. A composer opened for a list row took the row's
      // target only to stand in for the draft's, so whichever copy outranked
      // the row brings its own, even when that is the topic. The same post is
      // left alone: the row's target also knows whether it is a whisper.
      final adoptsTarget = listedDraft != null
          ? draft.replyToPostNumber != target.replyToPostNumber
          : draft.replyToPostNumber != null && target.replyToPostNumber == null;
      if (!retargeted && adoptsTarget && _isCurrentComposer(composer)) {
        composer.retarget(
          replyToPostNumber: draft.replyToPostNumber,
          replyToUsername: draft.replyToUsername,
          recordDraft: false,
        );
      }
      composer.captureDraftSavepoint();
    });
    return true;
  }

  Future<_DraftCredential> _readCredential(
    String siteUrl,
    SiteLease lease,
  ) async {
    try {
      final request = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(_credentials);
      if (request.apiKey == null) {
        return (
          request: null,
          failure: const WriteException(WriteFailure.forbidden),
        );
      }
      return (request: request, failure: null);
    } catch (error) {
      return (
        request: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  Future<T?> _readCurrent<T>(SiteLease lease, Future<T> Function() read) async {
    final value = await read();
    if (_isDisposed() || !lease.isCurrent) return null;
    return value;
  }

  bool _isCurrent(ComposerController composer) =>
      !_isDisposed() && _isCurrentComposer(composer);

  int _commitSequence(ComposerTarget target, int sequence, {int fallback = 0}) {
    final key = _sequenceKey(target.siteUrl, target.draftKey);
    final knownSequence = _sequences[key] ?? fallback;
    final committedSequence = sequence > knownSequence
        ? sequence
        : knownSequence;
    _sequences[key] = committedSequence;
    return committedSequence;
  }

  _DraftKeyState _stateFor(_DraftSessionKey key) =>
      _draftStates.putIfAbsent(key, _DraftKeyState.new);

  int _claimGeneration(_DraftSessionKey key, ComposerDraftSession session) {
    // A retained tab can become the latest writer again after another tab
    // used the same server draft key. Retired controllers keep their last
    // generation so delayed saves cannot reclaim a newer local draft.
    if (session._composer case final composer? when _isCurrent(composer)) {
      session._generation = ++_generation;
    }
    final generation = session._generation;
    final current = _draftStates[key]?.latestGeneration;
    if (current == null || generation > current) {
      _stateFor(key).latestGeneration = generation;
    }
    return generation;
  }

  Future<void> _waitForRetiredSaves(
    ComposerTarget target,
    ComposerDraftSession session,
  ) async {
    final latest = _draftStates[session._keyFor(target)]?.retiredSaves;
    if (latest == null) return;

    // A retiring controller waits behind older controllers, but not behind
    // the retirement task which is itself waiting for this save. A new
    // controller waits for the complete chain.
    var cursor = latest;
    while (!identical(cursor.owner, session._owner)) {
      final previous = cursor.previous;
      if (previous == null) {
        try {
          await latest.task;
        } catch (_) {}
        return;
      }
      cursor = previous;
    }
    final previous = cursor.previous;
    if (previous != null) {
      try {
        await previous.task;
      } catch (_) {}
    }
  }

  Future<T> _serialize<T>(
    _DraftSessionKey key,
    Future<T> Function() operation,
  ) {
    final previous = _draftStates[key]?.operationTail ?? Future<void>.value();
    final result = previous.then<T>((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _stateFor(key).operationTail = tail;
    unawaited(
      tail.then((_) {
        final state = _draftStates[key];
        if (identical(state?.operationTail, tail)) {
          state!.operationTail = null;
        }
      }),
    );
    return result;
  }

  static String _sequenceKey(String siteUrl, String draftKey) =>
      '$siteUrl#$draftKey';

  static String get _discardFailure => appL10n.couldnTDiscardThisDraftTryAgain;
  static String get _draftChanged =>
      appL10n.thisDraftChangedBeforeItCouldBeDiscardedReviewItAnd;
}

final class ComposerDraftSession {
  ComposerDraftSession._(
    this._coordinator,
    this._lease,
    this._generation,
    this._localSite,
  );

  final ComposerDraftCoordinator _coordinator;
  final SiteLease _lease;
  final String _localSite;
  int _generation;
  final Object _owner = Object();
  ComposerController? _composer;

  Future<int?> save(ComposerDraftSave save) => _coordinator._save(save, this);

  Future<void> stage(ComposerDraftSave save) => _coordinator._stage(save, this);

  _DraftSessionKey _keyFor(ComposerTarget target) => (
    siteUrl: target.siteUrl,
    draftKey: target.draftKey,
    session: _lease.session,
  );
}

final class _RetiredDraftSaves {
  _RetiredDraftSaves({required this.owner, required this.previous});

  final Object owner;
  final _RetiredDraftSaves? previous;
  late final Future<void> task;
}
