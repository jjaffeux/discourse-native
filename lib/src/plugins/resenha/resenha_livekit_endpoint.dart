/// A LiveKit endpoint that is unsafe to receive a room access token.
///
/// Deliberately does not retain the rejected value: URLs containing userinfo
/// can themselves contain credentials and may be included in error reports.
final class UnsafeLiveKitEndpointException implements Exception {
  const UnsafeLiveKitEndpointException();

  @override
  String toString() => 'UnsafeLiveKitEndpointException';
}

/// Parses a LiveKit endpoint and enforces transport safety.
///
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
      _isLoopbackHost(endpoint.host)) {
    return endpoint;
  }

  throw const UnsafeLiveKitEndpointException();
}

bool _isLoopbackHost(String host) {
  var normalized = host.toLowerCase();
  if (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  if (normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized == '::1') {
    return true;
  }

  final octets = normalized.split('.').map(int.tryParse).toList();
  return octets.length == 4 &&
      octets.every((octet) => octet != null && octet >= 0 && octet <= 255) &&
      octets.first == 127;
}
