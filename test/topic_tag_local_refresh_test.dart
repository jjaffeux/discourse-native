import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_tag_picker.dart';
import 'package:discourse_native/src/shell/topic_tag_selector.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

void main() {
  const known = TopicTag(id: 1, name: 'known');
  const disabled = TopicTag(id: 2, name: 'disabled', disabled: true);

  testWidgets('filter tag selector offers known tags while refreshing', (
    tester,
  ) async {
    final remote = Completer<TopicTagSearch>();
    List<TopicTag>? selected;
    await tester.pumpWidget(
      _app(
        TopicTagSelector(
          selectedTags: const [],
          knownTags: const [known, disabled],
          includeAll: true,
          search: (_) => remote.future,
          onChanged: (tags) => selected = tags,
        ),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(TopicTagSelector),
        matching: find.byType(DButton),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey(('tag-selector-option', 'known')));
    expect(row, findsOneWidget);
    final blocked = tester
        .widget<DCombobox<TopicTag>>(find.byType(DCombobox<TopicTag>))
        .options
        .singleWhere((option) => option.value.name == disabled.name);
    expect(blocked.enabled, isFalse);
    await tester.tap(row);
    await tester.pump();
    expect(selected, [known]);
    expect(remote.isCompleted, isFalse);
    remote.complete(const TopicTagSearch());
    await tester.pumpAndSettle();
  });

  testWidgets('selected authoring tags can be removed while search waits', (
    tester,
  ) async {
    final remote = Completer<TopicTagSearch>();
    List<TopicTag>? selected;
    await tester.pumpWidget(
      _app(
        TopicTagPicker(
          selectedTags: const [known],
          capabilities: const TopicComposerCapabilities(canTagTopics: true),
          search: (_) => remote.future,
          onSelected: (tags) => selected = tags,
        ),
      ),
    );
    await tester.pump();
    final row = find.byKey(
      const ValueKey(('topic-tag-picker-option', 'known')),
    );
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    expect(selected, isEmpty);
    expect(remote.isCompleted, isFalse);
    remote.complete(const TopicTagSearch());
    await tester.pumpAndSettle();
  });

  testWidgets('authoring tags do not preview unknown eligibility', (
    tester,
  ) async {
    final remote = Completer<TopicTagSearch>();
    await tester.pumpWidget(
      _app(
        TopicTagSelector(
          selectedTags: const [],
          knownTags: const [known],
          search: (_) => remote.future,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(TopicTagSelector),
        matching: find.byType(DButton),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey(('tag-selector-option', 'known'))),
      findsNothing,
    );
    remote.complete(const TopicTagSearch(forbidden: true));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(('tag-selector-option', 'known'))),
      findsNothing,
    );
  });

  testWidgets('Enter removes a matching selected tag while creation waits', (
    tester,
  ) async {
    final remote = Completer<TopicTagSearch>();
    List<TopicTag>? selected;
    await tester.pumpWidget(
      _app(
        TopicTagPicker(
          selectedTags: const [known],
          capabilities: const TopicComposerCapabilities(
            canTagTopics: true,
            canCreateTag: true,
          ),
          search: (_) => remote.future,
          onSelected: (tags) => selected = tags,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('topic-tag-picker-query')),
      'kn',
    );
    await tester.pump();
    expect(
      tester
          .widget<DButton>(
            find.byKey(const ValueKey('topic-tag-picker-create')),
          )
          .onPressed,
      isNull,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(selected, isEmpty);
    expect(remote.isCompleted, isFalse);
    remote.complete(const TopicTagSearch());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });
}
