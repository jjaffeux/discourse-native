abstract interface class PrivateStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Only file stores implement this. Keychain enumeration is deliberately not
/// exposed: the legacy macOS keychain authorizes every item separately, so a
/// broad read can create one password prompt per credential or draft.
abstract interface class EnumerablePrivateStorage implements PrivateStorage {
  Future<Map<String, String>> readAll();

  Future<void> deletePrefix(String prefix);
}
