import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_stream_target.dart';

/// Binds one editor to the shared draft without sharing its edit preparation.
final class ChatComposerDraftSession {
  ChatComposerDraftSession({
    required this.chat,
    required this.siteUrl,
    required this.target,
    required this.composer,
    ChatMessage? editingMessage,
  }) : _editingMessage = editingMessage {
    _accountId = chat.currentUserFor(siteUrl)?.id;
    _accountSession = chat.captureSession(siteUrl);
    _retainedDraft = chat.composerDraftListenableFor(siteUrl, target);
    chat.addListener(_accountChanged);
    _retainedDraft.addListener(_applyRetainedDraft);
    composer.addListener(_retainDraft);
    composer.text.addListener(_retainDraft);
    _applyRetainedDraft();
    _retainDraft();
    if (editingMessage != null) _replaceWithMessage(editingMessage);
  }

  final ChatController chat;
  final String siteUrl;
  final ChatStreamTarget target;
  final ComposerController composer;
  final Object editCookingOwner = Object();
  final _replyChanges = FrameSafeValueNotifier<ChatReplyTo?>(null);
  late ValueListenable<ChatComposerDraft?> _retainedDraft;
  late PluginSiteLease _accountSession;
  int? _accountId;
  ChatMessage? _editingMessage;
  int? _editCookingMessageId;
  ({ChatComposerDraft draft, Set<int> completedUploadIds})? _deferred;
  bool _applyingRetainedDraft = false;
  bool _disposed = false;

  ValueListenable<ChatReplyTo?> get replyChanges => _replyChanges;

  ChatReplyTo? get replyTo =>
      target.isThread ? null : _retainedDraft.value?.replyTo;

  void _accountChanged() {
    if (_disposed) return;
    final accountId = chat.currentUserFor(siteUrl)?.id;
    final sessionChanged = !_accountSession.isCurrent;
    if (accountId == _accountId && !sessionChanged) return;
    _accountId = accountId;
    cancelEditCooking();
    if (!sessionChanged) return;

    _accountSession = chat.captureSession(siteUrl);
    _deferred = null;
    _replaceDocument(chat.composerDraftFor(siteUrl, target));
    final next = chat.composerDraftListenableFor(siteUrl, target);
    if (identical(next, _retainedDraft)) return;
    _retainedDraft.removeListener(_applyRetainedDraft);
    _retainedDraft = next;
    next.addListener(_applyRetainedDraft);
    _applyRetainedDraft();
  }

  void _replaceDocument(ChatComposerDraft? draft) {
    _applyingRetainedDraft = true;
    try {
      composer.replacePluginDocument(
        raw: draft?.raw ?? '',
        uploads: draft?.uploads ?? const [],
      );
    } finally {
      _applyingRetainedDraft = false;
    }
  }

  void _applyRetainedDraft() {
    if (_disposed) return;
    _replyChanges.value = replyTo;
    if (_applyingRetainedDraft || _editingMessage != null) return;
    final next =
        _retainedDraft.value ?? ChatComposerDraft(raw: '', uploads: const []);
    final current = ChatComposerDraft(
      raw: composer.raw,
      uploads: composer.completedUploads,
      replyTo: replyTo,
    );
    if (current == next) return;

    if (!composer.hasActiveUploads) {
      _deferred = null;
      _replaceDocument(next);
      return;
    }
    _deferred = (
      draft: next,
      completedUploadIds:
          _deferred?.completedUploadIds ??
          {for (final upload in composer.completedUploads) upload.id},
    );
    _applyingRetainedDraft = true;
    try {
      if (composer.text.text != next.raw) {
        composer.text.value = TextEditingValue(
          text: next.raw,
          selection: TextSelection.collapsed(offset: next.raw.length),
        );
      }
    } finally {
      _applyingRetainedDraft = false;
    }
  }

  void _retainDraft() {
    if (_disposed || _applyingRetainedDraft) return;
    if (_editingMessage != null) {
      prepareEditCooking();
      return;
    }

    if (_deferred case final deferred?) {
      if (composer.hasActiveUploads) {
        final next = ChatComposerDraft(
          raw: composer.raw,
          uploads: deferred.draft.uploads,
          replyTo: replyTo,
        );
        _deferred = (
          draft: next,
          completedUploadIds: deferred.completedUploadIds,
        );
        _publish(next);
        return;
      }
      final mergedUploads = [...deferred.draft.uploads];
      final retainedIds = {for (final upload in mergedUploads) upload.id};
      for (final upload in composer.completedUploads) {
        if (!deferred.completedUploadIds.contains(upload.id) &&
            retainedIds.add(upload.id)) {
          mergedUploads.add(upload);
        }
      }
      final merged = ChatComposerDraft(
        raw: composer.raw,
        uploads: mergedUploads,
        replyTo: replyTo,
      );
      _deferred = null;
      _replaceDocument(merged);
      _publish(merged);
      return;
    }
    _publish(
      ChatComposerDraft(
        raw: composer.raw,
        uploads: composer.completedUploads,
        replyTo: replyTo,
      ),
    );
  }

  void _publish(ChatComposerDraft draft) => chat.retainComposerDraft(
    siteUrl,
    target,
    raw: draft.raw,
    uploads: draft.uploads,
    replyTo: draft.replyTo,
  );

  void updateEditingMessage(ChatMessage? message) {
    if (_disposed || _editingMessage?.id == message?.id) return;
    cancelEditCooking();
    _deferred = null;
    _editingMessage = message;
    if (message != null) {
      _replaceWithMessage(message);
    } else {
      _replaceDocument(_retainedDraft.value);
    }
  }

  void _replaceWithMessage(ChatMessage message) {
    composer.replacePluginDocument(
      raw: message.raw,
      uploads: [
        for (final upload in message.uploads)
          ComposerUploadResult(
            id: upload.id,
            originalFilename: upload.originalFilename,
            shortUrl: upload.url,
            url: upload.url,
            width: upload.width,
            height: upload.height,
            thumbnailUrl: upload.thumbnailUrl,
          ),
      ],
    );
    prepareEditCooking();
  }

  void prepareEditCooking() {
    final message = _editingMessage;
    if (_disposed || message == null) return;
    if (_editCookingMessageId != message.id) {
      cancelEditCooking();
      _editCookingMessageId = message.id;
    }
    chat.prepareEditCooking(
      siteUrl,
      message,
      composer.raw,
      owner: editCookingOwner,
    );
  }

  void cancelEditCooking() {
    final messageId = _editCookingMessageId;
    _editCookingMessageId = null;
    if (messageId != null) {
      chat.cancelEditCooking(siteUrl, messageId, owner: editCookingOwner);
    }
  }

  void clearEditDocument() {
    _applyingRetainedDraft = true;
    try {
      composer.clearDocument();
    } finally {
      _applyingRetainedDraft = false;
    }
  }

  void clearReply() {
    final draft = _retainedDraft.value;
    if (draft?.replyTo == null) return;
    chat.retainComposerDraft(
      siteUrl,
      target,
      raw: draft!.raw,
      uploads: draft.uploads,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelEditCooking();
    chat.removeListener(_accountChanged);
    composer.removeListener(_retainDraft);
    composer.text.removeListener(_retainDraft);
    _retainedDraft.removeListener(_applyRetainedDraft);
    _deferred = null;
    composer.dispose();
    _replyChanges.dispose();
    chat.suspendComposerCookingIfUnobserved(siteUrl, target);
  }
}
