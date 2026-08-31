import 'dart:async';

import 'package:discourse_native/src/data/push_registration.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.discourse.native/push_notifications');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('turns a macOS APNs token into a Discourse push registration', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'registrationToken');
          return 'apns-token';
        });
    final provider = PlatformPushRegistrationProvider(
      channel: channel,
      platform: TargetPlatform.macOS,
    );

    final registration = await provider.registration();

    expect(registration?.clientId, 'apns-token');
    expect(
      registration?.pushUrl,
      PlatformPushRegistrationProvider.macosPushUrl,
    );
  });

  test('uses the iOS publisher for an iOS APNs token', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'registrationToken');
          return 'ios-apns-token';
        });
    final provider = PlatformPushRegistrationProvider(
      channel: channel,
      platform: TargetPlatform.iOS,
    );

    final registration = await provider.registration();

    expect(registration?.clientId, 'ios-apns-token');
    expect(registration?.pushUrl, PlatformPushRegistrationProvider.iosPushUrl);
  });

  test('does not ask the native bridge on unsupported platforms', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls += 1;
          return 'unused';
        });
    final provider = PlatformPushRegistrationProvider(
      channel: channel,
      platform: TargetPlatform.linux,
    );

    expect(await provider.registration(), isNull);
    expect(calls, 0);
  });

  test('keeps sign-in available when APNs registration fails', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          throw PlatformException(code: 'registration_failed');
        });
    final provider = PlatformPushRegistrationProvider(
      channel: channel,
      platform: TargetPlatform.macOS,
    );

    expect(await provider.registration(), isNull);
    expect(methods, ['registrationToken']);
  });

  testWidgets('keeps sign-in available when APNs registration never answers', (
    tester,
  ) async {
    final methods = <String>[];
    final never = Completer<String?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          methods.add(call.method);
          return never.future;
        });
    final provider = PlatformPushRegistrationProvider(
      channel: channel,
      platform: TargetPlatform.macOS,
      registrationTimeout: const Duration(milliseconds: 10),
    );

    var completed = false;
    final registration = provider.registration().then((result) {
      completed = true;
      return result;
    });
    await tester.pump(const Duration(milliseconds: 9));

    expect(methods, ['registrationToken']);
    expect(completed, isFalse);

    await tester.pump(const Duration(milliseconds: 1));

    expect(await registration, isNull);
    expect(completed, isTrue);
  });
}
