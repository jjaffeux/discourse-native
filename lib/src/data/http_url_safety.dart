import '../foundation/loopback_host.dart';
import '../foundation/redacted_uri.dart';

final class UnsafeHttpTransportException implements Exception {
  UnsafeHttpTransportException(Uri url) : url = Uri.parse(redactUri(url));

  /// A safe representation with credentials, fragments, and query
  /// values removed. Rejected request data must not outlive the safety check.
  final Uri url;

  @override
  String toString() => 'UnsafeHttpTransportException($url)';
}

/// Plaintext is accepted only for loopback development.
Uri requireSafeHttpUrl(Uri url) {
  if (!url.hasAuthority || url.host.isEmpty || url.userInfo.isNotEmpty) {
    throw UnsafeHttpTransportException(url);
  }
  if (url.hasPort) {
    try {
      if (url.port < 1 || url.port > 65535) {
        throw UnsafeHttpTransportException(url);
      }
    } on FormatException {
      throw UnsafeHttpTransportException(url);
    }
  }
  if (url.scheme == 'https') return url;
  if (url.scheme == 'http' && isLoopbackHost(url.host)) return url;

  throw UnsafeHttpTransportException(url);
}

Uri resolveSafeHttpRedirect(Uri source, String location) {
  final target = source.resolve(location);
  if (source.scheme == 'https' && target.scheme != 'https') {
    throw UnsafeHttpTransportException(target);
  }
  return requireSafeHttpUrl(target);
}

bool isHttpRedirectStatus(int status) => switch (status) {
  301 || 302 || 303 || 307 || 308 => true,
  _ => false,
};
