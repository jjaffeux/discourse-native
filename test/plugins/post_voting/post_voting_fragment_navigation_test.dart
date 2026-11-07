import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/shell_controller.dart'
    show TabOpenResult;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shell_test_harness.dart';
import 'post_voting_integration_test.dart' as fixture;

void main() {
  for (final newTab in [true, false]) {
    testWidgets(
      'topic comment fragment survives ${newTab ? 'background tab' : 'panel'} opening',
      (tester) async {
        final f = await fixture.pumpFixture(tester, desktop);
        f.shell.desktopTopicTabs = true;
        final source = f.shell.activeTab!;
        final existingTabs = {
          for (final tab in f.shell.tabsForCurrentForum) tab.id,
        };
        var navigations = 0;

        expect(
          await openLink(
            tester.element(primaryMainContent),
            '${fixture.site}/t/project/7/3?filter=activity&tags[]=one&tags[]=two#post-voting-comment-51',
            newTab: newTab,
            panel: ForumPanel.secondary,
            onNavigated: () => navigations++,
          ),
          isTrue,
        );

        final opened = newTab
            ? f.shell.tabsForCurrentForum.singleWhere(
                (tab) => !existingTabs.contains(tab.id),
              )
            : f.shell.activeTab!;
        expect(opened.panel, ForumPanel.secondary);
        expect(opened.currentContent.postNumber, 3);
        expect(
          Uri(query: opened.currentContent.topicQuery).queryParametersAll,
          {
            'filter': ['activity'],
            'tags[]': ['one', 'two'],
            'post-voting-comment': ['51'],
          },
        );
        if (newTab) {
          expect(f.shell.activeTab, source);
          expect(navigations, 0);
        } else {
          expect(f.shell.activeTab!.id, opened.id);
          expect(navigations, 1);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final prefix in ['', '//meta.discourse.org']) {
    testWidgets(
      'core tab projection resolves ${prefix.isEmpty ? 'relative' : 'protocol-relative'} links',
      (tester) async {
        final f = await fixture.pumpFixture(tester, desktop);
        f.shell.desktopTopicTabs = true;
        final existingTabs = {
          for (final tab in f.shell.tabsForCurrentForum) tab.id,
        };

        expect(
          f.shell.openLinkInNewTab(
            '$prefix/t/project/7/3#post-voting-comment-51',
          ),
          TabOpenResult.opened,
        );

        final opened = f.shell.tabsForCurrentForum.singleWhere(
          (tab) => !existingTabs.contains(tab.id),
        );
        expect(Uri(query: opened.currentContent.topicQuery).queryParameters, {
          'post-voting-comment': '51',
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('comment route projection validates plugin-owned context', (
    tester,
  ) async {
    final f = await fixture.pumpFixture(tester, desktop);
    final route = ContentRoute.topic(
      topicId: 7,
      slug: 'project',
      title: 'Readable title',
      subtitle: 'Topic subtitle',
      postNumber: 3,
    );
    ContentRoute? project(String suffix) => f.services.projectCoreLink(
      siteUrl: fixture.site,
      url: '${fixture.site}/t/project/7/3$suffix',
      route: route,
    );

    final projected = project('?filter=activity#post-voting-comment-51')!;
    expect(projected.topicId, route.topicId);
    expect(projected.postNumber, route.postNumber);
    expect(projected.title, route.title);
    expect(projected.subtitle, route.subtitle);
    expect(projected.icon, route.icon);
    for (final suffix in [
      '#unrelated-anchor',
      '#post-voting-comment-0',
      '?filter=%FF#post-voting-comment-51',
      '?%C3=value#post-voting-comment-51',
    ]) {
      expect(project(suffix), isNull, reason: suffix);
    }
    expect(
      f.services.projectCoreLink(
        siteUrl: fixture.site,
        url: '${fixture.site}/latest#post-voting-comment-51',
        route: ContentRoute.homepage(),
      ),
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('comment fragment keeps core full-workspace feedback', (
    tester,
  ) async {
    final f = await fixture.pumpFixture(tester, desktop);
    f.shell.desktopTopicTabs = true;
    for (
      var i = f.shell.tabsForCurrentForum.length;
      i < ForumWorkspace.maximumTabs;
      i++
    ) {
      f.shell.createTab();
    }
    final before = f.shell.currentWorkspace;
    var navigations = 0;

    expect(
      await openLink(
        tester.element(primaryMainContent),
        '${fixture.site}/t/project/7/3#post-voting-comment-51',
        newTab: true,
        onNavigated: () => navigations++,
      ),
      isFalse,
    );
    await fixture.frames(tester);

    expect(f.shell.currentWorkspace, before);
    expect(navigations, 0);
    expect(find.text('Close a tab before opening another.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
