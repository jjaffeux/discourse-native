import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../foundation/private_file_permissions.dart';

/// Persistence for data which must not be mixed into the app's public
/// preferences.
///
/// Apple uses Keychain. Linux deliberately uses a private file instead of
/// requiring a Secret Service daemon: the file is protected by the user's
/// filesystem permissions (and by home-directory or full-disk encryption when
/// the system has it), but is not encrypted from other processes running as
/// that user.
abstract interface class PrivateStorage {
  Future<String?> read(String key);

  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final PrivateStorage platformPrivateStorage = _createPlatformPrivateStorage();

PrivateStorage _createPlatformPrivateStorage() {
  if (Platform.isLinux) return LinuxFileStorage();
  if (Platform.isIOS || Platform.isMacOS) return AppleKeychainStorage();
  throw UnsupportedError('Private storage is unavailable on this platform');
}

/// Calls the Darwin implementation directly, without depending on the
/// umbrella plugin that automatically links libsecret into Linux builds.
final class AppleKeychainStorage implements PrivateStorage {
  AppleKeychainStorage({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final MethodChannel _channel;

  Map<String, String> get _options => {
    'accountName': 'flutter_secure_storage_service',
    'accessibility': 'unlocked',
    'synchronizable': 'false',
    'useSecureEnclave': 'false',
    if (Platform.isMacOS) 'usesDataProtectionKeychain': 'false',
  };

  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String?>('read', {'key': key, 'options': _options});

  @override
  Future<Map<String, String>> readAll() async {
    final values = await _channel.invokeMethod<Map<Object?, Object?>>(
      'readAll',
      {'options': _options},
    );
    return values?.cast<String, String>() ?? <String, String>{};
  }

  @override
  Future<void> write(String key, String value) => _channel.invokeMethod<void>(
    'write',
    {'key': key, 'value': value, 'options': _options},
  );

  @override
  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', {'key': key, 'options': _options});
}

/// A serialized JSON store at
/// `$XDG_DATA_HOME/discourse-native/private-storage.json`.
///
/// The containing directory is mode 0700 and the file is mode 0600. Updates
/// are flushed to a same-directory temporary file before an atomic rename, so
/// interruption cannot leave half-written JSON behind.
final class LinuxFileStorage implements PrivateStorage {
  LinuxFileStorage({Directory? directory}) : _providedDirectory = directory;

  static const _fileName = 'private-storage.json';
  static const _formatVersion = 1;

  final Directory? _providedDirectory;
  final Random _random = Random.secure();
  Future<void> _tail = Future<void>.value();

  @override
  Future<String?> read(String key) =>
      _serialize(() async => (await _readValues())[key]);

  @override
  Future<Map<String, String>> readAll() =>
      _serialize(() async => Map.unmodifiable(await _readValues()));

  @override
  Future<void> write(String key, String value) => _serialize(() async {
    final values = await _readValues();
    values[key] = value;
    await _writeValues(values);
  });

  @override
  Future<void> delete(String key) => _serialize(() async {
    final values = await _readValues();
    if (values.remove(key) != null) await _writeValues(values);
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<Directory> _directory() async {
    final provided = _providedDirectory;
    if (provided != null) return provided;

    final environment = Platform.environment;
    final xdg = environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty && xdg.startsWith('/')) {
      return Directory('$xdg/discourse-native');
    }

    final home = environment['HOME'];
    if (home == null || home.isEmpty || !home.startsWith('/')) {
      throw StateError('HOME does not name an absolute directory');
    }
    return Directory('$home/.local/share/discourse-native');
  }

  Future<File> _file() async {
    final directory = await _directory();
    await ensurePrivateDirectory(directory);
    return File('${directory.path}/$_fileName');
  }

  Future<Map<String, String>> _readValues() async {
    final file = await _file();
    if (!await file.exists()) return {};
    restrictPrivateFile(file);

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw FormatException('Invalid private storage: ${error.message}');
    }

    if (decoded case {
      'version': final int version,
      'values': final Map<Object?, Object?> rawValues,
    } when version == _formatVersion) {
      final values = <String, String>{};
      for (final MapEntry(:key, :value) in rawValues.entries) {
        if (key is! String || value is! String) {
          throw const FormatException(
            'Invalid private storage: values must be strings',
          );
        }
        values[key] = value;
      }
      return values;
    }
    throw const FormatException('Invalid private storage format');
  }

  Future<void> _writeValues(Map<String, String> values) async {
    final file = await _file();
    final suffix = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final temporary = File('${file.path}.$pid.$suffix.tmp');

    try {
      await ensurePrivateFile(temporary);
      await temporary.writeAsString(
        jsonEncode({'version': _formatVersion, 'values': values}),
        flush: true,
      );
      await temporary.rename(file.path);
      restrictPrivateFile(file);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
