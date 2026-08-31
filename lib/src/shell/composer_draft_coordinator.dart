// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../data/discourse_api_contracts.dart';
import '../data/draft_store.dart';
import '../data/site_lifecycle.dart';
import '../models/composer_draft.dart';
import '../models/user_draft.dart';
import 'composer_controller.dart';

typedef ComposerDraftCredential = ({String? apiKey, WriteException? failure});
typedef ComposerDraftCredentialReader =
    Future<ComposerDraftCredential> Function(String siteUrl);
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
typedef ComposerDraftErrorReporter =
    void Function(Object error, StackTrace stackTrace, String operation);

typedef _DraftSessionKey = ({String siteUrl, String draftKey, Object session});

/// Owns the persistence lifecycle for composer drafts.
///
/// Navigation and presentation remain in the shell. This coordinator receives
/// narrow callbacks for the shell-owned cache and active composer so draft
/// ordering can be tested without coupling persistence to the whole shell.
final class ComposerDraftCoordinator {
  ComposerDraftCoordinator({
    required DraftStore localStore,
    required ComposerPersistenceApi persistence,
    required DraftsApi draftsApi,
    required SiteLifecycle lifecycle,
    required ComposerDraftCredentialReader readCredential,
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
    required ComposerDraftErrorReporter reportError,
  }) : _localStore = localStore,
       _persistence = persistence,
       _draftsApi = draftsApi,
       _lifecycle = lifecycle,
       _readCredential = readCredential,
       _readClientId = readClientId,
       _isDisposed = isDisposed,
       _isCurrentComposer = isCurrentComposer,
       _readCachedDraft = readCachedDraft,
       _readCachedSequence = readCachedSequence,
       _writeCachedDraft = writeCachedDraft,
       _minimumRequiredTagsFor = minimumRequiredTagsFor,
       _isServerDraftKnown = isServerDraftKnown,
       _recordDraftDestroyed = recordDraftDestroyed,
       _onComposerClosed = onComposerClosed,
       _reportError = reportError;

  final DraftStore _localStore;
  final ComposerPersistenceApi _persistence;
  final DraftsApi _draftsApi;
  final SiteLifecycle _lifecycle;
  final ComposerDraftCredentialReader _readCredential;
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
  final ComposerDraftErrorReporter _reportError;

  final Expando<ComposerDraftSession> _sessions = Expando();
  final Expando<Future<bool>> _restoreTasks = Expando();
  final Map<ComposerController, Future<String?>> _discardTasks = {};
  final Map<_DraftSessionKey, int> _latestGenerations = {};
  final Map<_DraftSessionKey, _RetiredDraftSaves> _retiredSaves = {};
  final Map<_DraftSessionKey, Object> _saveRequests = {};
  final Map<_DraftSessionKey, Future<void>> _operations = {};
  final Set<_DraftSessionKey> _knownServerDrafts = {};
  final Set<_DraftSessionKey> _draftsCreatedAfterCachedCount = {};
  final Map<String, int> _sequences = {};
  int _generation = 0;

  ComposerDraftSession openSession(ComposerTarget target) =>
      ComposerDraftSession._(
        this,
        _lifecycle.capture(target.siteUrl),
        ++_generation,
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

  void restoreListedDraft(ComposerController composer, UserDraft draft) {
    composer
      ..draftSequence = draft.sequence
      ..restore(draft.data!);
    rememberSequence(composer.target, draft.sequence);
  }

  Future<bool>? restoreTaskFor(ComposerController composer) =>
      _restoreTasks[composer];

  void startRestore(ComposerController composer) {
    final restore = _restoreDraft(composer);
    _restoreTasks[composer] = restore;
    unawaited(restore);
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
      composer.showNotice("Couldn't check for an existing draft. Try again.");
    }
    return restored && _isCurrent(composer) && !composer.isDisposed;
  }

  void retire(ComposerController composer) {
    if (!composer.canSaveDraft || !composer.draftPersistencePending) return;
    final session = _sessions[composer];
    if (session == null) return;
    final key = session._keyFor(composer.target);
    final previous = _retiredSaves[key];
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
    _retiredSaves[key] = retired;
    unawaited(
      retired.task.then((_) {
        if (identical(_retiredSaves[key], retired)) {
          final _ = _retiredSaves.remove(key);
        }
      }),
    );
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

  void settleAfterSubmission(
    ComposerController composer,
    SiteLease lease, {
    int? sequence,
  }) {
    forgetKnownServerDraft(composer);
    composer.draftSettled();
    final target = composer.target;
    unawaited(
      _localStore.clear(
        target.siteUrl,
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
    _knownServerDrafts.remove(key);
    _draftsCreatedAfterCachedCount.remove(key);
  }

  void forgetSite(String siteUrl) {
    _saveRequests.removeWhere((key, _) => key.siteUrl == siteUrl);
    _operations.removeWhere((key, _) => key.siteUrl == siteUrl);
    _retiredSaves.removeWhere((key, _) => key.siteUrl == siteUrl);
    _latestGenerations.removeWhere((key, _) => key.siteUrl == siteUrl);
    _knownServerDrafts.removeWhere((key) => key.siteUrl == siteUrl);
    _draftsCreatedAfterCachedCount.removeWhere((key) => key.siteUrl == siteUrl);
    _sequences.removeWhere((key, _) => key.startsWith('$siteUrl#'));
  }

  void preservePendingLocally(ComposerController? composer) {
    if (composer == null || !composer.draftPersistencePending) return;
    final target = composer.target;
    final data = composer.draft.encode();
    Future<void>.sync(
      () => _localStore.write(target.siteUrl, target.draftKey, data),
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
          target.siteUrl,
          target.draftKey,
          preserved.encode(),
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
        final credential = await _readCredential(target.siteUrl);
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
            await _draftsApi.deleteUserDraft(
              siteUrl: target.siteUrl,
              apiKey: credential.apiKey!,
              draftKey: target.draftKey,
              sequence: sequence,
            );
            session._lease.commit(() {
              _knownServerDrafts.remove(key);
              _draftsCreatedAfterCachedCount.remove(key);
            });
            if (!isCurrent() || !composer.discardRevisionIsCurrent(revision)) {
              return false;
            }
          } else {
            final nextSequence = await _persistence.saveDraft(
              siteUrl: target.siteUrl,
              apiKey: credential.apiKey!,
              draftKey: target.draftKey,
              sequence: sequence,
              data: preserved.encode(),
              owner: clientId,
            );
            session._lease.commit(() {
              if (nextSequence != null) {
                final committedSequence = _commitSequence(target, nextSequence);
                composer.draftSequence = committedSequence;
              }
              _knownServerDrafts.add(key);
              _draftsCreatedAfterCachedCount.remove(key);
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
          target.siteUrl,
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
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _reportError(error, stackTrace, 'composer.preserveUnappliedDraft');
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
        final credential = await _readCredential(target.siteUrl);
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
              _knownServerDrafts.contains(key) || _isServerDraftKnown(target);
          await _draftsApi.deleteUserDraft(
            siteUrl: target.siteUrl,
            apiKey: credential.apiKey!,
            draftKey: target.draftKey,
            sequence: sequence,
          );
          final localCleared = await _localStore.clearChecked(
            target.siteUrl,
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
                draftWasKnown && !_draftsCreatedAfterCachedCount.contains(key),
          );
          _knownServerDrafts.remove(key);
          _draftsCreatedAfterCachedCount.remove(key);
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
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _reportError(error, stackTrace, 'composer.discardDraft');
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
    _claimGeneration(key, session._generation);
    return _localStore.write(
      save.target.siteUrl,
      save.target.draftKey,
      save.draft.encode(),
      ifCurrent: () =>
          save.isCurrent() &&
          session._lease.isCurrent &&
          _latestGenerations[key] == session._generation,
    );
  }

  Future<int?> _save(
    ComposerDraftSave save,
    ComposerDraftSession session,
  ) async {
    final target = save.target;
    final lease = session._lease;
    final data = save.draft.encode();
    final key = session._keyFor(target);
    _claimGeneration(key, session._generation);
    bool ownsLatestGeneration() =>
        _latestGenerations[key] == session._generation;

    // Preserve the local-first durability guarantee even when an older
    // controller is still draining. Its later queued writes are generation
    // guarded, so they cannot overwrite this newer composer's local copy.
    final localWrite = () async {
      DraftWriteException? failure;
      try {
        await _localStore.write(
          target.siteUrl,
          target.draftKey,
          data,
          ifCurrent: () =>
              save.isCurrent() && ownsLatestGeneration() && lease.commit(() {}),
        );
      } on DraftWriteException catch (error) {
        failure = error;
      } catch (error) {
        failure = DraftWriteException(error);
      }
      return failure;
    }();

    await _waitForRetiredSaves(target, session);
    final localFailure = await localWrite;
    if (!lease.isCurrent || !save.isCurrent()) return null;

    final request = Object();
    _saveRequests[key] = request;

    return _serialize<int?>(key, () async {
      try {
        if (!lease.commit(() {})) return null;

        // After the sync has given up, the local copy above is the whole save:
        // the site is not asked again, and the copy is not cleared.
        if (save.localOnly) {
          if (localFailure != null) throw localFailure;
          return null;
        }

        try {
          final credential = await _readCredential(target.siteUrl);
          if (!lease.isCurrent) return null;
          if (credential.failure case final failure?) throw failure;
          final apiKey = credential.apiKey!;
          final clientId = await _readClientId();
          if (!lease.isCurrent) return null;

          final requestSequence = sequenceFor(target);
          final sequence = await _persistence.saveDraft(
            siteUrl: target.siteUrl,
            apiKey: apiKey,
            draftKey: target.draftKey,
            sequence: requestSequence,
            data: data,
            // Discourse uses this to distinguish another writer from this
            // client returning to its own draft.
            owner: clientId,
          );

          var clearLocal = false;
          var committedSequence = sequence;
          lease.commit(() {
            if (sequence != null) {
              committedSequence = _commitSequence(target, sequence);
            }
            session._composer?.unappliedDraftWasOverwritten();
            if (_knownServerDrafts.add(key)) {
              _draftsCreatedAfterCachedCount.add(key);
            }
            if (!save.isCurrent() || !identical(_saveRequests[key], request)) {
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
              target.siteUrl,
              target.draftKey,
              ifCurrent: () =>
                  save.isCurrent() &&
                  ownsLatestGeneration() &&
                  identical(_saveRequests[key], request) &&
                  lease.commit(() {}),
            );
          }

          return committedSequence;
        } catch (_) {
          if (localFailure != null) throw localFailure;
          rethrow;
        }
      } finally {
        if (identical(_saveRequests[key], request)) {
          _saveRequests.remove(key);
        }
      }
    });
  }

  Future<bool> _restoreDraft(ComposerController composer) async {
    final target = composer.target;
    final lease = _lifecycle.capture(target.siteUrl);
    final startingRevision = composer.draftRevision;

    bool isCurrent() => lease.isCurrent && _isCurrent(composer);

    // The local copy exists only while the site does not have the text, so if
    // there is one it is the newer of the two by construction.
    var localRead = await _localStore.readChecked(
      target.siteUrl,
      target.draftKey,
    );
    if (!localRead.succeeded) return false;
    var local = ComposerDraft.decode(localRead.value);
    if (!isCurrent()) return true;
    if (local == null) {
      final session = _sessions[composer];
      if (session != null) {
        await _waitForRetiredSaves(target, session);
        if (!isCurrent()) return true;
        // A retired controller may have failed its first local write and then
        // completed a remote save while this composer was opening.
        localRead = await _localStore.readChecked(
          target.siteUrl,
          target.draftKey,
        );
        if (!localRead.succeeded) return false;
        local = ComposerDraft.decode(localRead.value);
        if (!isCurrent()) return true;
      }
    }
    ComposerDraft? remote;
    var remoteSequence = 0;
    if (local == null && target.createsTopic) {
      try {
        final credential = await _readCurrent(
          lease,
          () => _readCredential(target.siteUrl),
        );
        if (credential == null || !isCurrent()) return true;
        if (credential.failure != null) return false;
        final found = await _persistence.draft(
          siteUrl: target.siteUrl,
          apiKey: credential.apiKey!,
          draftKey: target.draftKey,
        );
        remote = found.draft;
        remoteSequence = found.sequence;
      } catch (_) {
        return false;
      }
    }
    if (!isCurrent()) return true;
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
      final draft = local ?? remote ?? cached;
      if (draft == null) return;
      final session = _sessions[composer];
      if (session != null && (remote != null || cached != null)) {
        final key = session._keyFor(target);
        _knownServerDrafts.add(key);
        _draftsCreatedAfterCachedCount.remove(key);
      }
      if (!composer.canRestoreDraft(draft)) {
        composer.protectUnappliedDraft(draft, wasLocal: local != null);
        return;
      }

      // Body, title, category, tags and whisper all advance this revision.
      // Never restore an older snapshot over a choice made during the lookup.
      if (composer.draftRevision != startingRevision) return;

      if (!composer.restore(draft)) {
        composer.protectUnappliedDraft(draft, wasLocal: local != null);
        return;
      }
      composer.setMinimumRequiredTags(
        _minimumRequiredTagsFor(target.siteUrl, composer.categoryId),
      );
      if (draft.replyToPostNumber != null &&
          target.replyToPostNumber == null &&
          _isCurrentComposer(composer)) {
        composer.retarget(
          replyToPostNumber: draft.replyToPostNumber,
          replyToUsername: draft.replyToUsername,
        );
      }
    });
    return true;
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

  void _claimGeneration(_DraftSessionKey key, int generation) {
    final current = _latestGenerations[key];
    if (current == null || generation > current) {
      _latestGenerations[key] = generation;
    }
  }

  Future<void> _waitForRetiredSaves(
    ComposerTarget target,
    ComposerDraftSession session,
  ) async {
    final latest = _retiredSaves[session._keyFor(target)];
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
    final previous = _operations[key] ?? Future<void>.value();
    final result = previous.then<T>((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _operations[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_operations[key], tail)) {
          final _ = _operations.remove(key);
        }
      }),
    );
    return result;
  }

  static String _sequenceKey(String siteUrl, String draftKey) =>
      '$siteUrl#$draftKey';

  static const _discardFailure = "Couldn't discard this draft. Try again.";
  static const _draftChanged =
      'This draft changed before it could be discarded. Review it and try again.';
}

final class ComposerDraftSession {
  ComposerDraftSession._(this._coordinator, this._lease, this._generation);

  final ComposerDraftCoordinator _coordinator;
  final SiteLease _lease;
  final int _generation;
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
