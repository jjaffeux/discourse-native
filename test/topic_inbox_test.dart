import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
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
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/shell/topic_inbox_row.dart';
import 'package:discourse_native/src/shell/topic_list_indicators.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/button_surface.dart';
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
  testWidgets('open topic selection follows the reader', (tester) async {
    final setup = await _setup(tester);
    DItem card(int id) =>
        tester.widget<DItem>(find.byKey(ValueKey('topic-card-$id')));
    expect(card(setup.rows.first.id).selected, isFalse);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    expect(card(setup.rows.first.id).selected, isTrue);
    expect(card(setup.rows[1].id).selected, isFalse);
    setup.controller.openTopicFromList(setup.rows[1]);
    await tester.pumpAndSettle();
    expect(card(setup.rows.first.id).selected, isFalse);
    expect(card(setup.rows[1].id).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapse action belongs to the open topic list header', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final close = find.byKey(const ValueKey('topic-close-reader'));
    expect(close, findsNothing);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final listPane = find.byKey(const ValueKey('inbox-topic-list-pane'));
    expect(find.descendant(of: listPane, matching: close), findsOneWidget);
    expect(
      find.descendant(of: find.byType(TopicInboxHeader), matching: close),
      findsNothing,
    );
    final bounds = tester.getRect(close);
    final pane = tester.getRect(listPane);
    expect(
      bounds.right,
      closeTo(
        pane.right -
            DResizableHandle.resolveHitExtent(tester.element(close), 8),
        1,
      ),
    );
    expect(
      bounds.center.dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('topic-list-heading'))).dy,
        1,
      ),
    );
    expect(close.hitTestable(), findsOneWidget);
    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(TopicInboxHeader), matching: close),
      findsOneWidget,
    );
    expect(close.hitTestable(), findsOneWidget);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.descendant(of: listPane, matching: close), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(close, findsNothing);
    expect(find.byType(TopicView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ledger category rail fills the header beside quiet metadata', (
    tester,
  ) async {
    final setup = await _setup(tester, tags: const []);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final header = tester.getRect(
      find.byKey(const ValueKey('topic-content-header')),
    );
    final rail = tester.getRect(
      find.byKey(const ValueKey('topic-header-category-rail')),
    );
    expect(rail.left, header.left);
    expect(rail.top, header.top);
    expect(rail.bottom, closeTo(header.bottom, 1));
    expect(rail.width, lessThanOrEqualTo(160));
    expect(tester.widget<TopicTitle>(_compactHeader).style?.fontSize, 16);
    expect(find.byKey(const ValueKey('topic-header-edit')), findsNothing);
    expect(find.text('Add tag'), findsNothing);
    expect(find.byTooltip('Add tag'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ledger context stays fixed and preserves the scrolling reader', (
    tester,
  ) async {
    final tags = [
      for (var id = 1; id <= 7; id++) TopicTag(id: id, name: 'region-$id'),
    ];
    final setup = await _setup(tester, tags: tags);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await _scrollReaderToTop(tester);
    final header = find.byKey(const ValueKey('topic-content-header'));
    final category = find.byKey(const ValueKey('topic-header-category'));
    final taxonomy = find.byKey(const ValueKey('topic-header-taxonomy'));
    final bounds = [
      tester.getRect(header),
      tester.getRect(category),
      tester.getRect(taxonomy),
      tester.getRect(_compactHeader),
    ];
    final reader = tester.state(find.byType(TopicView));
    final scroll = _readerScroll(tester);
    for (final offset in [0.0, 180.0, 450.0, 20.0]) {
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
      expect([
        tester.getRect(header),
        tester.getRect(category),
        tester.getRect(taxonomy),
        tester.getRect(_compactHeader),
      ], bounds);
      expect(tester.state(find.byType(TopicView)), same(reader));
      for (final tag in tags) {
        expect(
          find.byKey(ValueKey(('topic-header-tag', tag.name))).hitTestable(),
          findsOneWidget,
        );
      }
    }
    expect(find.byKey(const ValueKey('topic-header-more-tags')), findsNothing);
    expect(find.byKey(const ValueKey('topic-header-activity')), findsNothing);
    expect(find.text('Switch topic'), findsNothing);
    expect(
      find.descendant(of: header, matching: find.byType(EditableText)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (cachedCategory, cachedTopic) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    testWidgets(
      'ledger loads the whole category path with caches $cachedCategory / $cachedTopic',
      (tester) async {
        final setup = await _setup(
          tester,
          listedCategoryId: null,
          categoryList: cachedCategory ? [_child] : [],
          categoryFindResults: const [_parent, _child],
        );
        final shell = setup.controller;
        if (cachedTopic) {
          final payload = setup.api.topics[1]!;
          shell.store.put(shell.currentInstance!.url, payload.detail);
          shell.store.putAll(shell.currentInstance!.url, payload.posts);
        }
        shell.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        final category = find.byKey(const ValueKey('topic-header-category'));
        expect(
          find.descendant(of: category, matching: find.text('Design')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: category, matching: find.text('Onboarding')),
          findsOneWidget,
        );
        expect(setup.api.categoryIdsRequested, [
          if (!cachedCategory) [_child.id],
          [_parent.id],
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ledger adapts without hiding taxonomy at narrow widths, RTL and large text',
    (tester) async {
      final tags = [
        for (var id = 1; id <= 7; id++) TopicTag(id: id, name: 'region-$id'),
      ];
      final setup = await _setup(tester, tags: tags);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final topic = setup.controller.currentTopic!;
      for (final width in [320.0, 420.0, 700.0, 1100.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final direction in TextDirection.values) {
            await tester.pumpWidget(
              ShellScope(
                controller: setup.controller,
                child: MaterialApp(
                  theme: AppTheme.dark,
                  home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                      textDirection: direction,
                      child: Scaffold(
                        body: SingleChildScrollView(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: width,
                              child: TopicInboxHeader(
                                title:
                                    'Customer setup with a long title that wraps naturally',
                                siteUrl: setup.controller.currentInstance!.url,
                                canReturnToSidebar: true,
                                keepTopicListOpen: true,
                                registry: PluginRegistry.empty,
                                topic: topic,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final category = tester.getRect(
              find.byKey(const ValueKey('topic-header-category')),
            );
            final title = tester.getRect(_compactHeader);
            if (width < 540 * scale) {
              expect(category.bottom, lessThanOrEqualTo(title.top));
            } else if (direction == TextDirection.ltr) {
              expect(category.right, lessThan(title.left));
            } else {
              expect(category.left, greaterThan(title.right));
            }
            for (final tag in tags) {
              final bounds = tester.getRect(
                find.byKey(ValueKey(('topic-header-tag', tag.name))),
              );
              expect(bounds.left, greaterThanOrEqualTo(0));
              expect(bounds.right, lessThanOrEqualTo(width));
            }
            expect(
              find.byKey(const ValueKey('topic-close-reader')),
              findsNothing,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$width / $scale / $direction',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'a crowded header stays reachable in a short window without displacing the reader',
    (tester) async {
      final tags = [
        for (var id = 1; id <= 27; id++)
          TopicTag(id: id, name: 'production-region-$id'),
      ];
      final setup = await _setup(tester, tags: tags);
      tester.view.physicalSize = const Size(390, 500);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final headerScroll = find.descendant(
        of: find.byType(TopicInboxHeader),
        matching: find.byType(DScrollArea),
      );
      final headerBounds = tester.getRect(headerScroll);
      final viewport = find.descendant(
        of: find.byType(TopicView),
        matching: find.byType(CustomScrollView),
      );
      expect(tester.getSize(viewport).height, greaterThan(100));
      final last = find.byKey(
        const ValueKey(('topic-header-tag', 'production-region-27')),
      );
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      _readerScroll(tester).jumpTo(200);
      await tester.pumpAndSettle();
      expect(tester.getRect(headerScroll), headerBounds);
      expect(last.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final save in [false, true]) {
    testWidgets(
      'title draft ${save ? 'saves on Enter' : 'cancels on Escape'} while reading context remains visible',
      (tester) async {
        final setup = await _setup(tester);
        setup.controller.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        final reader = tester.state(find.byType(TopicView));
        await tester.tap(find.byKey(const ValueKey('topic-header-title')));
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('topic-header-title-field'));
        await tester.enterText(field, 'A clearer topic title');
        _readerScroll(tester).jumpTo(200);
        await tester.pumpAndSettle();
        expect(tester.widget<TopicTitle>(_compactHeader).title, 'Topic 1');
        expect(
          find
              .byKey(const ValueKey(('topic-header-tag', 'community')))
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.widget<DInput>(field).controller!.text,
          'A clearer topic title',
        );
        await tester.sendKeyEvent(
          save ? LogicalKeyboardKey.enter : LogicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        expect(
          setup.controller.currentTopic!.title,
          save ? 'A clearer topic title' : 'Topic 1',
        );
        expect(setup.api.topicsUpdated, hasLength(save ? 1 : 0));
        expect(find.byKey(const ValueKey('topic-header-editor')), findsNothing);
        expect(tester.state(find.byType(TopicView)), same(reader));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'title blur keeps the draft and an empty save shows an inline error',
    (tester) async {
      final setup = await _setup(tester);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-header-title')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('topic-header-title-field'));
      await tester.enterText(field, 'Keep this draft');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(setup.api.topicsUpdated, isEmpty);
      expect(tester.widget<DInput>(field).controller!.text, 'Keep this draft');
      await tester.enterText(field, '  ');
      await tester.tap(find.byKey(const ValueKey('topic-header-save')));
      await tester.pumpAndSettle();
      expect(find.byType(DFieldError), findsOneWidget);
      expect(field, findsOneWidget);
      expect(setup.api.topicsUpdated, isEmpty);
      await tester.enterText(field, 'Corrected title');
      await tester.tap(find.byKey(const ValueKey('topic-header-save')));
      await tester.pumpAndSettle();
      expect(setup.controller.currentTopic!.title, 'Corrected title');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category lane stages a complete path and saves only on request',
    (tester) async {
      final setup = await _setup(tester);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit topic category'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topic-header-category-field')),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey(('topic-category-picker-option', 21))),
      );
      await tester.pumpAndSettle();
      expect(setup.controller.currentTopic!.categoryId, _child.id);
      expect(setup.api.topicsUpdated, isEmpty);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('topic-header-category')),
          matching: find.text('Onboarding'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('topic-header-save')));
      await tester.pumpAndSettle();
      expect(setup.controller.currentTopic!.categoryId, _parent.id);
      expect(setup.api.topicsUpdated.single['categoryId'], _parent.id);
      expect(find.byKey(const ValueKey('topic-header-editor')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final save in [true, false]) {
    testWidgets(
      'token editor stages tag removal and ${save ? 'saves' : 'cancels'} explicitly',
      (tester) async {
        final setup = await _setup(tester);
        setup.controller.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('topic-header-edit-tags')));
        await tester.pumpAndSettle();
        expect(find.byType(DComboboxChips<TopicTag>), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Remove community'));
        await tester.pumpAndSettle();
        expect(setup.controller.currentTopic!.tags, const [_tag]);
        expect(setup.api.topicTagsUpdated, isEmpty);
        await tester.tap(
          find.byKey(
            ValueKey(save ? 'topic-header-save' : 'topic-header-cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          setup.controller.currentTopic!.tags,
          save ? isEmpty : const [_tag],
        );
        expect(setup.api.topicTagsUpdated, hasLength(save ? 1 : 0));
        expect(find.byKey(const ValueKey('topic-header-editor')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty tags can be searched and staged as tokens before saving', (
    tester,
  ) async {
    final setup = await _setup(tester, tags: const []);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-header-edit-tags')));
    await tester.pumpAndSettle();
    final query = find.byKey(const ValueKey('topic-tag-picker-query'));
    await tester.enterText(query, 'community');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey(('topic-tag-picker-option', 'community'))),
    );
    await tester.pumpAndSettle();
    expect(setup.api.topicTagsUpdated, isEmpty);
    expect(find.byType(DComboboxChip<TopicTag>), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-tag-picker-popover')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('topic-header-save')));
    await tester.pumpAndSettle();
    expect(setup.controller.currentTopic!.tags, const [_tag]);
    expect(tester.takeException(), isNull);
  });

  for (final (canEdit, canEditTags) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets(
      'direct edit permissions remain independent: title $canEdit, tags $canEditTags',
      (tester) async {
        final setup = await _setup(
          tester,
          canEditTopic: canEdit,
          canEditTags: canEditTags,
        );
        setup.controller.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('topic-header-edit')), findsNothing);
        expect(
          find.byKey(const ValueKey('topic-header-title')),
          canEdit ? findsOneWidget : findsNothing,
        );
        expect(
          find.byTooltip('Edit topic category'),
          canEdit ? findsOneWidget : findsNothing,
        );
        final editTags = find.byKey(const ValueKey('topic-header-edit-tags'));
        expect(editTags, canEditTags ? findsOneWidget : findsNothing);
        if (canEditTags) {
          await tester.tap(editTags);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('topic-header-tag-field')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('topic-header-cancel')));
          await tester.pumpAndSettle();
        }
        expect(
          find
              .byKey(const ValueKey(('topic-header-tag', 'community')))
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a private message has direct tag editing and no category control',
    (tester) async {
      final setup = await _setup(tester, privateMessage: true);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-header-category')), findsNothing);
      expect(find.byKey(const ValueKey('topic-header-edit')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('topic-header-edit-tags')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-category-field')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('topic-header-tag-field')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closed status remains visible through scroll and moderation changes',
    (tester) async {
      final setup = await _setup(tester, closed: true, canCloseTopic: true);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      _readerScroll(tester).jumpTo(250);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-closed')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      expect(find.text('Share topic'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-status-closed')));
      await tester.pumpAndSettle();
      expect(setup.controller.currentTopic!.closed, isFalse);
      expect(find.byKey(const ValueKey('topic-header-closed')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact assignment details remain available without edit permission',
    (tester) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final setup = await _setup(
        tester,
        registry: registry,
        canEditTopic: false,
        canEditTags: false,
        topicPluginPayload: const {
          'can_assign': false,
          'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
        },
      );
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final assignment = find.byKey(const Key('assign-topic-header'));
      expect(assignment.hitTestable(), findsOneWidget);
      await tester.tap(assignment);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsOneWidget);
      expect(find.text('Assigned to'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('selecting a different topic retires the current title draft', (
    tester,
  ) async {
    final setup = await _setup(tester);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-header-title')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-header-title-field')),
      'Stale draft',
    );
    setup.controller.openTopicFromList(setup.rows[1]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-header-editor')), findsNothing);
    expect(tester.widget<TopicTitle>(_compactHeader).title, 'Topic 2');
    expect(setup.api.topicsUpdated, isEmpty);
    expect(tester.takeException(), isNull);
  });

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
          scenario.read ? theme.discourse.whisper : theme.colorScheme.onSurface,
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
      expect(titleColor(), theme.discourse.whisper);
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

  for (final canEdit in [true, false]) {
    for (final action in ['click', 'middle', 'menu-open', 'menu-new-tab']) {
      testWidgets(
        'category $action opens topics with edit permission $canEdit',
        (tester) async {
          final setup = await _setup(tester, canEditTopic: canEdit);
          final shell = setup.controller;
          shell.openTopicFromList(setup.rows.first);
          await tester.pumpAndSettle();
          final originalTab = shell.activeTab;
          final reader = tester.state(find.byType(TopicView));
          await tester.tap(
            find.byKey(const ValueKey('topic-header-category-open')),
            kind: PointerDeviceKind.mouse,
            buttons: action == 'click'
                ? kPrimaryMouseButton
                : action == 'middle'
                ? kMiddleMouseButton
                : kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          if (action.startsWith('menu-')) {
            expect(find.text('Open'), findsOneWidget);
            expect(find.text('Open in new tab'), findsOneWidget);
            expect(find.text('Use as filter'), findsOneWidget);
            await tester.tap(
              find.byKey(ValueKey('topic-header-category-$action')),
            );
            await tester.pumpAndSettle();
          }
          const path = '/c/design/onboarding/22.json';
          if (action == 'middle' || action == 'menu-new-tab') {
            expect(shell.activeTab, originalTab);
            expect(shell.tabsForCurrentForum, hasLength(2));
            expect(
              shell.tabsForCurrentForum.last.currentContent.feedPath,
              path,
            );
            expect(tester.state(find.byType(TopicView)), same(reader));
          } else {
            expect(shell.currentContent?.feedPath, path);
            expect(setup.api.feedPaths, contains(path));
            expect(shell.tabsForCurrentForum, hasLength(1));
          }
          expect(
            find.byKey(const ValueKey('topic-header-editor')),
            findsNothing,
          );
          expect(setup.api.topicsUpdated, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('category filter preserves tags, search, period and the reader', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    shell.selectTopicListCategory(_parent, keepTopicOpen: true);
    shell.selectTopicListTags(['community', 'mobile'], keepTopicOpen: true);
    await shell.selectTopicListMode(
      TopicListMode.topWeekly,
      keepTopicOpen: true,
    );
    shell.searchTopicList('welcome', keepTopicOpen: true);
    await tester.pumpAndSettle();
    final reader = tester.state(find.byType(TopicView));
    _readerScroll(tester).jumpTo(200);
    await tester.pumpAndSettle();
    final originalQuery = Uri.parse(shell.topicListContent!.feedPath!);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(
        find.byKey(const ValueKey('topic-header-category-open')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topic-header-category-menu-filter')),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 1);
      expect(shell.topicListContent?.categoryId, _child.id);
      expect(shell.topicListContent?.tagNames, ['community', 'mobile']);
      expect(shell.currentTopicListMode, TopicListMode.topWeekly);
      final filtered = Uri.parse(shell.topicListContent!.feedPath!);
      for (final entry in originalQuery.queryParametersAll.entries) {
        if (entry.key != 'category') {
          expect(filtered.queryParametersAll[entry.key], entry.value);
        }
      }
      expect(tester.state(find.byType(TopicView)), same(reader));
      expect(_readerScroll(tester).offset, closeTo(200, 1));
      expect(find.byType(DContextMenuContent), findsNothing);
    }
    expect(setup.api.topicsUpdated, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category keyboard menu restores focus beside its edit control', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TopicInboxHeader(
              title: shell.currentTopic!.title,
              siteUrl: shell.currentInstance!.url,
              topic: shell.currentTopic,
              canReturnToSidebar: true,
              keepTopicListOpen: true,
              registry: PluginRegistry.empty,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    FocusNode controlFocus(String key) => Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: key == 'topic-header-category-open'
                  ? find.text('Onboarding')
                  : find.byType(DIcon),
            )
            .last,
      ),
    );
    controlFocus('topic-header-category-open').requestFocus();
    await tester.pump();
    expect(controlFocus('topic-header-category-open').hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(DContextMenuContent), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controlFocus('topic-header-category-open').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controlFocus('topic-header-edit-category').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topic-header-category-field')),
      findsOneWidget,
    );
    expect(shell.currentContent?.topicId, 1);
    expect(setup.api.topicsUpdated, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category filter is disabled without a filterable source list', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    final topicRoute = shell.currentContent!;
    // A directory, followed by a direct topic, has no filterable source feed.
    shell.replaceCurrentContent(
      ContentRoute(
        id: 'categories',
        title: 'Categories',
        icon: topicRoute.icon,
      ),
    );
    shell.pushContent(topicRoute);
    await tester.pumpAndSettle();
    expect(shell.topicListContent?.isTopicListFilter, isNot(true));
    await tester.tap(
      find.byKey(const ValueKey('topic-header-category-open')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DContextMenuItem>(
            find.byKey(const ValueKey('topic-header-category-menu-filter')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Open in new tab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (canEditTags, newTab) in [
    (true, false),
    (true, true),
    (false, false),
    (false, true),
  ]) {
    for (final privateMessage in [false, true]) {
      testWidgets(
        'header tags open from the menu or middle click with editing $canEditTags, private messages $privateMessage, and new tab $newTab',
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
            buttons: newTab ? kMiddleMouseButton : kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          if (!newTab) {
            await tester.tap(
              find.byKey(
                const ValueKey(('topic-header-tag-open', 'community')),
              ),
            );
            await tester.pumpAndSettle();
          }

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
  }

  for (final canEditTags in [true, false]) {
    testWidgets('primary tag click respects edit permission $canEditTags', (
      tester,
    ) async {
      final setup = await _setup(tester, canEditTags: canEditTags);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final reader = tester.state(find.byType(TopicView));
      final routes = [...setup.api.feedPaths];
      await tester.tap(
        find.byKey(const ValueKey(('topic-header-tag', 'community'))),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-tag-field')),
        canEditTags ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(DContextMenuContent),
        canEditTags ? findsNothing : findsOneWidget,
      );
      expect(setup.controller.currentContent?.topicId, 1);
      expect(tester.state(find.byType(TopicView)), same(reader));
      expect(setup.api.feedPaths, routes);
      expect(setup.api.topicTagsUpdated, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tag filter adds to the source list and preserves the reader', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    shell.selectTopicListCategory(_child, keepTopicOpen: true);
    shell.selectTopicListTags(['mobile'], keepTopicOpen: true);
    await shell.selectTopicListMode(
      TopicListMode.topWeekly,
      keepTopicOpen: true,
    );
    shell.searchTopicList('welcome', keepTopicOpen: true);
    await tester.pumpAndSettle();
    final reader = tester.state(find.byType(TopicView));
    _readerScroll(tester).jumpTo(200);
    await tester.pumpAndSettle();
    final originalQuery = Uri.parse(shell.topicListContent!.feedPath!);

    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(
        find.byKey(const ValueKey(('topic-header-tag', 'community'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('topic-header-tag-filter', 'community'))),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 1);
      expect(shell.topicListContent?.categoryId, _child.id);
      expect(shell.topicListContent?.tagNames, ['community', 'mobile']);
      expect(shell.currentTopicListMode, TopicListMode.topWeekly);
      final filtered = Uri.parse(shell.topicListContent!.feedPath!);
      for (final entry in originalQuery.queryParameters.entries) {
        if (entry.key != 'tags[]') {
          expect(filtered.queryParameters[entry.key], entry.value);
        }
      }
      expect(tester.state(find.byType(TopicView)), same(reader));
      expect(_readerScroll(tester).offset, closeTo(200, 1));
      expect(find.byType(DContextMenuContent), findsNothing);
    }
    expect(setup.api.topicTagsUpdated, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private message tags do not filter a public topic list', (
    tester,
  ) async {
    final setup = await _setup(tester, privateMessage: true);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-header-tag', 'community'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final filter = tester.widget<DContextMenuItem>(
      find.byKey(const ValueKey(('topic-header-tag-filter', 'community'))),
    );
    expect(filter.onPressed, isNull);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Open in new tab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final taxonomy in ['tag', 'category']) {
    for (final change in ['topic', 'tab', 'list']) {
      testWidgets(
        '$taxonomy menu refuses a replaced $change before the next frame',
        (tester) async {
          final setup = await _setup(tester);
          final shell = setup.controller;
          shell.openTopicFromList(setup.rows.first);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(
              taxonomy == 'tag'
                  ? const ValueKey(('topic-header-tag', 'community'))
                  : const ValueKey('topic-header-category-open'),
            ),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          final filter = tester
              .widget<DContextMenuItem>(
                find.byKey(
                  taxonomy == 'tag'
                      ? const ValueKey(('topic-header-tag-filter', 'community'))
                      : const ValueKey('topic-header-category-menu-filter'),
                ),
              )
              .onPressed!;
          final open = tester
              .widget<DContextMenuItem>(
                find.byKey(
                  taxonomy == 'tag'
                      ? const ValueKey((
                          'topic-header-tag-open-new-tab',
                          'community',
                        ))
                      : const ValueKey('topic-header-category-menu-new-tab'),
                ),
              )
              .onPressed!;
          switch (change) {
            case 'topic':
              shell.openTopicFromList(setup.rows[1]);
            case 'tab':
              shell.createTab();
            case 'list':
              shell.selectTopicListTags(['mobile'], keepTopicOpen: true);
          }
          final route = shell.currentContent;
          final list = shell.topicListContent;
          final tabCount = shell.tabsForCurrentForum.length;
          filter();
          open();
          await tester.pumpAndSettle();
          expect(shell.currentContent, route);
          expect(shell.topicListContent, list);
          expect(shell.tabsForCurrentForum, hasLength(tabCount));
          expect(find.byType(DContextMenuContent), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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
      expect(find.text('Assigned to'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.byTooltip('# third, # fourth'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('inbox-row-1'))).height,
        lessThan(160),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'topic list and reader bottom bars align at every text scale',
    (tester) async {
      final setup = await _setup(tester);
      setup.controller.openTopicFromList(setup.rows.first);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final scale in [1.0, 1.25, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        final listBar = tester.getRect(
          find.byKey(
            const ValueKey('topic-list-bottom-bar'),
            skipOffstage: false,
          ),
        );
        final readerBar = tester.getRect(
          find.byKey(const ValueKey('topic-bottom-bar')),
        );
        expect(listBar.height, readerBar.height, reason: 'Text scale $scale');
        expect(listBar.top, readerBar.top, reason: 'Text scale $scale');
        expect(listBar.bottom, readerBar.bottom, reason: 'Text scale $scale');
        if (scale == 1) {
          final reply = find.byKey(const ValueKey('topic-reply-button'));
          final controlHeight = tester.getSize(reply).height;
          final touch =
              Theme.of(tester.element(reply)).platform ==
              TargetPlatform.android;
          expect(readerBar.height, touch ? 64 : 44);
          expect(controlHeight, touch ? 48 : 28);
          for (final key in [
            'topic-progress-button',
            if (touch) 'inbox-previous-topic',
            if (touch) 'inbox-next-topic',
          ]) {
            final control = find.byKey(ValueKey(key));
            expect(tester.getSize(control).height, controlHeight);
            expect(
              tester.getRect(control).center.dy,
              closeTo(tester.getRect(reply).center.dy, .01),
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'footer actions stay joined at wide and compact widths and remain usable',
    (tester) async {
      final setup = await _setup(tester);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final group = find.byKey(const ValueKey('topic-footer-actions'));
      final reply = find.byKey(const ValueKey('topic-reply-button'));
      final bookmark = find.byKey(const ValueKey('topic-bookmark-button'));
      final notifications = find.byKey(
        const ValueKey('topic-notification-level-button'),
      );
      for (final width in [2000.0, 500.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(group, findsOneWidget);
        final controls = [reply, bookmark, notifications];
        for (final control in controls) {
          expect(control.hitTestable(), findsOneWidget);
          expect(
            tester.widget<DButton>(control).variant,
            control == reply ? DButtonVariant.primary : DButtonVariant.outline,
          );
          final controls = DTokens.of(tester.element(control)).controls!;
          expect(
            buttonSurface(tester, of: control).color,
            control == reply
                ? controls.primary.background
                : controls.outline.background,
          );
          expect(
            buttonSurface(tester, of: control).borderColor,
            control == reply ? Colors.transparent : controls.outline.border,
          );
          expect(tester.getSize(control).height, tester.getSize(reply).height);
        }
        expect(
          tester.getRect(bookmark).left - tester.getRect(reply).right,
          DSpacing.sm,
        );
        expect(
          tester.getRect(bookmark).right,
          tester.getRect(notifications).left,
        );
        expect(
          buttonSurface(tester, of: reply).borderRadius.topRight,
          const Radius.circular(8),
        );
        expect(
          buttonSurface(tester, of: bookmark).borderRadius,
          const BorderRadius.horizontal(left: Radius.circular(8)),
        );
        expect(
          buttonSurface(tester, of: notifications).borderRadius.topLeft,
          Radius.zero,
        );
        expect(
          find.descendant(of: notifications, matching: find.text('Normal')),
          width == 2000 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(notifications);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Watching'));
      await tester.pumpAndSettle();
      expect(setup.api.topicNotificationLevelsUpdated, [
        (topicId: 1, notificationLevel: TopicNotificationLevel.watching),
      ]);
      await tester.tap(bookmark);
      await tester.pumpAndSettle();
      expect(find.text('Bookmark topic'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(reply);
      await tester.pumpAndSettle();
      expect(setup.controller.visibleComposer?.target.topicId, 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'saved bookmark retains its joined outline (${theme.brightness.name})',
      (tester) async {
        final setup = await _setup(tester, theme: theme);
        setup.controller.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        final bookmark = find.byKey(const ValueKey('topic-bookmark-button'));
        final notifications = find.byKey(
          const ValueKey('topic-notification-level-button'),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        for (final width in [2000.0, 500.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          final unselectedSize = tester.getSize(bookmark);
          for (final saved in [true, false]) {
            final payload = setup.api.topics[1]!;
            setup.api.topics[1] = (
              detail: payload.detail.copyWith(
                notificationLevel: TopicNotificationLevel.tracking,
                bookmarks: saved
                    ? const [
                        Bookmark(
                          id: 81,
                          bookmarkableId: 1,
                          bookmarkableType: 'Topic',
                        ),
                      ]
                    : const [],
              ),
              posts: payload.posts,
            );
            await setup.controller.loadTopic(1, 'topic-1', force: true);
            await tester.pumpAndSettle();
            final tokens = DTokens.of(tester.element(bookmark));
            final controls = tokens.controls!;
            final surface = buttonSurface(tester, of: bookmark);
            expect(surface.borderColor, controls.outline.border);
            expect(
              surface.color,
              saved ? controls.primary.background : controls.outline.background,
            );
            expect(
              surface.borderRadius,
              const BorderRadius.horizontal(left: Radius.circular(8)),
            );
            expect(tester.getSize(bookmark), unselectedSize);
            expect(
              tester.getRect(bookmark).right,
              tester.getRect(notifications).left,
            );
            expect(
              buttonSurface(tester, of: notifications).joinedAxis,
              Axis.horizontal,
            );
            expect(
              tester
                  .widget<DIcon>(
                    find.descendant(of: bookmark, matching: find.byType(DIcon)),
                  )
                  .icon,
              saved ? DNativeIcons.bookmarkCheck : DNativeIcons.bookmark,
            );
            expect(tester.widget<DButton>(bookmark).hasPopup, isTrue);
            if (saved) {
              await mouse.moveTo(tester.getCenter(bookmark));
              await tester.pumpAndSettle();
              expect(
                buttonSurface(tester, of: bookmark).color,
                controls.primary.hover,
              );
              expect(
                buttonSurface(tester, of: notifications).color,
                controls.accent.background,
              );
              await mouse.moveTo(Offset.zero);
              await tester.pumpAndSettle();
            }
          }
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'topic arrows hover independently inside the reduced list footer',
    (tester) async {
      final setup = await _setup(tester, canCreateTopic: true);
      tester.view.physicalSize = const Size(1440, 800);
      setup.controller.openTopicFromList(setup.rows[1]);
      await tester.pumpAndSettle();
      final previous = find.byKey(const ValueKey('inbox-previous-topic'));
      final next = find.byKey(const ValueKey('inbox-next-topic'));
      expect(
        tester.getRect(next).left - tester.getRect(previous).right,
        DSpacing.xs,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final hovered in [previous, next]) {
        await mouse.moveTo(tester.getCenter(hovered));
        await tester.pumpAndSettle();
        final other = hovered == previous ? next : previous;
        expect(
          buttonSurface(tester, of: hovered).color,
          isNot(Colors.transparent),
        );
        expect(buttonSurface(tester, of: other).color, Colors.transparent);
      }
      final footer = tester.getRect(
        find.byKey(const ValueKey('topic-list-bottom-bar')),
      );
      expect(footer.contains(tester.getCenter(previous)), isTrue);
      expect(footer.contains(tester.getCenter(next)), isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
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
      final footer = find.byKey(const ValueKey('topic-list-bottom-bar'));
      final footerRect = tester.getRect(footer);
      expect(footerRect.top, closeTo(tester.getRect(list).bottom, 1));
      for (final action in ['inbox-previous-topic', 'inbox-next-topic']) {
        expect(
          find.descendant(of: footer, matching: find.byKey(ValueKey(action))),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('topic-content-header')),
            matching: find.byKey(ValueKey(action)),
          ),
          findsNothing,
        );
      }
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(footer), footerRect);
      await tester.drag(list, const Offset(0, 300));
      await tester.pumpAndSettle();
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
          matching: find.byType(CustomScrollView),
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
          matching: find.byType(CustomScrollView),
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
    await tester.tap(find.byTooltip('Details'));
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
      final pathsBeforeTags = [...setup.api.feedPaths];
      for (final tag in ['community', 'mobile']) {
        await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey(('topic-list-tag-filter-option', tag))),
        );
        await tester.pumpAndSettle();
      }
      expect(shell.topicListContent?.tagNames, ['community', 'mobile']);
      expect(setup.api.feedPaths.length, pathsBeforeTags.length + 2);
      expect(tester.state(find.byType(TopicView)), same(readerState));
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
      expect(
        find.byKey(const ValueKey('topic-list-clear-filters')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('topic-list-subcategory-filter')),
        findsOneWidget,
      );

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
    final more = find.byKey(const ValueKey('post-more-actions-2'));
    expect(more.hitTestable(), findsOneWidget);
    expect(tester.getRect(more).left, tester.getRect(bookmark).right);
    expect(tester.getRect(more).right, closeTo(tester.getRect(body).right, 1));

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
      final more = find.byKey(const ValueKey('post-more-actions-2'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
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
      await shell.jumpToCurrentTopicIndex(2);
      await tester.pumpAndSettle();
      final list = tester.widget<CustomScrollView>(
        find.descendant(of: reader, matching: find.byType(CustomScrollView)),
      );
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
          .widget<CustomScrollView>(
            find.descendant(
              of: reader,
              matching: find.byType(CustomScrollView),
            ),
          )
          .controller!;
      final title = find.byKey(const ValueKey('topic-header-title'));
      await tester.tap(title);
      await tester.pumpAndSettle();
      final editOffset = editScroll.offset;
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
  ThemeData? theme,
  PluginRegistry registry = PluginRegistry.empty,
  bool recommendations = false,
  bool canCreateTopic = false,
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
  int? detailCategoryId = 22,
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
    creatableFeedPaths: canCreateTopic ? {'/latest.json'} : {},
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
            categoryId: detailCategoryId,
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
        theme: theme ?? AppTheme.light,
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

Finder get _compactHeader => find.descendant(
  of: find.byKey(const ValueKey('topic-content-header')),
  matching: find.byElementPredicate((element) {
    if (element.widget is! TopicTitle) return false;
    var visible = true;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget case Opacity(opacity: 0)) visible = false;
      return visible;
    });
    return visible;
  }),
);
ScrollController _readerScroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(
      find.descendant(
        of: find.byType(TopicView),
        matching: find.byType(CustomScrollView),
      ),
    )
    .controller!;
