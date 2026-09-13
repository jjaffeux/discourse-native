import 'dart:async';
import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_store.dart';

class MemoryPlaceholderPersistence implements PlaceholderPersistence {
  final values = <PlaceholderPostId, Map<String, String>>{};
  final writes = <({PlaceholderPostId post, String key, String? value})>[];
  Completer<Map<String, String>>? readGate;
  @override
  Future<Map<String, String>> read(PlaceholderPostId post) async =>
      readGate == null ? Map.of(values[post] ?? {}) : await readGate!.future;
  @override
  Future<void> write(PlaceholderPostId post, String key, String? value) async {
    writes.add((post: post, key: key, value: value));
    final saved = values.putIfAbsent(post, () => {});
    value == null ? saved.remove(key) : saved[key] = value;
  }

  @override
  Future<void> forget(String siteUrl) async =>
      values.removeWhere((key, _) => key.siteUrl == siteUrl);
}
