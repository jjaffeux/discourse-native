import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('selection formatting controls are accessible by keyboard', (
    tester,
  ) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.example',
        topicId: 7,
        slug: 'topic',
        topicTitle: 'A topic',
      ),
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await shell.load();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: SizedBox(
                width: 600,
                height: 300,
                child: ComposerPanel(composer: composer),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      composer.text.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();

      final toolbar = find.byKey(const ValueKey('composer-selection-toolbar'));
      final bold = find.byTooltip('Bold');
      final italic = find.byTooltip('Italic');
      expect(toolbar, findsOneWidget);
      expect(tester.getSize(toolbar), const Size(88, 44));
      expect(tester.getSize(bold), const Size.square(44));
      expect(tester.getSize(italic), const Size.square(44));
      expect(
        tester.getSemantics(bold),
        isSemantics(
          tooltip: 'Bold',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      final boldFocus = _focusButton(tester, bold);
      await tester.pumpAndSettle();
      expect(boldFocus.hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(bold),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(composer.text.text, '**format** me');

      final italicFocus = _focusButton(tester, italic);
      await tester.pumpAndSettle();
      expect(italicFocus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(composer.text.text, '***format*** me');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}

FocusNode _focusButton(WidgetTester tester, Finder tooltip) {
  final button = find
      .ancestor(of: tooltip, matching: find.byType(IconButton))
      .first;
  final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}
