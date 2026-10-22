part of 'chat_controller.dart';

enum _ChatPinsRetirement { forgotten, evicted, disposed }

final class _ChatChannelPins {
  _ChatChannelPins(this.chat, this.siteUrl, this.channelId)
    : lease = chat._requests.capture(siteUrl);

  final ChatController chat;
  final String siteUrl;
  final int channelId;
  final PluginSiteLease lease;
  final ref = FrameSafeValueNotifier(const ChatPinsState());
  Object? _request;
  int _liveRevision = 0;
  bool _retired = false;

  bool get isCurrent => chat._requestIsCurrent(lease, () => !_retired);

  void advanceLiveRevision() => _liveRevision++;

  void applyLiveEvent(int messageId, {required bool pinned}) {
    if (!isCurrent || !ref.value.fetched) return;
    if (pinned) {
      unawaited(load(force: true));
    } else {
      ref.value = ref.value.copyWith(
        pins: List.unmodifiable([
          for (final pin in ref.value.pins)
            if (pin.messageId != messageId) pin,
        ]),
        clearError: true,
      );
    }
  }

  Future<void> load({bool force = false}) async {
    if (!isCurrent || (!force && (ref.value.fetched || _request != null))) {
      return;
    }
    final target = ChatChannelTarget(channelId);
    final targetKey = ChatController._targetKey(siteUrl, target);
    chat._rememberTarget(siteUrl, target);
    chat._enforceSiteRetention(siteUrl, keep: targetKey);
    final request = Object();
    _request = request;
    ref.value = ref.value.copyWith(loading: true, clearError: true);
    bool ownsRequest() => isCurrent && identical(_request, request);

    try {
      final credentials = await chat._requests.credentialsFor(siteUrl);
      if (!ownsRequest()) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      while (ownsRequest()) {
        final revision = _liveRevision;
        final snapshot = await credentials.run(
          () => chat.api.chatPinnedMessages(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: credentials.clientId,
            channelId: channelId,
          ),
        );
        if (!ownsRequest()) return;
        if (revision != _liveRevision) continue;
        bool canPublish() => ownsRequest() && revision == _liveRevision;
        lease.commit(() {
          for (final pin in snapshot.pins) {
            if (!canPublish()) return;
            chat._putLiveMessage(siteUrl, pin.message);
          }
          if (!canPublish()) return;
          final channel = chat.channel(siteUrl, channelId);
          if (channel != null) {
            chat._putChannel(
              siteUrl,
              channel.withPinSnapshot(
                count: snapshot.pins.length,
                membership: snapshot.membership,
              ),
            );
          }
          if (!canPublish()) return;
          ref.value = ChatPinsState(
            pins: List.unmodifiable(snapshot.pins),
            fetched: true,
          );
          if (canPublish()) {
            chat._enforceSiteRetention(siteUrl, keep: targetKey);
          }
        });
        if (revision == _liveRevision) return;
      }
    } catch (error) {
      if (!ownsRequest()) return;

      ref.value = ref.value.copyWith(
        loading: false,
        fetched: true,
        error: appL10n.couldNotLoadPinnedMessages,
      );
    } finally {
      if (identical(_request, request)) _request = null;
    }
  }

  void retire(_ChatPinsRetirement retirement) {
    _retired = true;
    _request = null;
    if (retirement != _ChatPinsRetirement.disposed) {
      ref.value = const ChatPinsState();
    }
    if (retirement != _ChatPinsRetirement.forgotten) ref.dispose();
  }
}
