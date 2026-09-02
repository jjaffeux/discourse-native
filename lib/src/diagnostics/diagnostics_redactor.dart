import 'dart:io';

abstract final class DiagnosticsRedactor {
  static const int maximumStringLength = 64 * 1024;
  static const Set<String> allowedResponseHeaders = {
    'content-length',
    'content-type',
    'rate-limit',
    'ratelimit-limit',
    'ratelimit-remaining',
    'ratelimit-reset',
    'request-id',
    'retry-after',
    'x-discourse-route',
    'x-rate-limit-limit',
    'x-rate-limit-remaining',
    'x-rate-limit-reset',
    'x-ratelimit-limit',
    'x-ratelimit-remaining',
    'x-ratelimit-reset',
    'x-request-id',
  };

  static final RegExp _urlPattern = RegExp(
    // Capping the scheme scan keeps hostile long non-URL strings linear. A
    // longer scheme still has its final 32 characters matched and redacted.
    r'''[A-Za-z][A-Za-z0-9+.-]{0,31}://[^\s<>"']+''',
    caseSensitive: false,
  );
  static final RegExp _schemeRelativeUrlPattern = RegExp(
    // Scheme-relative URLs (common in Discourse avatar templates) can carry
    // credentials too. The lookbehind excludes `:` and `/` so the `//` inside
    // an absolute URL already handled above is never re-matched, and excludes
    // word characters so doubled slashes inside identifiers stay untouched.
    r'''(?<![:\w/])//[^\s<>"']+''',
  );
  // The name may be the tail of a snake_case identifier: Discourse's own
  // spelling of the credential is `user_api_key`, and push tokens arrive as
  // `push_token`/`device_token`. `\b` would refuse those because `_` is a
  // word character, so the boundary is "not preceded by a letter or digit".
  static final RegExp _sensitiveAssignment = RegExp(
    r'''["']?(?<![A-Za-z0-9])(authorization|proxy[-_ ]?authorization|cookie|set[-_ ]?cookie|x[-_ ]?api[-_ ]?key|api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|auth[-_ ]?token|token|password|passwd|secret|credential|client[-_ ]?(?:id|secret)|ice[-_ ]?(?:pwd|password|ufrag)|livekit[-_ ]?(?:token|jwt|key|secret|credential|password)|turn[-_ ]?(?:username|token|key|secret|credential|password))\b["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;]+)''',
    caseSensitive: false,
  );
  static final RegExp _authorizationValue = RegExp(
    r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _sensitiveHeader = RegExp(
    r'\b(authorization|proxy-authorization|cookie|set-cookie|x-api-key)\s*:\s*[^\r\n]*',
    caseSensitive: false,
  );
  static final RegExp _queryAssignment = RegExp(
    r'([?&][A-Za-z0-9_.~%+-]+)=[^\s&#]*',
  );
  static final RegExp _jwt = RegExp(
    r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])',
  );

  static String uri(Object? input) {
    // Do not truncate until user-info has been removed. In particular, a very
    // long credential can put its terminating `@` beyond the retention limit;
    // truncating first would turn it into an apparently malformed authority
    // whose secret prefix could then be retained.
    final raw = _stripUnambiguousUserInfo(safeString(input));
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

  static Map<String, List<String>> responseHeaders(
    Map<String, List<String>> headers,
  ) {
    final safe = <String, List<String>>{};
    for (final entry in headers.entries) {
      final name = entry.key.toLowerCase().trim();
      if (!allowedResponseHeaders.contains(name)) continue;
      safe[name] = List.unmodifiable(entry.value.map(scrub));
    }
    return Map.unmodifiable(safe);
  }

  static String scrub(Object? value, {String? homeDirectory}) {
    var text = safeString(value);
    if (text.isEmpty) return text;

    text = text.replaceAllMapped(_urlPattern, (match) => uri(match.group(0)));
    text = text.replaceAllMapped(
      _schemeRelativeUrlPattern,
      (match) => uri(match.group(0)),
    );
    text = text.replaceAllMapped(
      _sensitiveHeader,
      (match) => '${match.group(1)}: <redacted>',
    );
    text = text.replaceAllMapped(
      _authorizationValue,
      (match) => '${match.group(1)} <redacted>',
    );
    text = text.replaceAllMapped(
      _sensitiveAssignment,
      (match) => '${match.group(1)}=<redacted>',
    );
    text = text.replaceAll(_jwt, '<redacted-jwt>');
    text = text.replaceAllMapped(_queryAssignment, (match) => match.group(1)!);

    final homes = <String>{
      if (homeDirectory != null && homeDirectory.isNotEmpty) homeDirectory,
      ..._platformHomeDirectories(),
    };
    for (final home in homes) {
      text = text.replaceAll(home, '<home>');
    }
    return _truncate(text);
  }

  static String safeString(Object? value) {
    if (value == null) return '';
    try {
      return value.toString();
    } on Object {
      return '<unprintable ${value.runtimeType}>';
    }
  }

  static List<String> _queryNames(String query) {
    if (query.isEmpty) return const [];
    return [
      for (final part in query.split('&'))
        if (part.isNotEmpty) _safeQueryName(part.split('=').first),
    ];
  }

  static String _rawQuery(String value) {
    final question = value.indexOf('?');
    if (question < 0) return '';
    final fragment = value.indexOf('#');
    if (fragment >= 0 && fragment < question) return '';
    return value.substring(question + 1, fragment < 0 ? null : fragment);
  }

  static String _safeQueryName(String rawName) {
    try {
      // A percent-encoded `=` (`code%3DSECRET`) survives the raw `=` split as
      // an apparent bare name, so only what precedes `=` after decoding may be
      // retained.
      final decoded = Uri.decodeQueryComponent(rawName);
      return Uri.encodeQueryComponent(decoded.split('=').first);
    } on ArgumentError {
      // Keeping malformed bytes would make it too easy to accidentally retain
      // part of a value while attempting recovery. The shape still records
      // that a query component existed without preserving its contents.
      return 'invalid-query-name';
    }
  }

  static String _redactMalformedUri(String raw) {
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

  static String _stripUnambiguousUserInfo(String raw) {
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
    return raw.replaceRange(
      authorityStart,
      authorityStart + userInfoEnd + 1,
      '',
    );
  }

  static Set<String> _platformHomeDirectories() {
    try {
      return {
        if (Platform.environment['HOME'] case final home? when home.isNotEmpty)
          home,
        if (Platform.environment['USERPROFILE'] case final home?
            when home.isNotEmpty)
          home,
      };
    } on Object {
      return const {};
    }
  }

  static String _truncate(String value) {
    if (value.length <= maximumStringLength) return value;
    return '${value.substring(0, maximumStringLength)}…<truncated>';
  }
}
