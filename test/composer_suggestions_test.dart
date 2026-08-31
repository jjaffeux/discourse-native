import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_suggestions.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  testWidgets('rows are named 44-pixel choices in the field keyboard flow', (
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
      expect(tester.getSize(smileTarget).height, 44);
      expect(tester.getSize(smirkTarget).height, 44);
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
    ),
  );
}

TextEditingValue _typed(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);
