import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.iOS,
  TargetPlatform.android,
});

Finder _action(String action) => find.byKey(ValueKey('composer-$action'));

Finder _mainField(ComposerController composer) => find.byWidgetPredicate(
  (widget) =>
      widget is EditableText && identical(widget.controller, composer.text),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'toolbar follows available history and restores typing with its caret',
    (tester) async {
      final composer = await _pumpPanel(tester, source: 'Draft');
      expect(_action('undo'), findsNothing);
      expect(_action('redo'), findsNothing);

      composer.text.selection = const TextSelection.collapsed(offset: 2);
      await tester.pumpAndSettle();
      expect(_action('undo'), findsNothing);

      await tester.enterText(_mainField(composer), 'Draft updated');
      await tester.pump();
      await tester.pump();
      expect(_action('undo').hitTestable(), findsOneWidget);
      expect(_action('redo'), findsNothing);
      final undo = tester.widget<DButton>(_action('undo'));
      expect(undo.tooltip, 'Undo');
      expect(undo.onPressed, isNotNull);
      if (defaultTargetPlatform != TargetPlatform.macOS) {
        expect(find.byKey(const ValueKey('composer-formatting')), findsNothing);
        expect(tester.getRect(_action('undo')).bottom, lessThanOrEqualTo(470));
        expect(undo.size, DControlSize.large);
        expect(undo.variant, DButtonVariant.inline);
      }

      // Undo is available before the typing coalescing timer has elapsed.
      await tester.tap(_action('undo'));
      await tester.pumpAndSettle();
      expect(composer.raw, 'Draft');
      expect(composer.text.selection.extentOffset, 2);
      expect(composer.focus.hasFocus, isTrue);
      expect(_action('undo'), findsNothing);
      expect(_action('redo').hitTestable(), findsOneWidget);
      expect(tester.widget<DButton>(_action('redo')).tooltip, 'Redo');

      await tester.tap(_action('redo'));
      await tester.pumpAndSettle();
      expect(composer.raw, 'Draft updated');
      expect(composer.text.selection.extentOffset, 'Draft updated'.length);
      expect(composer.focus.hasFocus, isTrue);
      expect(_action('undo').hitTestable(), findsOneWidget);
      expect(_action('redo'), findsNothing);

      composer.history.transact(() {
        composer.text.value = const TextEditingValue(
          text: 'Another edit',
          selection: TextSelection.collapsed(offset: 12),
        );
      });
      await tester.pumpAndSettle();
      await tester.tap(_action('undo'));
      await tester.pumpAndSettle();
      expect(composer.raw, 'Draft updated');
      expect(_action('undo'), findsOneWidget);
      expect(_action('redo'), findsOneWidget);

      await tester.enterText(_mainField(composer), 'New typing');
      await tester.pumpAndSettle();
      expect(_action('undo'), findsOneWidget);
      expect(_action('redo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );

  testWidgets(
    'history reset, composition and submission update toolbar availability',
    (tester) async {
      final composer = await _pumpPanel(tester);
      await tester.enterText(_mainField(composer), 'First edit');
      await tester.pumpAndSettle();
      expect(_action('undo'), findsOneWidget);
      composer.history.reset();
      await tester.pumpAndSettle();
      expect(_action('undo'), findsNothing);
      expect(_action('redo'), findsNothing);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'First edit 文',
          selection: TextSelection.collapsed(offset: 12),
          composing: TextRange(start: 11, end: 12),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_action('undo'), findsNothing);
      expect(_action('redo'), findsNothing);
      tester.testTextInput.updateEditingValue(
        composer.text.value.copyWith(composing: TextRange.empty),
      );
      await tester.pumpAndSettle();
      expect(_action('undo'), findsOneWidget);

      final retainedUndo = tester.widget<DButton>(_action('undo')).onPressed!;
      final source = composer.raw;
      composer.beginSubmit();
      await tester.pump();
      await tester.pump();
      expect(_action('undo'), findsNothing);
      expect(_action('redo'), findsNothing);
      retainedUndo();
      expect(composer.raw, source);
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );

  for (final details in [false, true]) {
    testWidgets(
      'toolbar restores the active embedded ${details ? 'details' : 'list'} editor',
      (tester) async {
        final source = details
            ? '[details="Summary"]\nBody\n[/details]'
            : '- [ ] Body';
        final composer = await _pumpPanel(tester, source: source);
        final body = find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.controller.text == 'Body',
        );
        await tester.enterText(body, 'Changed body');
        await tester.pumpAndSettle();
        final embedded = composer.activeEditor;
        expect(embedded, isNot(same(composer)));
        expect(embedded.focus.hasFocus, isTrue);
        expect(_action('undo').hitTestable(), findsOneWidget);

        await tester.tap(_action('undo'));
        await tester.pumpAndSettle();
        expect(composer.raw, source);
        expect(composer.activeEditor.text.text, 'Body');
        expect(composer.activeEditor.focus.hasFocus, isTrue);
        expect(_action('undo'), findsNothing);
        expect(_action('redo').hitTestable(), findsOneWidget);

        if (details) {
          // Details have local history; changing focus must change the
          // toolbar's history subscription without losing the redo entry.
          composer.focus.requestFocus();
          await tester.pumpAndSettle();
          expect(composer.activeEditor, same(composer));
          expect(_action('redo'), findsNothing);
          composer.history.reset();
          await tester.pumpAndSettle();
          expect(_action('undo'), findsNothing);
          embedded.focus.requestFocus();
          await tester.pumpAndSettle();
          expect(composer.activeEditor, same(embedded));
          expect(_action('redo').hitTestable(), findsOneWidget);
        }

        await tester.tap(_action('redo'));
        await tester.pumpAndSettle();
        expect(composer.raw, source.replaceFirst('Body', 'Changed body'));
        expect(composer.activeEditor.text.text, 'Changed body');
        expect(composer.activeEditor.focus.hasFocus, isTrue);
        expect(_action('redo'), findsNothing);
        expect(composer.draft.reply, composer.raw);
        expect(tester.takeException(), isNull);
      },
      variant: _platforms,
    );
  }
}

Future<ComposerController> _pumpPanel(
  WidgetTester tester, {
  String source = '',
}) async {
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://example.test',
      topicId: 1,
      slug: 'topic',
      topicTitle: 'Topic',
    ),
  );
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    composer.dispose();
    shell.dispose();
  });
  final mobile = defaultTargetPlatform != TargetPlatform.macOS;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = mobile
      ? const Size(390, 800)
      : const Size(1000, 800);
  tester.view.viewInsets = FakeViewPadding(bottom: mobile ? 330 : 0);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: defaultTargetPlatform),
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: ComposerPanel(composer: composer, height: mobile ? 800 : 650),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}
