import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/site_emoji.dart';
import '../plugin_api/emoji_preferences.dart';
import '../plugin_api/emoji_usage.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class EmojiPickerPersistence {
  Future<String?> readPreferences({required String siteUrl});

  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  });
}

final class SharedPreferencesEmojiPickerPersistence
    implements EmojiPickerPersistence {
  const SharedPreferencesEmojiPickerPersistence();

  static const String _keyPrefix = 'discourse_native.emoji_picker';

  @override
  Future<String?> readPreferences({required String siteUrl}) async =>
      (await SharedPreferences.getInstance()).getString(_key(siteUrl));

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async =>
      (await SharedPreferences.getInstance()).setString(_key(siteUrl), encoded);

  static String _key(String siteUrl) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}';
}

final class EmojiPickerStore implements EmojiPreferenceStore {
  EmojiPickerStore({EmojiPickerPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesEmojiPickerPersistence();

  static const int formatVersion = 2;
  static const int maxTrackedEmoji = 40;
  static const int maxFavoriteEmoji = 20;

  static final SerialOperationQueue _operations = SerialOperationQueue();

  final EmojiPickerPersistence _persistence;
  final Map<String, _EmojiPickerPreferences> _preferences = {};
  final Map<String, Future<void>> _loads = {};

  Future<void> ensureLoaded({required String siteUrl}) async {
    final canonicalSiteUrl = _canonicalSiteUrl(siteUrl);
    if (_preferences.containsKey(canonicalSiteUrl)) return;

    final existing = _loads[canonicalSiteUrl];
    if (existing != null) return existing;

    final loading = _operations.run<void>(
      owner: _persistence,
      key: canonicalSiteUrl,
      operation: () async {
        if (_preferences.containsKey(canonicalSiteUrl)) return;
        _preferences[canonicalSiteUrl] = await _read(canonicalSiteUrl);
      },
    );
    _loads[canonicalSiteUrl] = loading;
    try {
      await loading;
    } finally {
      if (identical(_loads[canonicalSiteUrl], loading)) {
        final _ = _loads.remove(canonicalSiteUrl);
      }
    }
  }

  EmojiSkinTone skinToneFor({required String siteUrl}) =>
      _preferences[_canonicalSiteUrl(siteUrl)]?.tone ?? EmojiSkinTone.neutral;

  @override
  Future<EmojiSkinTone> readSkinTone({required String siteUrl}) async {
    await ensureLoaded(siteUrl: siteUrl);
    return skinToneFor(siteUrl: siteUrl);
  }

  List<String> favoriteEmojiCodesFor({
    required String siteUrl,
    required EmojiUsageContext context,
    required SiteEmojiCatalog catalog,
  }) {
    final history =
        _preferences[_canonicalSiteUrl(siteUrl)]?.historyFor(context) ??
        const <String>[];
    return _rankFavorites(history, catalog);
  }

  @override
  Future<List<String>> favoriteEmojiCodes({
    required String siteUrl,
    required EmojiUsageContext context,
    required SiteEmojiCatalog catalog,
  }) async {
    await ensureLoaded(siteUrl: siteUrl);
    return favoriteEmojiCodesFor(
      siteUrl: siteUrl,
      context: context,
      catalog: catalog,
    );
  }

  @override
  Future<void> writeSkinTone({
    required String siteUrl,
    required EmojiSkinTone tone,
  }) => _mutate(siteUrl, (preferences) => preferences.withTone(tone));

  @override
  Future<void> trackEmoji({
    required String siteUrl,
    required EmojiUsageContext context,
    required String emoji,
  }) {
    final normalized = _normalizeEmojiCode(emoji);
    if (normalized == null) return Future<void>.value();
    return _mutate(
      siteUrl,
      (preferences) => preferences.withTrackedEmoji(context, normalized),
    );
  }

  @override
  Future<void> clearHistory({
    required String siteUrl,
    required EmojiUsageContext context,
  }) => _mutate(
    siteUrl,
    (preferences) => preferences.withClearedHistory(context),
  );

  Future<void> _mutate(
    String siteUrl,
    _EmojiPickerPreferences Function(_EmojiPickerPreferences current) change,
  ) async {
    final canonicalSiteUrl = _canonicalSiteUrl(siteUrl);
    await _operations.run<void>(
      owner: _persistence,
      key: canonicalSiteUrl,
      operation: () async {
        var current = _preferences[canonicalSiteUrl];
        if (current == null || _unreadable.contains(canonicalSiteUrl)) {
          // Either never read, or read into a stand-in after a failure. Ask
          // again rather than mutate something that was never the document.
          current = await _read(canonicalSiteUrl);
          _preferences[canonicalSiteUrl] = current;
        }
        // Still unreadable: drop this change instead of saving over a
        // document that is intact on disk and unknown here. Losing one
        // recorded pick is recoverable; overwriting a reader's tone and
        // history with an empty default is not.
        if (_unreadable.contains(canonicalSiteUrl)) return;
        final updated = change(current);
        _preferences[canonicalSiteUrl] = updated;
        if (identical(updated, current)) return;
        await _write(canonicalSiteUrl, updated);
      },
    );
  }

  final Set<String> _unreadable = {};

  Future<_EmojiPickerPreferences> _read(String siteUrl) async {
    try {
      final encoded = await _persistence.readPreferences(siteUrl: siteUrl);
      _unreadable.remove(siteUrl);
      if (encoded == null || encoded.isEmpty) {
        return _EmojiPickerPreferences.empty;
      }
      return _EmojiPickerPreferences.fromEncoded(encoded);
    } catch (error, stackTrace) {
      _unreadable.add(siteUrl);
      reportStorageFailure(error, stackTrace, 'emojiPicker.read');
      return _EmojiPickerPreferences.empty;
    }
  }

  Future<void> _write(
    String siteUrl,
    _EmojiPickerPreferences preferences,
  ) async {
    try {
      final saved = await _persistence.writePreferences(
        siteUrl: siteUrl,
        encoded: preferences.encoded,
      );
      if (!saved) {
        throw StateError('Could not persist emoji picker preferences.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'emojiPicker.write');
    }
  }

  static List<String> _rankFavorites(
    List<String> history,
    SiteEmojiCatalog catalog,
  ) {
    final usage = <String, _EmojiUsage>{};
    for (var index = 0; index < history.length; index++) {
      final code = history[index];
      if (!catalog.byName.containsKey(_baseEmojiName(code))) continue;
      usage.update(
        code,
        (current) => _EmojiUsage(current.count + 1, index),
        ifAbsent: () => _EmojiUsage(1, index),
      );
    }

    final ranked = usage.entries.toList()
      ..sort((left, right) {
        final frequency = right.value.count.compareTo(left.value.count);
        if (frequency != 0) return frequency;
        final recency = right.value.lastIndex.compareTo(left.value.lastIndex);
        if (recency != 0) return recency;
        return left.key.compareTo(right.key);
      });
    return List<String>.unmodifiable(
      ranked.take(maxFavoriteEmoji).map((entry) => entry.key),
    );
  }
}

final class _EmojiPickerPreferences {
  const _EmojiPickerPreferences({required this.tone, required this.histories});

  static const empty = _EmojiPickerPreferences(
    tone: EmojiSkinTone.neutral,
    histories: {},
  );

  factory _EmojiPickerPreferences.fromEncoded(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<Object?, Object?> ||
        (decoded['version'] != 1 &&
            decoded['version'] != EmojiPickerStore.formatVersion)) {
      throw const FormatException('Unsupported emoji picker preferences.');
    }

    final Object? rawTone = decoded['tone'];
    if (rawTone != null && !_isSupportedTone(rawTone)) {
      throw const FormatException('Invalid emoji picker skin tone.');
    }

    final Object? rawHistory = decoded['history'];
    if (rawHistory != null && rawHistory is! Map<Object?, Object?>) {
      throw const FormatException('Invalid emoji picker history.');
    }
    final rawHistories = rawHistory as Map<Object?, Object?>?;
    final histories = <String, List<String>>{};
    if (rawHistories != null) {
      for (final entry in rawHistories.entries) {
        final key = entry.key;
        if (key is! String || key.isEmpty) {
          throw const FormatException('Invalid emoji picker context key.');
        }
        histories[key] = _decodeHistory(entry.value);
      }
    }

    return _EmojiPickerPreferences(
      tone: EmojiSkinTone.fromCode(rawTone),
      histories: Map<String, List<String>>.unmodifiable(histories),
    );
  }

  final EmojiSkinTone tone;
  final Map<String, List<String>> histories;

  List<String> historyFor(EmojiUsageContext context) {
    final current = histories[context.id];
    if (current != null) return current;
    final legacyKey = context.legacyStorageKey;
    return legacyKey == null ? const [] : histories[legacyKey] ?? const [];
  }

  _EmojiPickerPreferences withTone(EmojiSkinTone value) => value == tone
      ? this
      : _EmojiPickerPreferences(tone: value, histories: histories);

  _EmojiPickerPreferences withTrackedEmoji(
    EmojiUsageContext context,
    String emoji,
  ) {
    final tracked = [...historyFor(context), emoji];
    if (tracked.length > EmojiPickerStore.maxTrackedEmoji) {
      tracked.removeRange(0, tracked.length - EmojiPickerStore.maxTrackedEmoji);
    }
    return _copyWithHistory(context, List<String>.unmodifiable(tracked));
  }

  _EmojiPickerPreferences withClearedHistory(EmojiUsageContext context) =>
      historyFor(context).isEmpty ? this : _copyWithHistory(context, const []);

  _EmojiPickerPreferences _copyWithHistory(
    EmojiUsageContext context,
    List<String> history,
  ) {
    final updated = Map<String, List<String>>.of(histories);
    final legacyKey = context.legacyStorageKey;
    if (legacyKey != null && legacyKey != context.id) {
      updated.remove(legacyKey);
    }
    updated[context.id] = history;
    return _EmojiPickerPreferences(
      tone: tone,
      histories: Map<String, List<String>>.unmodifiable(updated),
    );
  }

  String get encoded => jsonEncode({
    'version': EmojiPickerStore.formatVersion,
    'tone': tone.code,
    'history': histories,
  });

  static List<String> _decodeHistory(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Invalid emoji picker context history.');
    }

    final normalized = <String>[];
    for (final entry in value) {
      if (entry is! String) continue;
      final code = _normalizeEmojiCode(entry);
      if (code != null) normalized.add(code);
    }
    if (normalized.length > EmojiPickerStore.maxTrackedEmoji) {
      normalized.removeRange(
        0,
        normalized.length - EmojiPickerStore.maxTrackedEmoji,
      );
    }
    return List<String>.unmodifiable(normalized);
  }

  static bool _isSupportedTone(Object value) =>
      value == 'neutral' ||
      value == 't2' ||
      value == 't3' ||
      value == 't4' ||
      value == 't5' ||
      value == 't6' ||
      value == 2 ||
      value == 3 ||
      value == 4 ||
      value == 5 ||
      value == 6;
}

final class _EmojiUsage {
  const _EmojiUsage(this.count, this.lastIndex);

  final int count;
  final int lastIndex;
}

String? _normalizeEmojiCode(String value) {
  var normalized = value.trim();
  normalized = normalized.replaceFirst(RegExp(r'^:+'), '');
  normalized = normalized.replaceFirst(RegExp(r':+$'), '').trim();
  return normalized.isEmpty ? null : normalized;
}

String _baseEmojiName(String code) =>
    code.replaceFirst(RegExp(r':t[2-6]$'), '');

String _canonicalSiteUrl(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return trimmed.length > 1
        ? trimmed.replaceFirst(RegExp(r'/+$'), '')
        : trimmed;
  }

  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final authority = host.contains(':') ? '[$host]' : host;
  final defaultPort =
      (scheme == 'http' && uri.port == 80) ||
      (scheme == 'https' && uri.port == 443);
  final port = uri.hasPort && !defaultPort ? ':${uri.port}' : '';
  final path = uri.path == '/' ? '' : uri.path.replaceFirst(RegExp(r'/+$'), '');
  return '$scheme://$authority$port$path';
}
