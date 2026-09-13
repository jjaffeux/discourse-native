import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/store_diagnostics.dart';
import '../../foundation/private_file_document.dart';

typedef PlaceholderPostId = ({
  String siteUrl,
  int? userId,
  int topicId,
  int postId,
});

abstract interface class PlaceholderPersistence {
  Future<Map<String, String>> read(PlaceholderPostId post);
  Future<void> write(PlaceholderPostId post, String key, String? value);
  Future<void> forget(String siteUrl);
}

final class PlaceholderStore implements PlaceholderPersistence {
  PlaceholderStore({File? file, DateTime Function()? now})
    : _providedFile = file,
      _now = now ?? DateTime.now;

  static const retention = Duration(days: 7);
  final File? _providedFile;
  final DateTime Function() _now;
  late final _document = PrivateFileDocument<Map<String, _SavedValue>>(
    target: () async =>
        _providedFile ??
        File(
          '${(await getApplicationSupportDirectory()).path}/plugins/discourse-placeholder/values-v1.json',
        ),
    empty: () => {},
    decode: _decode,
    encode: (values) => jsonEncode({
      'version': 1,
      'values': {
        for (final entry in values.entries)
          entry.key: {
            'value': entry.value.value,
            'expiresAt': entry.value.expiresAt,
          },
      },
    }),
  );

  @override
  Future<Map<String, String>> read(PlaceholderPostId post) async {
    try {
      return await _document.update((values) {
        final now = _now();
        _prune(values, now);
        final result = <String, String>{};
        for (final entry in values.entries.toList()) {
          final identity = _identity(entry.key);
          if (identity == null || identity.post != post) continue;
          result[identity.key] = entry.value.value;
          values[entry.key] = _SavedValue(
            entry.value.value,
            now.add(retention).millisecondsSinceEpoch,
          );
        }
        return PrivateFileResult(result);
      });
    } catch (error, stack) {
      reportStorageFailure(error, stack, 'placeholder.read');
      return {};
    }
  }

  @override
  Future<void> write(PlaceholderPostId post, String key, String? value) async {
    try {
      await _document.update((values) {
        final now = _now();
        _prune(values, now);
        final storageKey = jsonEncode([
          post.siteUrl,
          post.userId,
          post.topicId,
          post.postId,
          key,
        ]);
        if (value == null) {
          values.remove(storageKey);
        } else {
          values[storageKey] = _SavedValue(
            value,
            now.add(retention).millisecondsSinceEpoch,
          );
        }
        return PrivateFileResult.done;
      });
    } catch (error, stack) {
      reportStorageFailure(error, stack, 'placeholder.write');
    }
  }

  @override
  Future<void> forget(String siteUrl) async {
    try {
      await _document.update((values) {
        values.removeWhere((key, _) => _identity(key)?.post.siteUrl == siteUrl);
        return PrivateFileResult.done;
      });
    } catch (error, stack) {
      reportStorageFailure(error, stack, 'placeholder.forget');
    }
  }

  static void _prune(Map<String, _SavedValue> values, DateTime now) {
    values.removeWhere((_, v) => v.expiresAt <= now.millisecondsSinceEpoch);
  }

  static Map<String, _SavedValue> _decode(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      // Never include entered values in a diagnostic's exception message.
      reportStorageFailure(
        const FormatException('Invalid placeholder store'),
        StackTrace.current,
        'placeholder.decode',
      );
      return {};
    }
    if (json is! Map || json['version'] != 1 || json['values'] is! Map) {
      return {};
    }
    final result = <String, _SavedValue>{};
    for (final entry in (json['values'] as Map).entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || _identity(key) == null || value is! Map) continue;
      if (value['value'] case final String text) {
        if (value['expiresAt'] case final int expiry) {
          result[key] = _SavedValue(text, expiry);
        }
      }
    }
    return result;
  }

  static ({PlaceholderPostId post, String key})? _identity(String key) {
    try {
      return switch (jsonDecode(key)) {
        [
          final String site,
          final int? user,
          final int topic,
          final int post,
          final String key,
        ] =>
          (
            post: (siteUrl: site, userId: user, topicId: topic, postId: post),
            key: key,
          ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }
}

final class _SavedValue {
  const _SavedValue(this.value, this.expiresAt);
  final String value;
  final int expiresAt;
}
