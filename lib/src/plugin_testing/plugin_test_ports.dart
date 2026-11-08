import '../data/discourse_api_contracts.dart';
import '../data/live_channels.dart';
import '../data/site_lifecycle.dart';
import '../plugin_api/core_plugin_host.dart';

final class PluginTestRequestHost implements PluginRequestHost {
  PluginTestRequestHost({
    Map<String, String> apiKeys = const {},
    this.clientId = 'test-client',
  }) : apiKeys = Map.of(apiKeys);

  final Map<String, String> apiKeys;
  final String clientId;
  final _lifecycle = SiteLifecycle();

  void forget(String siteUrl) {
    _lifecycle.invalidate(siteUrl);
  }

  @override
  PluginSiteLease capture(String siteUrl) {
    return _PluginTestSiteLease(_lifecycle.capture(siteUrl));
  }

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      PluginRequestCredentials(apiKey: apiKeys[siteUrl], clientId: clientId);

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    final apiKey = apiKeys[siteUrl];
    return (
      credentials: apiKey == null
          ? null
          : PluginRequestCredentials(apiKey: apiKey, clientId: ''),
      failure: apiKey == null
          ? const WriteException(WriteFailure.forbidden)
          : null,
    );
  }
}

final class _PluginTestSiteLease implements PluginSiteLease {
  const _PluginTestSiteLease(this._lease);

  final SiteLease _lease;

  @override
  bool get isCurrent => _lease.isCurrent;

  @override
  bool commit(void Function() mutation) => _lease.commit(mutation);

  @override
  void Function() onRetire(void Function() observer) =>
      _lease.onRetire(observer);
}

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

  void deliver(String channel, Object? data, {int messageId = 1}) {
    for (final registration in List.of(
      _registrations[channel] ?? const <_PluginLiveRegistration>[],
    )) {
      registration.deliver(data, messageId);
    }
  }

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
