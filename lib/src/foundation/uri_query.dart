/// Decodes query parameters while dropping pairs with invalid UTF-8 bytes.
///
/// URI syntax validation does not decode query bytes. If decoding [uri] fails,
/// valid pairs and their repeated values are preserved independently.
Map<String, List<String>> validUriQueryParameters(Uri uri) {
  try {
    return uri.queryParametersAll;
  } on FormatException {
    final parameters = <String, List<String>>{};
    for (final pair in uri.query.split('&')) {
      if (pair.isEmpty) continue;
      final equals = pair.indexOf('=');
      try {
        final key = Uri.decodeQueryComponent(
          equals < 0 ? pair : pair.substring(0, equals),
        );
        final value = equals < 0
            ? ''
            : Uri.decodeQueryComponent(pair.substring(equals + 1));
        parameters.putIfAbsent(key, () => []).add(value);
      } on FormatException {
        // A malformed key or value invalidates only this pair.
      }
    }
    return parameters;
  }
}
