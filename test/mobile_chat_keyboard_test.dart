import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

void main() {
  testWidgets(
    'Topics releases chat input before replacing its editor',
    (tester) async {
      final shell = await fixture.pumpMobileShellFixture(tester);
      await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-inbox-sort-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Newest').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('sam').first);
      await tester.pumpAndSettle();
      final editor = find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byType(EditableText),
      );
      final topics = find.byKey(const ValueKey('mobile-mode-topics'));
      final topicsCenter = tester.getCenter(topics);
      await tester.tap(editor);
      final composer = tester
          .widget<ComposerEditor>(find.byType(ComposerEditor))
          .composer;
      expect(composer.focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tapAt(topicsCenter);
      await tester.idle();
      expect(shell.mobileNavigation.tab, MobileTab.topics);
      expect(
        tester.testTextInput.isVisible,
        isFalse,
        reason:
            'Leaving Chat must release text input before its editor is removed.',
      );
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.tab, MobileTab.topics);
      expect(find.byType(ComposerEditor), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
