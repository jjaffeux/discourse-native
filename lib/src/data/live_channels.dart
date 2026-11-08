/// Cancellation is the only connection lifecycle authority exposed to plugins.
abstract interface class PluginLiveChannelSubscription {
  void cancel();
}

/// Implementations reject channels outside the scopes declared by the
/// consuming plugin before reaching the transport.
abstract interface class PluginLiveChannelHandle {
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  });
}
