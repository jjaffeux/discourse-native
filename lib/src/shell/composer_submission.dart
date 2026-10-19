part of 'shell_controller.dart';

final class _ComposerAttempt {
  const _ComposerAttempt({
    required this.editor,
    required this.target,
    required this.lease,
    required this.username,
    required this.whisper,
    required this.sourceTabId,
  });

  final ComposerController editor;
  final ComposerTarget target;
  final SiteLease lease;
  final String? username;
  final bool whisper;
  final String? sourceTabId;
}

final class _SentComposerSubmission implements ComposerSubmission {
  _SentComposerSubmission(this.attempt)
    : raw = attempt.editor.raw,
      title = attempt.editor.title.text.trim(),
      draftSequence = attempt.editor.draftSequence,
      categoryId = attempt.editor.categoryId,
      tags = List.unmodifiable(attempt.editor.tags),
      typingDuration = attempt.editor.typingDuration,
      openDuration = attempt.editor.openDuration;

  @override
  final _ComposerAttempt attempt;
  final String raw;
  final String title;
  final int draftSequence;
  final int? categoryId;
  final List<TopicTag> tags;
  final Duration typingDuration;
  final Duration openDuration;
}

final class _ComposerEdit {
  _ComposerEdit(ComposerController editor)
    : raw = editor.editRaw,
      originalRaw = editor.originalRaw,
      title = editor.title.text.trim(),
      originalTitle = editor.originalTitle,
      categoryId = editor.categoryId,
      tags = List.unmodifiable(editor.tags),
      originalTags = List.unmodifiable(editor.originalTags),
      metadataChanged = editor.metadataChanged;

  final String raw;
  final String? originalRaw;
  final String title;
  final String originalTitle;
  final int? categoryId;
  final List<TopicTag> tags;
  final List<TopicTag> originalTags;
  final bool metadataChanged;
}

final class _SubmittedMetadata {
  const _SubmittedMetadata(this.title, this.categoryId, this.tags);

  final String title;
  final int? categoryId;
  final List<TopicTag> tags;
}

sealed class _SubmissionResult {
  const _SubmissionResult();
}

final class _SubmissionNotAdmitted extends _SubmissionResult {
  const _SubmissionNotAdmitted();
}

sealed class _CompletedSubmission extends _SubmissionResult {
  const _CompletedSubmission(this.attempt, {this.metadata});

  final _ComposerAttempt attempt;
  final _SubmittedMetadata? metadata;
}

final class _SubmissionInactive extends _CompletedSubmission {
  const _SubmissionInactive(super.attempt, {super.metadata});
}

final class _SubmissionRefused extends _CompletedSubmission {
  const _SubmissionRefused(super.attempt, this.failure, {super.metadata});

  final WriteException failure;
}

final class _SubmissionUnresolved extends _CompletedSubmission {
  const _SubmissionUnresolved(super.attempt, {super.metadata});
}

final class _SubmissionAccepted extends _CompletedSubmission {
  const _SubmissionAccepted(super.attempt, this.acceptance, {super.metadata});

  final _SubmissionAcceptance acceptance;
}

sealed class _SubmissionAcceptance {
  const _SubmissionAcceptance();
}

final class _SubmissionEnqueued extends _SubmissionAcceptance {
  const _SubmissionEnqueued();
}

final class _SubmissionReply extends _SubmissionAcceptance {
  const _SubmissionReply({required this.refresh});

  final bool refresh;
}

final class _SubmissionTopic extends _SubmissionAcceptance {
  const _SubmissionTopic(this.topicId, this.slug, this.title);

  final int topicId;
  final String slug;
  final String title;
}

final class _SubmissionEdited extends _SubmissionAcceptance {
  const _SubmissionEdited();
}

final class _ComposerSubmissionOwner {
  const _ComposerSubmissionOwner(this.shell);

  final ShellController shell;

  bool _accountCurrent(_ComposerAttempt attempt) =>
      !shell.accountSessionDisposed && attempt.lease.isCurrent;

  bool _editorCurrent(_ComposerAttempt attempt) =>
      _accountCurrent(attempt) &&
      shell._ownsComposer(attempt.editor) &&
      attempt.editor.ownsSubmission(attempt);

  Future<_SubmissionResult> submit(
    ComposerController? editor,
    void Function(String)? onPreparationNotice,
  ) async {
    if (editor == null ||
        !shell._ownsComposer(editor) ||
        editor.discarding ||
        editor.submitting ||
        !editor.canSubmit ||
        editor.target is PluginComposerTarget) {
      return const _SubmissionNotAdmitted();
    }
    final target = editor.target;
    final attempt = _ComposerAttempt(
      editor: editor,
      target: target,
      lease: shell.lifecycle.capture(target.siteUrl),
      username: shell._instanceAt(target.siteUrl)?.user?.username,
      whisper: editor.whisper,
      sourceTabId: shell._workspace.forSite(target.siteUrl)?.activeTabId,
    );
    final edit = target is EditComposerTarget ? _ComposerEdit(editor) : null;
    final refusal = target.isNewTopic ? _newTopicRefusal(editor) : null;
    editor.beginSubmit(attempt: attempt);
    if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
    if (refusal != null) {
      return _refuse(
        attempt,
        WriteException(WriteFailure.validation, errors: [refusal]),
      );
    }
    if (target is EditComposerTarget) {
      return _edit(attempt, target, edit!);
    }

    var preparationChanged = false;
    for (final preparer
        in shell._pluginSession.capabilities<PluginComposerSubmitPreparer>()) {
      if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
      final PluginComposerSubmitPreparation prepared;
      try {
        prepared = await preparer.prepareComposerSubmit(editor);
      } catch (error, stackTrace) {
        shell._pluginDiagnosticsReporter.reportError(
          error,
          stackTrace,
          operation: 'composer.prepareSubmit',
          source: 'plugin',
          handled: true,
          degraded: true,
        );
        if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
        if (preparationChanged) await editor.flushDraft();
        return _refuse(
          attempt,
          WriteException(
            WriteFailure.unreachable,
            errors: [appL10n.couldnTPrepareThisPostNothingWasPosted],
            notSent: true,
          ),
        );
      }
      if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
      if (prepared.failure case final failure?) {
        if (preparationChanged) await editor.flushDraft();
        return _refuse(attempt, failure);
      }
      preparationChanged |= prepared.changed;
      if (prepared.notice case final notice?) onPreparationNotice?.call(notice);
    }
    if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
    if (preparationChanged) await editor.flushDraft();
    if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
    await editor.finishDraftSaves();
    if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
    await shell._composerDrafts.finishRetiredSaves(editor);
    if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);

    final sent = _SentComposerSubmission(attempt);
    editor.retainSubmission(sent);
    final credential = await shell._credentialForWrite(
      target.siteUrl,
      lease: attempt.lease,
    );
    if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
    if (credential.failure case final failure?) {
      return _refuse(attempt, failure);
    }

    final PostCreation creation;
    try {
      creation = await credential.request!.run(
        () => switch (target) {
          TopicCreationComposerTarget() =>
            shell.api.composerPersistence.createTopic(
              siteUrl: target.siteUrl,
              apiKey: credential.apiKey!,
              title: sent.title,
              raw: sent.raw,
              categoryId: sent.categoryId,
              tags: sent.tags,
              typingDuration: sent.typingDuration,
              composerOpenDuration: sent.openDuration,
              targetRecipients: target.targetRecipients,
              draftKey: target.draftKey,
            ),
          ReplyComposerTarget() => shell.api.composerPersistence.createPost(
            siteUrl: target.siteUrl,
            apiKey: credential.apiKey!,
            topicId: target.topicId,
            raw: sent.raw,
            replyToPostNumber: target.replyToPostNumber,
            whisper: attempt.whisper,
            typingDuration: sent.typingDuration,
            composerOpenDuration: sent.openDuration,
            draftKey: target.draftKey,
          ),
          EditComposerTarget() || PluginComposerTarget() => throw StateError(
            'Unsupported forum submission target',
          ),
        },
      );
    } on WriteException catch (failure) {
      if (failure.notSent) {
        return _refuse(
          attempt,
          WriteException(
            WriteFailure.unreachable,
            errors: [appL10n.couldnTReachTheSiteNothingWasPosted],
            notSent: true,
          ),
        );
      }
      if (failure.failure != WriteFailure.unreachable) {
        return _refuse(attempt, failure);
      }
      return _reconcile(sent, failure);
    } catch (error, stackTrace) {
      if (_accountCurrent(attempt)) {
        shell._reportOperationalError(error, stackTrace, 'composer.submit');
      }
      return _reconcile(sent, const WriteException(WriteFailure.unreachable));
    }
    return _acceptCreation(sent, creation);
  }

  String? _newTopicRefusal(ComposerController editor) {
    final siteUrl = editor.target.siteUrl;
    final categoryId = editor.categoryId;
    final template = shell
        .categoryFor(categoryId, siteUrl: siteUrl)
        ?.topicTemplate;
    if (template != null && editor.raw.trim() == template.trim()) {
      return appL10n.pleaseAddDetailsAndSpecificsToYourTopicByEditingThe;
    }
    if (categoryId == null &&
        !shell.siteConfigFor(siteUrl).allowUncategorizedTopics &&
        shell
            .topicComposerCategories(siteUrl)
            .any((category) => category.topicTemplate != null)) {
      return appL10n.youMustChooseACategory;
    }
    return null;
  }

  _SubmissionRefused _refuse(
    _ComposerAttempt attempt,
    WriteException failure, {
    _SubmittedMetadata? metadata,
    bool checked = false,
  }) {
    if (_editorCurrent(attempt)) {
      if (checked) {
        attempt.editor.checkedNotPosted(failure);
      } else {
        attempt.editor.failed(failure);
      }
    }
    return _SubmissionRefused(attempt, failure, metadata: metadata);
  }

  _SubmissionUnresolved _unresolved(_ComposerAttempt attempt) {
    if (_editorCurrent(attempt)) attempt.editor.unresolved();
    return _SubmissionUnresolved(attempt);
  }

  _CompletedSubmission _editFailure(
    _ComposerAttempt attempt,
    WriteException failure,
    _SubmittedMetadata? metadata,
  ) {
    if (_editorCurrent(attempt)) attempt.editor.failed(failure);
    return failure.failure == WriteFailure.unreachable && !failure.notSent
        ? _SubmissionUnresolved(attempt, metadata: metadata)
        : _SubmissionRefused(attempt, failure, metadata: metadata);
  }

  Future<_SubmissionResult> recheck(ComposerController? editor) async {
    if (editor == null || !editor.canRecheck) {
      return const _SubmissionNotAdmitted();
    }
    final sent = editor.submission;
    if (sent is! _SentComposerSubmission || !_editorCurrent(sent.attempt)) {
      return const _SubmissionNotAdmitted();
    }
    return _reconcile(sent, const WriteException(WriteFailure.unreachable));
  }

  Future<_CompletedSubmission> _reconcile(
    _SentComposerSubmission sent,
    WriteException failure,
  ) async {
    final attempt = sent.attempt;
    final target = attempt.target;
    if (_editorCurrent(attempt)) attempt.editor.checking();
    if (!_accountCurrent(attempt)) return _unresolved(attempt);
    final data = shell._topicData.forLease(target.siteUrl, attempt.lease);
    if (data == null) return _unresolved(attempt);
    final credential = await shell._credentialForWrite(
      target.siteUrl,
      lease: attempt.lease,
    );
    if (!_accountCurrent(attempt) || credential.failure != null) {
      return _unresolved(attempt);
    }
    try {
      switch (target) {
        case TopicCreationComposerTarget():
          final retained = await credential.request!.run(
            () => shell.api.composerPersistence.draft(
              siteUrl: target.siteUrl,
              apiKey: credential.apiKey!,
              draftKey: target.draftKey,
            ),
          );
          if (!_accountCurrent(attempt)) return _unresolved(attempt);
          // A successful create advances this sequence, including when a later
          // draft recreates the key. Equality proves that this create never ran.
          if (retained.draft != null &&
              retained.sequence == sent.draftSequence) {
            return _refuse(attempt, failure, checked: true);
          }
          final username = attempt.username;
          if (username == null) return _unresolved(attempt);
          final match = await data.findCreatedTopic(
            username: username,
            title: sent.title,
            raw: sent.raw,
            privateMessage: target.isPrivateMessage,
            credential: credential.request!,
          );
          if (match == null) return _unresolved(attempt);
          _settleDraft(attempt);
          return _SubmissionAccepted(
            attempt,
            _SubmissionTopic(match.topicId, match.slug, match.title),
          );
        case ReplyComposerTarget():
          final landed = await data.findReply(
            topicId: target.topicId,
            slug: target.slug,
            username: attempt.username,
            raw: sent.raw,
            credential: credential.request!,
          );
          if (!_accountCurrent(attempt)) return _unresolved(attempt);
          if (landed == null) return _refuse(attempt, failure, checked: true);
          _settleDraft(attempt);
          return _SubmissionAccepted(
            attempt,
            const _SubmissionReply(refresh: false),
          );
        case EditComposerTarget() || PluginComposerTarget():
          throw StateError('Only creates can be reconciled');
      }
    } catch (error, stackTrace) {
      if (_accountCurrent(attempt)) {
        shell._reportOperationalError(
          error,
          stackTrace,
          target is TopicCreationComposerTarget
              ? 'composer.reconcileTopic'
              : 'composer.reconcile',
          severity: DiagnosticSeverity.warning,
        );
      }
      return _unresolved(attempt);
    }
  }

  _CompletedSubmission _acceptCreation(
    _SentComposerSubmission sent,
    PostCreation creation,
  ) {
    final attempt = sent.attempt;
    final target = attempt.target;
    if (_accountCurrent(attempt) && creation.post != null) {
      final data = shell._topicData.forLease(target.siteUrl, attempt.lease);
      if (target is ReplyComposerTarget) {
        data?.acceptReply(target.topicId, creation.post!);
      } else {
        data?.acceptNewTopicPost(creation.post!);
      }
    }
    _settleDraft(attempt, sequence: creation.draftSequence);
    if (creation.isEnqueued) {
      if (_editorCurrent(attempt)) attempt.editor.enqueued(creation.message);
      return _SubmissionAccepted(attempt, const _SubmissionEnqueued());
    }
    if (target is ReplyComposerTarget) {
      return _SubmissionAccepted(
        attempt,
        const _SubmissionReply(refresh: true),
      );
    }
    final topicId = creation.topicId;
    if (topicId == null) return _unresolved(attempt);
    return _SubmissionAccepted(
      attempt,
      _SubmissionTopic(
        topicId,
        creation.topicSlug ?? '',
        creation.topicTitle ?? sent.title,
      ),
    );
  }

  void _settleDraft(_ComposerAttempt attempt, {int? sequence}) {
    if (!_accountCurrent(attempt)) return;
    final editor = attempt.editor;
    // Disposal retires authoring but not an accepted server draft. A live
    // editor reused for another document must keep that document's draft.
    if (!editor.isDisposed && !editor.ownsSubmission(attempt)) return;
    shell._composerDrafts.settleAfterSubmission(
      editor,
      attempt.lease,
      sequence: sequence,
    );
    if (!_accountCurrent(attempt)) return;
    final target = attempt.target;
    if (target is ReplyComposerTarget) {
      shell.store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) =>
            detail.withDraft(null, shell._composerDrafts.sequenceFor(target)),
      );
    }
  }

  Future<_CompletedSubmission> _edit(
    _ComposerAttempt attempt,
    EditComposerTarget target,
    _ComposerEdit edit,
  ) async {
    final release = target is PostEditingComposerTarget
        ? shell._topicData
              .forLease(target.siteUrl, attempt.lease)
              ?.beginPostWrite(target.editingPostId)
        : null;
    if (target is PostEditingComposerTarget && release == null) {
      return _refuse(
        attempt,
        WriteException(
          WriteFailure.conflict,
          errors: [appL10n.anotherActionOnThisPostIsStillBeingSaved],
        ),
      );
    }
    try {
      if (target is PostEditingComposerTarget && edit.originalRaw == null) {
        return _refuse(
          attempt,
          const WriteException(WriteFailure.unreachable, notSent: true),
        );
      }
      final credential = await shell._credentialForWrite(
        target.siteUrl,
        lease: attempt.lease,
      );
      if (!_editorCurrent(attempt)) return _SubmissionInactive(attempt);
      if (credential.failure case final failure?) {
        return _refuse(attempt, failure);
      }
      _SubmittedMetadata? metadata;
      if (target is TagsEditComposerTarget) {
        try {
          await credential.request!.run(
            () => shell.api.topicMutations.updateTopicTags(
              siteUrl: target.siteUrl,
              apiKey: credential.apiKey!,
              topicId: target.topicId,
              tags: edit.tags,
            ),
          );
        } on WriteException catch (failure) {
          return _editFailure(attempt, failure, null);
        } catch (error, stackTrace) {
          if (_accountCurrent(attempt)) {
            shell._reportOperationalError(
              error,
              stackTrace,
              'composer.editTopicTags',
            );
          }
          return _editFailure(
            attempt,
            const WriteException(WriteFailure.unreachable),
            null,
          );
        }
        if (_accountCurrent(attempt)) {
          shell.store.update<TopicDetail>(
            target.siteUrl,
            target.topicId,
            (detail) => detail.copyWith(tags: edit.tags),
          );
          if (_accountCurrent(attempt)) {
            shell.store.update<Topic>(
              target.siteUrl,
              target.topicId,
              (topic) => topic.copyWith(tags: edit.tags),
            );
          }
        }
        return _SubmissionAccepted(attempt, const _SubmissionEdited());
      }
      if (target is CategoryEditComposerTarget ||
          (target.editsTopicMetadata && edit.metadataChanged)) {
        final TopicUpdate update;
        try {
          update = await credential.request!.run(
            () => shell.api.topicMutations.updateTopic(
              siteUrl: target.siteUrl,
              apiKey: credential.apiKey!,
              topicId: target.topicId,
              title: target is CategoryEditComposerTarget
                  ? target.topicTitle
                  : edit.title,
              originalTitle: target is CategoryEditComposerTarget
                  ? target.topicTitle
                  : edit.originalTitle,
              categoryId: edit.categoryId,
              tags: edit.tags,
              originalTags: edit.originalTags,
            ),
          );
        } on WriteException catch (failure) {
          return _editFailure(attempt, failure, null);
        } catch (error, stackTrace) {
          if (_accountCurrent(attempt)) {
            shell._reportOperationalError(
              error,
              stackTrace,
              target is CategoryEditComposerTarget
                  ? 'composer.editTopicCategory'
                  : 'composer.editTopic',
            );
          }
          return _editFailure(
            attempt,
            const WriteException(WriteFailure.unreachable),
            null,
          );
        }
        metadata = _SubmittedMetadata(
          target is CategoryEditComposerTarget
              ? target.topicTitle
              : update.title ?? edit.title,
          edit.categoryId,
          List.unmodifiable(
            target is CategoryEditComposerTarget
                ? edit.tags
                : update.tags ?? edit.tags,
          ),
        );
        _publishMetadata(
          attempt,
          target,
          metadata,
          titleChanged: target is! CategoryEditComposerTarget,
        );
        if (_editorCurrent(attempt)) {
          attempt.editor.metadataSettled(
            categoryId: metadata.categoryId,
            title: metadata.title,
            tags: metadata.tags,
          );
        }
        if (target is CategoryEditComposerTarget ||
            edit.raw == edit.originalRaw?.trimRight()) {
          return _SubmissionAccepted(
            attempt,
            const _SubmissionEdited(),
            metadata: metadata,
          );
        }
      }
      if (!_editorCurrent(attempt)) {
        return _SubmissionInactive(attempt, metadata: metadata);
      }
      if (target is! PostEditingComposerTarget) {
        throw StateError('Unsupported body edit target');
      }
      final Post updated;
      try {
        updated = await credential.request!.run(
          () => shell.api.composerPersistence.updatePost(
            siteUrl: target.siteUrl,
            apiKey: credential.apiKey!,
            postId: target.editingPostId,
            raw: edit.raw,
            originalText: edit.originalRaw,
          ),
        );
      } on WriteException catch (failure) {
        return _editFailure(attempt, failure, metadata);
      } catch (error, stackTrace) {
        if (_accountCurrent(attempt)) {
          shell._reportOperationalError(error, stackTrace, 'composer.edit');
        }
        return _editFailure(
          attempt,
          const WriteException(WriteFailure.unreachable),
          metadata,
        );
      }
      if (_accountCurrent(attempt)) {
        shell._topicData
            .forLease(target.siteUrl, attempt.lease)
            ?.acceptEditedPost(updated, raw: edit.raw);
      }
      return _SubmissionAccepted(
        attempt,
        const _SubmissionEdited(),
        metadata: metadata,
      );
    } finally {
      release?.call();
    }
  }

  void _publishMetadata(
    _ComposerAttempt attempt,
    EditComposerTarget target,
    _SubmittedMetadata metadata, {
    required bool titleChanged,
  }) {
    if (!_accountCurrent(attempt)) return;
    shell.store.update<TopicDetail>(
      target.siteUrl,
      target.topicId,
      (detail) => detail.copyWith(
        title: titleChanged ? metadata.title : null,
        categoryId: metadata.categoryId,
        clearCategory: metadata.categoryId == null,
        tags: metadata.tags,
      ),
    );
    if (!_accountCurrent(attempt)) return;
    shell.store.update<Topic>(
      target.siteUrl,
      target.topicId,
      (topic) => topic.copyWith(
        title: titleChanged ? metadata.title : null,
        categoryId: metadata.categoryId,
        clearCategory: metadata.categoryId == null,
        tags: metadata.tags,
      ),
    );
  }
}
