import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/topic_recommendations_tab_store.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_category_path.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

import 'support/shell_test_harness.dart';

void main() {
  _registerTopicReadingTests();
}

void _registerTopicReadingTests() {
  group('topic lists', () {
    final latest = [
      const Topic(
        id: 1,
        title: 'Welcome to the forum',
        slug: 'welcome',
        categoryId: 5,
      ),
      const Topic(
        id: 2,
        title: 'Something unread',
        slug: 'unread-one',
        unreadPosts: 3,
      ),
    ];

    testWidgets('the default destination loads latest on open', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Welcome to the forum'), findsOneWidget);
      expect(find.text('Something unread'), findsOneWidget);
      expect(find.text('Replace with deeper view'), findsNothing);
    });

    testWidgets('an authorized public list offers the topic composer', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': latest},
        creatableFeedPaths: const {'/latest.json'},
        categoryList: const [
          TopicCategory(id: 5, name: 'Support', color: '0088CC', permission: 1),
        ],
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(tester, desktop, api: api, authenticator: authenticator);

      expect(find.byKey(TopicCreateButton.buttonKey), findsOneWidget);
      await tester.tap(find.byKey(TopicCreateButton.buttonKey));
      await tester.pumpAndSettle();

      expect(find.text('Create a new topic'), findsOneWidget);
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Create topic'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      final categoryRequestCount = api.categoryRequests.length;
      final capabilityRequestCount = api.topicComposerCapabilityRequests.length;

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.byKey(TopicCreateButton.buttonKey));
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).visibleComposer,
        isNotNull,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(api.categoryRequests, hasLength(categoryRequestCount));
      expect(
        api.topicComposerCapabilityRequests,
        hasLength(capabilityRequestCount),
      );

      final fields = find.descendant(
        of: find.byType(ComposerPanel),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'A native topic');
      await tester.enterText(fields.at(1), 'Created from the docked composer.');
      await tester.pump();
      final composer = ShellScope.read(
        tester.element(find.byType(MainContent)),
      ).visibleComposer!;
      expect(composer.title.text, 'A native topic');
      expect(composer.raw, 'Created from the docked composer.');
      expect(composer.canSubmit, isTrue);
      await tester.tap(find.text('Create topic'));
      await tester.pumpAndSettle();

      expect(api.topicsCreated.single['title'], 'A native topic');
      expect(api.topicsCreated.single['categoryId'], isNull);
      expect(find.byType(ComposerPanel), findsNothing);
      expect(contentText('A native topic'), findsOneWidget);
      expect(
        api.feedPaths.where((path) => path == '/latest.json').length,
        greaterThanOrEqualTo(2),
      );
    });

    testWidgets(
      'a category list keeps its off-page category through draft restore',
      (tester) async {
        const categoryPath = '/c/discourse-native-app/features/5.json';
        const parent = TopicCategory(
          id: 4,
          name: 'Discourse Native App',
          color: '553388',
          slug: 'discourse-native-app',
        );
        const category = TopicCategory(
          id: 5,
          name: 'Features',
          color: '0088CC',
          slug: 'features',
          parentCategoryId: 4,
        );
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': [], categoryPath: []},
          creatableFeedPaths: const {categoryPath},
          categoryList: const [parent],
          draftToRestore: const (
            draft: ComposerDraft(
              reply: 'Saved draft body',
              title: 'Saved draft title',
            ),
            sequence: 1,
          ),
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          api: api,
          authenticator: authenticator,
        );
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent)),
        );
        controller.openCategory(category);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(TopicCreateButton.buttonKey));
        await tester.pumpAndSettle();

        expect(controller.visibleComposer?.title.text, 'Saved draft title');
        expect(controller.visibleComposer?.text.text, 'Saved draft body');
        expect(controller.visibleComposer?.categoryId, category.id);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('composer-category')),
            matching: find.text(
              topicCategoryPathLabel(category, parent: parent),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a restored category route resolves its off-page category for composing',
      (tester) async {
        const categoryPath = '/c/discourse-native-app/features/5.json';
        const parent = TopicCategory(
          id: 4,
          name: 'Discourse Native App',
          color: '553388',
          slug: 'discourse-native-app',
        );
        const category = TopicCategory(
          id: 5,
          name: 'Features',
          color: '0088CC',
          slug: 'features',
          parentCategoryId: 4,
        );
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': [], categoryPath: []},
          creatableFeedPaths: const {categoryPath},
          categoryList: const [parent],
          categoryFindResults: const [category],
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          api: api,
          authenticator: authenticator,
        );
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent)),
        );
        expect(
          controller.openListUrl('/c/discourse-native-app/features/5'),
          isTrue,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(TopicCreateButton.buttonKey));
        await tester.pumpAndSettle();

        expect(api.categoryIdsRequested, [
          [category.id],
        ]);
        expect(controller.visibleComposer?.categoryId, category.id);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('composer-category')),
            matching: find.text(
              topicCategoryPathLabel(category, parent: parent),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a restored category route keeps its selection when lookup is empty',
      (tester) async {
        const categoryPath = '/c/discourse-native-app/features/5.json';
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': [], categoryPath: []},
          creatableFeedPaths: const {categoryPath},
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          api: api,
          authenticator: authenticator,
        );
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent)),
        );
        expect(
          controller.openListUrl(
            '/c/discourse-native-app/features/5',
            title: 'Features',
          ),
          isTrue,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(TopicCreateButton.buttonKey));
        await tester.pumpAndSettle();

        expect(api.categoryIdsRequested, [
          [5],
        ]);
        expect(controller.visibleComposer?.categoryId, 5);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('composer-category')),
            matching: find.text('Features'),
          ),
          findsOneWidget,
        );
      },
    );

    const inbox = '/topics/private-messages/joffreyj.json';

    testWidgets(
      'the sidebar puts New Topic below Messages and opens it globally',
      (tester) async {
        const user = DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          canCreateTopic: true,
        );
        final api = FakeDiscourseApi(
          user: user,
          feeds: {
            '/latest.json': latest,
            inbox: [
              const Topic(id: 9, title: 'A private message', slug: 'a-pm'),
            ],
          },
          creatableFeedPaths: const {'/latest.json'},
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: user),
          ],
          api: api,
          authenticator: authenticator,
        );

        final messages = sidebarDestination('Messages');
        final newTopic = sidebarDestination('New Topic');
        final drafts = sidebarDestination('Drafts');
        expect(newTopic, findsOneWidget);
        expect(
          tester.getTopLeft(messages).dy,
          lessThan(tester.getTopLeft(newTopic).dy),
        );
        expect(
          tester.getTopLeft(newTopic).dy,
          lessThan(tester.getTopLeft(drafts).dy),
        );
        final newTopicTile = find
            .ancestor(of: newTopic, matching: find.byType(InkWell))
            .first;
        expect(
          find.descendant(of: newTopicTile, matching: find.dIcon(DIcons.plus)),
          findsOneWidget,
        );

        await tester.tap(messages);
        await tester.pumpAndSettle();
        expect(find.byKey(TopicCreateButton.buttonKey), findsNothing);

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        for (final position in [
          tester.getCenter(
            find.descendant(
              of: newTopicTile,
              matching: find.dIcon(DIcons.plus),
            ),
          ),
          tester.getCenter(newTopic),
          tester.getRect(newTopicTile).centerRight - const Offset(12, 0),
        ]) {
          await tester.tapAt(position, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();

          expect(find.byType(ComposerPanel), findsOneWidget);
          expect(shell.currentContent?.isMessages, isTrue);
          expect(shell.visibleComposer?.target.isNewTopic, isTrue);
          expect(shell.visibleComposer?.target.originFeedId, 'latest');

          await tester.tap(find.byTooltip('Save and close'));
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('C opens New Topic across forum routes but not Aggregate', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: {
          '/latest.json': latest,
          inbox: const [Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
        creatableFeedPaths: const {'/latest.json'},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );

      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyC), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.currentContent?.isMessages, isTrue);
      expect(shell.visibleComposer?.target.isNewTopic, isTrue);

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      shell.selectAggregate();
      await tester.pumpAndSettle();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyC), isFalse);
      await tester.pump();
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('New Topic reuses categories already loaded by the sidebar', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        canCreateTopic: true,
      );
      final api = _FailingNewTopicMetadataApi(user: user);
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';
      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.topicComposerCategories('https://meta.discourse.org'), [
        _FailingNewTopicMetadataApi.category,
      ]);
      final categoryRequestCount = api.categoryRequests.length;

      await tester.tap(sidebarDestination('New Topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(api.categoryRequests, hasLength(categoryRequestCount));
      expect(find.text('Tags'), findsOneWidget);
    });

    testWidgets('New Topic is visible before metadata requests finish', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        canCreateTopic: true,
      );
      final api = _FailingNewTopicMetadataApi(user: user);
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';
      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );
      final metadata = Completer<void>();
      api.capabilityGate = metadata;
      addTearDown(() {
        if (!metadata.isCompleted) metadata.complete();
      });

      await tester.tap(sidebarDestination('New Topic'));
      await tester.pump();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(metadata.isCompleted, isFalse);

      metadata.complete();
      await tester.pumpAndSettle();
      expect(find.text('Tags'), findsOneWidget);
    });

    for (final failedMetadata in ['settings', 'categories']) {
      testWidgets(
        'New Topic opens after a $failedMetadata failure and retries later',
        (tester) async {
          const user = DiscourseUser(
            id: 7,
            username: 'joffreyj',
            canCreateTopic: true,
          );
          final api = _FailingNewTopicMetadataApi(user: user)
            ..failCapabilities = failedMetadata == 'settings'
            ..failCategoryLoad = failedMetadata == 'categories';
          final authenticator = FakeAuthenticator()
            ..keys['https://meta.discourse.org'] = 'meta-key';
          await pumpShell(
            tester,
            desktop,
            instances: [instance('meta.discourse.org').copyWith(user: user)],
            api: api,
            authenticator: authenticator,
          );
          await tester.tap(sidebarDestination('New Topic'));
          await tester.pumpAndSettle();

          expect(find.byType(ComposerPanel), findsOneWidget);
          expect(find.text('Category'), findsOneWidget);
          expect(
            find.text('Tags'),
            failedMetadata == 'settings' ? findsNothing : findsOneWidget,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          expect(
            shell.topicComposerCategories('https://meta.discourse.org'),
            failedMetadata == 'categories'
                ? isEmpty
                : [_FailingNewTopicMetadataApi.category],
          );

          await tester.tap(find.byTooltip('Save and close'));
          await tester.pumpAndSettle();
          api.failCapabilities = false;
          api.failCategoryLoad = false;
          await tester.tap(sidebarDestination('New Topic'));
          await tester.pumpAndSettle();

          expect(find.byType(ComposerPanel), findsOneWidget);
          expect(find.text('Tags'), findsOneWidget);
          expect(shell.topicComposerCategories('https://meta.discourse.org'), [
            _FailingNewTopicMetadataApi.category,
          ]);
          expect(
            api.topicComposerCapabilityRequests,
            hasLength(failedMetadata == 'settings' ? 2 : 1),
          );
        },
      );
    }

    testWidgets('C leaves focused forum form controls alone', (tester) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: {'/latest.json': latest},
        creatableFeedPaths: const {'/latest.json'},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      shell.openPreferences('https://meta.discourse.org');
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey(('like-notification-frequency', 1))),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(
        find.byKey(const ValueKey('preferences-section-profile')),
      );
      await tester.pumpAndSettle();
      final timezone = find.descendant(
        of: find.byKey(const ValueKey('preferences-timezone')),
        matching: find.byType(EditableText),
      );
      await tester.tap(timezone);
      await tester.pump();
      expect(tester.widget<EditableText>(timezone).focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('the sidebar hides New Topic when the account cannot post', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        canCreateTopic: false,
      );
      final api = FakeDiscourseApi(user: user, feeds: {'/latest.json': latest});
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );

      expect(sidebarDestination('New Topic'), findsNothing);
    });

    testWidgets('compact New Topic reveals the composer pane', (tester) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: {'/latest.json': latest},
        creatableFeedPaths: const {'/latest.json'},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        phone,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);

      await tester.tap(sidebarDestination('New Topic'));
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        ShellScope.read(tester.element(find.byType(MainContent))).mobilePane,
        MobilePane.content,
      );
    });

    testWidgets('picking a destination fetches its own list', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains(inbox));
      expect(find.text('A private message'), findsOneWidget);
    });

    testWidgets('switches between personal and eligible group inboxes', (
      tester,
    ) async {
      const teamInbox = '/topics/private-messages-group/joffreyj/team.json';
      final api = FakeDiscourseApi(
        user: const DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          messageGroupNames: ['team', 'tech-advocates'],
        ),
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
          teamInbox: [
            const Topic(id: 10, title: 'Team escalation', slug: 'team-pm'),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('message-inbox-picker')),
        findsOneWidget,
      );
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('A private message'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
      await tester.pumpAndSettle();
      expect(find.text('team'), findsOneWidget);
      expect(find.text('tech-advocates'), findsOneWidget);
      await tester.tap(find.text('team'));
      await tester.pumpAndSettle();

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      expect(api.feedPaths, contains(teamInbox));
      expect(find.text('Team escalation'), findsOneWidget);
      expect(find.text('A private message'), findsNothing);
      expect(controller.currentContent?.messageGroupName, 'team');
      expect(controller.currentFeedId, 'messages-group-team');
      expect(controller.canCreateTopicHere, isFalse);

      await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();

      expect(find.text('A private message'), findsOneWidget);
      expect(controller.currentContent?.id, 'messages');
      expect(api.feedPaths.where((path) => path == inbox), hasLength(1));
    });

    testWidgets('restores the selected group inbox', (tester) async {
      const groupInbox =
          '/topics/private-messages-group/joffreyj/tech-advocates.json';
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        messageGroupNames: ['tech-advocates'],
      );
      final forumTabs = FakeForumTabStore([
        ForumWorkspace(
          siteUrl: 'https://meta.discourse.org',
          accountIdentity: 'user:joffreyj',
          activeTabId: 'group-inbox-tab',
          tabs: [
            ForumTab(
              id: 'group-inbox-tab',
              rootDestinationId: 'messages',
              contentStack: [
                ContentRoute.messages(groupName: 'tech-advocates'),
              ],
            ),
          ],
        ),
      ]);
      final api = FakeDiscourseApi(
        user: user,
        feeds: {
          groupInbox: [
            const Topic(
              id: 10,
              title: 'Restored group message',
              slug: 'restored-group-pm',
            ),
          ],
        },
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: user),
        ],
        api: api,
        authenticator: authenticator,
        forumTabs: forumTabs,
      );

      expect(api.feedPaths, [groupInbox]);
      expect(find.text('tech-advocates'), findsOneWidget);
      expect(find.text('Restored group message'), findsOneWidget);
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).currentContent?.messageGroupName,
        'tech-advocates',
      );
    });

    testWidgets('messages uses a topic-row skeleton while loading', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
        feedGates: {inbox: gate},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('topic-list-loading-skeleton')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Loading messages'), findsOneWidget);
      expect(activityIndicators, findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('A private message'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
      'messages never offers New Topic even if its feed says it can',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': latest,
            inbox: [
              const Topic(id: 9, title: 'A private message', slug: 'a-pm'),
            ],
          },
          creatableFeedPaths: const {'/latest.json', inbox},
        );

        await pumpShell(tester, desktop, api: api);
        await tester.tap(userMenu);
        await tester.pumpAndSettle();
        await tester.tap(sidebarDestination('Messages'));
        await tester.pumpAndSettle();

        expect(find.byKey(TopicCreateButton.buttonKey), findsNothing);
      },
    );

    testWidgets('a list is not refetched when revisited', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(
        api.feedPaths.where((p) => p == '/latest.json').length,
        2,
        reason: 'sign-in refreshes the personalized list, revisiting reuses it',
      );
    });

    testWidgets('tapping the destination on screen asks for it again', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);
      expect(api.feedPaths, ['/latest.json']);

      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, ['/latest.json', '/latest.json']);
    });

    testWidgets('unread topics carry a count', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('closed topics carry a lock before the title', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [
            Topic(
              id: 9,
              title: 'Closed topic',
              slug: 'closed-topic',
              categoryId: 5,
              closed: true,
            ),
          ],
        },
        categoryList: const [
          TopicCategory(id: 5, name: 'Feature', color: '00C58E'),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      final title = find.text('Closed topic');
      final row = minimumHeightAncestors(title, TopicListRow.minimumHeight);
      final lock = find.descendant(of: row, matching: find.dIcon(DIcons.lock));
      final lockGlyph = find.descendant(
        of: lock,
        matching: find.byType(SvgPicture),
      );
      final categoryBlock = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.minWidth == 9 &&
              widget.constraints?.maxWidth == 9 &&
              widget.constraints?.minHeight == 9 &&
              widget.constraints?.maxHeight == 9,
        ),
      );

      expect(lock, findsOneWidget);
      expect(tester.getTopLeft(lock).dx, lessThan(tester.getTopLeft(title).dx));
      expect(lockGlyph, findsOneWidget);
      expect(categoryBlock, findsOneWidget);
      expect(
        tester.getTopLeft(lockGlyph).dx,
        tester.getTopLeft(categoryBlock).dx,
      );
      expect(find.bySemanticsLabel('Closed topic'), findsOneWidget);
    });

    testWidgets('mirrored unread fields produce one undoubled count', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Tracked topic',
              slug: 'tracked-topic',
              unreadPosts: 3,
              newPosts: 3,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('6'), findsNothing);
    });

    testWidgets('caught-up titles are dimmed independently of badges', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 8,
              title: 'Caught up',
              slug: 'caught-up',
              lastReadPostNumber: 5,
              highestPostNumber: 5,
            ),
            const Topic(
              id: 9,
              title: 'Not caught up',
              slug: 'not-caught-up',
              lastReadPostNumber: 4,
              highestPostNumber: 5,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      final context = tester.element(find.text('Caught up'));
      final theme = Theme.of(context);
      expect(
        tester.widget<Text>(find.text('Caught up')).style?.color,
        theme.discourse.whisper,
      );
      expect(
        tester.widget<Text>(find.text('Not caught up')).style?.color,
        theme.colorScheme.onSurface,
      );
    });

    testWidgets('an unseen flat topic carries the new-topic dot', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Never opened',
              slug: 'never-opened',
              seen: false,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.byKey(const ValueKey('new-topic-dot')), findsOneWidget);
      expect(find.bySemanticsLabel('New topic'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-replies-dot')), findsNothing);
    });

    testWidgets('topic state follows the title instead of the row edge', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Short title',
              slug: 'short-title',
              seen: false,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      final title = find.text('Short title');
      final titleEnd = tester.getTopLeft(title).dx + _textWidth(tester, title);
      final dot = tester.getRect(find.byKey(const ValueKey('new-topic-dot')));
      expect(dot.left - titleEnd, moreOrLessEquals(8, epsilon: 0.5));
    });

    testWidgets('topic state follows the end of a wrapped title', (
      tester,
    ) async {
      const title = 'Footnotes can scroll?';
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: title,
              slug: 'wrapped-new-topic',
              seen: false,
              posterAvatars: ['', '', ''],
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      final titleRect = tester.getRect(find.text(title));
      final dot = _inlineWidgetBoxes(tester, find.text(title)).last;
      expect(titleRect.height, greaterThan(24));
      expect(dot.center.dy, greaterThan(titleRect.center.dy));
      expect(dot.bottom, lessThanOrEqualTo(titleRect.bottom));
    });

    testWidgets('unread count follows the end of a wrapped title', (
      tester,
    ) async {
      const title = 'Footnotes can scroll?';
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: title,
              slug: 'wrapped-unread-topic',
              unreadPosts: 3,
              posterAvatars: ['', '', ''],
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      final titleRect = tester.getRect(find.text(title));
      final count = _inlineWidgetBoxes(tester, find.text(title)).last;
      expect(titleRect.height, greaterThan(24));
      expect(count.center.dy, greaterThan(titleRect.center.dy));
      expect(count.bottom, lessThanOrEqualTo(titleRect.bottom));
    });

    testWidgets('a nested topic only carries its new-replies dot', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Nested topic',
              slug: 'nested-topic',
              isNestedView: true,
              hasNewReplies: true,
              seen: false,
              unreadPosts: 5,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.byKey(const ValueKey('new-replies-dot')), findsOneWidget);
      expect(find.bySemanticsLabel('Topic has new replies'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-topic-dot')), findsNothing);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('category badges render once categories arrive', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': latest},
        categoryList: const [
          TopicCategory(id: 5, name: 'Feature', color: '0088CC'),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      expect(
        find.descendant(
          of: find.byType(TopicListView),
          matching: find.text('Feature'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('topic rows link each category in an embedded breadcrumb', (
      tester,
    ) async {
      const parent = TopicCategory(
        id: 5,
        name: 'Discourse Native Application',
        color: '0088CC',
        slug: 'discourse-native-application',
      );
      const category = TopicCategory(
        id: 6,
        name: 'Feature requests',
        color: '00AEEF',
        slug: 'feature-requests',
        parentCategoryId: 5,
      );
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 3,
              title: 'Off-page child topic',
              slug: 'off-page-child-topic',
              categoryId: 6,
            ),
          ],
          '/c/discourse-native-application/5.json': const [],
          '/c/discourse-native-application/feature-requests/6.json': const [],
        },
        categoryList: const [parent],
        feedCategoriesByPath: const {
          '/latest.json': [parent, category],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(
        find.descendant(
          of: find.byType(TopicListView),
          matching: find.text(parent.name),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TopicListView),
          matching: find.text(category.name),
        ),
        findsOneWidget,
      );
      final parentLink = find.bySemanticsLabel(
        'Parent category: ${parent.name}',
      );
      final categoryLink = find.bySemanticsLabel('Category: ${category.name}');
      expect(parentLink, findsOneWidget);
      expect(categoryLink, findsOneWidget);
      expect(
        tester.getTopRight(parentLink).dx,
        lessThan(tester.getTopLeft(categoryLink).dx),
      );
      expect(api.categoryIdsRequested, isEmpty);

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      await tester.tap(parentLink);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'category-${parent.id}');
      expect(
        controller.currentContent?.feedPath,
        '/c/discourse-native-application/5.json',
      );

      expect(controller.handleBack(canReturnToSidebar: false), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(categoryLink);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'category-${category.id}');
      expect(
        controller.currentContent?.feedPath,
        '/c/discourse-native-application/feature-requests/6.json',
      );
    });

    testWidgets('short topic tags use the intended inline gap', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 3,
              title: 'A tagged topic',
              slug: 'a-tagged-topic',
              categoryId: 5,
              tags: [
                TopicTag(id: 8, name: 'ai', slug: 'ai'),
                TopicTag(id: 9, name: 'in-progress', slug: 'in-progress'),
              ],
            ),
          ],
          '/c/feature/5.json': const [],
          '/tag/ai/8.json': const [],
        },
        categoryList: const [
          TopicCategory(
            id: 5,
            name: 'Feature',
            color: '0088CC',
            slug: 'feature',
          ),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      final firstTag = find.text('ai,');
      final secondTag = find.text('in-progress');
      expect(firstTag, findsOneWidget);
      expect(secondTag, findsOneWidget);
      expect(find.bySemanticsLabel('Tag: ai'), findsOneWidget);
      expect(find.bySemanticsLabel('Tag: in-progress'), findsOneWidget);
      expect(
        tester.getSize(find.bySemanticsLabel('Category: Feature')).height,
        greaterThanOrEqualTo(24),
      );
      expect(
        tester.getSize(find.bySemanticsLabel('Tag: ai')).height,
        greaterThanOrEqualTo(24),
      );
      expect(
        tester.getTopLeft(secondTag).dx - tester.getTopRight(firstTag).dx,
        closeTo(3, 0.01),
      );
      final category = find.descendant(
        of: find.byType(TopicListView),
        matching: find.text('Feature'),
      );
      expect(
        tester.getTopRight(category).dx,
        lessThan(tester.getTopLeft(firstTag).dx),
      );

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      await tester.tap(category);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'category-5');
      expect(controller.currentContent?.feedPath, '/c/feature/5.json');
      expect(api.topicsOpened, isEmpty);

      expect(controller.handleBack(canReturnToSidebar: false), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(firstTag);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'tag-8');
      expect(controller.currentContent?.feedPath, '/tag/ai/8.json');
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('public and private tag feeds keep distinct identities', (
      tester,
    ) async {
      const tag = TopicTag(
        id: 8,
        name: 'priority / private',
        slug: 'priority%20%2F%20private',
      );
      const reader = DiscourseUser(id: 1, username: 'reader');
      final api = FakeDiscourseApi(
        user: reader,
        feeds: {
          '/latest.json': const [
            Topic(
              id: 2,
              title: 'A public tagged topic',
              slug: 'a-public-tagged-topic',
              tags: [tag],
            ),
            Topic(
              id: 3,
              title: 'A private tagged topic',
              slug: 'a-private-tagged-topic',
              privateMessage: true,
              tags: [tag],
            ),
          ],
          '/tag/priority%20%2F%20private/8.json': const [],
          '/topics/private-messages-tags/reader/'
                  'priority%20%2F%20private.json':
              const [],
        },
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
        authenticator: authenticator,
      );

      final tagLinks = find.bySemanticsLabel('Tag: ${tag.name}');
      expect(tagLinks, findsNWidgets(2));
      await tester.tap(tagLinks.first);
      await tester.pumpAndSettle();

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      expect(controller.currentContent?.id, 'tag-8');
      expect(
        controller.currentContent?.feedPath,
        '/tag/priority%20%2F%20private/8.json',
      );

      expect(controller.handleBack(canReturnToSidebar: false), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(tagLinks.last);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'pm-tag-8');
      expect(
        controller.currentContent?.feedPath,
        '/topics/private-messages-tags/reader/'
        'priority%20%2F%20private.json',
      );
      expect(
        api.feedPaths,
        containsAll([
          '/tag/priority%20%2F%20private/8.json',
          '/topics/private-messages-tags/reader/'
              'priority%20%2F%20private.json',
        ]),
      );
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('an idless numeric topic tag resolves before navigation', (
      tester,
    ) async {
      const tag = TopicTag(name: '2024');
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [
            Topic(
              id: 3,
              title: 'A numeric tagged topic',
              slug: 'a-numeric-tagged-topic',
              tags: [tag],
            ),
          ],
          '/tag/2024/77.json': const [],
        },
        hashtagSearches: const {
          '2024': [
            FoundHashtag(
              type: 'tag',
              ref: '2024::tag',
              slug: '2024',
              text: '2024',
              id: 77,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text(tag.name));
      await tester.pumpAndSettle();

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      expect(api.hashtagSearchesRequested, ['2024']);
      expect(controller.currentContent?.id, 'tag-77');
      expect(controller.currentContent?.feedPath, '/tag/2024/77.json');
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('a late numeric tag lookup cannot reopen content after Back', (
      tester,
    ) async {
      const tag = TopicTag(name: '2024');
      final hashtagGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [
            Topic(
              id: 3,
              title: 'A numeric tagged topic',
              slug: 'a-numeric-tagged-topic',
              tags: [tag],
            ),
          ],
          '/tag/2024/77.json': const [],
        },
        hashtagSearchGate: hashtagGate,
        hashtagSearches: const {
          '2024': [
            FoundHashtag(
              type: 'tag',
              ref: '2024::tag',
              slug: '2024',
              text: '2024',
              id: 77,
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      await tester.tap(find.text(tag.name));
      await tester.pump();
      expect(api.hashtagSearchesRequested, ['2024']);

      expect(controller.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);

      hashtagGate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
      expect(api.feedPaths, isNot(contains('/tag/2024/77.json')));
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('long topic tags wrap without overflowing a phone row', (
      tester,
    ) async {
      final longName = 'a-very-long-${List.filled(30, 'tag-name-').join()}';
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            Topic(
              id: 3,
              title: 'A tagged topic',
              slug: 'a-tagged-topic',
              tags: [
                const TopicTag(name: 'design'),
                TopicTag(name: longName),
                const TopicTag(name: 'accessibility'),
                const TopicTag(name: 'mobile'),
                const TopicTag(name: 'support'),
              ],
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(find.text('design,'), findsOneWidget);
      expect(find.textContaining(longName), findsOneWidget);
      expect(find.text('support'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long category name ellipsizes instead of overflowing', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': latest},
        categoryList: [
          TopicCategory(
            id: 5,
            name: 'Feature ${List.filled(30, 'requests-').join()}',
            color: '0088CC',
          ),
        ],
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('many topic tags stay inline and wrap from the row edge', (
      tester,
    ) async {
      const tags = [
        TopicTag(name: 'sea2'),
        TopicTag(name: 'sea1'),
        TopicTag(name: 'dub1'),
        TopicTag(name: 'blz-prod-eu'),
        TopicTag(name: 'blz-prod-us'),
        TopicTag(name: 'dub2'),
        TopicTag(name: 'sjc6'),
        TopicTag(name: 'dev-alert'),
        TopicTag(name: 'cdck-prod-meta'),
        TopicTag(name: 'yyz2'),
        TopicTag(name: 'agc-prod-us'),
        TopicTag(name: 'sea3'),
        TopicTag(name: 'yyz1'),
        TopicTag(name: 'epic-prod-us2'),
      ];
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 3,
              title: 'A heavily tagged topic',
              slug: 'a-heavily-tagged-topic',
              categoryId: 5,
              tags: tags,
            ),
          ],
        },
        categoryList: const [
          TopicCategory(id: 5, name: 'Alerts', color: 'E45735'),
        ],
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      final category = tester.getTopLeft(find.text('Alerts'));
      final tagPositions = [
        for (var index = 0; index < tags.length; index++)
          tester.getTopLeft(
            find.text(
              '${tags[index].name}${index == tags.length - 1 ? '' : ','}',
            ),
          ),
      ];

      expect(tagPositions.first.dy, closeTo(category.dy, 0.01));
      final nextRunTop = tagPositions
          .map((position) => position.dy)
          .firstWhere((top) => top > tagPositions.first.dy);
      final nextRunLeft = tagPositions
          .where((position) => position.dy == nextRunTop)
          .map((position) => position.dx)
          .reduce((left, right) => left < right ? left : right);
      final rowLeft = tester.getTopLeft(find.text('A heavily tagged topic')).dx;
      expect(nextRunTop - tagPositions.first.dy, lessThanOrEqualTo(24));
      expect(nextRunLeft, closeTo(rowLeft, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing list reports it instead of crashing', (
      tester,
    ) async {
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);

      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-out readers do not see account pages in the sidebar', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(sidebarDestination('Messages'), findsNothing);
      expect(sidebarDestination('Drafts'), findsNothing);
      expect(sidebarDestination('New Topic'), findsNothing);
      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('a signed-out Messages route explains the account boundary', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      controller.selectDestination(
        const SidebarDestination(
          id: 'messages',
          label: 'Messages',
          icon: DIcons.inbox,
        ),
      );
      await tester.pumpAndSettle();

      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Sign in to view your messages'), findsOneWidget);
      expect(
        find.text(
          'Private messages are tied to your forum account and aren’t '
          'available while you’re signed out.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('messages-sign-in')), findsOneWidget);
      expect(find.text('Replace with deeper view'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('messages-sign-in')));
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'latest');
      expect(sidebarDestination('Messages'), findsOneWidget);
      expect(find.text('Sign in to view your messages'), findsNothing);
    });
  });

  group('incoming topics', () {
    final onList = [
      const Topic(id: 1, title: 'Welcome to the forum', slug: 'welcome'),
      const Topic(id: 2, title: 'Something else', slug: 'something-else'),
    ];

    /// `/new`, shaped as `TopicTrackingState.publish_new` sends it.
    Map<String, Object?> created(int topicId) => {
      'topic_id': topicId,
      'message_type': 'new_topic',
      'payload': {'highest_post_number': 1, 'created_in_new_period': true},
    };

    /// `/latest`, published when a post bumps a topic that already exists.
    Map<String, Object?> bumped(int topicId) => {
      'topic_id': topicId,
      'message_type': 'latest',
      'payload': {'bumped_at': '2026-08-06T09:00:00.000Z'},
    };

    FakeSiteTracker tracker() => FakeSiteTracker.built.first;

    Future<void> pumpWithFeeds(
      WidgetTester tester,
      FakeDiscourseApi api,
    ) async {
      await pumpShell(tester, desktop, api: api);
      await tester.pumpAndSettle();
    }

    testWidgets('a topic created on the site announces itself', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      expect(find.textContaining('See '), findsNothing);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();

      expect(find.text('See 1 new or updated topic'), findsOneWidget);
    });

    testWidgets('the count is of topics, not of messages', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      tracker()
        ..deliver(created(99))
        ..deliver(created(100))
        ..deliver(bumped(99));
      await tester.pumpAndSettle();

      expect(find.text('See 2 new or updated topics'), findsOneWidget);
    });

    testWidgets('tapping it fetches those topics and puts them on top', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': onList,
          '/latest.json?topic_ids=99': [
            const Topic(id: 99, title: 'Just posted', slug: 'just-posted'),
          ],
        },
      );
      await pumpWithFeeds(tester, api);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/latest.json?topic_ids=99'));
      expect(find.text('Just posted'), findsOneWidget);
      expect(find.text('Welcome to the forum'), findsOneWidget);
      expect(find.textContaining('See '), findsNothing);
    });

    testWidgets('a topic that was only bumped is moved, not duplicated', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': onList,
          '/latest.json?topic_ids=2': [onList[1]],
        },
      );
      await pumpWithFeeds(tester, api);

      tracker().deliver(bumped(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      expect(find.text('Something else'), findsOneWidget);
    });

    testWidgets('a fetch that fails leaves the banner to be tried again', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      expect(find.text('See 1 new or updated topic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refetching the list clears what it is about to contain', (
      tester,
    ) async {
      final controller = ShellController(
        instanceStore: FakeInstanceStore(twoSites),
        api: FakeDiscourseApi(feeds: {'/latest.json': onList}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pump();

      FakeSiteTracker.built.first.deliver(created(99));
      expect(controller.incomingCount('latest'), 1);

      await controller.loadFeed('latest', force: true);

      expect(controller.incomingCount('latest'), 0);
    });

    testWidgets('only the site being read holds a connection open', (
      tester,
    ) async {
      await pumpWithFeeds(tester, FakeDiscourseApi());

      expect(FakeSiteTracker.built, hasLength(1));

      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built, hasLength(2));
      expect(FakeSiteTracker.built.first.polling, isFalse);
      expect(FakeSiteTracker.built.last.polling, isTrue);
    });

    testWidgets('an app coming back to the front reconnects at once', (
      tester,
    ) async {
      await pumpWithFeeds(tester, FakeDiscourseApi());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tracker().pollNowCalls, 0);
      expect(tracker().polling, isFalse);

      // Back in front, it is asked immediately rather than waiting out a
      // backoff that started while the connection was dead.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tracker().pollNowCalls, 1);
      expect(tracker().polling, isTrue);
    });
  });

  group('live counters', () {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');

    final avatarBadge = find.byKey(UserMenuButton.unreadDotKey);

    Future<FakeSiteTracker> pumpConnected(
      WidgetTester tester, {
      NotificationTotals totals = const NotificationTotals(),
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: FakeDiscourseApi(totals: totals),
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.pumpAndSettle();
      return FakeSiteTracker.built.first;
    }

    testWidgets('the account ID is what names the counter channels', (
      tester,
    ) async {
      final tracker = await pumpConnected(tester);

      expect(tracker.userId, 7);
    });

    testWidgets('the account avatar uses a hand cursor without a hover fill', (
      tester,
    ) async {
      await pumpConnected(tester);

      final avatar = find.byKey(UserMenuButton.avatarKey);
      final inkWell = tester.widget<InkWell>(avatar);
      final material = tester.widget<Material>(
        find.ancestor(of: avatar, matching: find.byType(Material)).first,
      );
      final theme = Theme.of(tester.element(avatar));
      final cursor = inkWell.mouseCursor! as WidgetStateMouseCursor;

      expect(cursor.resolve(const {}), SystemMouseCursors.click);
      expect(
        cursor.resolve(const {WidgetState.disabled}),
        SystemMouseCursors.basic,
      );
      expect(inkWell.hoverColor, Colors.transparent);
      expect(inkWell.focusColor, theme.shell.hover);
      expect(
        inkWell.borderRadius,
        BorderRadius.circular(theme.discourseButtons.borderRadius),
      );
      expect(material.type, MaterialType.transparency);
    });

    testWidgets('the account avatar carries a blue count with white text', (
      tester,
    ) async {
      await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      final badge = tester.widget<Container>(avatarBadge);
      final decoration = badge.decoration! as BoxDecoration;
      final theme = Theme.of(tester.element(avatarBadge));
      final size = tester.getSize(avatarBadge);
      final label = tester.widget<Text>(
        find.descendant(of: avatarBadge, matching: find.text('3')),
      );

      expect(decoration.color, theme.colorScheme.primary);
      expect(label.style?.color, Colors.white);
      expect(size.width, greaterThanOrEqualTo(20));
      expect(size.height, greaterThanOrEqualTo(20));
      expect(
        find.descendant(of: avatarBadge, matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('a notification arriving marks the avatar', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(avatarBadge, findsNothing);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 1,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(avatarBadge, findsOneWidget);
    });

    testWidgets('chat-only activity stays off the account avatar', (
      tester,
    ) async {
      await pumpConnected(
        tester,
        totals: chatNotificationTotals(chatNotifications: 1),
      );

      final railBadge = find.byKey(
        const ValueKey('instance-rail-badge-https://meta.discourse.org'),
      );
      expect(railBadge, findsOneWidget);
      expect(avatarBadge, findsNothing);
    });

    testWidgets('reading them somewhere else takes the mark away', (
      tester,
    ) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      expect(avatarBadge, findsOneWidget);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 0,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(avatarBadge, findsNothing);
    });

    testWidgets('the counts move with it, not just the mark', (tester) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );
      final railBadge = find.byKey(
        const ValueKey('instance-rail-badge-https://meta.discourse.org'),
      );

      expect(
        find.descendant(of: railBadge, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: avatarBadge, matching: find.text('3')),
        findsOneWidget,
      );

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 5,
        'new_personal_messages_notifications_count': 2,
      });
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: railBadge, matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: avatarBadge, matching: find.text('5')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('an inactive connected forum keeps its rail count live', (
      tester,
    ) async {
      const firstUrl = 'https://meta.discourse.org';
      const secondUrl = 'https://team.discourse.org';
      final authenticator = FakeAuthenticator()
        ..keys[firstUrl] = 'meta-key'
        ..keys[secondUrl] = 'team-key';
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
          instance('team.discourse.org', title: 'Team').copyWith(user: me),
        ],
        authenticator: authenticator,
      );

      final inactive = FakeSiteTracker.built.singleWhere(
        (tracker) => tracker.siteUrl == secondUrl,
      );
      expect(inactive.polling, isTrue);
      expect(avatarBadge, findsNothing);

      inactive.deliverNotification(const {
        'all_unread_notifications_count': 2,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      final railBadge = find.byKey(
        const ValueKey('instance-rail-badge-$secondUrl'),
      );
      expect(
        find.descendant(of: railBadge, matching: find.text('2')),
        findsOneWidget,
      );
      expect(avatarBadge, findsNothing);
    });

    testWidgets('a filling review queue marks it too', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(avatarBadge, findsNothing);

      // Published on a channel of its own, and only to staff.
      tracker.deliverReviewableCounts(const {
        'reviewable_count': 4,
        'unseen_reviewable_count': 2,
      });
      await tester.pumpAndSettle();

      expect(avatarBadge, findsOneWidget);
    });

    testWidgets('a site with nobody signed in has no counters to track', (
      tester,
    ) async {
      await pumpShell(tester, desktop);
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built.first.userId, isNull);
      expect(avatarBadge, findsNothing);
    });
  });

  group('infinite scroll', () {
    final topicList = find.descendant(
      of: find.byType(TopicListView),
      matching: find.byType(SuperListView),
    );

    List<Topic> page(int from, int count) => [
      for (var i = from; i < from + count; i++)
        Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
    ];

    testWidgets('pulling past the first topic does not refetch the list', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': page(1, 30)});

      await pumpShell(tester, desktop, api: api);
      expect(api.feedPaths, ['/latest.json']);

      await tester.drag(topicList, const Offset(0, 1200));
      await tester.pumpAndSettle();

      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('reaching the end appends the next page', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
          '/latest.json?page=1': page(31, 30),
        },
        nextPages: {'/latest.json': '/latest?page=1'},
      );

      await pumpShell(tester, desktop, api: api);
      expect(find.text('Topic 1'), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);

      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/latest.json?page=1'));
      expect(find.text('Topic 31'), findsOneWidget);
    });

    testWidgets('the next page can be asked for from inside a layout', (
      tester,
    ) async {
      // The caller this stands in for is the load-more handler. A viewport
      // that has to correct its scroll position starts a scroll from inside
      // its own layout, and the notification that comes out of it reaches the
      // handler there — so the controller is asked for a page mid-frame, where
      // marking the tree dirty is an error rather than a rebuild.
      //
      // Re-creating that correction takes a precise pile of geometry;
      // LayoutBuilder puts the call in the same phase directly, which is the
      // part that has to hold.
      final controller = ShellController(
        instanceStore: FakeInstanceStore(twoSites),
        api: FakeDiscourseApi(
          feeds: {
            '/latest.json': page(1, 3),
            '/latest.json?page=1': page(4, 3),
          },
          nextPages: {'/latest.json': '/latest?page=1'},
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            home: LayoutBuilder(
              builder: (context, _) {
                unawaited(ShellScope.of(context).loadMoreFeed('latest'));
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(controller.currentFeed?.topicIds, hasLength(6));
    });

    testWidgets('a topic repeated across pages is not duplicated', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
          '/latest.json?page=1': [...page(30, 1), ...page(31, 5)],
        },
        nextPages: {'/latest.json': '/latest?page=1'},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      expect(find.text('Topic 30'), findsOneWidget);
    });

    testWidgets('a last page stops further requests', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': page(1, 30)});

      await pumpShell(tester, desktop, api: api);
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      expect(api.feedPaths, ['/latest.json']);
    });
  });

  testWidgets('a response landing after the shell is gone is ignored', (
    tester,
  ) async {
    tester.view.physicalSize = desktop;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []}, gate: gate);

    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore(twoSites),
        api: api,
        authenticator: FakeAuthenticator(),
        forumTabs: FakeForumTabStore(),
        initialRootMode: ShellRootMode.forum,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  group('opening a topic', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    Post post(int id, int number, String body) => Post(
      id: id,
      postNumber: number,
      username: 'joffreyj',
      cooked: '<p>$body</p>',
    );

    TopicPayload detail({
      List<int> stream = const [1],
      Map<int, List<int>> gapsBefore = const {},
      Map<int, List<int>> gapsAfter = const {},
      TopicRecommendations? recommendations,
      TopicNotificationLevel notificationLevel = TopicNotificationLevel.normal,
      bool pinned = false,
      bool unpinned = false,
      bool pinnedGlobally = false,
      bool closed = false,
      bool archived = false,
      bool visible = true,
      bool canCloseTopic = false,
      bool canArchiveTopic = false,
      bool canToggleTopicVisibility = false,
      bool canDeleteTopic = false,
      bool canRecoverTopic = false,
      bool canFlagTopic = false,
      bool canCreatePost = false,
      List<PostActionSummary> topicActions = const [],
      List<Bookmark> bookmarks = const [],
    }) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [post(1, 1, 'First post body')],
      stream: stream,
      gapsBefore: gapsBefore,
      gapsAfter: gapsAfter,
      recommendations: recommendations,
      notificationLevel: notificationLevel,
      pinned: pinned,
      unpinned: unpinned,
      pinnedGlobally: pinnedGlobally,
      closed: closed,
      archived: archived,
      visible: visible,
      canCloseTopic: canCloseTopic,
      canArchiveTopic: canArchiveTopic,
      canToggleTopicVisibility: canToggleTopicVisibility,
      canDeleteTopic: canDeleteTopic,
      canRecoverTopic: canRecoverTopic,
      canFlagTopic: canFlagTopic,
      canCreatePost: canCreatePost,
      topicActions: topicActions,
      bookmarks: bookmarks,
    );

    TopicRecommendations suggestedRecommendations(Topic topic) =>
        TopicRecommendations(
          sources: [
            TopicRecommendationSource(
              definition: coreSuggestedTopicRecommendationSource,
              topics: [topic],
            ),
          ],
        );

    testWidgets('tapping a row replaces the list with the topic', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(find.byType(TopicView), findsOneWidget);
      expect(find.byType(TopicListView), findsNothing);
      expect(find.byType(InlineTopicTitleEditor), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-header-title-field')),
        findsNothing,
      );
      expect(renderedText('First post body'), findsOneWidget);
      expect(renderedText('<p>'), findsNothing);
    });

    testWidgets(
      'editable topic header saves title and preserves topic metadata',
      (tester) async {
        const tags = [
          TopicTag(id: 8, name: 'design'),
          TopicTag(id: 9, name: 'mobile'),
        ];
        final base = topicPayload(
          id: 7,
          title: 'A real topic',
          posts: [post(1, 1, 'First post body')],
          categoryId: 5,
          tags: tags,
        );
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: (detail: base.detail.copyWith(canEdit: true), posts: base.posts),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        final editor = find.byType(InlineTopicTitleEditor);
        final field = find.byKey(const ValueKey('topic-header-title-field'));
        expect(editor, findsOneWidget);
        expect(field, findsOneWidget);
        expect(
          tester
              .widget<MouseRegion>(
                find.byKey(const ValueKey('topic-header-title-pointer')),
              )
              .cursor,
          SystemMouseCursors.text,
        );

        final editorRect = tester.getRect(editor);
        await tester.tapAt(Offset(editorRect.left + 1, editorRect.center.dy));
        await tester.pump();
        var textField = tester.widget<TextField>(field);
        expect(textField.focusNode?.hasFocus, isTrue);
        expect(textField.controller?.selection.baseOffset, 0);

        await tester.enterText(field, '  Renamed topic  ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(api.topicsUpdated, [
          {
            'topicId': 7,
            'title': 'Renamed topic',
            'originalTitle': 'A real topic',
            'categoryId': 5,
            'tags': tags,
            'originalTags': tags,
          },
        ]);
        final shell = ShellScope.read(tester.element(find.byType(TopicView)));
        expect(shell.currentTopic?.title, 'Renamed topic');
        expect(shell.currentContent?.title, 'Renamed topic');
        expect(find.byType(ComposerPanel), findsNothing);
        textField = tester.widget<TextField>(field);
        expect(textField.focusNode?.hasFocus, isFalse);

        await tester.tap(field);
        await tester.enterText(field, ' Renamed topic ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(api.topicsUpdated, hasLength(1));
        expect(
          tester.widget<TextField>(field).controller?.text,
          'Renamed topic',
        );

        await tester.tap(field);
        await tester.enterText(field, '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        textField = tester.widget<TextField>(field);
        expect(api.topicsUpdated, hasLength(1));
        expect(textField.controller?.text, '');
        expect(textField.focusNode?.hasFocus, isTrue);
        expect(find.text('A topic title is required.'), findsOneWidget);
      },
    );

    testWidgets(
      'separates the header and bottom bar from the structural sidebar',
      (tester) async {
        const longTitle =
            'Chris weekly update for 2026 with roadmap decisions, operational '
            'priorities, cross-team blockers, and every next step we agreed on';
        final plugins = PluginData.none.withValue(
          assignmentsDataKey,
          Assignments(
            canAssign: true,
            direct: const Assignment(
              assignee: AssignmentUser(username: 'sam', name: 'Sam Example'),
            ),
          ),
        );
        final tags = [
          for (final name in const [
            'weekly-update',
            '2026',
            'team',
            'async',
            'roadmap',
            'priorities',
          ])
            TopicTag(name: name),
        ];
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': [
              const Topic(id: 7, title: longTitle, slug: 'weekly-update'),
            ],
          },
          categoryList: const [
            TopicCategory(id: 5, name: 'Announcements', color: '7C3AED'),
          ],
          topics: {
            7: topicPayload(
              id: 7,
              title: longTitle,
              posts: [
                post(1, 1, 'First post body'),
                post(2, 2, 'Second post body'),
              ],
              categoryId: 5,
              tags: tags,
              canCreatePost: true,
              notificationLevel: TopicNotificationLevel.tracking,
              plugins: plugins,
            ),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(find.text(longTitle));
        await tester.pumpAndSettle();

        final header = find.byKey(const ValueKey('topic-content-header'));
        final title = find.byKey(const ValueKey('topic-header-title'));
        final sidebarToggle = find.byKey(
          const ValueKey('topic-sidebar-toggle'),
        );
        final notificationLevel = find.byKey(
          const ValueKey('topic-notification-level-button'),
        );
        final bookmark = find.byKey(const ValueKey('topic-bookmark-button'));
        final share = find.byKey(const ValueKey('topic-share-button'));
        final more = find.byKey(const ValueKey('topic-status-button'));
        final backIcon = find.descendant(
          of: header,
          matching: find.dIcon(DIcons.arrowLeft),
        );
        final moreIcon = find.descendant(
          of: more,
          matching: find.dIcon(DIcons.ellipsis),
        );
        expect(header, findsOneWidget);
        expect(title, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.byTooltip('Back')),
          findsOneWidget,
        );
        expect(tester.getSize(backIcon), const Size.square(16));
        final titleWidget = tester.widget<TopicTitle>(title);
        expect(titleWidget.maxLines, 1);
        expect(titleWidget.overflow, TextOverflow.ellipsis);
        final titleTooltip = tester.widget<Tooltip>(
          find.ancestor(of: title, matching: find.byType(Tooltip)),
        );
        expect(titleTooltip.message, longTitle);
        expect(tester.getSize(title).height, lessThan(30));
        expect(
          find.byKey(const ValueKey('topic-header-metadata')),
          findsNothing,
        );
        expect(
          find.descendant(of: header, matching: sidebarToggle),
          findsOneWidget,
        );
        expect(
          find.descendant(of: header, matching: notificationLevel),
          findsOneWidget,
        );
        expect(find.descendant(of: header, matching: bookmark), findsOneWidget);
        expect(find.descendant(of: header, matching: share), findsOneWidget);
        expect(
          find.descendant(of: share, matching: find.dIcon(DIcons.link)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: share, matching: find.text('Share')),
          findsNothing,
        );
        expect(find.descendant(of: header, matching: more), findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.text('Tracking')),
          findsNothing,
        );

        final sidebar = find.byKey(const ValueKey('topic-sidebar-panel'));
        final sidebarSurface = find.byKey(
          const ValueKey('topic-sidebar-surface'),
        );
        final properties = find.byKey(const ValueKey('topic-properties-card'));
        expect(sidebar, findsOneWidget);
        expect(
          find.descendant(of: sidebar, matching: sidebarToggle),
          findsNothing,
        );
        final topicRect = tester.getRect(find.byType(TopicView));
        final sidebarRect = tester.getRect(sidebar);
        final headerRect = tester.getRect(header);
        final surfaceRect = tester.getRect(sidebarSurface);
        final titleRect = tester.getRect(title);
        final toggleRect = tester.getRect(sidebarToggle);
        final notificationRect = tester.getRect(notificationLevel);
        final bookmarkRect = tester.getRect(bookmark);
        final shareRect = tester.getRect(share);
        final bottomBar = find.byKey(const ValueKey('topic-bottom-bar'));
        final replyButton = find.byKey(const ValueKey('topic-reply-button'));
        final progressButton = find.byKey(
          const ValueKey('topic-progress-button'),
        );
        final replyRect = tester.getRect(replyButton);
        final bottomBarRect = tester.getRect(bottomBar);
        final moreRect = tester.getRect(more);
        expect(sidebarRect.top, topicRect.top);
        expect(sidebarRect.bottom, topicRect.bottom);
        expect(headerRect.left, topicRect.left);
        expect(headerRect.right, sidebarRect.left);
        expect(surfaceRect, sidebarRect);
        final sidebarDecoration =
            tester.widget<DecoratedBox>(sidebarSurface).decoration
                as BoxDecoration;
        final sidebarTheme = Theme.of(tester.element(sidebarSurface));
        expect(sidebarDecoration.color, sidebarTheme.shell.panel);
        expect(
          sidebarDecoration.border,
          Border(left: BorderSide(color: sidebarTheme.shell.divider)),
        );
        final sidebarScroll = find.byKey(
          const ValueKey('topic-sidebar-scroll-view'),
        );
        expect(
          find.descendant(of: sidebar, matching: sidebarScroll),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebarScroll, matching: properties),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebarScroll, matching: replyButton),
          findsNothing,
        );
        expect(
          find.descendant(of: bottomBar, matching: replyButton),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byType(SuperListView)).right,
          sidebarRect.left,
        );
        expect(
          tester.widget<SuperListView>(find.byType(SuperListView)).padding,
          EdgeInsets.zero,
        );
        expect(titleRect.right, lessThanOrEqualTo(moreRect.left));
        expect(shareRect.right, lessThanOrEqualTo(bookmarkRect.left));
        expect(bookmarkRect.right, lessThanOrEqualTo(notificationRect.left));
        expect(notificationRect.right, lessThanOrEqualTo(toggleRect.left));
        expect(headerRect.right - toggleRect.right, lessThanOrEqualTo(8.1));
        expect(bottomBarRect.right, sidebarRect.left);
        expect(bottomBarRect.height, 48);
        expect(replyRect.height, 32);
        expect(tester.getSize(progressButton), const Size(72, 32));
        expect(
          tester.getRect(find.byType(SuperListView)).bottom,
          bottomBarRect.top,
        );
        expect(replyRect.left, greaterThan(bottomBarRect.left));
        expect(
          replyRect.right,
          lessThan(tester.getRect(progressButton).left),
        );
        expect(moreIcon, findsOneWidget);
        expect(tester.getSize(moreIcon), const Size.square(16));
        expect(properties, findsOneWidget);
        expect(
          find.descendant(of: properties, matching: find.text('Announcements')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-sidebar-category-edit-indicator')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('topic-sidebar-tags-edit-indicator')),
          findsNothing,
        );
        expect(
          tester.getSize(
            find.byKey(const ValueKey('topic-sidebar-category-color')),
          ),
          const Size.square(9),
        );
        for (final tag in tags) {
          final tagPill = find.byKey(ValueKey(('topic-sidebar-tag', tag.name)));
          expect(
            find.descendant(of: properties, matching: tagPill),
            findsOneWidget,
          );
          final tagText = tester.widget<Text>(
            find.descendant(of: tagPill, matching: find.text(tag.name)),
          );
          expect(
            tagText.style?.fontSize,
            Theme.of(tester.element(tagPill)).textTheme.labelSmall?.fontSize,
          );
          expect(
            find.descendant(
              of: tagPill,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle,
              ),
            ),
            findsNothing,
          );
        }
        final topicAssignment = find.byKey(const Key('assign-topic-property'));
        expect(
          find.descendant(of: properties, matching: topicAssignment),
          findsNothing,
        );
        expect(
          find.descendant(of: sidebarScroll, matching: topicAssignment),
          findsOneWidget,
        );
        expect(find.text('Assignments'), findsOneWidget);
        expect(find.text('Topic · Sam Example'), findsOneWidget);
        expect(
          tester.getRect(topicAssignment).top,
          greaterThan(tester.getRect(properties).bottom),
        );

        expect(
          find.descendant(
            of: header,
            matching: find.byKey(const ValueKey('topic-reply-button')),
          ),
          findsNothing,
        );
        expect(find.descendant(of: sidebar, matching: more), findsNothing);
        expect(find.descendant(of: header, matching: more), findsOneWidget);
        expect(
          find.descendant(
            of: sidebar,
            matching: find.byKey(const ValueKey('topic-reply-button')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: sidebar, matching: notificationLevel),
          findsNothing,
        );
        expect(find.descendant(of: sidebar, matching: bookmark), findsNothing);
        expect(find.text('Topic context'), findsNothing);
        expect(find.text('Actions'), findsNothing);
        expect(find.text('Properties'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('keeps the pinned sidebar outside the topic scroll view', (
      tester,
    ) async {
      final longBody = List.generate(
        80,
        (index) => 'Scrollable post line $index',
      ).join('<br>');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [post(1, 1, longBody)],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final topicView = find.byType(TopicView);
      final sidebar = find.byKey(const ValueKey('topic-sidebar-panel'));
      final verticalScrollables = find.descendant(
        of: topicView,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(verticalScrollables, findsNWidgets(2));
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byKey(const ValueKey('topic-sidebar-scroll-view')),
        ),
        findsOneWidget,
      );
      final sidebarRect = tester.getRect(sidebar);
      final postStream = tester.widget<SuperListView>(
        find.byType(SuperListView),
      );

      await tester.drag(find.byType(SuperListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(postStream.controller!.position.pixels, greaterThan(0));
      expect(tester.getRect(sidebar), sidebarRect);
    });

    testWidgets(
      'scrolls the maximum assignment card without moving the bottom actions',
      (tester) async {
        final plugins = PluginData.none.withValue(
          assignmentsDataKey,
          Assignments(
            canAssign: false,
            postAssignments: {
              for (var id = 2; id <= Assignments.maximumPerTopic + 1; id++)
                id: Assignment(
                  assignee: AssignmentUser(
                    username: 'assignee-$id',
                    name: 'Assignee $id',
                  ),
                  postId: id,
                  postNumber: id,
                ),
            },
          ),
        );
        const recommendations = TopicRecommendations(
          sources: [
            TopicRecommendationSource(
              definition: coreSuggestedTopicRecommendationSource,
              topics: [
                Topic(id: 8, title: 'Reachable related topic', slug: 'related'),
              ],
            ),
          ],
        );
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A real topic',
              posts: [post(1, 1, 'First post body')],
              canCreatePost: true,
              recommendations: recommendations,
              plugins: plugins,
            ),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(find.text('A real topic'));
        await tester.pumpAndSettle();

        final sidebarScroll = find.byKey(
          const ValueKey('topic-sidebar-scroll-view'),
        );
        final reply = find.byKey(const ValueKey('topic-reply-button'));
        final moreTopics = find.text('More topics');
        final sidebarScrollable = find.descendant(
          of: sidebarScroll,
          matching: find.byType(Scrollable),
        );
        final sidebarPosition = tester
            .state<ScrollableState>(sidebarScrollable)
            .position;
        final postPosition = tester
            .widget<SuperListView>(find.byType(SuperListView))
            .controller!
            .position;
        final replyRect = tester.getRect(reply);
        final postPixels = postPosition.pixels;

        expect(sidebarPosition.maxScrollExtent, greaterThan(0));
        expect(
          find.descendant(of: sidebarScroll, matching: reply),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('topic-bottom-bar')),
            matching: reply,
          ),
          findsOneWidget,
        );
        expect(reply.hitTestable(), findsOneWidget);
        expect(moreTopics.hitTestable(), findsNothing);

        await tester.drag(sidebarScroll, const Offset(0, -5000));
        await tester.pumpAndSettle();

        expect(sidebarPosition.pixels, greaterThan(0));
        expect(moreTopics.hitTestable(), findsOneWidget);
        expect(reply.hitTestable(), findsOneWidget);
        expect(tester.getRect(reply), replyRect);
        expect(postPosition.pixels, postPixels);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('uses a thin scrollbar for topic posts', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail()},
        );

        await pumpShell(tester, desktop, api: api);
        await tester.tap(find.text('A real topic'));
        await tester.pumpAndSettle();

        final scrollbar = find.descendant(
          of: find.byType(SuperListView),
          matching: find.byType(Scrollbar),
        );
        expect(scrollbar, findsOneWidget);
        expect(
          ScrollbarTheme.of(
            tester.element(scrollbar),
          ).thickness?.resolve(const <WidgetState>{}),
          4,
        );
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('promotes sharing and overflows administrative actions', (
      tester,
    ) async {
      const reader = DiscourseUser(id: 1, username: 'reader');
      const spam = PostFlagType(
        id: 8,
        nameKey: 'spam',
        name: 'Spam',
        description: 'Promotional content',
        appliesTo: ['Topic'],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            pinned: true,
            canCloseTopic: true,
            canFlagTopic: true,
            canCreatePost: true,
            topicActions: const [PostActionSummary(id: 8, canAct: true)],
          ),
        },
        categoryPostActionCatalog: const SitePostActionCatalog(
          topicFlags: [spam],
        ),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      for (final tooltip in [
        'Share topic',
        'Bookmark this topic',
        'More topic actions',
        'Topic notifications',
        'Reply to this topic',
      ]) {
        final trigger = find.byTooltip(tooltip);
        expect(trigger, findsOneWidget, reason: tooltip);
        final button = find.ancestor(
          of: trigger,
          matching: find.byType(DButton),
        );
        expect(button, findsOneWidget, reason: tooltip);
      }

      expect(find.byTooltip('Flag this topic'), findsNothing);
      expect(find.byTooltip('Pinned topic options'), findsNothing);

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();

      expect(find.text('Share topic'), findsNothing);
      expect(find.text('Flag topic'), findsOneWidget);
      expect(find.text('Unpin topic'), findsOneWidget);
      expect(find.text('Close topic'), findsOneWidget);
    });

    testWidgets(
      'sidebar taxonomy values show subcategory parents and navigate',
      (tester) async {
        const parent = TopicCategory(
          id: 4,
          name: 'Trust and safety',
          color: '7C3AED',
          slug: 'trust-and-safety',
        );
        const category = TopicCategory(
          id: 5,
          name: 'Security',
          color: 'EC4899',
          slug: 'security',
          parentCategoryId: 4,
        );
        final categoryPath = topicCategoryPathLabel(category, parent: parent);
        const tag = TopicTag(name: 'security / fix');
        const reader = DiscourseUser(id: 1, username: 'reader');
        final base = topicPayload(
          id: 7,
          title: 'A real topic',
          posts: [post(1, 1, 'First post body')],
          categoryId: category.id,
          tags: const [tag],
        );
        final api = FakeDiscourseApi(
          user: reader,
          feeds: {
            '/latest.json': listed,
            '/c/trust-and-safety/security/5.json': const [],
            '/topics/private-messages-tags/reader/'
                    'security%20%2F%20fix.json':
                const [],
          },
          categoryList: const [parent, category],
          topics: {
            7: (
              detail: base.detail.copyWith(
                canEdit: true,
                canEditTags: true,
                privateMessage: true,
              ),
              posts: base.posts,
            ),
          },
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('topic-sidebar-category-edit-indicator')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-sidebar-tags-edit-indicator')),
          findsOneWidget,
        );
        expect(find.byTooltip('Edit topic category'), findsOneWidget);
        expect(find.byTooltip('Edit topic tags'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('topic-sidebar-category')),
            matching: find.text(categoryPath),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Category: $categoryPath'),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('topic-sidebar-category-action')),
              )
              .height,
          greaterThanOrEqualTo(32),
        );
        expect(
          tester.getSize(find.bySemanticsLabel('Tag: ${tag.name}')).height,
          greaterThanOrEqualTo(24),
        );
        expect(
          tester.getSize(
            find.byKey(const ValueKey('topic-sidebar-category-edit-action')),
          ),
          const Size.square(32),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('topic-sidebar-add-tag'))),
          const Size.square(32),
        );

        final controller = ShellScope.read(
          tester.element(find.byType(TopicView)),
        );
        await tester.tap(find.byKey(const ValueKey('topic-sidebar-category')));
        await tester.pumpAndSettle();

        expect(controller.currentContent?.id, 'category-5');
        expect(
          controller.currentContent?.feedPath,
          '/c/trust-and-safety/security/5.json',
        );
        expect(
          find.byKey(const ValueKey('topic-category-picker-popover')),
          findsNothing,
        );

        expect(controller.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(('topic-sidebar-tag', tag.name))));
        await tester.pumpAndSettle();

        expect(
          controller.currentContent?.id,
          'list-/topics/private-messages-tags/reader/'
          'security%20%2F%20fix.json',
        );
        expect(
          controller.currentContent?.feedPath,
          '/topics/private-messages-tags/reader/'
          'security%20%2F%20fix.json',
        );
        expect(
          find.byKey(const ValueKey('topic-tag-picker-popover')),
          findsNothing,
        );
        expect(api.topicsUpdated, isEmpty);
        expect(api.topicTagsUpdated, isEmpty);
      },
    );

    testWidgets(
      'uncategorized sidebar picker server-searches and saves a subcategory',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          const support = TopicCategory(
            id: 5,
            name: 'Support',
            color: '0088CC',
            permission: 1,
          );
          const supportDocs = TopicCategory(
            id: 6,
            name: 'Support docs',
            color: '00AEEF',
            parentCategoryId: 5,
          );
          final supportDocsPath = topicCategoryPathLabel(
            supportDocs,
            parent: support,
          );
          final base = detail();
          final api = FakeDiscourseApi(
            feeds: {'/latest.json': listed},
            categoryList: const [support],
            categorySearches: const {
              '': [support],
              'support': [support],
              'docs': [supportDocs],
            },
            topics: {
              7: (
                detail: base.detail.copyWith(canEdit: true),
                posts: base.posts,
              ),
            },
          );
          const reader = DiscourseUser(id: 1, username: 'reader');
          final authenticator = FakeAuthenticator()
            ..keys['https://meta.discourse.org'] = 'meta-key';

          await pumpShell(
            tester,
            desktop,
            instances: [instance('meta.discourse.org').copyWith(user: reader)],
            api: api,
            authenticator: authenticator,
          );
          await tester.tap(contentText('A real topic'));
          await tester.pumpAndSettle();

          final categoryProperty = find.byKey(
            const ValueKey('topic-sidebar-category-property'),
          );
          expect(categoryProperty, findsOneWidget);
          expect(find.byTooltip('Edit topic category'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-sidebar-category-edit-indicator')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: categoryProperty,
              matching: find.text('Uncategorized'),
            ),
            findsOneWidget,
          );

          final categoryAction = find.byKey(
            const ValueKey('topic-sidebar-category-edit-action'),
          );
          expect(categoryAction, findsOneWidget);
          final categoryInk = find.descendant(
            of: categoryAction,
            matching: find.byType(InkWell),
          );
          expect(categoryInk, findsOneWidget);
          expect(
            tester.widget<InkWell>(categoryInk).mouseCursor,
            SystemMouseCursors.click,
          );
          expect(
            tester.widget<InkWell>(categoryInk).hoverColor,
            Colors.transparent,
          );
          expect(
            tester.getSize(categoryAction).width,
            lessThan(tester.getSize(categoryProperty).width),
          );

          await tester.tap(categoryAction);
          await tester.pumpAndSettle();

          expect(find.byType(ComposerPanel), findsNothing);
          expect(find.byType(Dialog), findsNothing);
          expect(find.byType(BottomSheet), findsNothing);
          final picker = find.byKey(
            const ValueKey('topic-category-picker-popover'),
          );
          expect(picker, findsOneWidget);
          expect(
            find.descendant(
              of: picker,
              matching: find.byKey(
                const ValueKey('topic-category-picker-query'),
              ),
            ),
            findsOneWidget,
          );
          expect(tester.getSize(picker).width, 252);
          final categoryQuery = find.byKey(
            const ValueKey('topic-category-picker-query'),
          );
          expect(
            tester.widget<TextField>(categoryQuery).style?.fontSize,
            DiscourseTypography.fontDown1,
          );
          expect(
            tester.getSize(categoryQuery).height,
            inInclusiveRange(34, 42),
          );
          final categoryDivider = find.byKey(
            const ValueKey('topic-category-picker-divider'),
          );
          expect(
            tester.getSize(categoryDivider).width,
            tester.getSize(picker).width - 2,
          );
          final supportOption = find.byKey(
            const ValueKey('topic-category-option-5'),
          );
          expect(supportOption, findsOneWidget);
          final supportTile = tester.widget<ListTile>(
            find.descendant(of: supportOption, matching: find.byType(ListTile)),
          );
          expect(supportTile.minTileHeight, 32);
          expect(
            supportTile.titleTextStyle?.fontSize,
            DiscourseTypography.fontDown1,
          );
          await tester.enterText(categoryQuery, 'support');
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          expect(supportOption, findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-category-option-6')),
            findsNothing,
          );
          await tester.enterText(categoryQuery, 'docs');
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          final supportDocsOption = find.byKey(
            const ValueKey('topic-category-option-6'),
          );
          final supportDocsTile = tester.widget<ListTile>(
            find.descendant(
              of: supportDocsOption,
              matching: find.byType(ListTile),
            ),
          );
          expect(
            supportDocsTile.contentPadding,
            const EdgeInsets.only(left: 26, right: 10),
          );
          expect(
            find.descendant(
              of: supportDocsOption,
              matching: find.text(supportDocsPath),
            ),
            findsOneWidget,
          );
          expect(api.categoryPagesRequested, isNot(contains(2)));
          expect(api.categorySearchTerms, ['', 'support', 'docs']);
          await tester.tap(
            find.byKey(const ValueKey('topic-category-option-6')),
          );
          await tester.pumpAndSettle();

          expect(api.topicsUpdated.single, {
            'topicId': 7,
            'title': 'A real topic',
            'originalTitle': 'A real topic',
            'categoryId': 6,
            'tags': const <TopicTag>[],
            'originalTags': const <TopicTag>[],
          });
          expect(api.topicTagsUpdated, isEmpty);
          expect(
            find.descendant(
              of: categoryProperty,
              matching: find.text(supportDocsPath),
            ),
            findsOneWidget,
          );
          expect(picker, findsNothing);
          expect(find.byType(ComposerPanel), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );

    testWidgets('empty editable sidebar tags open a popover and save a tag', (
      tester,
    ) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const design = TopicTag(id: 8, name: 'design');
        const mobile = TopicTag(id: 9, name: 'mobile');
        final base = detail();
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: (
              detail: base.detail.copyWith(canEditTags: true),
              posts: base.posts,
            ),
          },
          composerCapabilities: const TopicComposerCapabilities(
            canTagTopics: true,
            maxTagsPerTopic: 5,
          ),
          topicTagSearches: const {
            '': TopicTagSearch(tags: [design, mobile]),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        final tagsProperty = find.byKey(
          const ValueKey('topic-sidebar-tags-property'),
        );
        final addTag = find.byKey(const ValueKey('topic-sidebar-add-tag'));
        expect(tagsProperty, findsOneWidget);
        expect(find.byTooltip('Add tag'), findsOneWidget);
        expect(find.text('Add tag'), findsOneWidget);
        expect(addTag, findsOneWidget);
        expect(tester.getSize(addTag).height, lessThan(24));
        expect(
          tester.getSize(addTag).width,
          lessThan(tester.getSize(tagsProperty).width * 0.75),
        );
        expect(
          tester.getCenter(find.text('Tags')).dy,
          closeTo(tester.getCenter(addTag).dy, 1),
        );

        final tagsRect = tester.getRect(tagsProperty);
        await tester.tapAt(Offset(tagsRect.left + 12, tagsRect.center.dy));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-tag-picker-popover')),
          findsNothing,
        );

        await tester.tap(addTag);
        await tester.pumpAndSettle();

        final picker = find.byKey(const ValueKey('topic-tag-picker-popover'));
        expect(picker, findsOneWidget);
        expect(tester.getSize(picker).width, 252);

        final query = find.byKey(const ValueKey('topic-tag-picker-query'));
        final queryWidget = tester.widget<TextField>(query);
        expect(queryWidget.style?.fontSize, DiscourseTypography.fontDown1);
        expect(tester.getSize(query).height, inInclusiveRange(34, 42));

        final divider = find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('topic-tag-picker-divider')),
        );
        expect(divider, findsOneWidget);
        expect(tester.getSize(divider).width, tester.getSize(picker).width - 2);

        expect(
          find.descendant(of: picker, matching: find.dIcon(DIcons.tag)),
          findsNothing,
        );
        expect(find.byType(ComposerPanel), findsNothing);
        expect(
          find.descendant(
            of: picker,
            matching: find.byKey(
              const ValueKey(('topic-tag-picker-option', 'mobile')),
            ),
          ),
          findsOneWidget,
        );
        final mobileOption = tester.widget<ListTile>(
          find.descendant(
            of: find.byKey(
              const ValueKey(('topic-tag-picker-option', 'mobile')),
            ),
            matching: find.byType(ListTile),
          ),
        );
        expect(mobileOption.minTileHeight, 32);
        expect(
          mobileOption.titleTextStyle?.fontSize,
          DiscourseTypography.fontDown1,
        );
        expect((mobileOption.leading! as Row).children, hasLength(1));
        await tester.tap(
          find.descendant(
            of: picker,
            matching: find.byKey(
              const ValueKey(('topic-tag-picker-option', 'mobile')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(api.topicTagsUpdated.single, {
          'topicId': 7,
          'tags': const [mobile],
        });
        expect(
          find.byKey(const ValueKey(('topic-sidebar-tag', 'mobile'))),
          findsOneWidget,
        );
        expect(find.text('mobile'), findsOneWidget);
        expect(picker, findsNothing);
        expect(find.byType(ComposerPanel), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });

    testWidgets('sidebar tag popover creates and removes tags', (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const design = TopicTag(id: 8, name: 'design');
        final base = detail();
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: (
              detail: base.detail.copyWith(
                canEditTags: true,
                tags: const [design],
              ),
              posts: base.posts,
            ),
          },
          composerCapabilities: const TopicComposerCapabilities(
            canTagTopics: true,
            canCreateTag: true,
            tagsFilterRegexp:
                r'''[\/\?#\[\]@!\$&'\(\)\*\+,;=%\\`^\s|\{\}"<>]+''',
            maxTagLength: 20,
            maxTagsPerTopic: 5,
          ),
          topicTagSearches: const {
            '': TopicTagSearch(tags: [design]),
            'mobile': TopicTagSearch(),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        final addTag = find.byKey(const ValueKey('topic-sidebar-add-tag'));
        await tester.tap(addTag);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('topic-tag-picker-query')),
          'mobile',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Create new tag: “mobile”'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('topic-tag-picker-create')));
        await tester.pumpAndSettle();

        expect(api.topicTagsUpdated.single, {
          'topicId': 7,
          'tags': const [design, TopicTag(name: 'mobile')],
        });
        expect(
          find.byKey(const ValueKey(('topic-sidebar-tag', 'mobile'))),
          findsOneWidget,
        );

        await tester.tap(addTag);
        await tester.pumpAndSettle();
        final picker = find.byKey(const ValueKey('topic-tag-picker-popover'));
        for (final name in ['design', 'mobile']) {
          await tester.tap(
            find.byKey(ValueKey(('topic-tag-picker-option', name))),
          );
          await tester.pumpAndSettle();
          expect(picker, findsOneWidget);
          expect(api.topicTagsUpdated, hasLength(1));
        }

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(api.topicTagsUpdated, hasLength(2));
        expect(api.topicTagsUpdated.last, {
          'topicId': 7,
          'tags': const <TopicTag>[],
        });
        expect(picker, findsNothing);
        expect(
          find.byKey(const ValueKey(('topic-sidebar-tag', 'design'))),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey(('topic-sidebar-tag', 'mobile'))),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });

    testWidgets('only a topic bookmark gives its action the core accent', (
      tester,
    ) async {
      const reader = DiscourseUser(id: 1, username: 'reader');
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      Future<DButtonVariant> bookmarkVariant(Bookmark bookmark) async {
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: detail(bookmarks: [bookmark]),
          },
        );
        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();
        return tester
            .widget<DButton>(
              find.byKey(const ValueKey('topic-bookmark-button')),
            )
            .variant;
      }

      expect(
        await bookmarkVariant(const Bookmark(id: 1, bookmarkableType: 'Topic')),
        DButtonVariant.transparentPrimary,
      );
      expect(
        await bookmarkVariant(const Bookmark(id: 2, bookmarkableType: 'Post')),
        DButtonVariant.flat,
      );
    });

    testWidgets('offers copy and system share for core’s canonical link', (
      tester,
    ) async {
      final copied = watchClipboard(tester);
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final shares = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shares.add(call);
        return 'test-share-target';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
      const reader = DiscourseUser(username: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        user: reader,
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: reader, config: const SiteConfig.unknown()),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-share-button')));
      await tester.pumpAndSettle();

      const url = 'https://meta.discourse.org/t/a-real-topic/7?u=reader';
      expect(find.text('Share this topic'), findsOneWidget);
      expect(find.text(url), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-share-copy')));
      await tester.pumpAndSettle();
      expect(copied, [url]);

      await tester.tap(find.byKey(const ValueKey('topic-share-system')));
      await tester.pumpAndSettle();
      expect(shares, hasLength(1));
      expect(shares.single.method, 'share');
      expect((shares.single.arguments as Map)['text'], url);
      expect((shares.single.arguments as Map)['subject'], 'A real topic');
    });

    testWidgets('post sharing targets that post and can continue elsewhere', (
      tester,
    ) async {
      const reader = DiscourseUser(id: 7, username: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            canCreatePost: true,
            canReplyAsNewTopic: true,
            posts: [
              post(1, 1, 'First post body'),
              post(2, 2, 'Second post body'),
            ],
          ),
        },
        user: reader,
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: reader, config: const SiteConfig.unknown()),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(renderedText('Second post body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Share this post');
      await tester.pumpAndSettle();

      expect(find.text('Share post #2'), findsOneWidget);
      expect(
        find.text('https://meta.discourse.org/t/a-real-topic/7/2?u=reader'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('topic-share-reply-as-new-topic')),
      );
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.visibleComposer, isNotNull);
      expect(
        shell.visibleComposer?.raw,
        'Continue the discussion from [A real topic]'
        '(https://meta.discourse.org/t/a-real-topic/7/2)',
      );
    });

    testWidgets('a permitted reader can flag the whole topic', (tester) async {
      const spam = PostFlagType(
        id: 8,
        nameKey: 'spam',
        name: 'Spam',
        description: '<p>This topic is promotional.</p>',
        appliesTo: ['Topic'],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            canFlagTopic: true,
            topicActions: const [PostActionSummary(id: 8, canAct: true)],
          ),
        },
        categoryPostActionCatalog: const SitePostActionCatalog(
          topicFlags: [spam],
        ),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flag topic'));
      await tester.pumpAndSettle();

      expect(find.text('Spam'), findsOneWidget);
      expect(renderedText('This topic is promotional.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
      await tester.pumpAndSettle();

      expect(api.topicFlagsCreated, [
        (topicId: 7, postActionTypeId: 8, message: null),
      ]);
      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      expect(find.text('Flag topic'), findsNothing);
    });

    testWidgets('shows the web topic map beneath the opening post', (
      tester,
    ) async {
      final posts = [
        post(1, 1, 'First post body'),
        post(2, 2, 'Second post body'),
        post(3, 3, 'Third post body'),
        post(4, 4, 'Fourth post body'),
      ];
      const participants = [
        TopicParticipant(username: 'sam', name: 'Sam'),
        TopicParticipant(username: 'lee', name: 'Lee'),
        TopicParticipant(username: 'pat', name: 'Pat'),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: posts,
            views: 218,
            likeCount: 9,
            participantCount: 6,
            wordCount: 2500,
            participants: participants,
            links: const [
              TopicMapLink(
                url: 'https://discourse.org',
                title: 'Discourse homepage',
              ),
            ],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-views')), findsOneWidget);
      expect(find.text('218'), findsOneWidget);
      expect(find.text('views'), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-likes')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-links')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-users')), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-map-links')));
      await tester.pumpAndSettle();
      expect(find.text('Discourse homepage'), findsOneWidget);
    });

    testWidgets('shows a hand cursor and expands reflected post links', (
      tester,
    ) async {
      final links = [
        for (var index = 1; index <= 6; index++)
          PostInboundLink(
            url: '/t/source-$index/$index',
            title: 'Source $index',
          ),
        const PostInboundLink(url: '/t/duplicate/99', title: 'Source 1'),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked: '<p>First post body</p>',
                inboundLinks: links,
              ),
            ],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('Source 1'), findsOneWidget);
      expect(find.text('Source 5'), findsOneWidget);
      expect(find.text('Source 6'), findsNothing);
      expect(find.text('1 more link'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(
                of: find.text('Source 1'),
                matching: find.byType(InkWell),
              ),
            )
            .mouseCursor,
        SystemMouseCursors.click,
      );

      await tester.tap(find.text('1 more link'));
      await tester.pumpAndSettle();

      expect(find.text('Source 6'), findsOneWidget);
      expect(find.text('Source 1'), findsOneWidget);
    });

    testWidgets('renders site emoji in reflected post link titles', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        emojisBySite: const {
          'https://meta.discourse.org': [
            SiteEmoji(name: 'mega', url: '/images/emoji/mega.png'),
          ],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked: '<p>First post body</p>',
                inboundLinks: [
                  PostInboundLink(
                    url: '/t/weekly-updates/99',
                    title: "Keegan's Weekly Updates (2025) :mega:",
                  ),
                ],
              ),
            ],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      replaceEmojiCache(
        MockClient((_) async => http.Response.bytes(emojiPng, 200)),
      );

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
      expect(emoji.name, 'mega');
      expect(
        find.bySemanticsLabel("Keegan's Weekly Updates (2025) :mega:"),
        findsOneWidget,
      );
    });

    testWidgets('summarizes top replies and restores the complete stream', (
      tester,
    ) async {
      final first = post(1, 1, 'First post body');
      final second = post(2, 2, 'Ordinary reply');
      final top = post(3, 3, 'Top reply');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [first, second, top],
            hasSummary: true,
          ),
        },
        summaryTopics: {
          7: topicPayload(id: 7, title: 'A real topic', posts: [first, top]),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      expect(renderedText('Ordinary reply'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-summary-button')));
      await tester.pumpAndSettle();

      expect(api.topicSummariesOpened, [7]);
      expect(renderedText('Ordinary reply'), findsNothing);
      expect(renderedText('Top reply'), findsOneWidget);
      expect(find.text('Show all'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-summary-button')));
      await tester.pumpAndSettle();

      expect(renderedText('Ordinary reply'), findsOneWidget);
      expect(find.text('Summarize'), findsOneWidget);
    });

    testWidgets('prefers the Discourse AI summary over the core summary', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [post(1, 1, 'First post body')],
            hasSummary: true,
            plugins: PluginData.none.withValue(
              aiSummaryAvailabilityDataKey,
              const AiSummaryAvailability(
                summarizable: true,
                hasCachedSummary: true,
              ),
            ),
          ),
        },
        pluginResponses: const {
          'GET /discourse-ai/summarization/t/7.json': {
            'ai_topic_summary': {
              'summarized_text': 'A concise AI summary.',
              'algorithm': 'test-model',
            },
          },
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('ai-topic-summary-button'));
      expect(action, findsOneWidget);
      expect(find.byKey(const ValueKey('topic-summary-button')), findsNothing);
      expect(find.text('Summarize'), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('Topic summary'), findsOneWidget);
      expect(find.text('A concise AI summary.'), findsOneWidget);
      expect(find.text('Generated with test-model'), findsOneWidget);
      expect(api.pluginReadPaths, ['/discourse-ai/summarization/t/7.json']);
    });

    testWidgets('a signed-in topic exposes all web notification levels', (
      tester,
    ) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(notificationLevel: TopicNotificationLevel.tracking)},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      final trigger = find.byTooltip('Topic notifications');
      expect(trigger, findsOneWidget);
      DIconData triggerIcon() => tester
          .widget<DIcon>(
            find.descendant(of: trigger, matching: find.byType(DIcon)),
          )
          .icon;
      expect(triggerIcon(), DIcons.bell);

      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(find.text('Topic notifications'), findsNothing);
      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('Every reply and unread count'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey((
              'choice-menu-option',
              TopicNotificationLevel.tracking,
            )),
          ),
          matching: find.text('Tracking'),
        ),
        findsOneWidget,
      );
      expect(find.text('Mentions, replies, and unread count'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Mentions and replies only'), findsOneWidget);
      expect(find.text('Muted'), findsOneWidget);
      expect(find.text('No notifications; hidden from Latest'), findsOneWidget);
      final muted = find.byKey(
        const ValueKey(('choice-menu-option', TopicNotificationLevel.muted)),
      );
      expect(
        tester
            .widgetList<DIcon>(
              find.descendant(of: muted, matching: find.byType(DIcon)),
            )
            .map((icon) => icon.icon),
        contains(DIcons.discourseBellSlash),
      );

      await tester.tap(muted);
      await tester.pumpAndSettle();

      expect(api.topicNotificationLevelsUpdated, const [
        (topicId: 7, notificationLevel: TopicNotificationLevel.muted),
      ]);
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).currentTopic?.notificationLevel,
        TopicNotificationLevel.muted,
      );
      expect(triggerIcon(), DIcons.discourseBellSlash);
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    testWidgets('a rejected notification change restores the confirmed level', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(notificationLevel: TopicNotificationLevel.tracking)},
        writeFailure: const WriteException(WriteFailure.forbidden),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Topic notifications'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(('choice-menu-option', TopicNotificationLevel.muted)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).currentTopic?.notificationLevel,
        TopicNotificationLevel.tracking,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps action hover affordances inside the viewport', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            canCloseTopic: true,
            canArchiveTopic: true,
            canToggleTopicVisibility: true,
            canDeleteTopic: true,
          ),
        },
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(508, 700);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Show topic sidebar'));
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('topic-status-button'));
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      final item = find.byKey(const ValueKey('topic-status-closed'));
      final button = tester.widget<TextButton>(
        find.descendant(of: item, matching: find.byType(TextButton)),
      );
      final theme = Theme.of(tester.element(item));
      final hoverColor = Color.alphaBlend(
        theme.colorScheme.onSurface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06,
        ),
        theme.shell.floating,
      );
      expect(
        button.style!.backgroundColor!.resolve({WidgetState.hovered}),
        hoverColor,
      );
      expect(button.style!.mouseCursor!.resolve({}), SystemMouseCursors.click);

      final menuSurface = find.byKey(const ValueKey('command-menu-surface'));
      expect(menuSurface, findsOneWidget);
      final menuRect = tester.getRect(menuSurface);
      expect(menuRect.left, greaterThanOrEqualTo(10));
      expect(menuRect.top, greaterThanOrEqualTo(10));
      expect(menuRect.right, lessThanOrEqualTo(498));
      expect(menuRect.bottom, lessThanOrEqualTo(690));
    });

    testWidgets(
      'gates status actions by guardian permissions and updates state',
      (tester) async {
        const reader = DiscourseUser(username: 'reader', name: 'Reader');
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: detail(
              canCloseTopic: true,
              canArchiveTopic: true,
              canToggleTopicVisibility: true,
            ),
          },
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: reader),
          ],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        Future<void> choose(String label) async {
          await tester.tap(find.byTooltip('More topic actions'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await choose('Close topic');
        expect(
          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).currentTopic?.closed,
          isTrue,
        );
        await choose('Archive topic');
        expect(
          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).currentTopic?.archived,
          isTrue,
        );
        await choose('Make topic unlisted');
        expect(
          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).currentTopic?.visible,
          isFalse,
        );
        expect(api.topicStatusesUpdated, const [
          (topicId: 7, status: TopicStatusProperty.closed, enabled: true),
          (topicId: 7, status: TopicStatusProperty.archived, enabled: true),
          (topicId: 7, status: TopicStatusProperty.visible, enabled: false),
        ]);

        await tester.tap(find.byTooltip('More topic actions'));
        await tester.pumpAndSettle();
        expect(find.text('Open topic'), findsOneWidget);
        expect(find.text('Unarchive topic'), findsOneWidget);
        expect(find.text('Make topic visible'), findsOneWidget);
      },
    );

    testWidgets('staff can delete and recover a topic from its action menu', (
      tester,
    ) async {
      const reader = DiscourseUser(
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final api = FakeDiscourseApi(
        user: reader,
        feeds: {'/latest.json': listed},
        topics: {7: detail(canDeleteTopic: true)},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-delete-confirm')));
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.topicsDeleted, [7]);
      expect(shell.currentTopic?.deletedAt, isNotNull);
      expect(shell.currentTopic?.canRecoverTopic, isTrue);

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover topic'));
      await tester.pumpAndSettle();

      expect(api.topicsRecovered, [7]);
      expect(shell.currentTopic?.deletedAt, isNull);
      expect(shell.currentTopic?.canDeleteTopic, isTrue);
    });

    testWidgets('share stays available when guardian-gated actions do not', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-share-button')), findsOneWidget);
      final more = tester.widget<DButton>(
        find.byKey(const ValueKey('topic-status-button')),
      );
      expect(more.onPressed, isNull);
      expect(find.text('Close topic'), findsNothing);
      expect(find.text('Archive topic'), findsNothing);
      expect(find.text('Delete topic'), findsNothing);
    });

    testWidgets('a personalized topic pin can be dismissed and restored', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [
            Topic(
              id: 7,
              title: 'A real topic',
              slug: 'a-real-topic',
              pinned: true,
            ),
          ],
        },
        topics: {7: detail(pinned: true, pinnedGlobally: true)},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      final trigger = find.byTooltip('More topic actions');
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin topic'));
      await tester.pumpAndSettle();

      var shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.topicPinPreferencesUpdated, const [
        (topicId: 7, pinned: false),
      ]);
      expect(shell.currentTopic?.pinned, isFalse);
      expect(shell.currentTopic?.unpinned, isTrue);
      expect(
        shell.store.read<Topic>('https://meta.discourse.org', 7)?.pinned,
        isFalse,
      );

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin topic'));
      await tester.pumpAndSettle();

      shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.topicPinPreferencesUpdated, const [
        (topicId: 7, pinned: false),
        (topicId: 7, pinned: true),
      ]);
      expect(shell.currentTopic?.pinned, isTrue);
      expect(shell.currentTopic?.unpinned, isFalse);
      expect(
        shell.store.read<Topic>('https://meta.discourse.org', 7)?.pinned,
        isTrue,
      );
    });

    testWidgets('a rejected topic pin change restores the prior preference', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [
            Topic(
              id: 7,
              title: 'A real topic',
              slug: 'a-real-topic',
              pinned: true,
            ),
          ],
        },
        topics: {7: detail(pinned: true)},
        writeFailure: const WriteException(WriteFailure.forbidden),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin topic'));
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.currentTopic?.pinned, isTrue);
      expect(shell.currentTopic?.unpinned, isFalse);
      expect(
        shell.store.read<Topic>('https://meta.discourse.org', 7)?.pinned,
        isTrue,
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('ordinary topics do not show personalized pin controls', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      expect(find.text('Pin topic'), findsNothing);
      expect(find.text('Unpin topic'), findsNothing);
    });

    testWidgets('signed-out topics do not expose notification controls', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Topic notifications'), findsNothing);
    });

    testWidgets('shows a faithful skeleton while the topic is loading', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        topicGate: gate,
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      try {
        await tester.tap(find.text('A real topic'));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('topic-loading-skeleton')),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('topic-loading-skeleton-content')),
              )
              .height,
          greaterThanOrEqualTo(
            tester
                .getSize(find.byKey(const ValueKey('topic-loading-skeleton')))
                .height,
          ),
        );
        final skeletonPosts = minimumHeightDescendants(
          find.byKey(const ValueKey('topic-loading-skeleton')),
          TopicView.minimumPostHeight,
        );
        expect(skeletonPosts, findsWidgets);
        expect(
          tester.getSize(skeletonPosts.first).height,
          greaterThanOrEqualTo(TopicView.minimumPostHeight),
        );
        expect(find.bySemanticsLabel('Loading topic'), findsOneWidget);
        expect(activityIndicators, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('topic-loading-skeleton')),
        findsNothing,
      );
      expect(renderedText('First post body'), findsOneWidget);
      final loadedPosts = minimumHeightDescendants(
        find.byType(TopicView),
        TopicView.minimumPostHeight,
      );
      expect(loadedPosts, findsOneWidget);
      expect(
        tester.getSize(loadedPosts.first).height,
        greaterThanOrEqualTo(TopicView.minimumPostHeight),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unread row opens at its first unread post', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 7,
              title: 'A real topic',
              slug: 'a-real-topic',
              unreadPosts: 5,
              lastReadPostNumber: 5,
              highestPostNumber: 10,
            ),
          ],
        },
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicPostNumbersOpened, [6]);
      expect(
        ShellScope.of(
          tester.element(find.byType(TopicView)),
        ).currentContent?.postNumber,
        6,
      );
    });

    testWidgets('back returns to the list without refetching it', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(TopicListView), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('reading a topic clears its unread count on every list it is '
        'in', (tester) async {
      final unread = [
        const Topic(
          id: 7,
          title: 'A real topic',
          slug: 'a-real-topic',
          unreadPosts: 3,
        ),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': unread},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsNothing);

      final controller = ShellScope.of(
        tester.element(find.byType(InstanceRail)),
      );
      expect(
        controller.store
            .read<Topic>(controller.currentInstance!.url, 7)!
            .hasUnread,
        isFalse,
      );
    });

    testWidgets('back lands where the list was left, not at the top', (
      tester,
    ) async {
      final many = [
        for (var i = 1; i <= 60; i++)
          Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': many},
        topics: {for (final topic in many) topic.id: detail()},
      );

      await pumpShell(tester, desktop, api: api);

      final list = find.descendant(
        of: find.byType(TopicListView),
        matching: find.byType(Scrollable),
      );
      final row = find.text('Topic 40');
      await tester.scrollUntilVisible(row, 400, scrollable: list);
      await tester.pumpAndSettle();
      expect(find.text('Topic 1'), findsNothing);

      await tester.tap(
        find.ancestor(of: row, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text('Topic 40'), findsOneWidget);
      expect(find.text('Topic 1'), findsNothing);
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        greaterThan(0),
      );
    });

    testWidgets('a topic that fails to load says so', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': listed});

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't load this topic"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remaining posts are fetched by ID, not by page', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(stream: [1, 2, 3]),
        },
        postsById: {
          2: post(2, 2, 'Second post body'),
          3: post(3, 3, 'Third post body'),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [2, 3],
      ]);
      expect(renderedText('Second post body'), findsOneWidget);
    });

    testWidgets('shows and expands server-provided hidden replies', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              post(1, 1, 'First post body'),
              post(4, 4, 'Fourth post body'),
            ],
            stream: const [1, 4],
            gapsBefore: const {
              4: [2, 3],
            },
            postsCount: 4,
          ),
        },
        postsById: {
          2: post(2, 2, 'Hidden second post'),
          3: post(3, 3, 'Hidden third post'),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('VIEW 2 HIDDEN REPLIES'), findsOneWidget);
      expect(renderedText('Hidden second post'), findsNothing);
      expect(api.postFetches, isEmpty);

      await tester.tap(find.text('VIEW 2 HIDDEN REPLIES'));
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [2, 3],
      ]);
      expect(find.text('VIEW 2 HIDDEN REPLIES'), findsNothing);
      expect(renderedText('Hidden second post'), findsOneWidget);
      expect(renderedText('Hidden third post'), findsOneWidget);
      expect(
        tester.getTopLeft(renderedText('Hidden second post')).dy,
        lessThan(tester.getTopLeft(renderedText('Fourth post body')).dy),
      );
    });

    testWidgets('shows ordered recommendation-source tabs in a panel', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
            topics: [
              Topic(
                id: 8,
                title: 'Locations :earth_africa:',
                slug: 'locations',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
            topics: [
              Topic(
                id: 9,
                title: 'An AI topic :sparkles:',
                slug: 'an-ai-topic',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: TopicRecommendationSourceDefinition(
              id: TopicRecommendationSourceId('test/nearby'),
              label: 'Nearby',
              icon: DIcons.globe,
            ),
            topics: [Topic(id: 10, title: 'A nearby topic', slug: 'nearby')],
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        emojisBySite: const {
          'https://meta.discourse.org': [
            SiteEmoji(
              name: 'earth_africa',
              url: 'https://emoji.discourse-cdn.com/twitter/earth_africa.png',
            ),
            SiteEmoji(
              name: 'sparkles',
              url: 'https://emoji.discourse-cdn.com/twitter/sparkles.png',
            ),
          ],
        },
        topics: {
          7: detail(recommendations: recommendations),
          9: topicPayload(
            id: 9,
            title: 'An AI topic :sparkles:',
            posts: [post(9, 1, 'Related topic body')],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsOneWidget);
      expect(find.text('More topics'), findsOneWidget);
      final moreTopicsCard = find.byKey(
        const ValueKey('topic-more-topics-card'),
      );
      final moreTopicsCardDecoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: moreTopicsCard,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(moreTopicsCardDecoration.border, isNull);
      expect(find.byTooltip('Hide topic sidebar'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      expect(find.text('Related'), findsOneWidget);
      expect(find.text('Nearby'), findsOneWidget);
      final earth = find.byWidgetPredicate(
        (widget) => widget is SiteEmojiImage && widget.name == 'earth_africa',
      );
      final sparkles = find.byWidgetPredicate(
        (widget) => widget is SiteEmojiImage && widget.name == 'sparkles',
      );
      expect(earth, findsOneWidget);
      expect(sparkles, findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('topic-recommendations-tab-discourse-ai/related'),
        ),
      );
      await tester.pumpAndSettle();

      expect(earth, findsNothing);
      expect(sparkles, findsOneWidget);

      await tester.tap(sparkles);
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 9]);
      expect(renderedText('Related topic body'), findsOneWidget);
    });

    testWidgets('hides a lone recommendation tab and compacts topic titles', (
      tester,
    ) async {
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
            topics: [
              Topic(
                id: 8,
                title: 'A compact suggested topic',
                slug: 'a-compact-suggested-topic',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('More topics'), findsOneWidget);
      expect(find.text('Suggested'), findsNothing);
      final compactTitle = tester.widget<TopicTitle>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TopicTitle &&
              widget.title == 'A compact suggested topic',
        ),
      );
      expect(compactTitle.style?.fontSize, DiscourseTypography.base);
      expect(
        compactTitle.style?.fontSize,
        lessThan(DiscourseTypography.fontUp1),
      );
    });

    testWidgets('omits More topics when every source is empty', (tester) async {
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-more-topics-card')),
        findsNothing,
      );
      expect(find.text('More topics'), findsNothing);
    });

    testWidgets('reserves the topic sidebar while a topic loads', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'A suggested topic',
          slug: 'a-suggested-topic',
        ),
      );
      final topicGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
        topicGate: topicGate,
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pump();
      final semantics = tester.ensureSemantics();

      final loadingPanel = find.byKey(
        const ValueKey('topic-recommendations-loading-skeleton'),
      );
      expect(loadingPanel, findsOneWidget);
      expect(find.bySemanticsLabel('Loading more topics'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('topic-sidebar-panel'))).width,
        344,
      );
      final loadingPostWidth = tester
          .getSize(find.byKey(const ValueKey('topic-loading-skeleton')))
          .width;

      topicGate.complete();
      await tester.pumpAndSettle();

      expect(loadingPanel, findsNothing);
      expect(find.text('A suggested topic'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SuperListView)).width,
        loadingPostWidth,
      );
      semantics.dispose();
    });

    testWidgets('keeps the panel width while final-page topics load', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'Suggested at the end',
          slug: 'suggested-end',
        ),
      );
      final postGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(stream: [1, 2]),
        },
        postsById: {2: post(2, 2, 'Last post body')},
        postRecommendations: {7: recommendations},
        postGate: postGate,
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(api.postFetches, [
        [2],
      ]);
      final loadingPanel = find.byKey(
        const ValueKey('topic-recommendations-loading-skeleton'),
      );
      expect(loadingPanel, findsOneWidget);
      final loadingPostWidth = tester.getSize(find.byType(SuperListView)).width;

      postGate.complete();
      await tester.pumpAndSettle();

      expect(loadingPanel, findsNothing);
      expect(find.text('Suggested at the end'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SuperListView)).width,
        loadingPostWidth,
      );
    });

    testWidgets('remembers a hidden topic sidebar for the forum', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final recommendations = suggestedRecommendations(
        const Topic(id: 8, title: 'Remembered suggestion', slug: 'remembered'),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      expect(find.text('Remembered suggestion'), findsOneWidget);
      final postViewportWidth = tester
          .getSize(find.byType(SuperListView))
          .width;
      expect(
        tester.widget<SuperListView>(find.byType(SuperListView)).padding,
        EdgeInsets.zero,
      );

      await tester.tap(find.byTooltip('Hide topic sidebar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show topic sidebar'), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
      expect(find.text('Remembered suggestion'), findsNothing);
      expect(
        tester.getSize(find.byType(SuperListView)).width,
        postViewportWidth + 344,
      );
      expect(
        tester.widget<SuperListView>(find.byType(SuperListView)).padding,
        EdgeInsets.zero,
      );
      // The UI intentionally fires this optional preference write without
      // blocking. Read through the same serialized store boundary so the
      // replacement below cannot overtake that write.
      expect(
        await const TopicSidebarStore().read(
          siteUrl: 'https://meta.discourse.org',
        ),
        isTrue,
      );

      await pumpShell(
        tester,
        desktop,
        api: api,
        key: const ValueKey('restored-topics-panel'),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Show topic sidebar'), findsOneWidget);
      expect(find.text('Remembered suggestion'), findsNothing);
    });

    testWidgets('remembers the more topics tab for the forum', (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
            topics: [
              Topic(
                id: 8,
                title: 'A suggested topic',
                slug: 'a-suggested-topic',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
            topics: [
              Topic(id: 9, title: 'An AI related topic', slug: 'an-ai-topic'),
            ],
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      expect(find.text('A suggested topic'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('topic-recommendations-tab-discourse-ai/related'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('An AI related topic'), findsOneWidget);
      // The UI intentionally fires this optional preference write without
      // blocking. Read through the same serialized store boundary so the
      // replacement below cannot overtake that write.
      expect(
        await const TopicRecommendationsTabStore().read(
          siteUrl: 'https://meta.discourse.org',
        ),
        discourseAiRelatedTopicRecommendationSourceId,
      );

      await pumpShell(
        tester,
        desktop,
        api: api,
        key: const ValueKey('restored-topics-tab'),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('An AI related topic'), findsOneWidget);
      expect(find.text('A suggested topic'), findsNothing);
    });

    testWidgets('falls back when the remembered tab has no topics', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      await const TopicRecommendationsTabStore().write(
        siteUrl: 'https://meta.discourse.org',
        sourceId: discourseAiRelatedTopicRecommendationSourceId,
      );
      final recommendations = suggestedRecommendations(
        const Topic(id: 8, title: 'Only suggestion', slug: 'only-suggestion'),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('Only suggestion'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('topic-recommendations-tab-discourse-ai/related'),
        ),
        findsNothing,
      );
    });

    testWidgets('keeps recommendations below the posts on narrow layouts', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'Narrow suggestion',
          slug: 'narrow-suggestion',
        ),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, laptop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
      expect(find.text('Narrow suggestion'), findsOneWidget);
      expect(find.byTooltip('Show topic sidebar'), findsOneWidget);
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('topic-sidebar-toggle')))
            .variant,
        DButtonVariant.flat,
      );
      expect(
        find.byKey(const ValueKey('topic-sidebar-icon-closed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('topic-sidebar-icon-open')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('topic-sidebar-icon'))),
        const Size(16, 14),
      );

      await tester.tap(find.byTooltip('Show topic sidebar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsOneWidget);
      expect(find.byTooltip('Hide topic sidebar'), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-status-button')), findsOneWidget);
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('topic-sidebar-toggle')))
            .variant,
        DButtonVariant.flat,
      );
      expect(
        find.byKey(const ValueKey('topic-sidebar-icon-open')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('topic-sidebar-icon-closed')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Hide topic sidebar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('topic-sidebar-toggle')))
            .variant,
        DButtonVariant.flat,
      );
      expect(
        find.byKey(const ValueKey('topic-sidebar-icon-closed')),
        findsOneWidget,
      );
    });

    testWidgets(
      'automatically unpins the sidebar when an expanded shell is too narrow',
      (tester) async {
        final recommendations = suggestedRecommendations(
          const Topic(
            id: 8,
            title: 'Responsive suggestion',
            slug: 'responsive-suggestion',
          ),
        );
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail(recommendations: recommendations)},
        );

        await pumpShell(tester, desktop, api: api);
        await tester.tap(find.text('A real topic'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-sidebar-panel')),
          findsOneWidget,
        );

        // This remains above the shell's expanded breakpoint, but its topic
        // viewport can no longer leave 640px for posts beside the 344px panel.
        tester.view.physicalSize = const Size(1240, 800);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
        expect(find.text('Responsive suggestion'), findsOneWidget);
        expect(find.byTooltip('Show topic sidebar'), findsOneWidget);
        expect(
          tester.widget<SuperListView>(find.byType(SuperListView)).padding,
          EdgeInsets.zero,
        );

        await tester.tap(find.byTooltip('Show topic sidebar'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('topic-sidebar-panel')),
          findsOneWidget,
        );
        expect(find.byTooltip('Hide topic sidebar'), findsOneWidget);
      },
    );

    testWidgets('gets more topics with the final page of a long topic', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'Suggested at the end',
          slug: 'suggested-end',
        ),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(stream: [1, 2]),
        },
        postsById: {2: post(2, 2, 'Last post body')},
        postRecommendations: {7: recommendations},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [2],
      ]);
      expect(renderedText('Last post body'), findsOneWidget);
      expect(find.text('Suggested at the end'), findsOneWidget);
    });

    testWidgets('a topic already held is not refetched', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
    });

    testWidgets('hovering a post leaves its surface unchanged', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(_postBackground(tester), Colors.transparent);

      final gesture = await hoverPost(tester);
      expect(_postBackground(tester), Colors.transparent);

      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_postBackground(tester), Colors.transparent);
    });

    testWidgets('whisper posts use core styling and an indicator', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              post(1, 1, 'First post body'),
              const Post(
                id: 2,
                postNumber: 2,
                username: 'sam',
                cooked: '<p>A private aside</p>',
                postType: Post.whisperPostType,
              ),
            ],
            stream: const [1, 2],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.farEyeSlash), findsOneWidget);
      expect(find.byTooltip('This post is a private whisper'), findsOneWidget);

      final whisper = tester.widget<RichText>(renderedText('A private aside'));
      expect(whisper.text.style?.fontStyle, FontStyle.italic);
      expect(
        whisper.text.style?.color,
        Theme.of(tester.element(find.byType(TopicView))).discourse.whisper,
      );
    });
  });
}

class _FailingNewTopicMetadataApi extends FakeDiscourseApi {
  _FailingNewTopicMetadataApi({required super.user})
    : super(
        feeds: const {'/latest.json': []},
        categoryList: const [category],
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
      );

  static const category = TopicCategory(
    id: 5,
    name: 'Support',
    color: '0088CC',
    permission: 1,
  );

  bool failCapabilities = false;
  bool failCategoryLoad = false;
  Completer<void>? capabilityGate;

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    if (failCategoryLoad) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return super.loadCategories(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      page: page,
    );
  }

  @override
  Future<List<TopicCategory>> categories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    categoryRequests.add(siteUrl);
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final capabilities = await super.topicComposerCapabilities(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    await capabilityGate?.future;
    if (failCapabilities) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return capabilities;
  }
}

double _textWidth(WidgetTester tester, Finder text) {
  final widget = tester.widget<Text>(text);
  final context = tester.element(text);
  final painter = TextPainter(
    text: TextSpan(text: widget.textSpan!.toPlainText(), style: widget.style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

/// The surface the first post paints for itself. The innermost [ColoredBox]
/// above the body is the post's own.
Color _postBackground(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .ancestor(
            of: renderedText('First post body'),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

List<Rect> _inlineWidgetBoxes(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final boxes = <Rect>[];
  paragraph.visitChildren((child) {
    final box = child as RenderBox;
    boxes.add(box.localToGlobal(Offset.zero) & box.size);
  });
  return boxes;
}
