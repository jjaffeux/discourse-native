/// A cancellable registration on one plugin-authorized MessageBus channel.
///
/// Cancellation is the only lifecycle authority exposed to plugin code. The
/// application retains ownership of the site's connection, polling cadence,
/// core channels, and final disposal.
abstract interface class PluginLiveChannelSubscription {
  void cancel();
}

/// The MessageBus surface granted to one plugin for one site tracker.
///
/// Implementations reject channels outside the scopes declared by the
/// consuming plugin before reaching the transport. The callback receives the
/// channel-local message id so a plugin can preserve a snapshot cursor across
/// view and tracker replacement.
abstract interface class PluginLiveChannelHandle {
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  });
}
