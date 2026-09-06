import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/shell/topic_inbox_row.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';

const _parent = TopicCategory(
  id: 21,
  name: 'Design',
  slug: 'design',
  color: '9464B8',
);
const _child = TopicCategory(
  id: 22,
  name: 'Onboarding',
  color: '9464B8',
  slug: 'onboarding',
  parentCategoryId: 21,
);
const _tag = TopicTag(id: 1, name: 'community');

void main() {
  testWidgets(
    'compact reader aligns taxonomy, title, activity, and post text',
    (tester) async {
      final state = ValueNotifier('Available');
      addTearDown(state.dispose);
      final setup = await _setup(
        tester,
        registry: PluginRegistry([_HeaderDetailsPlugin(state)]),
      );
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final parent = tester.getRect(find.byTooltip('Edit topic category'));
      final child = tester.getRect(find.byTooltip('Edit topic subcategory'));
      final tag = tester.getRect(
        find.byKey(const ValueKey(('topic-header-tag', 'community'))),
      );
      final addTag = tester.getRect(
        find.byKey(const ValueKey('topic-header-add-tag')),
      );
      expect(parent.right, lessThan(child.left));
      expect(child.right, lessThan(tag.left));
      expect(tag.right, lessThan(addTag.left));
      expect(parent.center.dy, closeTo(tag.center.dy, 1));
      expect(child.center.dy, closeTo(tag.center.dy, 1));
      final title = tester.getRect(
        find.byKey(const ValueKey('topic-header-title-field')),
      );
      final summary = tester.getRect(
        find.byKey(const ValueKey('topic-header-activity')),
      );
      final properties = tester.getRect(find.text('Manage details'));
      expect(summary.top, greaterThanOrEqualTo(title.bottom));
      expect(properties.center.dy, closeTo(summary.center.dy, 1));
      expect(properties.right, greaterThan(title.right - 32));
      expect(
        tester.getRect(find.byType(CookedHtml).first).left,
        closeTo(title.left, 1),
      );
      final footer = find.byKey(const ValueKey('topic-bottom-bar'));
      expect(
        find.descendant(of: footer, matching: find.byType(TopicBookmarkButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: footer,
          matching: find.byType(TopicNotificationLevelButton),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'many tags stay beside categories and hidden tags can be removed immediately',
    (tester) async {
      final tags = [
        for (var id = 1; id <= 27; id++) TopicTag(id: id, name: 'region-$id'),
      ];
      final setup = await _setup(tester, tags: tags);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final taxonomy = find.byKey(const ValueKey('topic-header-taxonomy'));
      final overflow = find.byKey(const ValueKey('topic-header-more-tags'));
      final parent = find.byTooltip('Edit topic category');
      final child = find.byTooltip('Edit topic subcategory');
      final height = tester.getSize(taxonomy).height;
      expect(height, lessThan(40));
      expect(
        tester.getCenter(overflow).dy,
        closeTo(tester.getCenter(parent).dy, 1),
      );
      expect(
        tester.getCenter(overflow).dy,
        closeTo(tester.getCenter(child).dy, 1),
      );
      expect(find.text('Last activity 2m ago'), findsOneWidget);

      await tester.tap(overflow);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-tag-picker-query')),
        'region-27',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey(('topic-tag-picker-option', 'region-27'))),
      );
      await tester.pumpAndSettle();
      expect(setup.controller.currentTopic!.tags, hasLength(26));
      expect(
        setup.api.topicTagsUpdated.single['tags'],
        isNot(contains('region-27')),
      );
      expect(tester.getSize(taxonomy).height, height);
      expect(find.text('Done'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read-only topics still expose every collapsed tag', (
    tester,
  ) async {
    final tags = [
      for (var id = 1; id <= 27; id++) TopicTag(id: id, name: 'region-$id'),
    ];
    final setup = await _setup(tester, tags: tags, canEditTags: false);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-header-add-tag')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('topic-header-more-tags')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-header-tags-search')),
      'REGION-27',
    );
    await tester.pumpAndSettle();
    expect(find.text('# region-27'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(setup.api.topicTagsUpdated, isEmpty);
    expect(setup.controller.currentTopic!.tags, hasLength(27));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow headers keep categories and tag overflow accessible with large text',
    (tester) async {
      final tags = [
        for (var id = 1; id <= 27; id++)
          TopicTag(id: id, name: 'long-production-region-$id'),
      ];
      final setup = await _setup(tester, tags: tags);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      for (final width in [320.0, 520.0, 900.0]) {
        await tester.pumpWidget(
          ShellScope(
            controller: setup.controller,
            child: MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: TopicInboxHeader(
                        title: setup.controller.currentTopic!.title,
                        siteUrl: setup.controller.currentInstance!.url,
                        canReturnToSidebar: true,
                        keepTopicListOpen: true,
                        registry: PluginRegistry.empty,
                        topic: setup.controller.currentTopic,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final overflow = find.byKey(const ValueKey('topic-header-more-tags'));
        for (final key in [
          'topic-header-browse-category-21',
          'topic-header-browse-category-22',
        ]) {
          final browse = find.byKey(ValueKey(key));
          expect(browse, findsOneWidget);
          expect(
            tester.getCenter(browse).dy,
            closeTo(tester.getCenter(overflow).dy, 1),
          );
        }
        expect(tester.getRect(overflow).right, lessThan(width));
        expect(tester.takeException(), isNull, reason: 'reader width $width');
      }
    },
  );

  testWidgets(
    'assigned cards share the activity row and disclose hidden tags',
    (tester) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final setup = await _setup(tester, registry: registry);
      final topic = setup.rows.first.copyWith(
        tags: const [
          TopicTag(id: 1, name: 'first'),
          TopicTag(id: 2, name: 'second'),
          TopicTag(id: 3, name: 'third'),
          TopicTag(id: 4, name: 'fourth'),
        ],
        plugins: registry.readTopic(const {
          'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
        }, setup.controller.currentInstance!.url),
      );
      await tester.pumpWidget(
        ShellScope(
          controller: setup.controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 304,
                  child: TopicInboxRow(
                    topic: topic,
                    siteUrl: setup.controller.currentInstance!.url,
                    selected: true,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First topic preview'), findsNothing);
      expect(find.text('Sam'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Sam')).dy,
        closeTo(tester.getCenter(find.text('3')).dy, 1),
      );
      expect(find.text('+2'), findsOneWidget);
      expect(find.byTooltip('# third, # fourth'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('inbox-row-1'))).height,
        lessThan(110),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resizing and topic arrows retain the source list and reader state',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final list = find.byType(TopicListView);
      final listState = tester.state(list);
      final readerState = tester.state(find.byType(TopicView));
      expect(tester.getSize(list).width, 325);
      final row = find.byKey(const ValueKey('inbox-row-1'));
      expect(tester.getRect(row).left, greaterThan(tester.getRect(list).left));
      expect(tester.getRect(row).right, lessThan(tester.getRect(list).right));
      final timestamp = find.byKey(const ValueKey('inbox-row-time-1'));
      expect(timestamp, findsOneWidget);
      expect(
        tester.getRect(timestamp).top,
        lessThan(tester.getRect(find.text('First topic preview')).top),
      );
      expect(
        find.byKey(const ValueKey('topic-ledger-activity-1')),
        findsNothing,
      );
      await tester.drag(
        find.byKey(const ValueKey('inbox-list-resize-handle')),
        const Offset(90, 0),
      );
      await tester.pumpAndSettle();
      final width = tester.getSize(list).width;
      expect(width, greaterThan(380));
      expect(tester.state(list), same(listState));
      expect(tester.state(find.byType(TopicView)), same(readerState));
      await tester.tap(find.byKey(const ValueKey('inbox-next-topic')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 2);
      expect(shell.contentStack, hasLength(2));
      expect(tester.state(list), same(listState));
      await tester.tap(find.byKey(const ValueKey('inbox-previous-topic')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 1);
      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inbox-list-resize-handle')),
        findsNothing,
      );
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pumpAndSettle();
      expect(tester.getSize(list).width, width);
      expect(tester.state(list), same(listState));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact recommendations keep the source list when opened', (
    tester,
  ) async {
    final setup = await _setup(tester, recommendations: true);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final listState = tester.state(find.byType(TopicListView));
    await tester.tap(find.byKey(const ValueKey('topic-more-topics-jump')));
    await tester.pumpAndSettle();
    final recommendations = find.byWidgetPredicate(
      (widget) => widget is TopicInboxRow && widget.recommendation,
    );
    expect(recommendations, findsOneWidget);
    expect(find.text('Suggested'), findsOneWidget);
    expect(
      find.descendant(of: recommendations, matching: find.byType(TopicListRow)),
      findsNothing,
    );
    await tester.tap(recommendations);
    await tester.pumpAndSettle();
    expect(setup.controller.currentContent?.topicId, 2);
    expect(setup.controller.contentStack, hasLength(2));
    expect(tester.state(find.byType(TopicListView)), same(listState));
    expect(tester.takeException(), isNull);
  });

  testWidgets('header details stay live and dismiss on post navigation', (
    tester,
  ) async {
    final state = ValueNotifier('Available');
    addTearDown(state.dispose);
    final setup = await _setup(
      tester,
      registry: PluginRegistry([_HeaderDetailsPlugin(state)]),
    );
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage details'));
    await tester.pumpAndSettle();
    expect(find.text('Details: Topic 1 · Available'), findsOneWidget);

    shell.store.put(
      shell.currentInstance!.url,
      shell.currentTopic!.copyWith(title: 'Updated topic'),
    );
    state.value = 'Saving';
    await tester.pumpAndSettle();
    expect(find.text('Details: Updated topic · Saving'), findsOneWidget);
    expect(find.text('Details: Topic 1 · Available'), findsNothing);

    await shell.jumpToCurrentTopicIndex(2);
    await tester.pumpAndSettle();
    expect(find.text('Details: Updated topic · Saving'), findsNothing);
    expect(shell.currentContent?.topicId, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps the source list mounted across topic selection, back, and window resizing',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      final listFinder = find.byType(TopicListView);
      final listState = tester.state(listFinder);
      final list = tester.widget<SuperListView>(
        find.descendant(of: listFinder, matching: find.byType(SuperListView)),
      );
      list.listController!.jumpToItem(
        index: 40,
        scrollController: list.controller!,
        alignment: 0,
      );
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(500));

      await tester.tap(
        find.descendant(
          of: listFinder,
          matching: find.byWidgetPredicate(
            (widget) => widget is TopicTitle && widget.title == 'Topic 21',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 21);
      expect(setup.api.topicPostNumbersOpened.last, 2);
      expect(tester.state(listFinder), same(listState));
      expect(tester.getSize(listFinder).width, lessThan(400));
      expect(
        tester.getRect(listFinder).right,
        lessThanOrEqualTo(tester.getRect(find.byType(TopicView)).left),
      );
      final retainedScroll = tester
          .widget<SuperListView>(
            find.descendant(
              of: listFinder,
              matching: find.byType(SuperListView),
            ),
          )
          .controller;
      expect(retainedScroll, same(list.controller));
      expect(retainedScroll!.offset, greaterThan(500));

      shell.openTopicFromList(setup.rows[21]);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 22);
      expect(shell.contentStack, hasLength(2));
      expect(tester.state(listFinder), same(listState));

      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();
      expect(listFinder, findsNothing);
      expect(
        tester.state(find.byType(TopicListView, skipOffstage: false)),
        same(listState),
      );
      expect(tester.getSize(find.byType(TopicView)).width, 600);

      await tester.tap(find.byKey(const ValueKey('topic-close-reader')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.isTopic, isFalse);
      expect(tester.state(listFinder), same(listState));
      expect(tester.getSize(listFinder).width, 600);
      expect(retainedScroll.offset, greaterThan(500));
      expect(
        setup.api.feedPaths.where((path) => path == '/latest.json'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('continues paging the source feed beside a reader', (
    tester,
  ) async {
    final setup = await _setup(tester);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final list = tester.widget<SuperListView>(
      find.descendant(
        of: find.byType(TopicListView),
        matching: find.byType(SuperListView),
      ),
    );
    list.listController!.jumpToItem(
      index: 118,
      scrollController: list.controller!,
      alignment: 1,
    );
    await tester.pumpAndSettle();
    expect(setup.api.feedPaths, contains('/latest.json?page=1'));
    expect(setup.controller.currentFeed?.topicIds.last, 61);
    expect(setup.controller.currentContent?.topicId, 1);
    list.listController!.jumpToItem(
      index: 120,
      scrollController: list.controller!,
      alignment: 1,
    );
    await tester.pumpAndSettle();
    expect(find.text('Next page topic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filters preserve the reader and combine category, tags, and period on the server',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final readerState = tester.state(find.byType(TopicView));
      shell.selectTopicListCategory(_child, keepTopicOpen: true);
      await tester.pumpAndSettle();
      for (final tag in ['community', 'mobile']) {
        await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey(('topic-list-tag-filter-option', tag))),
        );
        await tester.pumpAndSettle();
      }
      await shell.selectTopicListMode(
        TopicListMode.topWeekly,
        keepTopicOpen: true,
      );
      await tester.pumpAndSettle();
      final uri = Uri.parse(setup.api.feedPaths.last);
      expect(uri.path, '/top.json');
      expect(uri.queryParameters['period'], 'weekly');
      expect(uri.queryParameters['category'], '22');
      expect(uri.queryParametersAll['tags[]'], ['community', 'mobile']);
      expect(uri.queryParameters['match_all_tags'], 'true');
      expect(shell.currentContent?.topicId, 1);
      expect(shell.topicListContent?.tagNames, ['community', 'mobile']);
      expect(shell.currentTopicListMode, TopicListMode.topWeekly);
      expect(tester.state(find.byType(TopicView)), same(readerState));
      expect(find.text('Clear all'), findsNothing);
      expect(find.text('Tags · 2'), findsOneWidget);

      shell.browseTopicCategory(_parent, keepTopicOpen: true);
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, 21);
      expect(shell.topicListContent?.tagNames, isEmpty);
      expect(shell.currentContent?.topicId, 1);
      shell.closeTopicListReader();
      await tester.pumpAndSettle();
      expect(shell.currentContent?.categoryId, 21);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edits title inline and applies subcategory and tag removal immediately',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      await tester.tap(title);
      await tester.enterText(title, 'A clearer topic title');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.title, 'A clearer topic title');
      expect(setup.api.topicsUpdated.last['title'], 'A clearer topic title');
      await tester.tap(title);
      await tester.enterText(title, 'Discard this title');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.title, 'A clearer topic title');
      expect(setup.api.topicsUpdated, hasLength(1));

      await tester.tap(find.byTooltip('Edit topic subcategory'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-category-remove')));
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.categoryId, _parent.id);
      expect(find.text('Done'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey(('topic-header-tag', 'community'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('topic-tag-picker-option', 'community'))),
      );
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.tags, isEmpty);
      expect(setup.api.topicTagsUpdated.single['tags'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('post Reply is visible and opens the composer for that post', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();

    final reply = find.byKey(
      const ValueKey(('post-footer-action', 2, 'Reply')),
    );
    expect(reply, findsOneWidget);
    await tester.ensureVisible(reply);
    await tester.pumpAndSettle();
    expect(reply.hitTestable(), findsOneWidget);
    final body = find.byWidgetPredicate(
      (widget) => widget is CookedHtml && widget.post?.postNumber == 2,
    );
    expect(tester.getRect(reply).top, greaterThan(tester.getRect(body).bottom));
    expect(tester.getRect(reply).right, closeTo(tester.getRect(body).right, 1));

    await tester.tap(reply);
    await tester.pumpAndSettle();
    expect(shell.visibleComposer?.target.topicId, 1);
    expect(shell.visibleComposer?.target.replyToPostNumber, 2);
    expect(shell.visibleComposer?.target.replyToUsername, 'sam');
    expect(shell.currentContent?.topicId, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('posts without reply permission do not expose Reply', (
    tester,
  ) async {
    final setup = await _setup(tester, canCreatePost: false);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reply to this post'), findsNothing);
    expect(
      find.byKey(const ValueKey(('post-footer-action', 2, 'Reply'))),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('post-more-actions-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows post actions without hover and J/K navigate posts without switching topics',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final reader = find.byType(TopicView);
      final list = tester.widget<SuperListView>(
        find.descendant(of: reader, matching: find.byType(SuperListView)),
      );
      await tester.tap(find.byKey(const ValueKey('post-more-actions-2')));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Reply'),
        ),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Copy link'), findsNothing);
      final before = list.controller!.offset;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 1);
      expect(shell.contentStack, hasLength(2));
      expect(list.controller!.offset, greaterThan(before));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(list.controller!.offset, closeTo(before, 2));
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      await tester.tap(title);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      expect(list.controller!.offset, closeTo(before, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<({ShellController controller, FakeDiscourseApi api, List<Topic> rows})>
_setup(
  WidgetTester tester, {
  PluginRegistry registry = PluginRegistry.empty,
  bool recommendations = false,
  List<TopicTag> tags = const [_tag],
  bool canEditTags = true,
  bool canCreatePost = true,
}) async {
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 7, username: 'sam', unifiedNewEnabled: true);
  final site = instance(
    'meta.example',
  ).copyWith(user: user, config: const SiteConfig(taggingEnabled: true));
  final rows = [
    for (var id = 1; id <= 60; id++)
      Topic(
        id: id,
        title: 'Topic $id',
        slug: 'topic-$id',
        categoryId: 22,
        excerpt: id == 1 ? 'First topic preview' : null,
        lastPosterUsername: 'sam',
        bumpedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        replyCount: 3,
        unreadPosts: 3,
        lastReadPostNumber: 1,
        highestPostNumber: 4,
      ),
  ];
  final posts = {
    for (final row in rows)
      row.id: [
        for (var number = 1; number <= 4; number++)
          Post(
            id: row.id * 100 + number,
            postNumber: number,
            username: 'sam',
            userId: 7,
            canEdit: true,
            canDelete: false,
            cooked:
                '<p>Post $number</p><p>${List.filled(90, 'Topic design and feedback.').join(' ')}</p>',
          ),
      ],
  };
  final api = FakeDiscourseApi(
    user: user,
    feeds: {
      '/latest.json': rows,
      '/latest.json?page=1': const [
        Topic(id: 61, title: 'Next page topic', slug: 'next-page'),
      ],
      '/c/design/onboarding/22.json': rows,
      '/tags/c/design/onboarding/22/community.json': rows,
      ContentRoute.filteredTopicList(
        TopicListMode.latest,
        categoryId: 22,
        tags: const ['community', 'mobile'],
      ).feedPath!: rows,
      ContentRoute.filteredTopicList(
        TopicListMode.topWeekly,
        categoryId: 22,
        tags: const ['community', 'mobile'],
      ).feedPath!: rows,
      ContentRoute.filteredTopicList(
        TopicListMode.topWeekly,
        categoryId: 21,
      ).feedPath!: rows,
    },
    nextPages: const {'/latest.json': '/latest.json?page=1'},
    categoryList: const [_parent, _child],
    categorySearches: const {
      '': [_parent, _child],
    },
    categorySiteTopTags: const [
      SidebarTag(id: 1, name: 'community', slug: 'community'),
      SidebarTag(id: 2, name: 'mobile', slug: 'mobile'),
    ],
    composerCapabilities: const TopicComposerCapabilities(canTagTopics: true),
    topicTagSearches: const {
      '': TopicTagSearch(tags: [_tag]),
      'community': TopicTagSearch(tags: [_tag]),
    },
    topics: {
      for (final row in rows)
        row.id: (
          detail: TopicDetail(
            id: row.id,
            title: row.title,
            stream: posts[row.id]!.map((post) => post.id).toList(),
            postsCount: 4,
            replyCount: 3,
            participants: const [
              TopicParticipant(username: 'sam', name: 'Sam'),
            ],
            recommendations: recommendations
                ? TopicRecommendations(
                    sources: [
                      TopicRecommendationSource(
                        definition: coreSuggestedTopicRecommendationSource,
                        topics: [rows[1]],
                      ),
                    ],
                  )
                : null,
            categoryId: 22,
            canEdit: true,
            canEditTags: canEditTags,
            tags: tags,
            canCreatePost: canCreatePost,
          ),
          posts: posts[row.id]!,
        ),
    },
  );
  final plugins = PluginInstaller.install(
    PluginManifest([
      for (final plugin in registry.plugins) _InboxTestModule(plugin),
    ]),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator()..keys[site.url] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
    plugins: plugins,
  );
  addTearDown(() async {
    shell.dispose();
    await plugins.close();
  });
  await shell.load();
  await shell.loadFeed('latest');
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MainContent(layout: ShellLayout.expanded, registry: registry),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller: shell, api: api, rows: rows);
}

final class _HeaderDetailsPlugin
    implements SitePlugin, TopicPropertiesPlugin, TopicPropertiesRebuildPlugin {
  const _HeaderDetailsPlugin(this.state);

  final ValueNotifier<String> state;

  @override
  String get name => 'header-details';

  @override
  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    TopicPropertySection(
      label: 'Details',
      header: (context, showDetails) => TextButton(
        onPressed: showDetails,
        child: const Text('Manage details'),
      ),
      values: [Text('Details: ${topic.title} · ${state.value}')],
    ),
  ];

  @override
  Listenable topicPropertiesRebuildOn(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => state;
}

final class _InboxTestModule implements PluginModule {
  const _InboxTestModule(this.plugin);

  final SitePlugin plugin;

  @override
  PluginDescriptor get descriptor =>
      PluginDescriptor(id: PluginId(plugin.name));

  @override
  void register(PluginRegistrar registrar) => registrar.addCapability(plugin);
}
