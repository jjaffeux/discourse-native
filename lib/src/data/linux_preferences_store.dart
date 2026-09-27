import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../foundation/private_file_document.dart';
import 'store_diagnostics.dart';

/// The name `shared_preferences_linux` gave the preferences file inside the
/// application support directory. Keeping it carries earlier builds' data over.
const String linuxSharedPreferencesFileName = 'shared_preferences.json';

/// Keeps `SharedPreferences` on Linux in the file and format
/// `shared_preferences_linux` used — one JSON object of `flutter.`-prefixed
/// keys — but commits every change the way private documents are committed.
///
/// The plugin rewrote the whole file in place from its own cache on each save.
/// A save cut short by a full disk, a kill, or a power cut left a truncated
/// document it could never decode again, so every later launch failed to load
/// the saved sites, and a zero-length one read as no preferences at all. A
/// second process also wrote its stale cache over the first one's keys. Here
/// each set, remove, and clear is a read-modify-write of the document on disk,
/// staged to an owner-only file and renamed over it under the cross-process
/// lock: an interrupted save leaves the previous document, and a process only
/// changes the keys it writes.
///
/// A document that still cannot be decoded, such as one the plugin tore, is set
/// aside beside the file, reported once, and read as empty, so the app starts
/// instead of refusing to on every launch.
final class LinuxPreferencesStore extends SharedPreferencesStorePlatform {
  LinuxPreferencesStore({this._file});

  /// Replaces the plugin the Flutter tool registered. It must run before the
  /// first `SharedPreferences.getInstance`, which caches what it read.
  static void install({bool? isLinux}) {
    if (!(isLinux ?? Platform.isLinux)) return;
    SharedPreferencesStorePlatform.instance = LinuxPreferencesStore();
  }

  static const String _defaultPrefix = 'flutter.';

  final PrivateFileResolver? _file;
  Future<File>? _location;

  /// The last document text this store decoded or encoded, with the
  /// preferences it holds. Every save reads the file again under the lock and
  /// encodes it before and after its change; tab anchors alone save twice a
  /// second while a list scrolls. A text or preferences equal to these are
  /// answered from here, which leaves one encoding per save, as the plugin had.
  ({String text, Map<String, Object> preferences})? _known;

  late final PrivateFileDocument<Map<String, Object>> _document =
      PrivateFileDocument(
        target: _target,
        empty: () => <String, Object>{},
        decode: _decode,
        encode: _encode,
        setAsideUndecodable: _reportSetAside,
      );

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: _defaultPrefix)),
  );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => _document.read(
    (preferences) => PrivateFileResult({
      for (final MapEntry(:key, :value) in preferences.entries)
        if (_matches(parameters.filter, key))
          key: value is List<String> ? List.of(value) : value,
    }),
  );

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    // The caller keeps its list and may change it before this write runs.
    final saved = value is List ? List<String>.of(value.cast()) : value;
    return _commit((preferences) => preferences[key] = saved);
  }

  @override
  Future<bool> remove(String key) =>
      _commit((preferences) => preferences.remove(key));

  @override
  Future<bool> clear() => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: _defaultPrefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) => _commit(
    (preferences) =>
        preferences.removeWhere((key, _) => _matches(parameters.filter, key)),
  );

  /// Answers false rather than throwing, as the plugin did: callers already
  /// turn a refused save into their own report.
  Future<bool> _commit(
    void Function(Map<String, Object> preferences) change,
  ) async {
    try {
      await _document.update((preferences) {
        change(preferences);
        return PrivateFileResult.done;
      });
      return true;
    } on Exception {
      return false;
    }
  }

  /// Shared while pending so operations reach the document's queue in the
  /// order they were issued; forgotten on failure so a later one can retry.
  Future<File> _target() {
    if (_location case final location?) return location;
    final location = _locate();
    _location = location;
    unawaited(
      location.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_location, location)) _location = null;
        },
      ),
    );
    return location;
  }

  Future<File> _locate() async {
    if (_file case final file?) return file();
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/$linuxSharedPreferencesFileName');
  }

  static bool _matches(PreferencesFilter filter, String key) =>
      key.startsWith(filter.prefix) &&
      (filter.allowList?.contains(key) ?? true);

  /// A value `SharedPreferences` cannot hold is dropped rather than handed to
  /// a getter that would throw on it; nothing this API writes produces one.
  Map<String, Object> _decode(String text) {
    final known = _known;
    if (known != null && known.text == text) return Map.of(known.preferences);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Preferences are not a JSON object.');
    }
    final preferences = {
      for (final MapEntry(:key, :value) in decoded.entries)
        key: ?_storedValue(value),
    };
    _known = (text: text, preferences: Map.of(preferences));
    return preferences;
  }

  /// Lists are never changed in place, so the remembered copy may share them.
  String _encode(Map<String, Object> preferences) {
    final known = _known;
    if (known != null && _holdSameValues(known.preferences, preferences)) {
      return known.text;
    }
    final text = jsonEncode(preferences);
    _known = (text: text, preferences: Map.of(preferences));
    return text;
  }

  /// Identity, not equality: `1 == 1.0`, yet the two are saved differently.
  /// Copies of one decoded document share their values, so they still match.
  static bool _holdSameValues(Map<String, Object> a, Map<String, Object> b) =>
      a.length == b.length &&
      a.entries.every((entry) => identical(b[entry.key], entry.value));

  static Object? _storedValue(Object? value) => switch (value) {
    bool() || int() || double() || String() => value,
    List() when value.every((item) => item is String) => List<String>.of(
      value.cast(),
    ),
    _ => null,
  };

  static void _reportSetAside(File damaged) => reportStorageFailure(
    // Never quote the contents: they hold forum titles and usernames.
    FormatException(
      'Unreadable preferences were set aside as '
      '${damaged.uri.pathSegments.last}.',
    ),
    StackTrace.current,
    'preferences.decode',
    severity: DiagnosticSeverity.error,
  );
}
