import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> keyboardFramePayload({
  double inset = 300,
  int milliseconds = 400,
  int elapsedMilliseconds = 0,
  int curve = 3,
  Map<String, double>? spring,
}) => {
  'frame': {'x': 0.0, 'y': 844 - inset, 'width': 390.0, 'height': inset},
  'bottomInset': inset,
  'duration': milliseconds / 1000,
  'elapsed': elapsedMilliseconds / 1000,
  'curve': curve,
  'spring': ?spring,
};

Future<void> sendKeyboardFrame(
  WidgetTester tester, {
  double inset = 300,
  int milliseconds = 400,
  int curve = 3,
  Map<String, double>? spring,
}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'org.discourse.native/keyboard',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        'keyboardTransition',
        keyboardFramePayload(
          inset: inset,
          milliseconds: milliseconds,
          curve: curve,
          spring: spring,
        ),
      ),
    ),
    (_) {},
  );
}
