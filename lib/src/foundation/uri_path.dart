/// Decodes a URI path only when every percent-encoded segment is valid UTF-8.
///
/// URI syntax validation does not decode these bytes, so even a URI returned
/// by `Uri.tryParse` can throw when a link reader asks for its segments.
List<String>? tryUriPathSegments(Uri uri) {
  try {
    return uri.pathSegments;
  } on FormatException {
    return null;
  }
}
