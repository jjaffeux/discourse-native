import 'dart:io';

/// Browser-equivalent rules matter here: Discourse marks
/// avatar and emoji assets public and immutable for about a year.
DateTime? persistentByteCacheExpiry(Map<String, String> headers, DateTime now) {
  if (!responseAllowsPersistentByteCache(headers)) return null;

  final directives = _cacheControlDirectives(headers);
  final parsedAge = int.tryParse(_headerValue(headers, 'age') ?? '') ?? 0;
  final age = parsedAge < 0 ? 0 : parsedAge;
  final sharedMaxAge = _freshnessDirective(directives, 's-maxage');
  final generalMaxAge = _freshnessDirective(directives, 'max-age');
  if (sharedMaxAge.specified || generalMaxAge.specified) {
    final maxAge = sharedMaxAge.specified
        ? sharedMaxAge.seconds
        : generalMaxAge.seconds;
    if (maxAge == null) return null;
    final seconds = (maxAge - age).clamp(
      0,
      const Duration(days: 366).inSeconds,
    );
    if (seconds == 0) return null;
    return now.add(Duration(seconds: seconds));
  }

  final expiresHeader = _headerValue(headers, 'expires');
  if (expiresHeader == null || expiresHeader.isEmpty) return null;
  late final DateTime expires;
  try {
    expires = HttpDate.parse(expiresHeader);
  } on HttpException {
    return null;
  }
  final receivedAt = now.toUtc();
  if (!expires.isAfter(receivedAt)) return null;
  var responseDate = receivedAt;
  final dateHeader = _headerValue(headers, 'date');
  if (dateHeader != null) {
    try {
      responseDate = HttpDate.parse(dateHeader);
    } on HttpException {
      // Without a usable Date, receipt time supplies the response reference.
    }
  }
  final lifetime = expires.difference(responseDate);
  if (age > lifetime.inSeconds) return null;
  final remaining = lifetime - Duration(seconds: age);
  if (remaining <= Duration.zero) return null;
  final ageExpiry = receivedAt.add(remaining);
  final freshUntil = ageExpiry.isBefore(expires) ? ageExpiry : expires;
  final maximum = receivedAt.add(const Duration(days: 366));
  return freshUntil.isAfter(maximum) ? maximum : freshUntil;
}

/// The native byte store has no validator metadata and is shared by the app's
/// accounts, so directives which require a private cache or a conditional
/// request must remain memory-only.
bool responseAllowsPersistentByteCache(Map<String, String> headers) {
  final directives = _cacheControlDirectives(headers);
  for (final directive in directives) {
    if (directive.name == 'no-store' ||
        directive.name == 'no-cache' ||
        directive.name == 'private') {
      return false;
    }
  }

  final vary = _headerValue(headers, 'vary');
  return vary == null || !vary.split(',').any((field) => field.trim() == '*');
}

String? _headerValue(Map<String, String> headers, String name) {
  final direct = headers[name];
  if (direct != null) return direct;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

List<({String name, String? value})> _cacheControlDirectives(
  Map<String, String> headers,
) {
  final header = _headerValue(headers, 'cache-control') ?? '';
  final parts = <String>[];
  var start = 0;
  var quoted = false;
  var escaped = false;
  for (var index = 0; index < header.length; index++) {
    final character = header[index];
    if (escaped) {
      escaped = false;
    } else if (quoted && character == r'\') {
      escaped = true;
    } else if (character == '"') {
      quoted = !quoted;
    } else if (!quoted && character == ',') {
      parts.add(header.substring(start, index));
      start = index + 1;
    }
  }
  parts.add(header.substring(start));

  final directives = <({String name, String? value})>[];
  for (final untrimmed in parts) {
    final part = untrimmed.trim();
    if (part.isEmpty) continue;
    final equals = part.indexOf('=');
    final name = (equals < 0 ? part : part.substring(0, equals))
        .trim()
        .toLowerCase();
    if (name.isEmpty) continue;
    directives.add((
      name: name,
      value: equals < 0 ? null : part.substring(equals + 1).trim(),
    ));
  }
  return directives;
}

({bool specified, int? seconds}) _freshnessDirective(
  List<({String name, String? value})> directives,
  String name,
) {
  final matches = directives.where((directive) => directive.name == name);
  if (matches.isEmpty) return (specified: false, seconds: null);
  if (matches.length != 1) return (specified: true, seconds: null);

  var value = matches.single.value;
  if (value == null) return (specified: true, seconds: null);
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    return (specified: true, seconds: null);
  }
  return (specified: true, seconds: int.tryParse(value));
}
