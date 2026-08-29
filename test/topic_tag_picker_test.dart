import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/anchored_picker.dart';
import 'package:discourse_native/src/shell/topic_tag_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps the create row mounted while search results refresh', (
    tester,
  ) async {
    final pendingSearch = Completer<TopicTagSearch>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TopicTagPicker(
            selectedTags: const [],
            capabilities: const TopicComposerCapabilities(canCreateTag: true),
            search: (term) => term.isEmpty
                ? Future.value(const TopicTagSearch())
                : pendingSearch.future,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('topic-tag-picker-query')),
      'mobile',
    );
    await tester.pump();

    final createRow = find.byKey(const ValueKey('topic-tag-picker-create'));
    expect(createRow, findsOneWidget);
    final createElement = tester.element(createRow);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AnchoredPickerProgress), findsOneWidget);
    expect(createRow, findsOneWidget);
    expect(tester.element(createRow), same(createElement));

    pendingSearch.complete(const TopicTagSearch());
    await tester.pumpAndSettle();

    expect(find.byType(AnchoredPickerProgress), findsNothing);
    expect(createRow, findsOneWidget);
    expect(tester.element(createRow), same(createElement));
  });
}
