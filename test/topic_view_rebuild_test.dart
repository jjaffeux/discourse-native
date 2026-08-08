import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('unrelated shell notifications do not rebuild cooked posts', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      topics: {
        7: topicPayload(
          id: 7,
          title: 'A topic',
          posts: const [
            Post(
              id: 1,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>Already rendered</p>',
            ),
          ],
        ),
      },
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    controller.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
    );
    await controller.loadTopic(7, 'a-topic');

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: TopicView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CookedHtml), findsOneWidget);
    expect(find.byType(PostActions), findsOneWidget);

    var cookedRebuilds = 0;
    final rebuilt = <Element>{};
    final actions = tester.element(find.byType(PostActions));
    final actionChildren = <Element>[];
    actions.visitChildren(actionChildren.add);
    expect(actionChildren, hasLength(1));
    final actionsSelector = actionChildren.single;
    final previousRebuildHook = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousRebuildHook?.call(element, builtOnce);
      rebuilt.add(element);
      if (builtOnce && element.widget is CookedHtml) cookedRebuilds += 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildHook);

    // Selecting the already-current site only asks the adaptive shell to show
    // its sidebar. The topic id, post stream and loading state do not change.
    controller.selectInstance(0);
    await tester.pump();

    expect(cookedRebuilds, 0);
    expect(rebuilt, isNot(contains(actions)));
    expect(rebuilt, isNot(contains(actionsSelector)));
  });
}
