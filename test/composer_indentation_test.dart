import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'composer_list_items_test.dart' show bodies, pumpEditor;
import 'support/fakes.dart';

void main() {
  for (final newline in ['\n', '\r\n']) {
    testWidgets('todo keyboard indentation preserves its subtree and cursor '
        'with ${newline.length}-character line endings', (tester) async {
      final source = [
        '- [ ] First',
        '- [x] Second',
        '  continued',
        '  - [ ] Child',
        '- [ ] Third',
      ].join(newline);
      final nested = [
        '- [ ] First',
        '  - [x] Second',
        '    continued',
        '    - [ ] Child',
        '- [ ] Third',
      ].join(newline);
      final root = await pumpEditor(tester, source);
      final second = bodies(tester)[1];
      const caret = 10; // In the continuation line.
      second.text.selection = const TextSelection.collapsed(offset: caret);
      second.requestFocus();
      await tester.pumpAndSettle();
      expect(second.canIndent, isTrue);
      expect(second.canOutdent, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(root.raw, nested);
      final moved = root.activeEditor as ComposerListBodyController;
      expect(moved.text.text, 'Second\ncontinued\n- [ ] Child');
      expect(moved.focus.hasPrimaryFocus, isTrue);
      expect(moved.text.selection.extentOffset, caret);
      expect(moved.canOutdent, isTrue);
      expect(moved.canIndent, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(root.raw, source);
      expect(root.activeEditor.text.selection.extentOffset, caret);
      expect(root.activeEditor.focus.hasPrimaryFocus, isTrue);
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.raw, nested);
      root.history.redo();
      await tester.pumpAndSettle();
      expect(root.raw, source);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('indent does not cross an intervening paragraph', (tester) async {
    const source = '- [ ] First\n\nParagraph\n\n- [ ] Second';
    final root = await pumpEditor(tester, source);
    final second = bodies(tester).last;
    expect(second.canIndent, isFalse);
    expect(second.canOutdent, isFalse);
    second.indent();
    second.outdent();
    await tester.pumpAndSettle();
    expect(root.raw, source);
  });

  testWidgets('indentation leaves active composition untouched', (
    tester,
  ) async {
    final root = await pumpEditor(tester, '- [ ] First\n  - [ ] Second');
    final second = bodies(tester).last;
    second.requestFocus();
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Second 文',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 7, end: 8),
      ),
    );
    await tester.pump();
    final source = root.raw;
    expect(second.canIndent, isFalse);
    expect(second.canOutdent, isFalse);
    second.indent();
    second.outdent();
    await tester.pump();
    expect(root.raw, source);
    expect(second.text.value.composing, const TextRange(start: 7, end: 8));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('toolbar indents and outdents todos on ${platform.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final shell = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      await shell.load();
      addTearDown(shell.dispose);
      final root = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://example.test',
          topicId: 1,
          slug: 'topic',
          topicTitle: 'Topic',
        ),
      );
      addTearDown(root.dispose);
      final size = platform == TargetPlatform.iOS
          ? const Size(340, 720)
          : const Size(900, 650);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: platform),
          home: ShellScope(
            controller: shell,
            child: Scaffold(body: ComposerPanel(composer: root, height: 500)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final indent = find.byKey(const ValueKey('composer-indent'));
      final outdent = find.byKey(const ValueKey('composer-outdent'));
      bool enabled(Finder button) =>
          tester.widget<DButton>(button).onPressed != null;
      Future<void> tap(Finder button) async {
        await Scrollable.ensureVisible(tester.element(button), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      expect(indent, findsNothing);
      expect(outdent, findsNothing);
      const source = '- [ ] Parent\n- [x] Child';
      root.text.value = const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 6),
      );
      root.requestFocus();
      await tester.pumpAndSettle();
      expect(enabled(indent), isFalse);
      expect(enabled(outdent), isFalse);

      final second = bodies(tester).last;
      second.text.selection = const TextSelection.collapsed(offset: 3);
      second.requestFocus();
      await tester.pumpAndSettle();
      expect(enabled(indent), isTrue);
      expect(enabled(outdent), isFalse);
      second.text.value = second.text.value.copyWith(
        composing: const TextRange(start: 0, end: 2),
      );
      await tester.pumpAndSettle();
      expect(enabled(indent), isFalse);
      second.text.value = second.text.value.copyWith(
        composing: TextRange.empty,
      );
      await tester.pumpAndSettle();
      expect(enabled(indent), isTrue);
      await tap(indent);
      expect(root.raw, '- [ ] Parent\n  - [x] Child');
      expect(root.activeEditor.focus.hasPrimaryFocus, isTrue);
      expect(root.activeEditor.text.selection.extentOffset, 3);
      expect(enabled(indent), isFalse);
      expect(enabled(outdent), isTrue);
      final checkboxes = find.byType(DCheckbox);
      expect(
        tester.getTopLeft(checkboxes.last).dx,
        greaterThan(tester.getTopLeft(checkboxes.first).dx),
      );

      await tap(outdent);
      expect(root.raw, source);
      expect(root.activeEditor.text.selection.extentOffset, 3);
      expect(root.activeEditor.focus.hasPrimaryFocus, isTrue);
      expect(enabled(indent), isTrue);
      expect(enabled(outdent), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(platform));
  }
}
