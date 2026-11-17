import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' as fixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Start chatting dismisses a disconnected iPhone keyboard', (
    tester,
  ) async {
    await fixture.pumpMobileShellFixture(tester);
    tester.view.reset();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-panel-action')));
    await tester.pumpAndSettle();
    await _nativeTime(tester);

    final sheet = find.byKey(const ValueKey('chat-new-direct-message-sheet'));
    final input = tester.widget<EditableText>(
      find.descendant(of: sheet, matching: find.byType(EditableText)),
    );
    expect(input.focusNode.hasFocus, isTrue);
    expect(tester.view.viewInsets.bottom, greaterThan(0));
    tester.testTextInput.closeConnection();
    await tester.pump();
    expect(input.focusNode.hasFocus, isFalse);
    expect(tester.view.viewInsets.bottom, greaterThan(0));

    await tester.fling(
      find.descendant(
        of: sheet,
        matching: find.byKey(const ValueKey('sheet-drag-handle')),
      ),
      const Offset(0, 320),
      1200,
    );
    await _nativeTime(tester);
    expect(sheet, findsNothing);
    expect(tester.view.viewInsets.bottom, 0);
  }, skip: defaultTargetPlatform != TargetPlatform.iOS);
}

Future<void> _nativeTime(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pumpAndSettle();
}
