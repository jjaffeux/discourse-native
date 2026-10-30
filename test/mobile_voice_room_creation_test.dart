import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;

void main() {
  testWidgets('Chat opens the new voice room editor on a phone', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester, voice: true);
    shell.selectMobilePanel('chat');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DButton, 'New voice room'));
    await tester.pumpAndSettle();
    expect(find.text('Create voice room'), findsOneWidget);
    expect(find.byType(DInput), findsWidgets);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
