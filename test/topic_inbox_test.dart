import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
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
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/shell/topic_inbox_row.dart';
import 'package:discourse_native/src/shell/topic_list_indicators.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
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
  for (final (username, initial) in [
    ('sam', 'S'),
    ('𐐨ser', '𐐀'),
    ('मित्र', 'मि'),
    ('', '?'),
  ]) {
    testWidgets(
      'header participant avatar uses "$initial" for username "$username"',
      (tester) async {
        final setup = await _setup(
          tester,
          participants: [
            TopicParticipant(username: username, name: 'Topic participant'),
          ],
        );
        setup.controller.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        await _scrollReaderToTop(tester);

        expect(tester.takeException(), isNull);
        final avatar = find.descendant(
          of: find.byKey(const ValueKey('topic-header-activity')),
          matching: find.byTooltip('Topic participant'),
        );
        expect(avatar, findsOneWidget);
        expect(
          find.descendant(of: avatar, matching: find.text(initial)),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'reader collapses smoothly and restores the full header at the top',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-compact')),
        findsOneWidget,
      );
      final header = find.byKey(const ValueKey('topic-content-header'));
      final compactHeight = tester.getSize(header).height;
      expect(compactHeight, greaterThan(shellHeaderHeight));

      await shell.jumpToCurrentTopicIndex(0);
      await tester.pumpAndSettle();
      final expandedHeight = tester.getSize(header).height;
      expect(expandedHeight, greaterThan(compactHeight));
      final reader = find.byType(TopicView);
      final readerState = tester.state(reader);
      final listFinder = find.descendant(
        of: reader,
        matching: find.byType(SuperListView),
      );
      final listElement = tester.element(listFinder);
      final list = tester.widget<SuperListView>(listFinder);

      list.controller!.jumpTo(200);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
      expect(tester.getSize(header).height, greaterThan(compactHeight));
      expect(tester.getSize(header).height, lessThan(expandedHeight));
      await tester.pumpAndSettle();
      expect(tester.getSize(header).height, compactHeight);
      expect(tester.state(reader), same(readerState));
      expect(tester.element(listFinder), same(listElement));
      expect(find.byKey(const ValueKey('topic-header-activity')), findsNothing);
      expect(find.byKey(const ValueKey('topic-header-taxonomy')), findsNothing);
      final category = find.byKey(
        const ValueKey('topic-header-compact-category'),
      );
      final title = find.byKey(const ValueKey('topic-header-compact-title'));
      expect(
        find.descendant(of: category, matching: find.text(_child.name)),
        findsOneWidget,
      );
      expect(
        tester.getRect(category).top,
        greaterThan(tester.getRect(title).bottom),
      );
      expect(
        tester
            .getRect(
              find.byKey(
                const ValueKey('topic-header-compact-parent-category'),
              ),
            )
            .left,
        closeTo(tester.getRect(title).left, 1),
      );
      expect(tester.widget<TopicTitle>(title).maxLines, 1);

      list.controller!.jumpTo(40);
      await tester.pumpAndSettle();
      expect(tester.getSize(header).height, compactHeight);
      list.controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getSize(header).height, expandedHeight);
      expect(
        find.byKey(const ValueKey('topic-header-taxonomy')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stationary toolbar controls stay visible through transitions with a wrapped title',
    (tester) async {
      final setup = await _setup(
        tester,
        registry: const PluginRegistry([AssignPlugin()]),
        topicPluginPayload: const {
          'can_assign': false,
          'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
        },
        firstTopicTitle:
            'Customer Support Coverage Week - Seville 2026: coordinating schedules, travel, and team availability',
      );
      tester.view.physicalSize = const Size(1400, 800);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      await _scrollReaderToTop(tester);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('topic-header-title-field')))
            .height,
        greaterThan(shellHeaderHeight),
      );
      final controls = [
        for (final finder in [
          find.byKey(const ValueKey('topic-close-reader')),
          find.byKey(const ValueKey('inbox-previous-topic')),
          find.byKey(const ValueKey('inbox-next-topic')),
          find.byKey(const ValueKey('topic-status-button')),
          find.byType(TopicShareButton),
        ])
          (
            finder: finder,
            element: tester.element(finder),
            bounds: tester.getRect(finder),
          ),
      ];
      final scroll = tester
          .widget<SuperListView>(
            find.descendant(
              of: find.byType(TopicView),
              matching: find.byType(SuperListView),
            ),
          )
          .controller!;

      for (final offset in [200.0, 0.0]) {
        scroll.jumpTo(offset);
        await tester.pump();
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 190));
          for (final control in controls) {
            expect(control.finder, findsOneWidget);
            expect(tester.element(control.finder), same(control.element));
            expect(tester.getRect(control.finder), control.bounds);
            expect(control.finder.hitTestable(), findsOneWidget);
            for (final fade in tester.widgetList<FadeTransition>(
              find.ancestor(
                of: control.finder,
                matching: find.byType(FadeTransition),
              ),
            )) {
              expect(fade.opacity.value, 1);
            }
          }
        }
        await tester.pumpAndSettle();
      }

      scroll.jumpTo(200);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
      await tester.tap(find.byKey(const ValueKey('topic-close-reader')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, isNull);
      expect(find.byType(TopicView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact category navigates and assignment details remain available',
    (tester) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final setup = await _setup(
        tester,
        registry: registry,
        topicPluginPayload: const {
          'can_assign': false,
          'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
        },
      );
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final assignment = find.byKey(const Key('assign-topic-header'));
      final touch =
          Theme.of(tester.element(assignment)).platform == TargetPlatform.iOS;
      expect(
        tester.getSize(assignment).width,
        touch ? greaterThanOrEqualTo(48) : lessThanOrEqualTo(40),
      );
      expect(find.bySemanticsLabel('Manage assignment to Sam'), findsOneWidget);
      await tester.tap(assignment);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsOneWidget);
      expect(find.text('Assigned to'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topic-header-browse-category-22')),
      );
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, _child.id);
      expect(shell.currentContent?.topicId, setup.rows.first.id);
      expect(setup.api.topicsUpdated, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );

  for (final (cachedCategory, cachedTopic) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    testWidgets(
      'topic headers resolve the category hierarchy with category cached $cachedCategory and topic cached $cachedTopic',
      (tester) async {
        final setup = await _setup(
          tester,
          listedCategoryId: null,
          categoryList: cachedCategory ? [_child] : [],
          categoryFindResults: const [_parent, _child],
        );
        final shell = setup.controller;
        final row = setup.rows.first;
        final siteUrl = shell.currentInstance!.url;
        if (cachedTopic) {
          final payload = setup.api.topics[row.id]!;
          shell.store.put(siteUrl, payload.detail);
          shell.store.putAll(siteUrl, payload.posts);
        }
        expect(setup.api.categoryIdsRequested, isEmpty);
        shell.openTopicFromList(row);
        await tester.pumpAndSettle();
        expect(setup.api.categoryIdsRequested, [
          if (!cachedCategory) [_child.id],
          [_parent.id],
        ]);
        expect(setup.api.topicsOpened, cachedTopic ? isEmpty : [row.id]);
        final parent = find.byKey(
          const ValueKey('topic-header-compact-parent-category'),
        );
        final child = find.byKey(
          const ValueKey('topic-header-compact-category'),
        );
        expect(
          find.descendant(of: parent, matching: find.text(_parent.name)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: child, matching: find.text(_child.name)),
          findsOneWidget,
        );
        expect(
          tester.getRect(parent).right,
          lessThan(tester.getRect(child).left),
        );
        await _scrollReaderToTop(tester);
        final taxonomy = find.byKey(const ValueKey('topic-header-taxonomy'));
        expect(
          find.descendant(of: taxonomy, matching: find.text(_parent.name)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: taxonomy, matching: find.text(_child.name)),
          findsOneWidget,
        );
        expect(find.text('+ Category'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final canEdit in [true, false]) {
    testWidgets(
      'compact parent browse button keeps the reader with editing $canEdit',
      (tester) async {
        final setup = await _setup(tester, canEditTopic: canEdit);
        final shell = setup.controller;
        shell.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Edit topic category'),
          canEdit ? findsOneWidget : findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('topic-header-browse-category-21')),
        );
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, _parent.id);
        expect(shell.currentContent?.topicId, setup.rows.first.id);
        expect(setup.api.topicsUpdated, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact category names open separate category editors', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final originalList = shell.topicListContent;

    await tester.tap(find.byTooltip('Edit topic category'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topic-category-option-21')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('topic-category-option-22')),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit topic subcategory'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topic-category-option-22')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('topic-category-option-21')),
      findsNothing,
    );
    await tester.tap(find.text('Remove subcategory'));
    await tester.pumpAndSettle();

    expect(shell.currentTopic!.categoryId, _parent.id);
    expect(setup.api.topicsUpdated.single['categoryId'], _parent.id);
    expect(shell.topicListContent, originalList);
    expect(find.byKey(const ValueKey('topic-header-compact')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-header-browse-category-21')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('topic-header-browse-category-22')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final compact in [true, false]) {
    testWidgets('empty header tags offer Add tag in compact mode $compact', (
      tester,
    ) async {
      final setup = await _setup(tester, tags: const []);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      if (!compact) await _scrollReaderToTop(tester);
      final add = find.byKey(const ValueKey('topic-header-edit-tags'));
      expect(
        find.descendant(of: add, matching: find.text('Add tag')),
        findsOneWidget,
      );
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('topic-tag-picker-option', 'community'))),
      );
      await tester.pumpAndSettle();
      expect(shell.currentTopic!.tags, [_tag]);
      expect(setup.api.topicTagsUpdated.single['tags'], [_tag]);
      expect(find.text('Add tag'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scrolling keeps an active title edit until it is saved', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await shell.jumpToCurrentTopicIndex(0);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('topic-header-title-field'));
    await tester.enterText(field, 'Updated coverage plan');
    final list = tester.widget<SuperListView>(
      find.descendant(
        of: find.byType(TopicView),
        matching: find.byType(SuperListView),
      ),
    );
    list.controller!.jumpTo(200);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'Updated coverage plan',
    );
    expect(find.byKey(const ValueKey('topic-header-compact')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(shell.currentTopic!.title, 'Updated coverage plan');
    expect(find.byKey(const ValueKey('topic-header-compact')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final save in [true, false]) {
    testWidgets(
      'compact title click takes focus from another control and ${save ? 'saves on Enter' : 'cancels on Escape'}',
      (tester) async {
        final setup = await _setup(tester);
        final shell = setup.controller;
        shell.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        final originalTitle = shell.currentTopic!.title;
        final compact = find.byKey(const ValueKey('topic-header-compact'));
        final title = find.byKey(const ValueKey('topic-header-compact-title'));
        final field = find.byKey(const ValueKey('topic-header-title-field'));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(FocusScope.of(tester.element(title)).focusedChild, isNotNull);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: tester.getCenter(title));
        await tester.pump();
        await mouse.down(tester.getCenter(title));
        await tester.pump(const Duration(milliseconds: 16));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(compact, findsNothing);
        expect(find.text('Enter to save · Esc to cancel'), findsOneWidget);

        await tester.enterText(field, 'Updated coverage plan');
        await tester.sendKeyEvent(
          save ? LogicalKeyboardKey.enter : LogicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        final expectedTitle = save ? 'Updated coverage plan' : originalTitle;
        expect(shell.currentTopic!.title, expectedTitle);
        expect(compact, findsOneWidget);
        expect(tester.widget<TopicTitle>(title).title, expectedTitle);
        if (save) {
          expect(setup.api.topicsUpdated.single['title'], expectedTitle);
        } else {
          expect(setup.api.topicsUpdated, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('compact titles remain read-only without edit permission', (
    tester,
  ) async {
    final setup = await _setup(tester, canEditTopic: false);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-header-compact-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-header-compact')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-header-title-field')),
      findsNothing,
    );
    expect(setup.api.topicsUpdated, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact tags can be removed and added without expanding', (
    tester,
  ) async {
    final setup = await _setup(tester);
    tester.view.physicalSize = const Size(1500, 800);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final compact = find.byKey(const ValueKey('topic-header-compact'));
    final tag = find.byKey(const ValueKey(('topic-header-tag', 'community')));
    final edit = find.byKey(const ValueKey('topic-header-edit-tags'));
    expect(compact, findsOneWidget);
    expect(tag, findsOneWidget);

    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-tag-picker-option', 'community'))),
    );
    await tester.pumpAndSettle();
    expect(shell.currentTopic!.tags, isEmpty);
    expect(setup.api.topicTagsUpdated.single['tags'], isEmpty);
    expect(tag, findsNothing);
    expect(compact, findsOneWidget);
    expect(find.text('Add tag'), findsOneWidget);

    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-tag-picker-option', 'community'))),
    );
    await tester.pumpAndSettle();
    expect(shell.currentTopic!.tags, [_tag]);
    expect(setup.api.topicTagsUpdated.last['tags'], [_tag]);
    expect(tag, findsOneWidget);
    expect(find.text('Add tag'), findsNothing);
    expect(compact, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final canEditTags in [true, false]) {
    testWidgets(
      'compact tag overflow exposes hidden tags with editing $canEditTags',
      (tester) async {
        final tags = [
          for (var id = 1; id <= 27; id++) TopicTag(id: id, name: 'region-$id'),
        ];
        final setup = await _setup(
          tester,
          tags: tags,
          canEditTags: canEditTags,
        );
        final shell = setup.controller;
        shell.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-header-compact')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('topic-header-more-tags')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(
            ValueKey(
              canEditTags
                  ? 'topic-tag-picker-query'
                  : 'topic-header-tags-search',
            ),
          ),
          'region-27',
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        if (canEditTags) {
          await tester.tap(
            find.byKey(
              const ValueKey(('topic-tag-picker-option', 'region-27')),
            ),
          );
          await tester.pumpAndSettle();
          expect(shell.currentTopic!.tags, hasLength(26));
          expect(
            setup.api.topicTagsUpdated.single['tags'],
            isNot(contains(tags.last)),
          );
          expect(
            find.byKey(const ValueKey('topic-header-compact')),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(const ValueKey('topic-header-edit-tags')),
            findsNothing,
          );
          expect(find.byType(DCheckbox), findsNothing);
          await tester.tap(
            find.byKey(
              const ValueKey(('topic-header-tag-option', 'region-27')),
            ),
          );
          await tester.pumpAndSettle();
          expect(shell.currentContent?.feedPath, '/tag/region-27/27.json');
          expect(setup.api.topicTagsUpdated, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'both header modes keep title first in the centered reading column at desktop widths and zoom levels',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(2200, 800);

      for (final (width, zoom) in [
        (1200.0, AppTextScale.percent100),
        (2000.0, AppTextScale.percent100),
        (2000.0, AppTextScale.percent150),
      ]) {
        await shell.appSettings.setTextScale(zoom);
        Future<void> pumpHeader(bool compact) async {
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: AppTheme.dark,
                home: ContentAlignmentScope(
                  controller: shell.appSettings,
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: TopicInboxHeader(
                          title: shell.currentTopic!.title,
                          siteUrl: shell.currentInstance!.url,
                          canReturnToSidebar: false,
                          keepTopicListOpen: true,
                          registry: PluginRegistry.empty,
                          topic: shell.currentTopic,
                          hasEarlierPosts: compact,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await pumpHeader(false);
        final expandedTitle = tester.getRect(
          find.byKey(const ValueKey('topic-header-title-field')),
        );
        final expandedTaxonomy = tester.getRect(
          find.byKey(const ValueKey('topic-header-taxonomy')),
        );
        expect(expandedTaxonomy.left, closeTo(expandedTitle.left, 1));
        expect(expandedTaxonomy.top, greaterThan(expandedTitle.bottom));
        final close = find.byKey(const ValueKey('topic-close-reader'));
        final share = find.byType(TopicShareButton);
        final closeBefore = tester.getRect(close);
        final shareBefore = tester.getRect(share);

        await pumpHeader(true);
        final header = tester.getRect(
          find.byKey(const ValueKey('topic-content-header')),
        );
        final title = tester.getRect(
          find.byKey(const ValueKey('topic-header-compact-title')),
        );
        final taxonomy = tester.getRect(
          find.byKey(const ValueKey('topic-header-compact-taxonomy')),
        );
        expect(title.center.dx, closeTo(width / 2, 1));
        expect(title.left, closeTo(expandedTitle.left, 1));
        expect(title.right, closeTo(expandedTitle.right, 1));
        expect(taxonomy.left, closeTo(title.left, 1));
        expect(taxonomy.right, closeTo(title.right, 1));
        expect(taxonomy.top - title.bottom, closeTo(8, .1));
        expect(
          header.bottom - taxonomy.bottom,
          closeTo(title.top - header.top, .1),
        );
        expect(
          tester.getRect(find.byTooltip('Edit topic category')).left,
          closeTo(title.left, 1),
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('topic-header-compact-tags')))
              .right,
          lessThanOrEqualTo(taxonomy.right),
        );
        expect(tester.getRect(close), closeBefore);
        expect(tester.getRect(share), shareBefore);
        expect(title.center.dy, closeTo(closeBefore.center.dy, 1));
        expect(tester.takeException(), isNull, reason: '$width, $zoom');
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('compact header fits narrow windows and enlarged text', (
    tester,
  ) async {
    final setup = await _setup(
      tester,
      tags: [
        for (var id = 1; id <= 27; id++)
          TopicTag(id: id, name: 'long-production-region-$id'),
      ],
    );
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    for (final width in [320.0, 520.0, 900.0]) {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: TopicInboxHeader(
                        title:
                            'Customer Support Coverage Week - Seville 🇪🇸 2026',
                        siteUrl: shell.currentInstance!.url,
                        canReturnToSidebar: false,
                        keepTopicListOpen: true,
                        registry: PluginRegistry.empty,
                        topic: shell.currentTopic,
                        hasEarlierPosts: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final header = find.byKey(const ValueKey('topic-content-header'));
        expect(tester.getSize(header).height, greaterThan(shellHeaderHeight));
        final title = find.byKey(const ValueKey('topic-header-compact-title'));
        final category = find.byKey(
          const ValueKey('topic-header-compact-category'),
        );
        final parent = find.byKey(
          const ValueKey('topic-header-compact-parent-category'),
        );
        expect(
          tester.getRect(parent).left,
          closeTo(tester.getRect(title).left, 1),
        );
        expect(
          tester.getRect(parent).right,
          lessThan(tester.getRect(category).left),
        );
        for (final id in [_parent.id, _child.id]) {
          final browse = find.byKey(
            ValueKey('topic-header-browse-category-$id'),
          );
          expect(browse.hitTestable(), findsOneWidget);
          expect(tester.getSize(browse).width, 25);
        }
        expect(tester.getRect(title).right, lessThan(width));
        final tags = find.byKey(const ValueKey('topic-header-compact-tags'));
        final overflow = find.byKey(const ValueKey('topic-header-more-tags'));
        expect(overflow, findsOneWidget);
        expect(tester.getSize(overflow).width, greaterThanOrEqualTo(28));
        expect(
          tester.getRect(category).right,
          lessThan(tester.getRect(tags).left),
        );
        expect(tester.getRect(tags).right, lessThan(width));
        expect(
          tester.getCenter(tags).dy,
          closeTo(tester.getCenter(category).dy, 1),
        );
        expect(
          tester.getRect(tags).top,
          greaterThan(tester.getRect(title).bottom),
        );
        for (final key in ['topic-close-reader', 'topic-status-button']) {
          expect(
            tester.getCenter(find.byKey(ValueKey(key))).dy,
            closeTo(tester.getCenter(title).dy, 1),
          );
        }
        expect(
          tester.getRect(tags).bottom,
          lessThan(tester.getRect(header).bottom),
        );
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
    }
  });

  testWidgets(
    'narrow toolbar categories can be browsed without edit permission',
    (tester) async {
      final setup = await _setup(tester, canEditTopic: false);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: TopicInboxHeader(
                    title: shell.currentTopic!.title,
                    siteUrl: shell.currentInstance!.url,
                    canReturnToSidebar: false,
                    keepTopicListOpen: true,
                    registry: PluginRegistry.empty,
                    topic: shell.currentTopic,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Browse ${_child.name}'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, _child.id);
      expect(shell.currentContent?.topicId, setup.rows.first.id);
      expect(setup.api.topicsUpdated, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'header rows keep category and tags accessible as space shrinks',
    (tester) async {
      final tags = [
        for (final name in ['a', 'b', 'c', 'd', 'e', 'f']) TopicTag(name: name),
      ];
      final setup = await _setup(tester, tags: tags);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1400, 800);

      for (final compact in [false, true]) {
        var wideTagCount = 0;
        for (final (width, navigation, share) in [
          (1200.0, true, true),
          (780.0, true, true),
          (600.0, false, true),
          (390.0, false, false),
        ]) {
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: TopicInboxHeader(
                        title: shell.currentTopic!.title,
                        siteUrl: shell.currentInstance!.url,
                        canReturnToSidebar: false,
                        keepTopicListOpen: true,
                        registry: PluginRegistry.empty,
                        topic: shell.currentTopic,
                        hasEarlierPosts: compact,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final close = find.byKey(const ValueKey('topic-close-reader'));
          final category = compact
              ? find.byKey(const ValueKey('topic-header-compact-category'))
              : find.byTooltip('Edit topic category');
          final overflow = find.byKey(const ValueKey('topic-header-more-tags'));
          final status = find.byKey(const ValueKey('topic-status-button'));
          expect(
            tester.getRect(close).right,
            lessThan(tester.getRect(category).left),
          );
          expect(
            tester.getRect(category).right,
            lessThan(tester.getRect(overflow).left),
          );
          expect(
            tester.getCenter(category).dy,
            closeTo(tester.getCenter(overflow).dy, 1),
          );
          final title = find.byKey(
            ValueKey(
              compact
                  ? 'topic-header-compact-title'
                  : 'topic-header-title-field',
            ),
          );
          final parent = compact
              ? find.byKey(
                  const ValueKey('topic-header-compact-parent-category'),
                )
              : category;
          expect(
            tester.getRect(category).overlaps(tester.getRect(close)),
            isFalse,
          );
          expect(
            tester.getRect(overflow).overlaps(tester.getRect(status)),
            isFalse,
          );
          expect(
            tester.getRect(category).top,
            greaterThan(tester.getRect(title).bottom),
          );
          expect(
            tester.getRect(parent).left,
            closeTo(tester.getRect(title).left, 1),
          );
          expect(
            tester.getRect(title).right,
            lessThan(tester.getRect(status).left),
          );
          if (!compact) {
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('topic-header-activity')))
                  .top,
              greaterThan(tester.getRect(category).bottom),
            );
          }
          for (final control in [status, title]) {
            expect(
              tester.getCenter(control).dy,
              closeTo(tester.getCenter(close).dy, 1),
            );
          }
          expect(
            find.byKey(const ValueKey('inbox-previous-topic')),
            navigation ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('inbox-next-topic')),
            navigation ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(TopicShareButton),
            share ? findsOneWidget : findsNothing,
          );
          final visibleTags = tags
              .where(
                (tag) => find
                    .byKey(ValueKey(('topic-header-tag', tag.name)))
                    .evaluate()
                    .isNotEmpty,
              )
              .length;
          if (width == 1200) {
            wideTagCount = visibleTags;
            expect(wideTagCount, greaterThan(0));
          } else if (width == 390) {
            expect(visibleTags, lessThan(wideTagCount));
          }
          expect(
            tester.takeException(),
            isNull,
            reason: 'width $width, compact $compact',
          );
        }
      }
    },
  );

  for (final dark in [false, true]) {
    testWidgets('inbox read colors and badges follow web topic state ($dark)', (
      tester,
    ) async {
      final setup = await _setup(tester);
      final siteUrl = setup.controller.currentInstance!.url;
      final theme = dark ? AppTheme.dark : AppTheme.light;
      const scenarios = [
        (
          name: 'Caught up',
          fields: {'last_read_post_number': 5},
          read: true,
          count: 0,
          dot: null,
        ),
        (
          name: 'Deleted final post',
          fields: {'last_read_post_number': 6},
          read: true,
          count: 0,
          dot: null,
        ),
        (
          name: 'Untracked unread topic',
          fields: {'last_read_post_number': 4},
          read: false,
          count: 0,
          dot: null,
        ),
        (
          name: 'Unknown read position',
          fields: <String, Object>{},
          read: false,
          count: 0,
          dot: null,
        ),
        (
          name: 'Tracked unread posts',
          fields: {
            'last_read_post_number': 2,
            'unread_posts': 3,
            'new_posts': 3,
          },
          read: false,
          count: 3,
          dot: null,
        ),
        (
          name: 'Legacy unread count',
          fields: {'last_read_post_number': 2, 'new_posts': 3},
          read: false,
          count: 3,
          dot: null,
        ),
        (
          name: 'New topic',
          fields: {'unseen': true},
          read: false,
          count: 0,
          dot: 'new-topic-dot',
        ),
        (
          name: 'Nested replies',
          fields: {
            'is_nested_view': true,
            'has_new_replies': true,
            'unseen': true,
            'unread_posts': 3,
          },
          read: false,
          count: 0,
          dot: 'new-replies-dot',
        ),
      ];
      for (final scenario in scenarios) {
        final topic = Topic.fromJson(
          {
            'id': 101,
            'title': scenario.name,
            'slug': 'read-state',
            'highest_post_number': 5,
            'posts_count': 5,
            'reply_count': 2,
            ...scenario.fields,
          },
          const {},
          siteUrl,
        );
        await tester.pumpWidget(
          ShellScope(
            controller: setup.controller,
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 304,
                    child: TopicInboxRow(
                      topic: topic,
                      siteUrl: siteUrl,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.widget<TopicTitle>(find.byType(TopicTitle));
        expect(
          title.style?.color,
          scenario.read
              ? Color.lerp(
                  theme.discourse.whisper,
                  theme.colorScheme.onSurface,
                  .25,
                )
              : theme.colorScheme.onSurface,
          reason: scenario.name,
        );
        expect(
          find.text('4'),
          findsOneWidget,
          reason: 'Total replies: ${scenario.name}',
        );
        expect(
          find.byType(TopicUnreadBadge),
          scenario.count > 0 ? findsOneWidget : findsNothing,
          reason: scenario.name,
        );
        if (scenario.count > 0) {
          expect(find.text('${scenario.count}'), findsOneWidget);
          expect(
            find.byTooltip('${scenario.count} unread posts'),
            findsOneWidget,
          );
          expect(find.text('6'), findsNothing);
        }
        expect(
          find.byKey(const ValueKey('new-topic-dot')),
          scenario.dot == 'new-topic-dot' ? findsOneWidget : findsNothing,
          reason: scenario.name,
        );
        expect(
          find.byKey(const ValueKey('new-replies-dot')),
          scenario.dot == 'new-replies-dot' ? findsOneWidget : findsNothing,
          reason: scenario.name,
        );
        expect(tester.takeException(), isNull, reason: scenario.name);
      }
    });
  }

  testWidgets(
    'retained inbox updates read colors and counts as activity changes',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      final siteUrl = shell.currentInstance!.url;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('inbox-row-1'));
      final badge = find.byKey(const ValueKey('inbox-row-unread-1'));
      final listState = tester.state(find.byType(TopicListView).first);
      final theme = Theme.of(tester.element(row));
      Color? titleColor() => tester
          .widget<TopicTitle>(
            find.descendant(of: row, matching: find.byType(TopicTitle)),
          )
          .style
          ?.color;
      expect(badge, findsOneWidget);
      expect(titleColor(), theme.colorScheme.onSurface);

      await shell.markTopicRead(siteUrl, 1, 3, caughtUp: false);
      await tester.pumpAndSettle();
      expect(badge, findsOneWidget);
      expect(titleColor(), theme.colorScheme.onSurface);

      await shell.markTopicRead(siteUrl, 1, 4, caughtUp: true);
      await tester.pumpAndSettle();
      expect(badge, findsNothing);
      expect(
        titleColor(),
        Color.lerp(theme.discourse.whisper, theme.colorScheme.onSurface, .25),
      );
      expect(shell.currentContent?.topicId, 1);

      shell.store.put(
        siteUrl,
        const Topic(
          id: 1,
          title: 'Topic 1',
          slug: 'topic-1',
          highestPostNumber: 6,
          lastReadPostNumber: 4,
          unreadPosts: 2,
          replyCount: 5,
        ),
      );
      await tester.pumpAndSettle();
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('2')),
        findsOneWidget,
      );
      expect(titleColor(), theme.colorScheme.onSurface);
      expect(tester.state(find.byType(TopicListView).first), same(listState));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unread badge stays visible and opens the topic at large text', (
    tester,
  ) async {
    final setup = await _setup(tester);
    var opened = false;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: setup.controller,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 304,
                    child: TopicInboxRow(
                      topic: Topic(
                        id: 101,
                        title:
                            'A long topic title that needs to wrap beside its unread badge',
                        slug: 'long-topic',
                        unreadPosts: 128,
                        replyCount: 200,
                        bumpedAt: DateTime.now().subtract(
                          const Duration(days: 12),
                        ),
                      ),
                      siteUrl: setup.controller.currentInstance!.url,
                      onTap: () => opened = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final badge = find.byType(TopicUnreadBadge);
      final badgeRect = tester.getRect(badge);
      final timeRect = tester.getRect(
        find.byKey(const ValueKey('inbox-row-time-101')),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'\b128 unread posts\b')),
        findsOneWidget,
      );
      expect(find.text('200'), findsOneWidget);
      expect(badgeRect.right, lessThan(timeRect.left));
      expect(timeRect.right, lessThan(304));
      await tester.tap(badge);
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('wide reader aligns title, taxonomy, activity, and post text', (
    tester,
  ) async {
    final state = ValueNotifier('Available');
    addTearDown(state.dispose);
    final setup = await _setup(
      tester,
      registry: PluginRegistry([_HeaderDetailsPlugin(state)]),
    );
    tester.view.physicalSize = const Size(2000, 800);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await _scrollReaderToTop(tester);
    final parent = tester.getRect(find.byTooltip('Edit topic category'));
    final child = tester.getRect(find.byTooltip('Edit topic subcategory'));
    final tag = tester.getRect(
      find.byKey(const ValueKey(('topic-header-tag', 'community'))),
    );
    final editTags = find.byKey(const ValueKey('topic-header-edit-tags'));
    final editTagRect = tester.getRect(editTags);
    expect(
      tester
          .widget<DIcon>(
            find.descendant(of: editTags, matching: find.byType(DIcon)),
          )
          .icon,
      DIcons.pencil,
    );
    expect(parent.right, lessThan(child.left));
    expect(child.right, lessThan(tag.left));
    expect(tag.right, lessThan(editTagRect.left));
    expect(parent.center.dy, closeTo(tag.center.dy, 1));
    expect(child.center.dy, closeTo(tag.center.dy, 1));
    final title = tester.getRect(
      find.byKey(const ValueKey('topic-header-title-field')),
    );
    final summary = tester.getRect(
      find.byKey(const ValueKey('topic-header-activity')),
    );
    final properties = tester.getRect(find.text('Manage details'));
    expect(parent.left, closeTo(title.left, 1));
    expect(parent.top, greaterThan(title.bottom));
    expect(summary.left, closeTo(title.left, 1));
    expect(summary.top, greaterThan(parent.bottom));
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'header closed status updates from topic actions without moving the title',
    (tester) async {
      final setup = await _setup(tester, canCloseTopic: true);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      await _scrollReaderToTop(tester);
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      final badge = find.byKey(const ValueKey('topic-header-closed'));
      final titleRect = tester.getRect(title);
      expect(badge, findsNothing);

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-status-closed')));
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.closed, isTrue);
      expect(find.text('Closed'), findsOneWidget);
      expect(badge, findsOneWidget);
      expect(tester.getRect(title), titleRect);
      expect(tester.getRect(badge).top, greaterThan(titleRect.bottom));
      expect(tester.getRect(badge).left, closeTo(titleRect.left, 1));

      await tester.tap(title);
      await tester.pump();
      final frame = find.byKey(const ValueKey('topic-header-title-edit-frame'));
      expect(frame, findsOneWidget);
      expect(
        tester.getRect(badge).top,
        greaterThan(tester.getRect(frame).bottom),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      expect(find.text('Open topic'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-status-closed')));
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.closed, isFalse);
      expect(badge, findsNothing);
      expect(tester.getRect(title), titleRect);
      expect(setup.api.topicStatusesUpdated, const [
        (topicId: 1, status: TopicStatusProperty.closed, enabled: true),
        (topicId: 1, status: TopicStatusProperty.closed, enabled: false),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closed status is readable in narrow headers without edit permissions',
    (tester) async {
      final setup = await _setup(tester, closed: true, canEditTopic: false);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      try {
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          for (final width in [320.0, 420.0]) {
            await tester.pumpWidget(
              ShellScope(
                controller: shell,
                child: MaterialApp(
                  theme: theme,
                  home: Scaffold(
                    body: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(2),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: width,
                          child: TopicInboxHeader(
                            title: shell.currentTopic!.title,
                            siteUrl: shell.currentInstance!.url,
                            canReturnToSidebar: false,
                            keepTopicListOpen: false,
                            registry: PluginRegistry.empty,
                            topic: shell.currentTopic,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final badge = find.byKey(const ValueKey('topic-header-closed'));
            expect(find.text('Closed'), findsOneWidget);
            expect(find.bySemanticsLabel('Topic closed'), findsOneWidget);
            expect(find.byType(InlineTopicTitleEditor), findsNothing);
            final rect = tester.getRect(badge);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThan(width));
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        semantics.dispose();
      }
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
      await _scrollReaderToTop(tester);
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

  for (final (canEditTags, newTab) in [
    (true, false),
    (true, true),
    (false, false),
    (false, true),
  ]) {
    for (final privateMessage in [false, true]) {
      testWidgets(
        'header tags navigate with editing $canEditTags, private messages $privateMessage, and new tab $newTab',
        (tester) async {
          final setup = await _setup(
            tester,
            canEditTags: canEditTags,
            privateMessage: privateMessage,
          );
          final shell = setup.controller;
          shell.openTopicFromList(setup.rows.first);
          await tester.pumpAndSettle();
          await _scrollReaderToTop(tester);
          final originalTab = shell.activeTab;

          await tester.tap(
            find.byKey(const ValueKey(('topic-header-tag', 'community'))),
            kind: PointerDeviceKind.mouse,
            buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
          );
          await tester.pumpAndSettle();

          final path = privateMessage
              ? '/topics/private-messages-tags/sam/community.json'
              : '/tag/community/1.json';
          if (newTab) {
            expect(shell.activeTab, originalTab);
            expect(shell.tabsForCurrentForum, hasLength(2));
            expect(
              shell.tabsForCurrentForum.last.currentContent.feedPath,
              path,
            );
          } else {
            expect(shell.currentContent?.feedPath, path);
            expect(setup.api.feedPaths, contains(path));
          }
          expect(
            find.byKey(const ValueKey('topic-tag-picker-query')),
            findsNothing,
          );
          expect(setup.api.topicTagsUpdated, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'collapsed tags navigate without saving with editing $canEditTags and new tab $newTab',
      (tester) async {
        final tags = [
          for (var id = 1; id <= 27; id++) TopicTag(id: id, name: 'region-$id'),
        ];
        final setup = await _setup(
          tester,
          tags: tags,
          canEditTags: canEditTags,
        );
        final shell = setup.controller;
        shell.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        await _scrollReaderToTop(tester);
        final originalTab = shell.activeTab;

        expect(
          find.byKey(const ValueKey(('topic-header-tag', 'region-27'))),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('topic-header-more-tags')));
        await tester.pumpAndSettle();
        final query = find.byKey(
          ValueKey(
            canEditTags ? 'topic-tag-picker-query' : 'topic-header-tags-search',
          ),
        );
        await tester.enterText(query, 'REGION-27');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        await tester.tap(
          find.byKey(
            ValueKey((
              canEditTags ? 'topic-tag-picker-open' : 'topic-header-tag-option',
              'region-27',
            )),
          ),
          kind: PointerDeviceKind.mouse,
          buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
        );
        await tester.pumpAndSettle();

        if (newTab) {
          expect(shell.activeTab, originalTab);
          expect(shell.tabsForCurrentForum, hasLength(2));
          expect(
            shell.tabsForCurrentForum.last.currentContent.feedPath,
            '/tag/region-27/27.json',
          );
        } else {
          expect(shell.currentContent?.feedPath, '/tag/region-27/27.json');
          expect(setup.api.feedPaths, contains('/tag/region-27/27.json'));
        }
        expect(query, findsNothing);
        expect(setup.api.topicTagsUpdated, isEmpty);
        expect(
          shell.store.read<TopicDetail>(shell.currentInstance!.url, 1)?.tags,
          tags,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (category, compact) in [
    for (final category in [_parent, _child])
      for (final compact in [false, true]) (category, compact),
  ]) {
    testWidgets(
      'middle-click opens the ${category.name} category arrow in a background tab with compact mode $compact',
      (tester) async {
        final setup = await _setup(tester);
        final shell = setup.controller;
        shell.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        if (!compact) await _scrollReaderToTop(tester);
        final originalTab = shell.activeTab;

        await tester.tap(
          find.byKey(ValueKey('topic-header-browse-category-${category.id}')),
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await tester.pumpAndSettle();

        expect(shell.activeTab, originalTab);
        expect(shell.tabsForCurrentForum, hasLength(2));
        expect(
          shell.tabsForCurrentForum.last.currentContent.categoryId,
          category.id,
        );
        expect(setup.api.topicsUpdated, isEmpty);
        expect(
          find.byKey(const ValueKey('topic-category-picker-query')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('read-only topics still expose every collapsed tag', (
    tester,
  ) async {
    final tags = [
      for (var id = 1; id <= 27; id++) TopicTag(id: id, name: 'region-$id'),
    ];
    final setup = await _setup(tester, tags: tags, canEditTags: false);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await _scrollReaderToTop(tester);
    expect(find.byKey(const ValueKey('topic-header-edit-tags')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('topic-header-more-tags')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-header-tags-search')),
      'REGION-27',
    );
    await tester.pumpAndSettle();
    expect(find.text('# region-27'), findsOneWidget);
    expect(find.byType(DCheckbox), findsNothing);
    expect(setup.api.topicTagsUpdated, isEmpty);
    expect(setup.controller.currentTopic!.tags, hasLength(27));
    expect(tester.takeException(), isNull);
  });

  testWidgets('private category chips fit across narrow header widths', (
    tester,
  ) async {
    final setup = await _setup(
      tester,
      categoryList: [
        for (final category in [_parent, _child])
          TopicCategory(
            id: category.id,
            name: category.name,
            color: category.color,
            parentCategoryId: category.parentCategoryId,
            styleType: 'icon',
            icon: 'folder',
            readRestricted: true,
          ),
      ],
    );
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();

    for (final width in [320.0, 390.0, 400.0, 420.0, 440.0, 520.0, 900.0]) {
      for (final textScale in [1.0, 2.0]) {
        await tester.pumpWidget(
          ShellScope(
            controller: setup.controller,
            child: MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
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
        expect(
          tester.takeException(),
          isNull,
          reason: 'reader width $width at text scale $textScale',
        );
        for (final tooltip in [
          'Edit topic category',
          'Edit topic subcategory',
        ]) {
          final category = find.byTooltip(tooltip);
          expect(category.hitTestable(), findsOneWidget);
          final lock = find.descendant(
            of: category,
            matching: find.byWidgetPredicate(
              (widget) => widget is DIcon && widget.icon == DIcons.lock,
            ),
          );
          expect(lock, findsOneWidget);
          final categoryRect = tester.getRect(category);
          final lockRect = tester.getRect(lock);
          expect(lockRect.left, greaterThanOrEqualTo(categoryRect.left));
          expect(lockRect.right, lessThanOrEqualTo(categoryRect.right));
        }
      }
    }
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
                        title:
                            'Customer Support Coverage Week - Seville 🇪🇸 2026',
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
        for (final tooltip in [
          'Edit topic category',
          'Edit topic subcategory',
        ]) {
          final category = find.byTooltip(tooltip);
          expect(category, findsOneWidget);
          expect(
            tester.getCenter(category).dy,
            closeTo(tester.getCenter(overflow).dy, 1),
          );
        }
        final title = find.byKey(const ValueKey('topic-header-title-field'));
        final titleRect = tester.getRect(title);
        expect(tester.getRect(overflow).top, greaterThan(titleRect.bottom));
        expect(
          tester.getRect(find.byTooltip('Edit topic category')).left,
          closeTo(titleRect.left, 1),
        );
        expect(tester.getRect(overflow).right, lessThan(width));
        await tester.tap(title);
        await tester.pumpAndSettle();
        final frame = tester.getRect(
          find.byKey(const ValueKey('topic-header-title-edit-frame')),
        );
        expect(
          frame.top,
          greaterThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('topic-content-header')))
                .top,
          ),
        );
        expect(tester.getRect(overflow).top, greaterThan(frame.bottom));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
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
        closeTo(
          tester
              .getCenter(find.byKey(const ValueKey('inbox-row-replies-1')))
              .dy,
          1,
        ),
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

  testWidgets('recommendations appear below posts and keep the source list', (
    tester,
  ) async {
    final setup = await _setup(tester, recommendations: true);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final listState = tester.state(find.byType(TopicListView));
    expect(find.byKey(const ValueKey('topic-more-topics-jump')), findsNothing);
    final footer = find.byKey(const ValueKey('topic-bottom-bar'));
    expect(
      find.descendant(of: footer, matching: find.text('Related / Suggested')),
      findsNothing,
    );
    expect(
      find.descendant(of: footer, matching: find.text('More topics')),
      findsNothing,
    );
    final recommendations = find.byWidgetPredicate(
      (widget) => widget is TopicInboxRow && widget.recommendation,
    );
    await tester.scrollUntilVisible(
      recommendations,
      500,
      scrollable: find.descendant(
        of: find.descendant(
          of: find.byType(TopicView),
          matching: find.byType(SuperListView),
        ),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
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

  testWidgets('omits the recommendation section when none are available', (
    tester,
  ) async {
    final setup = await _setup(tester);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey(('post-footer-action', 4, 'Reply'))),
      500,
      scrollable: find.descendant(
        of: find.descendant(
          of: find.byType(TopicView),
          matching: find.byType(SuperListView),
        ),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-more-topics-jump')), findsNothing);
    expect(find.text('Suggested'), findsNothing);
    expect(find.text('Related'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is TopicInboxRow && widget.recommendation,
      ),
      findsNothing,
    );
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
    await _scrollReaderToTop(tester);
    await tester.tap(find.text('Manage details'));
    await tester.pumpAndSettle();
    expect(find.byType(DPopoverContent), findsOneWidget);
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
    expect(find.byType(DPopoverContent), findsNothing);
    expect(find.text('Details: Updated topic · Saving'), findsNothing);
    expect(shell.currentContent?.topicId, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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

      await tester.tap(find.byTooltip('Collapse topic'));
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
      final heading = find.byKey(const ValueKey('topic-list-title'));
      expect(tester.widget<Text>(heading).data, 'Topics');
      shell.selectTopicListCategory(_child, keepTopicOpen: true);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(heading).data, _child.name);
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
      expect(tester.widget<Text>(heading).data, _child.name);
      expect(tester.state(find.byType(TopicView)), same(readerState));
      expect(find.text('Clear all'), findsNothing);
      expect(find.text('Tags · 2'), findsOneWidget);

      shell.browseTopicCategory(_parent, keepTopicOpen: true);
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, 21);
      expect(tester.widget<Text>(heading).data, _parent.name);
      expect(shell.topicListContent?.tagNames, isEmpty);
      expect(shell.currentContent?.topicId, 1);
      await tester.tap(find.byTooltip('Collapse topic'));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.categoryId, 21);
      expect(tester.widget<Text>(heading).data, _parent.name);
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
      await _scrollReaderToTop(tester);
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      final frame = find.byKey(const ValueKey('topic-header-title-edit-frame'));
      final hint = find.text('Enter to save · Esc to cancel');
      expect(frame, findsNothing);
      expect(hint, findsNothing);
      await tester.tap(title);
      await tester.pump();
      expect(frame, findsOneWidget);
      expect(hint, findsOneWidget);
      await tester.enterText(title, 'A clearer topic title');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.title, 'A clearer topic title');
      expect(setup.api.topicsUpdated.last['title'], 'A clearer topic title');
      expect(frame, findsNothing);
      expect(hint, findsNothing);
      await tester.tap(title);
      await tester.enterText(title, 'Discard this title');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.title, 'A clearer topic title');
      expect(setup.api.topicsUpdated, hasLength(1));
      expect(frame, findsNothing);
      expect(hint, findsNothing);

      await tester.tap(find.byTooltip('Edit topic subcategory'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-category-remove')));
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.categoryId, _parent.id);
      expect(find.text('Done'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('topic-header-edit-tags')));
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
    final edit = find.byKey(const ValueKey(('post-footer-action', 2, 'Edit')));
    final bookmark = find.byKey(
      const ValueKey(('post-footer-action', 2, 'Bookmark')),
    );
    expect(reply, findsOneWidget);
    await tester.ensureVisible(reply);
    await tester.pumpAndSettle();
    expect(reply.hitTestable(), findsOneWidget);
    final body = find.byWidgetPredicate(
      (widget) => widget is CookedHtml && widget.post?.postNumber == 2,
    );
    expect(tester.getRect(reply).top, greaterThan(tester.getRect(body).bottom));
    expect(edit.hitTestable(), findsOneWidget);
    expect(
      find.descendant(of: edit, matching: find.text('Edit')),
      findsNothing,
    );
    expect(tester.getRect(edit).left, tester.getRect(reply).right);
    expect(
      tester.getRect(edit).center.dy,
      closeTo(tester.getRect(reply).center.dy, 1),
    );
    expect(bookmark.hitTestable(), findsOneWidget);
    expect(tester.getRect(bookmark).left, tester.getRect(edit).right);
    expect(
      tester.getRect(bookmark).center.dy,
      closeTo(tester.getRect(reply).center.dy, 1),
    );
    expect(
      tester.getRect(bookmark).right,
      closeTo(tester.getRect(body).right, 1),
    );

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
    expect(
      find.byKey(const ValueKey(('post-footer-action', 2, 'Bookmark'))),
      findsOneWidget,
    );
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
      expect(find.widgetWithText(MenuItemButton, 'Edit'), findsNothing);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.widgetWithText(MenuItemButton, 'Bookmark'), findsNothing);
      expect(
        find.widgetWithText(MenuItemButton, 'Edit bookmark'),
        findsNothing,
      );
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
      await _scrollReaderToTop(tester);
      final editScroll = tester
          .widget<SuperListView>(
            find.descendant(of: reader, matching: find.byType(SuperListView)),
          )
          .controller!;
      final editOffset = editScroll.offset;
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      await tester.tap(title);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      expect(editScroll.offset, closeTo(editOffset, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _scrollReaderToTop(WidgetTester tester) async {
  final shell = ShellScope.read(tester.element(find.byType(TopicView)));
  await shell.jumpToCurrentTopicIndex(0);
  await tester.pumpAndSettle();
}

Future<({ShellController controller, FakeDiscourseApi api, List<Topic> rows})>
_setup(
  WidgetTester tester, {
  PluginRegistry registry = PluginRegistry.empty,
  bool recommendations = false,
  List<TopicParticipant> participants = const [
    TopicParticipant(username: 'sam', name: 'Sam'),
  ],
  List<TopicTag> tags = const [_tag],
  bool canEditTags = true,
  bool privateMessage = false,
  bool canCreatePost = true,
  bool closed = false,
  bool canCloseTopic = false,
  bool canEditTopic = true,
  Map<String, dynamic> topicPluginPayload = const {},
  String? firstTopicTitle,
  int? listedCategoryId = 22,
  List<TopicCategory> categoryList = const [_parent, _child],
  List<TopicCategory> categoryFindResults = const [],
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
        title: id == 1 && firstTopicTitle != null
            ? firstTopicTitle
            : 'Topic $id',
        slug: 'topic-$id',
        categoryId: listedCategoryId,
        privateMessage: privateMessage,
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
    categoryList: categoryList,
    categoryFindResults: categoryFindResults,
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
            participants: participants,
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
            closed: closed,
            canCloseTopic: canCloseTopic,
            canEdit: canEditTopic,
            canEditTags: canEditTags,
            privateMessage: privateMessage,
            tags: tags,
            canCreatePost: canCreatePost,
            plugins: registry.readTopic(topicPluginPayload, site.url),
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
