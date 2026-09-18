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
          text: 'Hi /inline code',
          selection: TextSelection.collapsed(offset: 15),
        ),
      ),
      (start: 3, end: 15, query: 'inline code'),
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
              label: 'Edit event',
              icon: DIcons.list,
              onInvoke: () {
                invokedOffset = capturedOffset;
              },
            ),
          ];
        },
      );
      composer.text.value = const TextEditingValue(
        text: '/edit event [event]',
        selection: TextSelection.collapsed(offset: 11),
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
    expect(composer.text.text, '/');
    expect(find.text('Close menu'), findsNothing);
    await type(tester, '/bo');
    expect(find.text('Close menu'), findsNothing);
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
