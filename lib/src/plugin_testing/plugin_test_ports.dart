import '../data/discourse_api_contracts.dart';
import '../plugin_api/core_plugin_host.dart';
import '../plugin_api/live_channels.dart';

/// Deterministic credentials and site-generation authority for plugin tests.
///
/// Tests can mutate [apiKeys] to model connection changes and call [forget] to
/// invalidate leases captured before an account or site boundary changed.
final class PluginTestRequestHost implements PluginRequestHost {
  PluginTestRequestHost({
    Map<String, String> apiKeys = const {},
    this.clientId = 'test-client',
  }) : apiKeys = Map.of(apiKeys);

  final Map<String, String> apiKeys;
  final String clientId;
  final Map<String, int> _generations = {};

  /// Invalidates every lease already captured for [siteUrl].
  void forget(String siteUrl) {
    _generations[siteUrl] = (_generations[siteUrl] ?? 0) + 1;
  }

  @override
  PluginSiteLease capture(String siteUrl) {
    final generation = _generations[siteUrl] ?? 0;
    return _PluginTestSiteLease(
      () => (_generations[siteUrl] ?? 0) == generation,
    );
  }

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      PluginRequestCredentials(apiKey: apiKeys[siteUrl], clientId: clientId);

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    final apiKey = apiKeys[siteUrl];
    return (
      apiKey: apiKey,
      failure: apiKey == null
          ? const WriteException(WriteFailure.forbidden)
          : null,
    );
  }
}

final class _PluginTestSiteLease implements PluginSiteLease {
  const _PluginTestSiteLease(this._isCurrent);

  final bool Function() _isCurrent;

  @override
  bool get isCurrent => _isCurrent();

  @override
  bool commit(void Function() mutation) {
    if (!isCurrent) return false;
    mutation();
    return true;
  }
}

/// In-memory plugin live channels with explicit delivery and cancellation.
///
/// It implements only the least-privilege plugin port. Core tracker polling,
/// topic subscriptions, and connection lifecycle are intentionally absent.
class RecordingPluginLiveChannels implements PluginLiveChannelHandle {
  final Map<String, List<_PluginLiveRegistration>> _registrations = {};
  final Map<String, int?> _lastIds = {};

  Map<String, int?> get lastIds => Map.unmodifiable(_lastIds);

  List<String> get channels => List.unmodifiable(_registrations.keys);

  int subscriberCount(String channel) => _registrations[channel]?.length ?? 0;

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    _lastIds[channel] = lastId;
    late final _PluginLiveRegistration registration;
    registration = _PluginLiveRegistration(
      onMessage,
      () => _remove(channel, registration),
    );
    (_registrations[channel] ??= []).add(registration);
    return registration;
  }

  /// Delivers one channel-local MessageBus event to current subscribers.
  void deliver(String channel, Object? data, {int messageId = 1}) {
    for (final registration in List.of(
      _registrations[channel] ?? const <_PluginLiveRegistration>[],
    )) {
      registration.deliver(data, messageId);
    }
  }

  /// Cancels every subscription and forgets recorded cursors.
  void clear() {
    final registrations = [
      for (final values in _registrations.values) ...values,
    ];
    for (final registration in registrations) {
      registration.cancel();
    }
    _registrations.clear();
    _lastIds.clear();
  }

  void _remove(String channel, _PluginLiveRegistration registration) {
    final registrations = _registrations[channel];
    registrations?.remove(registration);
    if (registrations?.isEmpty == true) _registrations.remove(channel);
  }
}

final class _PluginLiveRegistration implements PluginLiveChannelSubscription {
  _PluginLiveRegistration(this._onMessage, this._remove);

  final void Function(Object? data, int messageId) _onMessage;
  final void Function() _remove;
  bool _cancelled = false;

  void deliver(Object? data, int messageId) {
    if (!_cancelled) _onMessage(data, messageId);
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _remove();
  }
}
