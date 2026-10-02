import 'dart:async';

import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _tagOption = TopicFilterOption(name: 'tag:', priority: 1, type: 'tag');

void main() {
  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.tab]) {
    for (final nextQuery in ['tag:c', 'tag:b', null]) {
      final scenario = switch (nextQuery) {
        'tag:c' => 'ignores a lookup after the query changes',
        'tag:b' => 'ignores a lookup after returning to the original query',
        _ => 'accepts a delayed suggestion for the unchanged query',
      };
      testWidgets('${key.keyLabel} $scenario', (tester) async {
        final lookup = Completer<List<TopicFilterLookupValue>>();
        final shell = _FilterShell(
          tags: (term) => term == 'b'
              ? lookup.future
              : Future.value([TopicFilterLookupValue(name: '${term}lpha')]),
        );
        addTearDown(shell.dispose);
        await _pumpFilter(tester, shell);

        final field = find.byKey(const ValueKey('topic-filter-input'));
        await tester.enterText(field, 'tag:a');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.enterText(field, 'tag:b');
        await tester.sendKeyEvent(key);
        if (nextQuery != null) {
          await tester.enterText(field, 'tag:c');
          if (nextQuery == 'tag:b') await tester.enterText(field, nextQuery);
        }
        lookup.complete(const [TopicFilterLookupValue(name: 'beta')]);
        await tester.pump();

        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          nextQuery ?? 'tag:beta ',
        );
        expect(shell.submissions, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('Enter ignores a lookup after suggestions are dismissed', (
    tester,
  ) async {
    final lookup = Completer<List<TopicFilterLookupValue>>();
    final shell = _FilterShell(
      tags: (term) => term == 'b'
          ? lookup.future
          : Future.value(const [TopicFilterLookupValue(name: 'alpha')]),
    );
    addTearDown(shell.dispose);
    await _pumpFilter(tester, shell);

    final field = find.byKey(const ValueKey('topic-filter-input'));
    await tester.enterText(field, 'tag:a');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(field, 'tag:b');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    lookup.complete(const [TopicFilterLookupValue(name: 'beta')]);
    await tester.pump();

    expect(shell.submissions, isEmpty);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Enter cannot submit a replacement filter after a lookup', (
    tester,
  ) async {
    final lookup = Completer<List<TopicFilterLookupValue>>();
    final first = _FilterShell(
      tags: (term) => term == 'b'
          ? lookup.future
          : Future.value(const [TopicFilterLookupValue(name: 'alpha')]),
    );
    final replacement = _FilterShell();
    addTearDown(first.dispose);
    addTearDown(replacement.dispose);
    var active = first;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return _filterApp(
            active,
            initialQuery: active == first ? '' : 'new query',
          );
        },
      ),
    );

    final field = find.byKey(const ValueKey('topic-filter-input'));
    await tester.enterText(field, 'tag:a');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(field, 'tag:b');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    rebuild(() => active = replacement);
    await tester.pump();
    lookup.complete(const [TopicFilterLookupValue(name: 'beta')]);
    await tester.pump();

    expect(first.submissions, isEmpty);
    expect(replacement.submissions, isEmpty);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'new query',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('filter submissions follow a replacement shell controller', (
    tester,
  ) async {
    final first = _FilterShell();
    final replacement = _FilterShell();
    addTearDown(first.dispose);
    addTearDown(replacement.dispose);

    var active = first;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return ShellScope(
            controller: active,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: TopicFilterInput(
                  siteUrl: _siteUrl,
                  initialQuery: '',
                  options: const [
                    TopicFilterOption(name: 'status:', priority: 1),
                  ],
                  onSubmitted: active.submitTopicFilter,
                  categories: const [],
                ),
              ),
            ),
          );
        },
      ),
    );

    rebuild(() => active = replacement);
    await tester.pump();

    final field = find.byKey(const ValueKey('topic-filter-input'));
    await tester.enterText(field, 'unseen');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(first.submissions, isEmpty);
    expect(replacement.submissions, ['unseen']);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpFilter(WidgetTester tester, _FilterShell shell) =>
    tester.pumpWidget(_filterApp(shell));

Widget _filterApp(_FilterShell shell, {String initialQuery = ''}) => ShellScope(
  controller: shell,
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: TopicFilterInput(
        siteUrl: _siteUrl,
        initialQuery: initialQuery,
        options: const [_tagOption],
        onSubmitted: shell.submitTopicFilter,
        categories: const [],
      ),
    ),
  ),
);

final class _FilterShell extends ShellController {
  _FilterShell({this.tags})
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );

  final List<String> submissions = [];
  final Future<List<TopicFilterLookupValue>> Function(String term)? tags;

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
  }) async => await tags?.call(term) ?? const [];

  @override
  String filterQueryFor(String siteUrl) => '';

  @override
  Future<void> submitTopicFilter(String query) async {
    submissions.add(query);
  }
}
