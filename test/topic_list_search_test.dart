import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/shell/topic_list_search.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search preserves scope and filters, resets pagination and clears', () {
    final source = ContentRoute.list(
      ListLink.parse('/c/design/42?status=open&assigned=nobody&page=3')!,
    );
    final searched = source.withTopicListSearch('  café & layouts  ');
    expect(searched.categoryId, 42);
    expect(searched.topicListSearch, 'café & layouts');
    expect(Uri.parse(searched.feedPath!).queryParameters, {
      'status': 'open',
      'assigned': 'nobody',
      'search': 'café & layouts',
    });
    final tagged = ContentRoute.filteredTopicList(
      TopicListMode.unread,
      categoryId: 42,
      tags: const ['design', 'mobile'],
    ).withTopicListQueryFrom(searched);
    expect(tagged.topicListSearch, searched.topicListSearch);
    expect(tagged.tagNames, ['design', 'mobile']);
    expect(TopicListMode.fromRoute(tagged), TopicListMode.unread);
    expect(
      ContentRoute.fromJson(tagged.toJson()).topicListSearch,
      searched.topicListSearch,
    );
    expect(tagged.withTopicListSearch('').tagNames, tagged.tagNames);
    expect(tagged.withTopicListSearch('').topicListSearch, isEmpty);
    final latest = ContentRoute.topicList(TopicListMode.latest);
    expect(
      latest.withTopicListSearch('hello').withTopicListSearch('').feedPath,
      '/latest.json',
    );
    expect(
      latest
          .withTopicListSearch('hello')
          .withTopicListSearch('')
          .topicListSearch,
      isEmpty,
    );
    expect(
      latest.withTopicListSearch('one').id,
      isNot(latest.withTopicListSearch('two').id),
    );
  });

  testWidgets('slash focuses search without stealing keys from editors', (
    tester,
  ) async {
    final otherFocus = FocusNode();
    addTearDown(otherFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              TopicListSearch(query: '', onChanged: (_) {}),
              DInputGroup(children: [DInputGroupInput(focusNode: otherFocus)]),
            ],
          ),
        ),
      ),
    );
    final search = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TopicListSearch),
        matching: find.byType(EditableText),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pump();
    expect(search.focusNode.hasFocus, isTrue);
    expect(search.controller.text, isEmpty);
    otherFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pump();
    expect(otherFocus.hasFocus, isTrue);
    otherFocus.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(search.focusNode.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'debounces, keeps drafts across scope changes, and clears immediately',
    (tester) async {
      final first = <String>[];
      final second = <String>[];
      Widget build(String category, ValueChanged<String> onChanged) =>
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TopicListSearch(
                query: '',
                categoryName: category,
                onChanged: onChanged,
              ),
            ),
          );
      await tester.pumpWidget(build('UX', first.add));
      final input = find.byKey(const ValueKey('topic-list-search'));
      await tester.enterText(input, 'layout');
      await tester.pump(const Duration(milliseconds: 200));
      expect(first, isEmpty);
      await tester.pumpWidget(build('Support', second.add));
      await tester.pump(const Duration(milliseconds: 300));
      expect(first, isEmpty);
      expect(second, ['layout']);
      expect(find.text('layout'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(second, ['layout', '']);
      await tester.enterText(input, 'abandoned');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(second, ['layout', '']);
    },
  );
}
