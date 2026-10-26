part of 'voice_controller.dart';

final class _VoiceChatAssociation {
  _VoiceChatAssociation(this.controller, this.siteUrl, this.roomId)
    : siteSession = controller._siteSession(siteUrl);

  final VoiceController controller;
  final String siteUrl;
  final int roomId;
  final Object siteSession;
  VoiceChatSession session = const VoiceChatSession();
  _VoiceChatBinding? _binding;
  ChatConversation? get conversation => _binding?.conversation;
  PluginLiveChannelSubscription? liveUpdates;
  Object? _request;
  bool _retired = false;
  bool visible = false;
  bool loading = false;
  bool sending = false;
  String? error;

  bool get isCurrent =>
      !_retired &&
      controller._isCurrentSiteSession(siteUrl, siteSession) &&
      identical(controller._chats[(siteUrl, roomId)], this);

  VoiceChatSnapshot get snapshot {
    final value = conversation?.value;
    return VoiceChatSnapshot(
      session: session,
      messages: value?.messages ?? const [],
      loading: loading || (value?.loading ?? false),
      sending: sending || (value?.sending ?? false),
      canLoadMorePast: value?.canLoadMorePast ?? false,
      error: error ?? value?.error,
    );
  }

  void _notifyChanged() {
    controller._notifyChatChanged(this);
  }

  void hide() {
    _request = null;
    visible = false;
    loading = false;
    detachTracker();
    _closeConversation();
  }

  void retire() {
    _retired = true;
    hide();
  }

  Future<void> loadOlder() => conversation?.loadOlder() ?? Future<void>.value();

  Future<void> open({bool force = false}) async {
    if (!isCurrent || (!force && loading)) return;
    final request = Object();
    _request = request;
    bool ownsRequest() => isCurrent && identical(_request, request);
    this
      ..visible = true
      ..loading = true
      ..error = null;
    _notifyChanged();
    try {
      final credentials = await controller._keyRequestCredentials(
        siteUrl,
        ifCurrent: ownsRequest,
      );
      if (credentials == null) return;
      final loadedSession = await credentials.run(
        () => controller.api.chatSession(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: credentials.apiKey!,
        ),
      );
      if (!ownsRequest()) return;
      session = loadedSession;
      syncTracker();
      final conversation = _bindConversation();
      if (conversation != null) await conversation.refresh(force: force);
    } catch (error) {
      if (!ownsRequest()) return;
      this.error = appL10n.couldnTLoadRoomChat;
    } finally {
      if (ownsRequest()) {
        _request = null;
        loading = false;
        _notifyChanged();
      }
    }
  }

  void syncTracker() {
    if (!isCurrent || !visible || liveUpdates != null) return;
    final tracker = controller._trackerFor(siteUrl);
    if (tracker == null) return;
    final root = controller.api.namespaceFor(siteUrl).root;
    liveUpdates = tracker.subscribe('$root/rooms/$roomId/chat', (data, _) {
      if (!isCurrent || !visible) {
        return;
      }
      if (data is Map && data['type'] == 'updated') {
        controller._observe(_refreshSession);
      }
    });
  }

  void detachTracker() {
    liveUpdates?.cancel();
    liveUpdates = null;
  }

  Future<void> _refreshSession() async {
    if (!isCurrent || !visible) return;
    if (loading) return open(force: true);
    final request = Object();
    _request = request;
    bool ownsRequest() => isCurrent && identical(_request, request) && visible;
    try {
      final credentials = await controller._keyRequestCredentials(
        siteUrl,
        ifCurrent: ownsRequest,
      );
      if (credentials == null) return;
      final loadedSession = await credentials.run(
        () => controller.api.chatSession(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: credentials.apiKey!,
        ),
      );
      if (!ownsRequest()) return;
      final changed =
          loadedSession.channelId != session.channelId ||
          loadedSession.threadId != session.threadId;
      session = loadedSession;
      final conversation = _bindConversation();
      if (conversation != null && changed) {
        await conversation.refresh(force: true);
      }
      if (ownsRequest()) _notifyChanged();
    } catch (_) {
    } finally {
      if (identical(_request, request)) _request = null;
    }
  }

  Future<void> send(String message) async {
    if (!isCurrent || message.trim().isEmpty) return;
    final heldConversation = conversation;
    if (heldConversation != null) {
      if (error != null) {
        error = null;
        _notifyChanged();
      }
      await heldConversation.send(message);
      return;
    }
    final credentials = await controller._keyRequestCredentials(
      siteUrl,
      ifCurrent: () => isCurrent,
    );
    if (credentials == null) return;
    final apiKey = credentials.apiKey!;
    this
      ..sending = true
      ..error = null;
    _notifyChanged();
    try {
      var sendSession = session;
      if (sendSession.channelId == null) {
        sendSession = await credentials.run(
          () => controller.api.chatSession(
            siteUrl: siteUrl,
            roomId: roomId,
            apiKey: apiKey,
            ensure: true,
          ),
        );
        if (!isCurrent) return;
      }
      var sentFirstMessage = false;
      if (sendSession.threadId == null) {
        sendSession = await credentials.run(
          () => controller.api.firstChatMessage(
            siteUrl: siteUrl,
            roomId: roomId,
            apiKey: apiKey,
            message: message,
          ),
        );
        if (!isCurrent) return;
        sentFirstMessage = true;
      }
      this
        ..session = sendSession
        ..sending = false;
      final retainConversation = visible;
      final conversation = retainConversation
          ? _bindConversation()
          : sentFirstMessage
          ? null
          : _temporaryConversation(session);
      try {
        if (conversation != null) {
          if (sentFirstMessage) {
            if (retainConversation) await conversation.refresh(force: true);
          } else {
            await conversation.send(message);
            final sendError = conversation.value.error;
            if (isCurrent && !retainConversation && sendError != null) {
              error = sendError;
            }
          }
        }
      } finally {
        if (!retainConversation) conversation?.close();
      }
      if (isCurrent) _notifyChanged();
    } catch (error) {
      if (!isCurrent) return;
      this
        ..sending = false
        ..error = appL10n.messageNotSent;

      _notifyChanged();
    }
  }

  ChatConversation? _bindConversation() {
    if (!isCurrent || !visible) {
      _closeConversation();
      return null;
    }
    final channelId = session.channelId;
    final threadId = session.threadId;
    final held = this.conversation;
    if (channelId == null || threadId == null) {
      _closeConversation();
      return null;
    }
    if (held != null &&
        held.channelId == channelId &&
        held.threadId == threadId) {
      return held;
    }

    _closeConversation();
    final conversation = controller.chatConversations.openThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
    );
    void conversationChanged() {
      if (isCurrent && identical(this.conversation, conversation)) {
        _notifyChanged();
      }
    }

    _binding = _VoiceChatBinding(conversation, conversationChanged);
    return conversation;
  }

  ChatConversation? _temporaryConversation(VoiceChatSession session) {
    final channelId = session.channelId;
    final threadId = session.threadId;
    if (channelId == null || threadId == null) return null;
    return controller.chatConversations.openThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
    );
  }

  void _closeConversation() {
    final binding = _binding;
    _binding = null;
    binding?.close();
  }
}

final class _VoiceChatBinding {
  _VoiceChatBinding(this.conversation, this.listener) {
    conversation.addListener(listener);
  }

  final ChatConversation conversation;
  final VoidCallback listener;

  void close() {
    conversation.removeListener(listener);
    conversation.close();
  }
}
