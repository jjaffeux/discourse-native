import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.discourse.native/window');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('dismisses the native placeholder after the first macOS frame', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });

      MacOSLaunchScreen.dismissAfterFirstFlutterFrame();

      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(calls, [isMethodCall('dismissLaunchScreen', arguments: null)]);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('leaves the launch screen channel alone on other platforms', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });

      MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
      await tester.pumpWidget(const SizedBox());

      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
