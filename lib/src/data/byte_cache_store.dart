import 'dart:typed_data';

abstract interface class ByteCacheStore {
  Future<Uint8List?> read(String url);

  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  });

  Future<void> remove(String url);
}
