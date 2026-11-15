import 'dart:collection';
import 'dart:io' show Platform;

/// Where an unhandled error was observed.
enum ErrorSource { framework, platform, zone, startup }

final class ErrorLogEntry {
  const ErrorLogEntry({
    required this.at,
    required this.lastAt,
    required this.source,
    required this.type,
    required this.message,
    required this.stack,
    required this.count,
  });

  /// When the error was first seen, in UTC.
  final DateTime at;

  /// When the latest consecutive repeat was seen, in UTC.
  final DateTime lastAt;
  final ErrorSource source;
  final String type;
  final String message;
  final String stack;

  /// How many consecutive times the same error was seen.
  final int count;

  bool _repeats(ErrorLogEntry other) =>
      source == other.source &&
      type == other.type &&
      message == other.message &&
      stack == other.stack;

  ErrorLogEntry _repeatedAt(DateTime moment) => ErrorLogEntry(
    at: at,
    lastAt: moment,
    source: source,
    type: type,
    message: message,
    stack: stack,
    count: count + 1,
  );
}

/// The recent unhandled errors of this process, kept in memory only.
///
/// Nothing here is persisted or sent anywhere: the log leaves the device only
/// when the user copies it. Entries are redacted as they are stored, so no
/// reader of the buffer can observe an unredacted error.
///
/// Recording is safe from any phase of a frame and from pure Dart: the log
/// notifies nobody and needs no binding.
final class ErrorLog {
  ErrorLog({this.capacity = 50, DateTime Function()? now})
    : assert(capacity > 0),
      _now = now ?? DateTime.now;

  static final ErrorLog instance = ErrorLog();

  final int capacity;
  final DateTime Function() _now;
  final ListQueue<ErrorLogEntry> _entries = ListQueue<ErrorLogEntry>();
  WeakReference<Object>? _lastError;

  /// Oldest first.
  List<ErrorLogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  /// Never throws: capture must not change how an error is handled.
  void record(Object error, StackTrace? stack, {required ErrorSource source}) {
    try {
      // One throw can reach several handlers: a guarded zone forwards to its
      // parent, which reports the same object to the platform dispatcher.
      if (identical(_lastError?.target, error)) return;
      _lastError = _weakly(error);

      final moment = _now().toUtc();
      final entry = ErrorLogEntry(
        at: moment,
        lastAt: moment,
        source: source,
        type: _printed(() => error.runtimeType.toString()),
        message: _redactMessage(_printed(error.toString)),
        stack: stack == null ? '' : _redactStack(_printed(stack.toString)),
        count: 1,
      );
      // A layout or paint failure repeats every frame and would otherwise
      // evict everything that led up to it.
      if (_entries.isNotEmpty && _entries.last._repeats(entry)) {
        _entries.add(_entries.removeLast()._repeatedAt(moment));
        return;
      }
      _entries.add(entry);
      while (_entries.length > capacity) {
        _entries.removeFirst();
      }
    } on Object {
      return;
    }
  }

  void clear() {
    _entries.clear();
    _lastError = null;
  }

  /// The text handed to the user. [appVersion] is supplied by the caller
  /// because the release constants live above this layer.
  String export({String appVersion = ''}) {
    final out = StringBuffer()
      ..writeln('Discourse Native error log')
      ..writeln('version: ${appVersion.isEmpty ? 'unknown' : appVersion}')
      ..writeln(
        'platform: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}',
      )
      ..writeln('exported: ${_now().toUtc().toIso8601String()}')
      ..writeln(
        'entries: ${_entries.length} '
        '(newest $capacity kept, in memory only, since launch)',
      );
    var index = 0;
    for (final entry in _entries) {
      index++;
      out
        ..writeln()
        ..write('[$index] ${entry.at.toIso8601String()} ')
        ..write('${entry.source.name} ${entry.type}');
      if (entry.count > 1) {
        out.write(' x${entry.count}, last ${entry.lastAt.toIso8601String()}');
      }
      out
        ..writeln()
        ..writeln(entry.message);
      if (entry.stack.isNotEmpty) out.writeln(entry.stack);
    }
    return out.toString();
  }
}

const int _maximumMessageLength = 400;
const int _maximumStackLines = 40;
const int _maximumStackLineLength = 300;

// Numbers, strings, booleans and records cannot be weakly referenced. They are
// simply never recognised as the same throw.
WeakReference<Object>? _weakly(Object error) {
  try {
    return WeakReference<Object>(error);
  } on ArgumentError {
    return null;
  }
}

String _printed(String Function() print) {
  try {
    return print();
  } on Object {
    return '<unprintable>';
  }
}

final _credentialHeader = RegExp(
  r'\b((?:proxy-)?authorization|(?:set-)?cookie|user-api-key|api-key|'
  r'api-username|x-csrf-token)\b\s*[:=].*',
  caseSensitive: false,
);
final _namedSecret = RegExp(
  r'''(["']?)([\w-]*(?:key|token|secret|passw(?:or)?d|session|nonce|payload|'''
  r'''signature|credential|auth|otp)[\w-]*)\1\s*[:=]\s*'''
  r'''(?:"[^"]*"|'[^']*'|[^\s,;&)}\]]+)''',
  caseSensitive: false,
);
final _authorizationScheme = RegExp(
  r'\b(Bearer|Basic)\s+[A-Za-z0-9+/._~=-]+',
  caseSensitive: false,
);
final _quoted = RegExp(r'''(?<![A-Za-z0-9])(["'])(.*?)\1''');
final _codeName = RegExp(
  r'^(?:(?:package|dart):[\w./-]+|'
  r'[A-Za-z_$][\w$.<>?]*(?:, ?[\w$.<>?]+)*)$',
);
final _fileUri = RegExp(r'''file://[^\s'"<>)\]]*/([^/\s:'"<>)\]]+)''');
final _uri = RegExp(r'''\b([A-Za-z][A-Za-z0-9+.-]*)://[^\s'"<>)\]]+''');
final _absolutePath = RegExp(r'''(?<![\w<:/])/(?:[^\s/'":]+/)+[^\s/'":)]*''');
final _email = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+');
final _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
final _ipv6 = RegExp(r'\[[0-9A-Fa-f.]*:[0-9A-Fa-f.]*:[0-9A-Fa-f:.]*\]');
// Lowercase only, so `RenderBox.size` survives. A source file name is the one
// dotted lowercase token a message legitimately carries.
final _hostname = RegExp(r'\b(?:[a-z0-9-]+\.)+[a-z]{2,}\b');
final _opaqueToken = RegExp(r'[A-Za-z0-9+/_=-]{20,}');
final _digit = RegExp(r'\d');
final _letter = RegExp('[A-Za-z]');

/// Free text cannot be proven clean, so the message is cut down before it is
/// pattern-matched: only the first line survives, because the lines after it
/// are where `FormatException` and friends print the offending source —
/// a response body or something the user typed.
String _redactMessage(String raw) {
  var text = raw
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  // Locations go first: a query string would otherwise be cut out of its URL
  // by the named-secret rule, leaving the rest of the query behind.
  text = _redactLocations(text)
      .replaceAllMapped(_credentialHeader, (m) => '${m[1]}: <redacted>')
      .replaceAllMapped(_namedSecret, (m) => '${m[2]}=<redacted>')
      .replaceAllMapped(_authorizationScheme, (m) => '${m[1]} <redacted>')
      .replaceAllMapped(_quoted, (m) {
        final content = m[2]!;
        final named = content.length <= 80 && _codeName.hasMatch(content);
        return named ? m[0]! : '${m[1]}<redacted>${m[1]}';
      });
  text = text
      .replaceAll(_email, '<email>')
      .replaceAll(_ipv4, '<host>')
      .replaceAll(_ipv6, '<host>')
      .replaceAllMapped(
        _hostname,
        (m) => m[0]!.endsWith('.dart') ? m[0]! : '<host>',
      )
      .replaceAllMapped(_opaqueToken, (m) {
        final token = m[0]!;
        return token.contains(_digit) && token.contains(_letter)
            ? '<redacted>'
            : token;
      });
  return _capped(text, _maximumMessageLength);
}

/// Frames are code locations written by the VM, not user data, and a release
/// build needs its header lines and instruction offsets intact to symbolize.
/// Only locations are rewritten: a debug build prints the developer's home
/// directory in every `file://` frame.
String _redactStack(String raw) => raw
    .trimRight()
    .split('\n')
    .take(_maximumStackLines)
    .map((line) => _capped(_redactLocations(line), _maximumStackLineLength))
    .join('\n');

String _redactLocations(String text) => text
    .replaceAllMapped(_fileUri, (m) => m[1]!)
    .replaceAllMapped(_uri, (m) => '${m[1]}://<redacted>')
    .replaceAll(_absolutePath, '<path>');

String _capped(String text, int length) =>
    text.length <= length ? text : '${text.substring(0, length)}…';
