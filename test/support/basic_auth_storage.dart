import 'dart:async';

import 'package:discourse_native/src/data/private_storage.dart';

final class BasicAuthMemoryStorage implements PrivateStorage {
  final Map<String, String> values = {};
  Completer<void>? writeGate;
  Object? writeFailure;
  int writes = 0;
  void Function()? onRead;

  @override
  Future<String?> read(String key) async {
    onRead?.call();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await writeGate?.future;
    if (writeFailure case final failure?) throw failure;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
