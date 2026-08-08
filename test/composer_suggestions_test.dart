import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_suggestions.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a popup that was open before the field mounted', (
    tester,
  ) async {
    final composer = _composer('already open');
    composer.autocomplete.update(_typed(':item'));

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
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    rebuild(() => shown = second);
    await tester.pump();
    await tester.pump();
    expect(find.text('first'), findsNothing);

    second.autocomplete.update(_typed(':item'));
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
}

ComposerController _composer(String label) => ComposerController(
  const ComposerTarget(
    siteUrl: 'https://meta.discourse.org',
    topicId: 1,
    slug: 'topic',
    topicTitle: 'Topic',
  ),
  search: (
    users: (_) async => const [],
    hashtags: (_) async => const [],
    emojis: (_) => [
      ComposerSuggestion(
        kind: ComposerTriggerKind.emoji,
        value: label,
        label: label,
      ),
    ],
  ),
);

TextEditingValue _typed(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);
