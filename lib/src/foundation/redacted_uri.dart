const int _maximumStringLength = 64 * 1024;

String redactUri(Object? input) {
  // Do not truncate until user-info has been removed. In particular, a very
  // long credential can put its terminating `@` beyond the retention limit;
  // truncating first would turn it into an apparently malformed authority
  // whose secret prefix could then be retained.
  final raw = _stripUnambiguousUserInfo(_safeString(input));
  if (raw.isEmpty) return raw;

  try {
    final parsed = Uri.parse(raw);
    // Uri.parse normalizes malformed percent escapes (for example `%ZZ` to
    // `%25ZZ`). Validate the original query names so malformed bytes never
    // leak through under the guise of a normalized name.
    final queryNames = _queryNames(_rawQuery(raw));
    var base = parsed.replace(userInfo: '').toString();
    final queryStart = base.indexOf('?');
    final fragmentStart = base.indexOf('#');
    final privateStart = switch ((queryStart, fragmentStart)) {
      (-1, -1) => -1,
      (-1, _) => fragmentStart,
      (_, -1) => queryStart,
      _ => queryStart < fragmentStart ? queryStart : fragmentStart,
    };
    if (privateStart >= 0) base = base.substring(0, privateStart);
    final safe = queryNames.isEmpty ? base : '$base?${queryNames.join('&')}';
    return _truncate(safe);
  } on FormatException {
    return _truncate(_redactMalformedUri(raw));
  }
}

String _safeString(Object? value) {
  if (value == null) return '';
  try {
    return value.toString();
  } on Object {
    return '<unprintable ${value.runtimeType}>';
  }
}

List<String> _queryNames(String query) {
  if (query.isEmpty) return const [];
  return [
    for (final part in query.split('&'))
      if (part.isNotEmpty) _safeQueryName(part.split('=').first),
  ];
}

String _rawQuery(String value) {
  final question = value.indexOf('?');
  if (question < 0) return '';
  final fragment = value.indexOf('#');
  if (fragment >= 0 && fragment < question) return '';
  return value.substring(question + 1, fragment < 0 ? null : fragment);
}

String _safeQueryName(String rawName) {
  try {
    // A percent-encoded `=` (`code%3DSECRET`) survives the raw `=` split as
    // an apparent bare name, so only what precedes `=` after decoding may be
    // retained.
    final decoded = Uri.decodeQueryComponent(rawName);
    return Uri.encodeQueryComponent(decoded.split('=').first);
  } on FormatException {
    // Well-formed percent escapes can still encode invalid UTF-8. The
    // malformed-URI fallback uses this decoder too, so this failure must be
    // contained here instead of escaping while reporting another error.
    return 'invalid-query-name';
  } on ArgumentError {
    // Keeping malformed bytes would make it too easy to accidentally retain
    // part of a value while attempting recovery. The shape still records
    // that a query component existed without preserving its contents.
    return 'invalid-query-name';
  }
}

String _redactMalformedUri(String raw) {
  final hash = raw.indexOf('#');
  var value = hash < 0 ? raw : raw.substring(0, hash);
  final question = value.indexOf('?');
  final base = question < 0 ? value : value.substring(0, question);
  final names = question < 0
      ? const <String>[]
      : _queryNames(value.substring(question + 1));

  // If an absolute URI cannot be parsed, none of its apparent authority is
  // trustworthy. Redact it as a unit rather than trying to recover around
  // delimiters: malformed credentials can contain `/` before their `@`, and
  // invalid ports can otherwise look like `user:password`.
  final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):\/\/').firstMatch(base);
  if (scheme != null) {
    final prefix = '${scheme.group(1)}://<redacted-malformed-uri>';
    return names.isEmpty ? prefix : '$prefix?${names.join('&')}';
  }

  // A scheme-relative authority that fails to parse is just as
  // untrustworthy: its malformed credentials can also contain `/` before
  // their `@`, which the fallback below deliberately never matches across.
  if (base.startsWith('//')) {
    const prefix = '//<redacted-malformed-uri>';
    return names.isEmpty ? prefix : '$prefix?${names.join('&')}';
  }

  value = names.isEmpty ? base : '$base?${names.join('&')}';
  return value.replaceFirst(RegExp(r'//[^/@\s]+@'), '//<redacted>@');
}

String _stripUnambiguousUserInfo(String raw) {
  final scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:\/\/').firstMatch(raw);
  if (scheme == null) return raw;

  final authorityStart = scheme.end;
  var authorityEnd = raw.length;
  for (final delimiter in const ['/', '?', '#']) {
    final index = raw.indexOf(delimiter, authorityStart);
    if (index >= 0 && index < authorityEnd) authorityEnd = index;
  }
  final authority = raw.substring(authorityStart, authorityEnd);
  final userInfoEnd = authority.lastIndexOf('@');
  if (userInfoEnd < 0) return raw;
  return raw.replaceRange(authorityStart, authorityStart + userInfoEnd + 1, '');
}

String _truncate(String value) {
  if (value.length <= _maximumStringLength) return value;
  return '${value.substring(0, _maximumStringLength)}…<truncated>';
}
