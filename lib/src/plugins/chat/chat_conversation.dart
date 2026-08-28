import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chat_controller.dart';
import 'chat_conversation_contract.dart';
import 'chat_message.dart';
import 'chat_stream_target.dart';

/// Adapts Chat's complete controller to the deliberately small embedded
/// conversation contract exposed to dependent plugins.
final class ChatControllerConversationCapability
    implements ChatConversationCapability {
  const ChatControllerConversationCapability(this._chat);

  final ChatController _chat;

  @override
  ChatConversation openThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
  }) {
    if (channelId <= 0 || threadId <= 0) {
      throw ArgumentError('Chat conversation ids must be positive.');
    }
    return _ControllerChatConversation(
      chat: _chat,
      siteUrl: siteUrl,
      target: ChatThreadTarget(channelId: channelId, threadId: threadId),
    );
  }
}

final class _ControllerChatConversation extends ChangeNotifier
    implements ChatConversation {
  _ControllerChatConversation({
    required ChatController chat,
    required this.siteUrl,
    required ChatThreadTarget target,
  }) : _chat = chat,
       _target = target,
       _stream = chat.streamListenableFor(siteUrl, target),
       _viewToken = chat.beginViewingThread(siteUrl, target) {
    _stream.addListener(_streamChanged);
  }

  final ChatController _chat;
  final ChatThreadTarget _target;
  final ValueListenable<ChatStreamState> _stream;
  final Object _viewToken;

  bool _refreshing = false;
  bool _sending = false;
  bool _closed = false;
  int? _lastReadMessageId;
  String? _operationError;
  Object? _refreshGeneration;

  @override
  final String siteUrl;

  @override
  int get channelId => _target.channelId;

  @override
  int get threadId => _target.threadId;

  @override
  ChatConversationSnapshot get value {
    final stream = _stream.value;
    return ChatConversationSnapshot(
      messages: List.unmodifiable(_chat.messagesFor(siteUrl, _target)),
      loading: _refreshing || stream.loading || stream.loadingOlder,
      sending: _sending,
      canLoadMorePast: stream.canLoadMorePast,
      error: _operationError ?? stream.error,
    );
  }

  @override
  Future<void> refresh({bool force = false}) async {
    if (_closed) return;
    final generation = Object();
    _refreshGeneration = generation;
    _refreshing = true;
    _operationError = null;
    notifyListeners();
    try {
      final channel = await _chat.ensureChannel(siteUrl, channelId);
      if (_closed || !identical(_refreshGeneration, generation)) return;
      if (channel == null) {
        _operationError = 'Could not load this conversation.';
        return;
      }
      await _chat.openThread(siteUrl, _target, force: force);
      if (_closed || !identical(_refreshGeneration, generation)) return;
      _markNewestRead();
    } catch (_) {
      if (!_closed && identical(_refreshGeneration, generation)) {
        _operationError = 'Could not load this conversation.';
      }
    } finally {
      if (!_closed && identical(_refreshGeneration, generation)) {
        _refreshing = false;
        _refreshGeneration = null;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> loadOlder() async {
    if (_closed || !value.canLoadMorePast) return;
    _operationError = null;
    notifyListeners();
    await _chat.loadOlderFor(siteUrl, _target);
  }

  @override
  Future<void> send(String message) async {
    final text = message.trim();
    if (_closed || _sending || text.isEmpty) return;
    _sending = true;
    _operationError = null;
    notifyListeners();
    try {
      final handle = _chat.sendMessageTo(
        siteUrl,
        _target,
        OutgoingChatMessage.text(text),
      );
      if (handle == null) {
        _operationError = 'Message not sent.';
        return;
      }
      final result = await handle.settled;
      if (_closed) return;
      if (result == ChatSendResult.failed) {
        _operationError = 'Message not sent.';
      }
    } finally {
      if (!_closed) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  void _streamChanged() {
    if (_closed) return;
    _markNewestRead();
    notifyListeners();
  }

  void _markNewestRead() {
    final stream = _stream.value;
    final messageId = stream.newestId;
    if (messageId == null ||
        messageId <= 0 ||
        messageId == _lastReadMessageId) {
      return;
    }
    _lastReadMessageId = messageId;
    unawaited(_chat.markReadFor(siteUrl, _target, messageId));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _stream.removeListener(_streamChanged);
    _chat.endViewingThread(siteUrl, _target, _viewToken);
    dispose();
  }
}
