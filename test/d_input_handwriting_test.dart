import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'iPhone capability updates preserve the mounted editing session',
    (tester) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/device_info');
      final response = Completer<Map<String, Object?>>();
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getDeviceInfo');
            requests++;
            return response.future;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'Before',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final edits = <String>[];
      Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(child: SizedBox(width: 300, child: child)),
        ),
      );
      await tester.pumpWidget(
        host(
          DInput(
            controller: controller,
            focusNode: focus,
            onChanged: edits.add,
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .stylusHandwritingEnabled,
        isTrue,
      );
      expect(requests, 1);

      const editing = TextEditingValue(
        text: 'Before writing',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 7, end: 14),
      );
      tester.testTextInput.updateEditingValue(editing);
      await tester.pump();
      expect(controller.value, editing);
      expect(edits, ['Before writing']);

      response.complete(_iphone);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .stylusHandwritingEnabled,
        isFalse,
      );
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(state),
      );
      expect(focus.hasPrimaryFocus, isTrue);
      expect(controller.value, editing);
      expect(edits, ['Before writing']);

      await tester.pumpWidget(const SizedBox.shrink());
      final beforeRemount = controller.value;
      await tester.pumpWidget(host(DInput(controller: controller)));
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .stylusHandwritingEnabled,
        isFalse,
      );
      expect(requests, 1);
      expect(controller.value, beforeRemount);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('$platform input keeps handwriting without an iOS query', (
      tester,
    ) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/device_info');
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            requests++;
            throw PlatformException(code: 'unexpected_device_query');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: Center(child: SizedBox(width: 300, child: DInput())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .stylusHandwritingEnabled,
        isTrue,
      );
      expect(requests, 0);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}

const _iphone = <String, Object?>{
  'name': 'iPhone',
  'systemName': 'iOS',
  'systemVersion': '27.0',
  'model': 'iPhone',
  'modelName': 'iPhone 15 Pro Max',
  'localizedModel': 'iPhone',
  'identifierForVendor': null,
  'freeDiskSize': 1024,
  'totalDiskSize': 2048,
  'isPhysicalDevice': true,
  'physicalRamSize': 8192,
  'availableRamSize': 4096,
  'isiOSAppOnMac': false,
  'isiOSAppOnVision': false,
  'utsname': <String, Object?>{
    'sysname': 'Darwin',
    'nodename': 'phone',
    'release': '26.0',
    'version': 'test',
    'machine': 'iPhone16,2',
  },
};
