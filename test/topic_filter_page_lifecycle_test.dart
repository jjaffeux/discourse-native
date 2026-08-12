import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_filter_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _feed = TopicFeed(
  loaded: true,
  filterOptions: [TopicFilterOption(name: 'status:', priority: 1)],
);

void main() {
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
              home: const Scaffold(
                body: TopicFilterPage(
                  siteUrl: _siteUrl,
                  feed: _feed,
                  categories: [],
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

final class _FilterShell extends ShellController {
  _FilterShell()
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

  @override
  String filterQueryFor(String siteUrl) => '';

  @override
  Future<void> submitTopicFilter(String query) async {
    submissions.add(query);
  }
}
