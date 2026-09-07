import 'http_transport.dart';

/// Validates persisted forum identities without accepting user-input shorthand.
/// Subfolder paths are retained; trailing slashes match connected-site storage.
String requireStoredForumBase(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid stored forum base URL.');
  }

  final Uri parsed;
  try {
    parsed = Uri.parse(value);
  } on FormatException {
    // Uri.parse's exception retains its source. Do not put a damaged value
    // (which may contain credentials) into diagnostics.
    throw const FormatException('Invalid stored forum base URL.');
  }

  final safe = requireSafeHttpUrl(parsed);
  if (safe.hasQuery || safe.hasFragment) {
    throw UnsafeHttpTransportException(safe);
  }

  // `DiscourseInstance.url` is both identity and base URL, and a forum can
  // be served from a subfolder. Keep one stable spelling — no trailing
  // slash — even when an older entry persisted the root slash.
  final path = safe.path.replaceFirst(RegExp(r'/+$'), '');
  return '${safe.origin}$path';
}

/// Invalid preference entries are skipped without losing the rest of the tab.
String? tryStoredForumBase(Object? value) {
  try {
    return requireStoredForumBase(value);
  } on FormatException {
    return null;
  } on UnsafeHttpTransportException {
    return null;
  }
}
