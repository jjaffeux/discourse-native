import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' as fixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Topics dismisses an already open native chat keyboard', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    tester.view.reset();
    await tester.pumpAndSettle();
    for (var iteration = 0; iteration < 10; iteration++) {
      await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
      await tester.pumpAndSettle();
      if (iteration == 0) {
        await tester.tap(find.byKey(const ValueKey('chat-inbox-sort-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Newest').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('sam').first);
      await tester.pumpAndSettle();
      final editor = find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byType(EditableText),
      );
      await tester.tap(editor);
      await _nativeTime(tester, const Duration(milliseconds: 800));
      expect(
        tester.view.viewInsets.bottom,
        greaterThan(0),
        reason: 'the native keyboard must be open before iteration $iteration',
      );
      final dock = tester.widget<DMobileDock>(
        find.byKey(const ValueKey('mobile-bottom-bar')),
      );
      dock.places
          .singleWhere(
            (place) => place.key == const ValueKey('mobile-mode-topics'),
          )
          .onPressed();
      await tester.pump();
      await _nativeTime(tester, const Duration(milliseconds: 1000));
      expect(shell.mobileNavigation.tab, MobileTab.topics);
      expect(find.byType(ComposerEditor), findsNothing);
      expect(
        tester.view.viewInsets.bottom,
        0,
        reason:
            'Topics must release the native keyboard in iteration $iteration',
      );
      debugPrint('NATIVE_CHAT_TOPICS_KEYBOARD iteration=$iteration inset=0');
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _nativeTime(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pumpAndSettle();
}
