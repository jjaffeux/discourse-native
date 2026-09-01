import 'package:discourse_native/discourse_plugin_sdk.dart';

/// Deliberately does not retain the rejected value: URLs containing userinfo
/// can themselves contain credentials and may be included in error reports.
final class UnsafeLiveKitEndpointException implements Exception {
  const UnsafeLiveKitEndpointException();

  @override
  String toString() => 'UnsafeLiveKitEndpointException';
}

/// The pinned LiveKit client converts `https` to `wss` and `http` to `ws` when
/// constructing its signaling URL. Plaintext variants are therefore reserved
/// for explicit loopback development hosts.
Uri requireSafeLiveKitEndpoint(String value) {
  final endpoint = Uri.tryParse(value);
  if (endpoint == null ||
      !endpoint.hasAuthority ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.fragment.isNotEmpty ||
      (endpoint.hasPort && (endpoint.port < 1 || endpoint.port > 65535))) {
    throw const UnsafeLiveKitEndpointException();
  }

  if (endpoint.scheme == 'wss' || endpoint.scheme == 'https') {
    return endpoint;
  }
  if ((endpoint.scheme == 'ws' || endpoint.scheme == 'http') &&
      isLoopbackHost(endpoint.host)) {
    return endpoint;
  }

  throw const UnsafeLiveKitEndpointException();
}
