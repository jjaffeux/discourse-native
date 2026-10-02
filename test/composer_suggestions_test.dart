import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_suggestions.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final duringLookup in [false, true]) {
    for (final activation in ['Enter', 'Numpad Enter', 'Tab', 'tap']) {
      testWidgets(
        '$activation does not accept a retained mention ${duringLookup ? 'during lookup' : 'before debounce'}',
        (tester) async {
          final pending = Completer<List<ComposerSuggestion>>();
          final asked = <String>[];
          const sam = ComposerSuggestion(
            kind: ComposerTriggerKind.mention,
            value: 'sam',
            label: 'sam',
          );
          const alice = ComposerSuggestion(
            kind: ComposerTriggerKind.mention,
            value: 'alice',
            label: 'alice',
          );
          final composer = ComposerController(
            const ComposerTarget(
              siteUrl: 'https://meta.discourse.org',
              topicId: 1,
              slug: 'topic',
              topicTitle: 'Topic',
            ),
            search: (
              users: (query) async {
                asked.add(query);
                return query == 'sa' ? [sam] : pending.future;
              },
              hashtags: (_) async => const [],
              emojis: (_) async => const [],
            ),
          );
          addTearDown(composer.dispose);
          composer.text.value = _typed('@sa');
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: ComposerSuggestionField(
                  composer: composer,
                  field: DInput(
                    controller: composer.text,
                    focusNode: composer.focus,
                  ),
                ),
              ),
            ),
          );
          await tester.pump(ComposerAutocomplete.debounce);
          await tester.pumpAndSettle();
          expect(find.text('sam'), findsOneWidget);

          final search = find.descendant(
            of: find.byType(DCommandInput<ComposerSuggestion>),
            matching: find.byType(EditableText),
          );
          await tester.enterText(search, 'alice');
          await tester.pump();
          expect(composer.raw, '@alice');
          expect(find.text('sam'), findsOneWidget);
          if (duringLookup) {
            await tester.pump(ComposerAutocomplete.debounce);
            expect(asked, ['sa', 'alice']);
          } else {
            expect(asked, ['sa']);
          }

          switch (activation) {
            case 'tap':
              await tester.tap(find.text('sam'));
            case 'Enter':
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            case 'Numpad Enter':
              await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
            case 'Tab':
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          }
          await tester.pump();
          expect(composer.raw, '@alice');
          expect(composer.autocomplete.isOpen, isTrue);
          expect(find.text('sam'), findsOneWidget);

          pending.complete([alice]);
          await tester.pump(ComposerAutocomplete.debounce);
          await tester.pumpAndSettle();
          expect(find.text('sam'), findsNothing);
          expect(
            find.byWidgetPredicate(
              (widget) => widget is Text && widget.data == 'alice',
            ),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(composer.text.text, '@alice ');
          expect(composer.autocomplete.isOpen, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('retained emoji action rows wait for the current query', (
    tester,
  ) async {
    final pending = Completer<List<ComposerSuggestion>>();
    ComposerSuggestion action(String query) => ComposerSuggestion(
      kind: ComposerTriggerKind.emoji,
      value: query,
      label: 'More emoji',
      action: ComposerSuggestionAction.openEmojiPicker,
    );
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 1,
        slug: 'topic',
        topicTitle: 'Topic',
      ),
      search: (
        users: (_) async => const [],
        hashtags: (_) async => const [],
        emojis: (query) async =>
            query == 'sm' ? [action(query)] : pending.future,
      ),
    );
    addTearDown(composer.dispose);
    composer.text.value = _typed(':sm');
    ComposerSuggestion? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ComposerSuggestionField(
            composer: composer,
            onAction:
                ({
                  required context,
                  required composer,
                  required suggestion,
                  anchor,
                }) async => opened = suggestion,
            field: DInput(controller: composer.text, focusNode: composer.focus),
          ),
        ),
      ),
    );
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pumpAndSettle();
    composer.focus.requestFocus();
    await tester.pump();

    composer.text.value = _typed(':gr');
    await tester.pump(ComposerAutocomplete.debounce);
    expect(find.text('More emoji'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.text('More emoji'));
    await tester.pump();
    expect(opened, isNull);
    expect(composer.text.text, ':gr');
    expect(composer.autocomplete.isOpen, isTrue);

    pending.complete([action('gr')]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('More emoji'));
    await tester.pump();
    expect(opened?.value, 'gr');
    expect(composer.text.text, ':gr');
    expect(composer.autocomplete.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final hardwareKeyboard in [true, false]) {
    testWidgets(
      '${hardwareKeyboard ? 'hardware' : 'mobile'} Backspace removes an empty mention and closes its menu',
      (tester) async {
        final composer = _composer('unused');
        addTearDown(composer.dispose);
        composer.text.value = const TextEditingValue(
          text: 'Hello @s there',
          selection: TextSelection.collapsed(offset: 8),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ComposerSuggestionField(
                composer: composer,
                field: DInput(
                  borderless: true,
                  controller: composer.text,
                  focusNode: composer.focus,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byType(DCommandInput<ComposerSuggestion>),
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);

        Future<void> backspace() async {
          if (hardwareKeyboard) {
            await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          } else {
            final value = TextEditingValue.fromJSON(
              tester.testTextInput.editingState!,
            );
            final caret = value.selection.baseOffset;
            if (caret > 0) {
              tester.testTextInput.updateEditingValue(
                TextEditingValue(
                  text: value.text.replaceRange(caret - 1, caret, ''),
                  selection: TextSelection.collapsed(offset: caret - 1),
                ),
              );
            }
          }
          await tester.pumpAndSettle();
        }

        await backspace();
        expect(composer.text.text, 'Hello @ there');
        expect(composer.autocomplete.isOpen, isTrue);
        expect(search, findsOneWidget);

        await backspace();
        expect(composer.text.text, 'Hello  there');
        expect(
          composer.text.selection,
          const TextSelection.collapsed(offset: 6),
        );
        expect(composer.autocomplete.isOpen, isFalse);
        expect(search, findsNothing);
        expect(composer.focus.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant(
        hardwareKeyboard
            ? {TargetPlatform.macOS}
            : {TargetPlatform.iOS, TargetPlatform.android},
      ),
    );
  }

  testWidgets('shows a popup that was open before the field mounted', (
    tester,
  ) async {
    final composer = _composer('already open');
    composer.autocomplete.update(_typed(':item'));
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ComposerSuggestionField(
            composer: composer,
            field: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('already open'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    composer.dispose();
  });

  testWidgets('follows the composer when the field is updated in place', (
    tester,
  ) async {
    final first = _composer('first');
    final second = _composer('second');
    var shown = first;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ComposerSuggestionField(
                composer: shown,
                field: const SizedBox(width: 200, height: 40),
              );
            },
          ),
        ),
      ),
    );

    first.autocomplete.update(_typed(':item'));
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    rebuild(() => shown = second);
    await tester.pump();
    await tester.pump();
    expect(find.text('first'), findsNothing);

    second.autocomplete.update(_typed(':item'));
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();
    expect(find.text('second'), findsOneWidget);

    first.autocomplete.dismiss();
    await tester.pump();
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    second.dispose();
  });

  testWidgets('an open popup follows a field moved by a rebuild', (
    tester,
  ) async {
    final composer = _composer('moving');
    var top = 220.0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Stack(
                children: [
                  Positioned(
                    top: top,
                    left: 40,
                    child: ComposerSuggestionField(
                      composer: composer,
                      field: SizedBox(width: 200 + top * 0, height: 40),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    composer.autocomplete.update(_typed(':item'));
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();
    final before = tester.getTopLeft(find.text('moving'));

    rebuild(() => top = 320);
    await tester.pump();
    await tester.pump();
    final after = tester.getTopLeft(find.text('moving'));

    expect(after.dy - before.dy, closeTo(100, 0.01));
    await tester.pumpWidget(const SizedBox.shrink());
    composer.dispose();
  });

  testWidgets('Native command rows stay in the field keyboard flow', (
    tester,
  ) async {
    final composer = _composerWith(['smile', 'smirk']);
    composer.text.value = _typed(':sm');
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ComposerSuggestionField(
              composer: composer,
              field: TextField(
                controller: composer.text,
                focusNode: composer.focus,
              ),
            ),
          ),
        ),
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();

      final smile = find.text('smile');
      final smirk = find.text('smirk');
      final smileTarget = find
          .ancestor(of: smile, matching: find.byType(GestureDetector))
          .first;
      final smirkTarget = find
          .ancestor(of: smirk, matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(smileTarget).height, 32);
      expect(tester.getSize(smirkTarget).height, 32);
      _expectSuggestion(tester, smile, selected: true);
      _expectSuggestion(tester, smirk, selected: false);
      expect(composer.focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      _expectSuggestion(tester, smile, selected: false);
      _expectSuggestion(tester, smirk, selected: true);
      expect(composer.focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(composer.text.text, ':smirk: ');
      expect(composer.autocomplete.isOpen, isFalse);
      expect(composer.focus.hasPrimaryFocus, isTrue);
    } finally {
      semantics.dispose();
      composer.dispose();
    }
  });

  testWidgets('an action row opens its secondary surface without completing', (
    tester,
  ) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 1,
        slug: 'topic',
        topicTitle: 'Topic',
      ),
      search: (
        users: (_) async => const [],
        hashtags: (_) async => const [],
        emojis: (query) async => [
          ComposerSuggestion(
            kind: ComposerTriggerKind.emoji,
            value: query,
            label: 'More emoji',
            action: ComposerSuggestionAction.openEmojiPicker,
          ),
        ],
      ),
    );
    addTearDown(composer.dispose);
    composer.text.value = _typed(':sm');
    ComposerSuggestion? opened;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ComposerSuggestionField(
            composer: composer,
            onAction:
                ({
                  required context,
                  required composer,
                  required suggestion,
                  anchor,
                }) async {
                  opened = suggestion;
                },
            field: TextField(
              controller: composer.text,
              focusNode: composer.focus,
            ),
          ),
        ),
      ),
    );
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();
    composer.focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(opened?.action, ComposerSuggestionAction.openEmojiPicker);
    expect(opened?.value, 'sm');
    expect(composer.text.text, ':sm');
    expect(composer.autocomplete.isOpen, isFalse);
  });
}

ComposerController _composer(String label) => ComposerController(
  const ComposerTarget(
    siteUrl: 'https://meta.discourse.org',
    topicId: 1,
    slug: 'topic',
    topicTitle: 'Topic',
  ),
  search: _search([label]),
);

ComposerController _composerWith(List<String> labels) => ComposerController(
  const ComposerTarget(
    siteUrl: 'https://meta.discourse.org',
    topicId: 1,
    slug: 'topic',
    topicTitle: 'Topic',
  ),
  search: _search(labels),
);

ComposerSearch _search(List<String> labels) => (
  users: (_) async => const [],
  hashtags: (_) async => const [],
  emojis: (_) async => [
    for (final label in labels)
      ComposerSuggestion(
        kind: ComposerTriggerKind.emoji,
        value: label,
        label: label,
      ),
  ],
);

void _expectSuggestion(
  WidgetTester tester,
  Finder suggestion, {
  required bool selected,
}) {
  expect(
    tester.getSemantics(suggestion),
    isSemantics(
      label: tester.widget<Text>(suggestion).data,
      isButton: true,
      hasSelectedState: true,
      isSelected: selected,
      hasTapAction: true,
      hasEnabledState: true,
      isEnabled: true,
    ),
  );
}

TextEditingValue _typed(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);
