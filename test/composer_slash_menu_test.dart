import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_slash_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slash query excludes URLs, paths, code, selections and IME', () {
    for (final text in [
      'https://example.com/',
      'path/file',
      '` /bold',
      '```\n/bold',
      '~~~\n/bold',
      '//',
      '/ ',
      '/sometext ',
      '/inline code',
      '    /bold',
      '```\n~~~\n/bold',
    ]) {
      expect(
        composerSlashQuery(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        ),
        isNull,
        reason: text,
      );
    }
    expect(
      composerSlashQuery(
        const TextEditingValue(
          text: '`` /bold ``',
          selection: TextSelection.collapsed(offset: 8),
        ),
      ),
      isNull,
    );
    expect(
      composerSlashQuery(
        const TextEditingValue(
          text: 'Hi /inline',
          selection: TextSelection.collapsed(offset: 10),
        ),
      ),
      (start: 3, end: 10, query: 'inline'),
    );
    expect(
      composerSlashQuery(
        const TextEditingValue(
          text: '/bold',
          selection: TextSelection(baseOffset: 0, extentOffset: 5),
        ),
      ),
      isNull,
    );
    expect(
      composerSlashQuery(
        const TextEditingValue(
          text: '/bold',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 1, end: 5),
        ),
      ),
      isNull,
    );
  });

  Future<ComposerController> pump(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
    List<ComposerSlashAction> Function(ComposerController)? actions,
  }) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://example.test',
        topicId: 1,
        slug: 'test',
        topicTitle: 'Test',
      ),
    );
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 360,
                height: 240,
                child: ComposerEditor(
                  composer: composer,
                  slashActions: (_) => actions?.call(composer) ?? [],
                  hintText: 'Reply',
                  textStyle: const TextStyle(fontSize: 16),
                  hintStyle: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return composer;
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(EditableText).first, text);
    await tester.pumpAndSettle();
  }

  for (var level = 1; level <= 4; level++) {
    testWidgets('heading $level filters and inserts from the keyboard', (
      tester,
    ) async {
      final composer = await pump(tester);
      await type(tester, '/h$level');
      expect(find.text('Heading $level'), findsOneWidget);
      expect(find.text('#' * level), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(composer.text.text, '${'#' * level} ');
      expect(composer.text.selection.extentOffset, level + 1);
      expect(composer.focus.hasFocus, isTrue);
    });
  }

  for (final edit in [
    (source: '/', replacement: ''),
    (source: 'Before /', replacement: 'Hi'),
  ]) {
    testWidgets(
      'shortening "${edit.source}" to "${edit.replacement}" during layout hides the slash hint',
      (tester) async {
        final composer = await pump(tester);
        await type(tester, edit.source);
        expect(find.text('Type to search'), findsOneWidget);

        // Rebuild the editor's layout before the menu refreshes its cached
        // query in the post-frame callback.
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: edit.replacement,
            selection: TextSelection.collapsed(offset: edit.replacement.length),
          ),
        );
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.physicalSize =
            const Size(340, 600) * tester.view.devicePixelRatio;
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Type to search'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('Close menu'), findsNothing);
        expect(composer.text.text, edit.replacement);
        expect(composer.focus.hasFocus, isTrue);
      },
    );
  }

  testWidgets('heading preserves the line and replaces its existing level', (
    tester,
  ) async {
    final composer = await pump(tester);
    await type(tester, 'Previous paragraph\n\n### Existing /h2');
    await tester.tap(find.text('Heading 2'));
    await tester.pumpAndSettle();
    expect(composer.text.text, 'Previous paragraph\n\n## Existing ');
    expect(composer.text.selection.extentOffset, composer.text.text.length);
  });

  testWidgets(
    'plugin callbacks resolve source offsets after removing slash query',
    (tester) async {
      int? invokedOffset;
      final composer = await pump(
        tester,
        actions: (composer) {
          final capturedOffset = composer.text.text.indexOf('[event]');
          return [
            ComposerSlashAction(
              label: 'Event',
              icon: DIcons.list,
              onInvoke: () {
                invokedOffset = capturedOffset;
              },
            ),
          ];
        },
      );
      composer.text.value = const TextEditingValue(
        text: '/event [event]',
        selection: TextSelection.collapsed(offset: 6),
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(composer.text.text, ' [event]');
      expect(invokedOffset, 1);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'slash hint and filtering preserve focus (${dark ? 'dark' : 'light'})',
      (tester) async {
        final composer = await pump(tester, dark: dark);
        await type(tester, '/');
        expect(find.text('Type to search'), findsOneWidget);
        expect(find.text('Bold'), findsOneWidget);
        expect(find.text('Table'), findsOneWidget);
        expect(find.text('Details'), findsOneWidget);
        expect(composer.focus.hasFocus, isTrue);
        await type(tester, 'Before /bold');
        expect(find.text('Table'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(composer.text.text, 'Before ****');
        expect(composer.text.selection.extentOffset, 9);
        expect(find.text('Close menu'), findsNothing);
        expect(composer.focus.hasFocus, isTrue);
      },
    );
  }

  testWidgets('arrow selection, Escape, empty results and pointer activation', (
    tester,
  ) async {
    final composer = await pump(tester);
    await type(tester, '/');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(composer.text.text, '**'); // Italic is the second action.
    await type(tester, '/');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(composer.text.text, '');
    expect(find.text('Close menu'), findsNothing);
    await type(tester, '/bo');
    expect(find.text('Close menu'), findsOneWidget);
    await type(tester, '');
    await type(tester, '/notacommand');
    expect(find.text('No matching commands.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(composer.text.text, '/notacommand');
    await type(tester, '/table');
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(composer.text.text, contains('|'));
    expect(composer.text.text, isNot(contains('/table')));
  });

  for (final closeButton in [false, true]) {
    for (final query in ['', 'bold']) {
      testWidgets(
        '${closeButton ? 'Close button' : 'Escape'} removes only a bare slash ($query)',
        (tester) async {
          final composer = await pump(tester);
          final source = 'Before /$query\nAfter';
          composer.text.value = TextEditingValue(
            text: source,
            selection: TextSelection.collapsed(offset: 8 + query.length),
          );
          composer.focus.requestFocus();
          await tester.pumpAndSettle();
          expect(find.text('Close menu'), findsOneWidget);
          if (closeButton) {
            await tester.tap(find.text('Close menu'));
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          }
          await tester.pumpAndSettle();
          expect(composer.text.text, query.isEmpty ? 'Before \nAfter' : source);
          expect(composer.text.selection.extentOffset, query.isEmpty ? 7 : 12);
          expect(find.text('Close menu'), findsNothing);
          expect(composer.focus.hasFocus, isTrue);
        },
      );
    }
  }

  for (final query in ['', 'sometext']) {
    testWidgets('Space closes /$query while preserving literal text', (
      tester,
    ) async {
      final composer = await pump(tester);
      await type(tester, '/$query');
      expect(find.text('Close menu'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Close menu'), findsNothing);
      // Widget tests deliver hardware keys and platform text input separately.
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '/$query ',
          selection: TextSelection.collapsed(offset: query.length + 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(composer.text.text, '/$query ');
      expect(find.text('Close menu'), findsNothing);
      await type(tester, '/$query more');
      expect(find.text('Close menu'), findsNothing);
    });
  }

  for (final dismissal in ['backspace', 'escape', 'space']) {
    testWidgets('$dismissal keeps slash menu geometry during exit', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'First line\nSome text /');
      final anchor = find.descendant(
        of: find.byType(ComposerSlashMenu),
        matching: find.byType(DPopoverAnchor),
      );
      final position = tester.getTopLeft(anchor);
      final menu = find.byType(DDropdownMenuContent);
      final size = tester.getSize(menu);
      if (dismissal == 'backspace') {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      } else {
        await tester.sendKeyEvent(
          dismissal == 'escape'
              ? LogicalKeyboardKey.escape
              : LogicalKeyboardKey.space,
        );
      }
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(anchor), position);
        if (menu.evaluate().isNotEmpty) {
          expect(tester.getSize(menu), size);
          expect(find.text('Bold'), findsOneWidget);
        }
      }
      await tester.pumpAndSettle();
      expect(find.text('Close menu'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow scaled popup fits and dismisses outside', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, scale: 2);
    await type(tester, '/');
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Close menu'), findsNothing);
  });
}
