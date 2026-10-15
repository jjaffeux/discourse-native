import 'package:discourse_native/src/data/private_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.discourse.native/android_credentials');
  const storage = AndroidCredentialStorage(channel: channel);
  final values = <String, String>{};

  setUp(() {
    values.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = call.arguments as Map;
          final key = arguments['key'] as String;
          switch (call.method) {
            case 'read':
              return values[key];
            case 'write':
              values[key] = arguments['value'] as String;
            case 'delete':
              values.remove(key);
            default:
              fail('Unexpected storage method ${call.method}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads, replaces, and deletes credentials through the native bridge',
    () async {
      const key = 'api_key::https://forum.example';
      expect(await storage.read(key), isNull);
      await storage.write(key, 'first');
      expect(await storage.read(key), 'first');
      await storage.write(key, 'replacement');
      expect(await storage.read(key), 'replacement');
      await storage.delete(key);
      expect(await storage.read(key), isNull);
      await storage.delete(key);
    },
  );

  test(
    'propagates native failures instead of treating them as missing keys',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'credential_storage');
          });
      await expectLater(storage.read('key'), throwsA(isA<PlatformException>()));
      await expectLater(
        storage.write('key', 'value'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        storage.delete('key'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
