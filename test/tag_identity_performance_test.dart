import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final size in [10, 10000]) {
    testWidgets('two filtered headers resolve a $size tag directory', (
      tester,
    ) async {
      const site = 'https://meta.discourse.org';
      const config = SiteConfig(taggingEnabled: true);
      final personal = _CountingTags(const [
        SidebarTag(id: 10001, name: 'Personal', slug: 'personal'),
      ]);
      final user = DiscourseUser(
        id: 7,
        username: 'reader',
        unifiedNewEnabled: true,
        sidebarTags: personal,
      );
      final tags = List.generate(
        size,
        (i) => SidebarTag(id: i + 1, name: 'Tag $i', slug: 'tag-$i'),
      );
      final selected = [size - 3, size - 2, size - 1];
      final api = FakeDiscourseApi(
        user: user,
        siteConfigs: const {site: config},
        feeds: const {'/latest.json': []},
        tagList: tags,
        trackingState: TopicTrackingState([
          TrackedTopicState(
            topicId: 42,
            createdInNewPeriod: true,
            tagIds: selected.map((i) => i + 1).toSet(),
          ),
        ]),
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: user, config: config),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        ownsApi: false,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await tester.pump();
      await shell.loadTags(site);
      shell.selectTopicListTags(selected.map((i) => 'tag-$i').toList());
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: TopicListNavigation(child: SizedBox())),
                  Expanded(child: TopicListNavigation(child: SizedBox())),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TopicFeedMenu), findsNWidgets(2));
      expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
      for (final menu in tester.widgetList<TopicFeedMenu>(
        find.byType(TopicFeedMenu),
      )) {
        expect(menu.newCount, 1);
      }
      for (var i = 0; i < 10; i++) {
        shell.notifyPluginStateChanged();
      }
      personal.iterations = 0;
      final samples = <int>[];
      for (var run = 0; run < 5; run++) {
        final clock = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          shell.notifyPluginStateChanged();
        }
        clock.stop();
        samples.add(clock.elapsedMicroseconds);
      }
      final sourceIterations = personal.iterations;
      if (Platform.environment['TAG_IDENTITY_BASELINE'] != '1') {
        expect(sourceIterations, 0);
      }
      expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final output = Platform.environment['TAG_IDENTITY_OUTPUT'];
      if (output != null) {
        File(output).writeAsStringSync(
          '${jsonEncode({'size': size, 'notifications': 100, 'headers': 2, 'samples_us': samples, 'count': shell.topicListNewCounts.all, 'source_iterations': sourceIterations})}\n',
          mode: FileMode.append,
        );
      }
      final routeName = shell.topicListContent!.tagNames.first;
      for (final trimOnly in [false, true]) {
        final shadow = SidebarTag(
          id: 20001,
          name: trimOnly ? ' $routeName ' : 'Private shadow',
          slug: trimOnly ? 'unrelated' : routeName.toUpperCase(),
          pmOnly: true,
        );
        shell.applyAccountSessionInstance(
          shell
              .instanceFor(site)!
              .copyWith(
                user: DiscourseUser(
                  id: 7,
                  username: 'reader',
                  unifiedNewEnabled: true,
                  sidebarTags: [shadow],
                ),
              ),
          AccountSessionPhase.connecting,
        );
        await tester.pump();
        final expected = trimOnly ? 1 : 0;
        expect(shell.topicListNewCounts.all, expected);
        for (final menu in tester.widgetList<TopicFeedMenu>(
          find.byType(TopicFeedMenu),
        )) {
          expect(menu.newCount, expected);
        }
      }
      shell.selectTopicListTags(['missing']);
      await tester.pump();
      expect(shell.topicListNewCounts.all, 0);
    });
  }
}

final class _CountingTags extends UnmodifiableListView<SidebarTag> {
  _CountingTags(super.source);
  int iterations = 0;
  @override
  Iterator<SidebarTag> get iterator {
    iterations++;
    return super.iterator;
  }
}
