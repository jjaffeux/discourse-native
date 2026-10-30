import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../foundation/private_file_document.dart';
import 'private_storage.dart';

/// Keeps credentials encrypted for the signed-in Windows user. The document
/// transaction owns locking and atomic replacement; the host owns DPAPI.
final class WindowsDpapiStorage implements PrivateStorage {
  WindowsDpapiStorage({File? file, MethodChannel? channel})
    : _providedFile = file,
      _channel =
          channel ?? const MethodChannel('org.discourse.native/windows_dpapi');

  final File? _providedFile;
  final MethodChannel _channel;
  late final _document = PrivateFileDocument<Map<String, String>>(
    target: _file,
    empty: () => <String, String>{},
    decode: _decode,
    encode: _encode,
    snapshot: jsonEncode,
  );

  @override
  Future<String?> read(String key) =>
      _document.read((values) => PrivateFileResult(values[key]));

  @override
  Future<void> write(String key, String value) => _document.update((values) {
    values[key] = value;
    return PrivateFileResult.done;
  });

  @override
  Future<void> delete(String key) => _document.update((values) {
    values.remove(key);
    return PrivateFileResult.done;
  });

  Future<File> _file() async {
    if (_providedFile case final file?) return file;
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/credentials/dpapi-v1.dat');
  }

  Future<Map<String, String>> _decode(String encrypted) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'decrypt',
      base64Decode(encrypted),
    );
    if (bytes == null) throw StateError('DPAPI returned no plaintext');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded.values.any((value) => value is! String)) {
      throw const FormatException('Invalid Windows credential document');
    }
    return decoded.cast<String, String>();
  }

  Future<String> _encode(Map<String, String> values) async {
    final encrypted = await _channel.invokeMethod<Uint8List>(
      'encrypt',
      Uint8List.fromList(utf8.encode(jsonEncode(values))),
    );
    if (encrypted == null) throw StateError('DPAPI returned no ciphertext');
    return base64Encode(encrypted);
  }
}
