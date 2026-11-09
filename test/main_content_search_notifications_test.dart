import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/tags_page.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'joffreyj');

/// Distinct elements rebuilt by [action] at or under a [T].
Future<int> _rebuiltUnder<T extends Widget>(
  Future<void> Function() action,
) async {
  final rebuilt = <Element>{};
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    var inside = element.widget is T;
    if (!inside) {
      element.visitAncestorElements((ancestor) {
        inside = ancestor.widget is T;
        return !inside;
      });
    }
    if (inside) rebuilt.add(element);
  };
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilt.length;
}

FakeDiscourseApi _api() => FakeDiscourseApi(
  user: _user,
  feeds: {
    '/latest.json': [
      for (var id = 1; id <= 30; id++)
        Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
    ],
  },
  tagList: [
    for (var id = 1; id <= 40; id++)
      SidebarTag(
        id: id,
        name: id == 7 ? 'needle' : 'tag$id',
        slug: 'tag$id',
        count: 100 - id,
      ),
  ],
);

void main() {
  for (final (name, size, platform) in [
    ('phone', phone, TargetPlatform.iOS),
    ('mac', desktop, TargetPlatform.macOS),
  ]) {
    Future<ShellController> pump(WidgetTester tester) async {
      await pumpShell(
        tester,
        size,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: _user),
        ],
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        api: _api(),
      );
      await tester.pumpAndSettle();
      return ShellScope.read(tester.element(primaryMainContent));
    }

    testWidgets('$name opening search leaves the tags page built', (
      tester,
    ) async {
      final shell = await pump(tester);
      const route = ContentRoute(
        destination: PageDestination(CorePage.tags),
        title: 'Tags',
        icon: DIcons.tag,
      );
      shell.pushContent(route);
      await tester.pumpAndSettle();
      expect(find.byType(TagDirectoryRow), findsWidgets);

      final opened = await _rebuiltUnder<TagsPage>(() async {
        shell.search.openPanel();
        await tester.pump();
      });
      expect(shell.search.panelOpen, isTrue);
      final closed = await _rebuiltUnder<TagsPage>(() async {
        shell.search.closePanel();
        await tester.pump();
      });
      expect(shell.search.panelOpen, isFalse);

      // ignore: avoid_print
      print(
        'PERF_PROOF main-content-search ${name}_open_tags_elements=$opened',
      );
      // ignore: avoid_print
      print(
        'PERF_PROOF main-content-search ${name}_close_tags_elements=$closed',
      );
      expect(opened, 0);
      expect(closed, 0);

      shell.search.setPageWords(
        _site,
        shell.activeTabId,
        shell.currentContent!.id,
        'needle',
      );
      await tester.pumpAndSettle();
      expect(find.text('tag8'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(TagDirectoryRow),
          matching: find.text('needle'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('$name opening search leaves the topic list built', (
      tester,
    ) async {
      final shell = await pump(tester);
      expect(find.byType(TopicListView), findsWidgets);
      final opened = await _rebuiltUnder<TopicListView>(() async {
        shell.search.openPanel();
        await tester.pump();
      });
      expect(shell.search.panelOpen, isTrue);
      // ignore: avoid_print
      print(
        'PERF_PROOF main-content-search ${name}_open_list_elements=$opened',
      );
      expect(opened, 0);
      expect(find.text('Topic 1'), findsWidgets);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
