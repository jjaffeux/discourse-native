import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/native_ui_evidence.dart';

Widget gameApp(
  Widget child, {
  bool scroll = false,
  double scale = 1,
  bool rtl = false,
  TargetPlatform platform = TargetPlatform.macOS,
}) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: platform),
  builder: (context, child) => DTouchTargets(
    child: DToaster(
      child: nativeUiEvidenceBuilder(
        context,
        MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
      ),
    ),
  ),
  home: Scaffold(
    body: scroll
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(DSpacing.lg),
            child: DTouchFields(child: child),
          )
        : child,
  ),
);
void gameSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder gameInput(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DInput && w.labelText == label),
  matching: find.byType(EditableText),
);
Future<void> gameTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> gameEnter(WidgetTester tester, String label, String value) async {
  final input = gameInput(label);
  await tester.ensureVisible(input);
  await tester.enterText(input, value);
  await tester.pumpAndSettle();
}
