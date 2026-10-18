abstract final class FeedPathPolicy {
  static const maximumPathLength = 2048;

  // A 2048-code-unit search can expand ninefold in a UTF-8 URI.
  static const maximumEncodedLength = 24 * 1024;

  static bool accepts(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximumEncodedLength) {
      return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.path.length > maximumPathLength ||
        uri.toString().length > maximumEncodedLength ||
        !value.startsWith('/') ||
        value.startsWith('//') ||
        uri.path.isEmpty ||
        !uri.path.endsWith('.json') ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return false;
    }
    try {
      final _ = uri.pathSegments;
      final _ = uri.queryParametersAll;
    } on FormatException {
      return false;
    }
    return true;
  }
}
