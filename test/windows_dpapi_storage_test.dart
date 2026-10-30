import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/windows_dpapi_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('windows-dpapi-test');
  late Directory directory;
  late File file;
  var refuseEncryption = false;
  var encryptions = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('windows-dpapi-test-');
    file = File('${directory.path}/credentials.dat');
    refuseEncryption = false;
    encryptions = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'encrypt') {
            encryptions++;
            if (refuseEncryption) {
              throw PlatformException(code: 'dpapi_error');
            }
          }
          return Uint8List.fromList(
            (call.arguments as Uint8List).map((byte) => byte ^ 0x5a).toList(),
          );
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  WindowsDpapiStorage storage() =>
      WindowsDpapiStorage(file: file, channel: channel);

  test(
    'reopens encrypted credentials larger than the Credential Manager limit',
    () async {
      final secret = 'password-${List.filled(8000, 'é').join()}';
      await storage().write('http-basic-auth', secret);
      expect(await storage().read('http-basic-auth'), secret);
      expect(
        utf8.decode(await file.readAsBytes()),
        isNot(contains('password')),
      );
      expect(
        base64Decode(await file.readAsString()),
        isNot(utf8.encode(secret)),
      );
      expect(encryptions, 1);
    },
  );

  test(
    'deletion preserves unrelated credentials and does not rewrite on a no-op',
    () async {
      final store = storage();
      await store.write('first', 'one');
      await store.write('second', 'two');
      await store.delete('first');
      expect(await storage().read('first'), isNull);
      expect(await storage().read('second'), 'two');
      final ciphertext = await file.readAsString();
      final before = encryptions;
      await store.delete('missing');
      expect(await file.readAsString(), ciphertext);
      expect(encryptions, before);
    },
  );

  test(
    'failed encryption leaves the previous durable credentials intact',
    () async {
      final store = storage();
      await store.write('key', 'original');
      final ciphertext = await file.readAsString();
      refuseEncryption = true;
      await expectLater(
        store.write('key', 'replacement'),
        throwsA(isA<PlatformException>()),
      );
      expect(await file.readAsString(), ciphertext);
      expect(await storage().read('key'), 'original');
    },
  );

  test('refuses a corrupt encrypted document without replacing it', () async {
    await file.writeAsString('invalid ciphertext');
    await expectLater(storage().write('key', 'value'), throwsFormatException);
    expect(await file.readAsString(), 'invalid ciphertext');
  });
}
