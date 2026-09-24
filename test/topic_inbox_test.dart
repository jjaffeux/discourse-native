import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
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
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';
import 'support/page_scrollbar.dart';

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
  testWidgets('window corner follows topic panel opening and closing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final setup = await _setup(
      tester,
      windowCorners: true,
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    );
    DCard cardIn(String key) => tester.widget<DCard>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(DCard),
          )
          .first,
    );
    bool hasCorner(DCard card) =>
        (card.borderRadius as BorderRadius?)?.bottomRight ==
        const Radius.circular(10);

    expect(hasCorner(cardIn('inbox-topic-list-pane')), isTrue);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    expect(hasCorner(cardIn('inbox-topic-list-pane')), isFalse);
    expect(hasCorner(cardIn('inbox-topic-reader-pane')), isTrue);
    setup.controller.closeTopicListReader();
    await tester.pumpAndSettle();
    expect(hasCorner(cardIn('inbox-topic-list-pane')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'activity summary has stacked avatars, complete stats and a persistent inset separator',
    (tester) async {
      final setup = await _setup(
        tester,
        activityStats: true,
        participants: const [
          TopicParticipant(username: 'robin'),
          TopicParticipant(username: 'nora'),
          TopicParticipant(username: 'tom'),
          TopicParticipant(username: 'pat'),
        ],
      );
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      final activity = find.byKey(const ValueKey('topic-header-activity'));
      final avatars = find.descendant(
        of: activity,
        matching: find.byType(DAvatarGroup),
      );
      expect(
        find.descendant(of: avatars, matching: find.byType(DAvatar)),
        findsNWidgets(4),
      );
      for (final label in [
        '3 replies',
        '61 views',
        '29 likes',
        '5 links',
        '4 min read',
      ]) {
        expect(
          find.descendant(
            of: activity,
            matching: find.text(label, findRichText: true),
          ),
          findsOneWidget,
        );
      }
      final stats = find.descendant(
        of: activity,
        matching: find.text('3 replies', findRichText: true),
      );
      expect(
        tester.getRect(stats).top,
        greaterThan(tester.getRect(avatars).bottom),
      );
      final viewport = find.descendant(
        of: find.byType(TopicView),
        matching: find.byType(CustomScrollView),
      );
      final separator = find.byKey(const ValueKey('topic-scroll-separator'));
      void verifySeparator() {
        expect(separator, findsOneWidget);
        final line = tester.getRect(separator);
        final bounds = tester.getRect(viewport);
        expect(line.left, greaterThan(bounds.left));
        expect(line.right, lessThan(bounds.right));
        expect(line.top, closeTo(bounds.top, 1));
      }

      verifySeparator();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(viewport),
          scrollDelta: const Offset(0, 240),
        ),
      );
      await tester.pumpAndSettle();
      expect(activity.hitTestable(), findsNothing);
      verifySeparator();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(viewport),
          scrollDelta: const Offset(0, -240),
        ),
      );
      await tester.pumpAndSettle();
      expect(activity.hitTestable(), findsOneWidget);
      verifySeparator();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('topic header retracts while the list header stays visible', (
    tester,
  ) async {
    final setup = await _setup(
      tester,
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    );
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await _scrollReaderToTop(tester);
    final reader = find.descendant(
      of: find.byType(TopicView),
      matching: find.byType(CustomScrollView),
    );
    final list = find
        .descendant(
          of: find.byType(TopicListView),
          matching: find.byType(Scrollable),
        )
        .first;
    final title = find.byKey(const ValueKey('topic-header-title-field'));
    final readerTop = tester.getTopLeft(reader).dy;
    final listTop = tester.getTopLeft(find.byType(TopicListView)).dy;
    final readerElement = tester.element(reader);
    final listElement = tester.element(list);
    Future<void> wheel(Finder target, double delta) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: Offset(0, delta),
        ),
      );
      await tester.pump();
    }

    await wheel(reader, 240);
    expect(title.hitTestable(), findsNothing);
    expect(tester.getTopLeft(reader).dy, lessThan(readerTop));
    expect(tester.getTopLeft(find.byType(TopicListView)).dy, listTop);
    final hiddenReaderTop = tester.getTopLeft(reader).dy;
    await wheel(reader, -20);
    expect(tester.getTopLeft(reader).dy, closeTo(hiddenReaderTop + 20, 0.001));
    expect(title.hitTestable(), findsNothing);
    await wheel(reader, -220);
    expect(title.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(reader).dy, readerTop);
    await wheel(list, 240);
    expect(tester.getTopLeft(find.byType(TopicListView)).dy, listTop);
    expect(title.hitTestable(), findsOneWidget);
    await wheel(list, -10);
    expect(tester.getTopLeft(find.byType(TopicListView)).dy, listTop);
    await wheel(list, -230);
    expect(tester.getTopLeft(find.byType(TopicListView)).dy, listTop);
    expect(tester.element(reader), same(readerElement));
    expect(tester.element(list), same(listElement));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop panel gutter resizes while retaining list and reader', (
    tester,
  ) async {
    final setup = await _setup(
      tester,
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    );
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final list = find.byType(TopicListView);
    final reader = find.byKey(const ValueKey('inbox-topic-reader-pane'));
    final listState = tester.state(list);
    final readerState = tester.state(find.byType(TopicView));
    double gap() => tester.getRect(reader).left - tester.getRect(list).right;
    expect(gap(), 12);
    final width = tester.getSize(list).width;
    final handle = find.byKey(const ValueKey('inbox-list-resize-handle'));
    expect(tester.getSize(handle).width, 12);
    await tester.drag(handle, const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, greaterThan(width));
    expect(gap(), 12);
    expect(tester.state(list), same(listState));
    expect(tester.state(find.byType(TopicView)), same(readerState));
    final resizedWidth = tester.getSize(list).width;
    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    expect(handle, findsNothing);
    tester.view.physicalSize = const Size(1100, 800);
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, resizedWidth);
    expect(gap(), 12);
    expect(tester.state(list), same(listState));
    expect(tester.takeException(), isNull);
  });

  for (final (assignable, width) in [
    (false, 1100.0),
    (true, 1100.0),
    (true, 600.0),
  ]) {
    testWidgets(
      'a loading reader reserves its loaded rows ${assignable ? 'with' : 'without'} Assign at $width',
      (tester) async {
        final gate = Completer<void>();
        final setup = await _setup(
          tester,
          topicGate: gate,
          closed: true,
          registry: assignable
              ? const PluginRegistry([AssignPlugin()])
              : PluginRegistry.empty,
          topicPluginPayload: assignable
              ? const {'can_assign': true}
              : const {},
        );
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        final shell = setup.controller;
        final row = setup.rows.first.copyWith(
          closed: true,
          posterAvatars: const ['https://meta.example/avatar/sam.png'],
        );
        shell.store.put(shell.currentInstance!.url, row);
        shell.openTopicFromList(row);
        await tester.pump();

        final header = find.byType(TopicInboxHeader);
        Finder inHeader(Finder finder) =>
            find.descendant(of: header, matching: finder);
        final toolbar = inHeader(
          find.byKey(const ValueKey('topic-content-header')),
        );
        final closed = inHeader(
          find.byKey(const ValueKey('topic-header-closed')),
        );
        final footer = find.byKey(const ValueKey('topic-bottom-bar'));
        final separator = find.byKey(const ValueKey('topic-scroll-separator'));
        // Only what renders identically once loaded is drawn from the row.
        expect(inHeader(find.text('Topic 1')), findsOneWidget);
        expect(closed, findsOneWidget);
        expect(inHeader(find.text('Onboarding')), findsNothing);
        expect(inHeader(find.text('# community')), findsNothing);
        expect(inHeader(find.byType(AvatarImage)), findsNothing);
        // Permission-dependent controls wait for the topic, disabled in place.
        expect(inHeader(find.byType(InlineTopicTitleEditor)), findsNothing);
        expect(inHeader(find.byType(TopicStatusButton)), findsNothing);
        expect(inHeader(find.byType(TopicStatusButtonPlaceholder)), findsOne);
        expect(find.byKey(const ValueKey('topic-reply-button')), findsNothing);
        expect(
          tester
              .widget<DButton>(
                find.byKey(const ValueKey('topic-reply-placeholder')),
              )
              .onPressed,
          isNull,
        );
        expect(find.byType(TopicBookmarkButtonPlaceholder), findsOneWidget);
        expect(find.byType(TopicNotificationLevelPlaceholder), findsOneWidget);
        expect(
          find.byKey(const ValueKey('topic-loading-skeleton')),
          findsOneWidget,
        );
        final loadingElement = tester.element(header);
        final title = tester.getRect(toolbar);
        final lock = tester.getRect(closed);
        final taxonomy = tester.getRect(
          find.byKey(const ValueKey('topic-header-taxonomy-placeholder')),
        );
        final activity = tester.getRect(
          find.byKey(const ValueKey('topic-header-activity-placeholder')),
        );
        final body = tester.getRect(separator);
        final actions = tester.getRect(footer);

        gate.complete();
        await tester.pump();
        await tester.pump();

        expect(find.byType(CookedHtml), findsWidgets);
        expect(
          find.byKey(const ValueKey('topic-loading-skeleton')),
          findsNothing,
        );
        expect(
          tester.element(header),
          same(loadingElement),
          reason:
              'the arriving topic fills the header instead of remounting it',
        );
        expect(tester.getRect(toolbar), title);
        expect(tester.getRect(closed), lock);
        final loadedTaxonomy = tester.getRect(
          find.byKey(const ValueKey('topic-header-taxonomy')),
        );
        expect(loadedTaxonomy.top, taxonomy.top);
        expect(loadedTaxonomy.height, taxonomy.height);
        final loadedActivity = tester.getRect(
          find.byKey(const ValueKey('topic-header-activity')),
        );
        expect(loadedActivity.top, activity.top);
        expect(loadedActivity.height, activity.height);
        expect(tester.getRect(separator), body);
        expect(tester.getRect(footer), actions);
        expect(inHeader(find.byType(TopicStatusButton)), findsOneWidget);
        expect(inHeader(find.byType(InlineTopicTitleEditor)), findsOneWidget);
        expect(
          inHeader(find.byKey(const Key('assign-topic-header'))),
          assignable ? findsOneWidget : findsNothing,
        );
        expect(find.byKey(const ValueKey('topic-reply-button')), findsOne);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('loading placeholders follow navigation and a failed load', (
    tester,
  ) async {
    final gate = Completer<void>();
    final setup = await _setup(tester, topicGate: gate);
    final shell = setup.controller;
    final siteUrl = shell.currentInstance!.url;
    final first = setup.rows.first.copyWith(
      tags: const [TopicTag(name: 'first')],
    );
    final second = setup.rows[1].copyWith(
      categoryId: 21,
      tags: const [TopicTag(name: 'second')],
    );
    final header = find.byType(TopicInboxHeader);
    Finder inHeader(Finder finder) =>
        find.descendant(of: header, matching: finder);
    final placeholder = find.byKey(
      const ValueKey('topic-header-taxonomy-placeholder'),
    );
    shell.store.putAll(siteUrl, [first, second]);
    shell.openTopicFromList(first);
    await tester.pump();
    expect(inHeader(find.text('Topic 1')), findsOneWidget);
    expect(inHeader(find.text('# first')), findsNothing);
    expect(placeholder, findsOneWidget);
    shell.openTopicFromList(second);
    await tester.pump();
    expect(inHeader(find.text('Topic 1')), findsNothing);
    expect(inHeader(find.text('Topic 2')), findsOneWidget);
    expect(placeholder, findsOneWidget);

    shell.pushContent(
      ContentRoute.topic(
        topicId: 999,
        slug: 'uncached',
        title: 'Uncached topic',
      ),
    );
    final loading = shell.loadTopic(999, 'uncached');
    await tester.pump();
    expect(inHeader(find.text('Uncached topic')), findsOneWidget);
    expect(placeholder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-header-activity-placeholder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('topic-loading-skeleton')),
      findsOneWidget,
    );

    gate.complete();
    await tester.pumpAndSettle();
    await loading;
    expect(find.text("Couldn't load this topic."), findsOneWidget);
    expect(placeholder, findsNothing);
    expect(
      find.byKey(const ValueKey('topic-header-activity-placeholder')),
      findsNothing,
    );
    expect(inHeader(find.byType(TopicStatusButtonPlaceholder)), findsNothing);
    expect(find.byKey(const ValueKey('topic-header-taxonomy')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open topic selection follows the reader', (tester) async {
    final setup = await _setup(tester);
    DItem card(int id) =>
        tester.widget<DItem>(find.byKey(ValueKey('topic-card-$id')));
    expect(card(setup.rows.first.id).selected, isFalse);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    expect(card(setup.rows.first.id).selected, isTrue);
    expect(
      card(setup.rows.first.id).selectionStyle,
      DItemSelectionStyle.leadingAccent,
    );
    expect(card(setup.rows.first.id).showSelectionIndicator, isFalse);
    expect(card(setup.rows[1].id).selected, isFalse);
    setup.controller.openTopicFromList(setup.rows[1]);
    await tester.pumpAndSettle();
    expect(card(setup.rows.first.id).selected, isFalse);
    expect(card(setup.rows[1].id).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader back action follows topic list visibility', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final close = find.byKey(const ValueKey('topic-close-reader'));
    expect(close, findsNothing);
    for (final width in [1200.0, 600.0]) {
      tester.view.physicalSize = Size(width, 800);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      expect(close.hitTestable(), findsOneWidget);
      expect(
        find.descendant(of: find.byType(TopicInboxHeader), matching: close),
        findsOneWidget,
      );
      expect(
        find.byTooltip(width == 1200 ? 'Collapse topic' : 'Back to topic list'),
        findsOneWidget,
      );
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(TopicView), findsNothing);
      expect(find.byType(TopicListView), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

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
    'programmatic topic scrolling preserves the header and viewport',
    (tester) async {
      final setup = await _setup(tester);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      await _scrollReaderToTop(tester);
      final viewport = find.descendant(
        of: find.byType(TopicView),
        matching: find.byType(CustomScrollView),
      );
      final scroll = tester.widget<CustomScrollView>(viewport).controller!;
      final viewportElement = tester.element(viewport);
      final viewportBounds = tester.getRect(viewport);
      final toolbar = find.byKey(const ValueKey('topic-content-header'));
      final toolbarBounds = tester.getRect(toolbar);
      final taxonomy = find.byKey(const ValueKey('topic-header-taxonomy'));
      final taxonomyElement = tester.element(taxonomy);
      final taxonomyBounds = tester.getRect(taxonomy);
      final scrollbar = find.ancestor(
        of: viewport,
        matching: find.byType(DScrollBar),
      );
      expect(
        viewportBounds.top,
        closeTo(
          tester
                  .getRect(find.byKey(const ValueKey('topic-header-activity')))
                  .bottom +
              20,
          1,
        ),
      );
      expect(tester.getRect(scrollbar), viewportBounds);
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      final toolbarTitleBounds = tester.getRect(_compactHeader);
      final toolbarTitleElement = tester.element(_compactHeader);
      expect(
        find.byKey(const ValueKey('topic-header-title-field')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TopicInboxHeader),
          matching: find.byType(TopicTitle),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TopicTitle>(_compactHeader).title,
        setup.rows.first.title,
      );
      expect(
        find.descendant(of: toolbar, matching: find.text('Onboarding')),
        findsNothing,
      );
      expect(tester.widget<TopicTitle>(_compactHeader).style!.fontSize, 20);

      for (final offset in [12.0, 200.0, 199.0, 300.0, 180.0]) {
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-header-title-field')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.getRect(_compactHeader), toolbarTitleBounds);
        expect(tester.element(_compactHeader), same(toolbarTitleElement));
        expect(tester.getRect(viewport), viewportBounds);
        expect(tester.getRect(toolbar), toolbarBounds);
        expect(tester.element(viewport), same(viewportElement));
        expect(tester.element(taxonomy), same(taxonomyElement));
        expect(tester.getRect(taxonomy), taxonomyBounds);
        expect(tester.getRect(scrollbar), viewportBounds);
        expect(taxonomy.hitTestable(), findsOneWidget);
      }
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-title-field')).hitTestable(),
        findsOneWidget,
      );
      expect(title.hitTestable(), findsOneWidget);
      expect(tester.getRect(viewport), viewportBounds);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(taxonomy),
          scrollDelta: const Offset(0, 80),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      await expectPageEdgeScrolling(
        tester,
        viewport: viewport,
        right: viewportBounds.right,
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
      final toolbarTop = tester
          .getTopLeft(find.byKey(const ValueKey('topic-content-header')))
          .dy;
      for (final action in [
        find.byKey(const ValueKey('topic-status-button')),
      ]) {
        expect(
          tester.getCenter(action).dy,
          closeTo(toolbarTop + 4 + DSpacing.touchTarget / 2, 1),
        );
      }
      final controls = [
        for (final finder in [
          find.byKey(const ValueKey('topic-close-reader')),
          find.byKey(const ValueKey('topic-status-button')),
        ])
          (
            finder: finder,
            element: tester.element(finder),
            bounds: tester.getRect(finder),
          ),
      ];
      final scroll = tester
          .widget<CustomScrollView>(
            find.descendant(
              of: find.byType(TopicView),
              matching: find.byType(CustomScrollView),
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
    'assignment count opens details once and can reopen the selected topic',
    (tester) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final setup = await _setup(
        tester,
        registry: registry,
        privateMessage: true,
        topicPluginPayload: const {
          'can_assign': false,
          'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
          'indirectly_assigned_to': {
            '102': {
              'post_number': 2,
              'assigned_to': {'username': 'alex', 'name': 'Alex'},
            },
          },
        },
      );
      final disclosure = find.descendant(
        of: find.byKey(const ValueKey('topic-card-1')),
        matching: find.bySemanticsLabel('Open topic to view all 2 assignments'),
      );
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(setup.controller.currentContent?.topicId, 1);
      expect(find.byKey(const Key('assign-topic-property')), findsOneWidget);
      expect(find.text('@alex'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsNothing);
      setup.controller.notifyPluginStateChanged();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsNothing);
      expect(setup.controller.currentContent?.topicId, 1);
      setup.controller.requestTopicProperty(
        siteUrl: setup.controller.currentInstance!.url,
        topicId: 1,
        label: 'Assignments',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsOneWidget);
      setup.controller.openTopicFromList(setup.rows[1]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsNothing);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsNothing);
      // Leaving before the next frame must discard the pending disclosure.
      setup.controller.requestTopicProperty(
        siteUrl: setup.controller.currentInstance!.url,
        topicId: 1,
        label: 'Assignments',
      );
      setup.controller.openTopicFromList(setup.rows[1]);
      setup.controller.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
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
      expect(assignment.hitTestable(), findsOneWidget);
      expect(
        find.descendant(of: assignment, matching: find.text('Sam')),
        findsOneWidget,
      );
      await tester.tap(assignment);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-topic-property')), findsOneWidget);
      expect(find.text('Assigned to'), findsWidgets);
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
          const ValueKey('topic-header-parent-category'),
        );
        final child = find.byKey(const ValueKey('topic-header-category'));
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

  for (final permission in [null, 1, 2, 3]) {
    testWidgets(
      'empty subcategory field requires an available child (permission $permission)',
      (tester) async {
        final setup = await _setup(
          tester,
          listedCategoryId: _parent.id,
          detailCategoryId: _parent.id,
          categoryList: [
            _parent,
            if (permission != null)
              TopicCategory(
                id: _child.id,
                name: _child.name,
                color: _child.color,
                parentCategoryId: _parent.id,
                permission: permission,
              ),
            const TopicCategory(
              id: 24,
              name: 'Other parent child',
              color: '9464B8',
              parentCategoryId: 23,
              permission: 1,
            ),
          ],
        );
        setup.controller.openTopicFromList(setup.rows.first);
        await tester.pumpAndSettle();
        expect(_compactHeader, findsOneWidget);
        expect(
          find.byTooltip('Edit topic subcategory'),
          permission == 1 ? findsOneWidget : findsNothing,
        );
        await _scrollReaderToTop(tester);

        expect(find.byTooltip('Edit topic category'), findsOneWidget);
        expect(
          find.byTooltip('Edit topic subcategory'),
          permission == 1 ? findsOneWidget : findsNothing,
        );
        expect(setup.api.categorySearchTerms, isEmpty);
        if (permission == 1) {
          await tester.tap(find.byTooltip('Edit topic subcategory'));
          await tester.pumpAndSettle();
          expect(find.text('Remove subcategory'), findsNothing);
        }
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
      find.byKey(const ValueKey(('topic-category-picker-option', 21))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('topic-category-picker-option', 22))),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit topic subcategory'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(('topic-category-picker-option', 22))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('topic-category-picker-option', 21))),
      findsNothing,
    );
    await tester.tap(find.text('Remove subcategory'));
    await tester.pumpAndSettle();

    expect(shell.currentTopic!.categoryId, _parent.id);
    expect(setup.api.topicsUpdated.single['categoryId'], _parent.id);
    expect(shell.topicListContent, originalList);
    expect(_compactHeader, findsOneWidget);
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
      final headerControls = [
        (add, DButtonSize.regular, 44.0),
        if (find
            .byKey(const ValueKey('topic-close-reader'))
            .evaluate()
            .isNotEmpty)
          (
            find.byKey(const ValueKey('topic-close-reader')),
            DButtonSize.regular,
            44.0,
          ),
        (
          find.byKey(const ValueKey('topic-header-browse-category-22')),
          DButtonSize.regular,
          44.0,
        ),
        (
          find.byWidgetPredicate(
            (widget) =>
                widget is DButton && widget.tooltip == 'Edit topic category',
          ),
          DButtonSize.regular,
          44.0,
        ),
      ];
      for (final (control, size, height) in headerControls) {
        expect(tester.widget<DButton>(control).size, size);
        final surface = find.descendant(
          of: control,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedContainer &&
                widget.decoration is DButtonDecoration,
          ),
        );
        expect(tester.getSize(surface).height, height);
      }
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('topic-tag-picker-option', 'community'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close').last);
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
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Updated coverage plan');
    final list = tester.widget<CustomScrollView>(
      find.descendant(
        of: find.byType(TopicView),
        matching: find.byType(CustomScrollView),
      ),
    );
    list.controller!.jumpTo(200);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    expect(
      tester.widget<DInput>(field).controller!.text,
      'Updated coverage plan',
    );
    expect(_compactHeader, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(shell.currentTopic!.title, 'Updated coverage plan');
    expect(_compactHeader, findsOneWidget);
    expect(field.hitTestable(), findsOneWidget);
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
        final scroll = _readerScroll(tester);
        scroll.jumpTo(200);
        await tester.pumpAndSettle();
        final scrollOffset = scroll.offset;
        final compact = _compactHeader;
        final title = _compactHeader;
        final field = find.byKey(const ValueKey('topic-header-title-field'));
        final titleLeft = tester.getRect(field).left;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(FocusScope.of(tester.element(title)).focusedChild, isNotNull);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: tester.getCenter(field));
        await tester.pump();
        await mouse.down(tester.getCenter(field));
        await tester.pump(const Duration(milliseconds: 16));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(tester.widget<DInput>(field).focusNode!.hasFocus, isTrue);
        expect(compact, findsNothing);
        final toolbar = find.byKey(const ValueKey('topic-content-header'));
        expect(find.descendant(of: toolbar, matching: field), findsOneWidget);
        expect(tester.getRect(field).left, titleLeft);
        expect(scroll.offset, scrollOffset);
        expect(find.text('Enter to save · Esc to cancel'), findsNothing);
        expect(find.widgetWithText(DButton, 'Cancel'), findsNothing);
        expect(find.widgetWithText(DButton, 'Save'), findsNothing);

        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'Updated coverage plan');
        await tester.sendKeyEvent(
          save ? LogicalKeyboardKey.enter : LogicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        final expectedTitle = save ? 'Updated coverage plan' : originalTitle;
        expect(shell.currentTopic!.title, expectedTitle);
        expect(compact, findsOneWidget);
        expect(field.hitTestable(), findsOneWidget);
        expect(tester.widget<DInput>(field).focusNode!.hasFocus, isFalse);
        expect(tester.widget<TopicTitle>(title).title, expectedTitle);
        expect(scroll.offset, scrollOffset);
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

  testWidgets('saving a wrapped title on blur still opens the clicked category', (
    tester,
  ) async {
    final setup = await _setup(tester);
    setup.controller.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('topic-header-title-field'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    const title =
        'Customer Support Coverage Week - Seville 2026: coordinating schedules, '
        'travel, and team availability across every time zone';
    await tester.enterText(field, title);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final category = tester.getCenter(find.byTooltip('Edit topic category'));
    await mouse.addPointer(location: category);
    await mouse.down(category);
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(setup.controller.currentTopic!.title, title);
    expect(
      find.byKey(const ValueKey(('topic-category-picker-option', 21))),
      findsOneWidget,
    );
    expect(_compactHeader, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('compact titles remain read-only without edit permission', (
    tester,
  ) async {
    final setup = await _setup(tester, canEditTopic: false);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await tester.tap(_compactHeader);
    await tester.pumpAndSettle();
    expect(_compactHeader, findsOneWidget);
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
    final compact = _compactHeader;
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
    await tester.tap(find.byTooltip('Close').last);
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
    await tester.tap(find.byTooltip('Close').last);
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
        expect(_compactHeader, findsOneWidget);
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
          await tester.tap(find.byTooltip('Close').last);
          await tester.pumpAndSettle();
          expect(shell.currentTopic!.tags, hasLength(26));
          expect(
            setup.api.topicTagsUpdated.single['tags'],
            isNot(contains(tags.last)),
          );
          expect(_compactHeader, findsOneWidget);
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
    'topic header and posts share the optional 825 px limit across zoom levels',
    (tester) async {
      final setup = await _setup(tester);
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      for (final (width, zoom, limited) in [
        (1200.0, AppTextScale.percent100, false),
        (1200.0, AppTextScale.percent100, true),
        (2000.0, AppTextScale.percent100, false),
        (2000.0, AppTextScale.percent100, true),
        (2000.0, AppTextScale.percent150, false),
        (2000.0, AppTextScale.percent150, true),
      ]) {
        tester.view.physicalSize = Size(width, 800);
        await shell.appSettings.setTextScale(zoom);
        await shell.appSettings.setLimitContentSize(limited);
        await tester.pumpAndSettle();
        await _scrollReaderToTop(tester);
        final title = tester.getRect(
          find.byKey(const ValueKey('topic-header-title-field')),
        );
        final taxonomy = find.byKey(const ValueKey('topic-header-taxonomy'));
        final before = tester.getRect(taxonomy);
        final close = tester.getRect(
          find.byKey(const ValueKey('topic-header-common-actions')),
        );
        final viewport = tester.getRect(
          find.descendant(
            of: find.byType(TopicView),
            matching: find.byType(CustomScrollView),
          ),
        );
        final summary = tester.getRect(
          find.byKey(const ValueKey('topic-header-activity')),
        );
        final divider = tester.getRect(
          find.byKey(const ValueKey('topic-scroll-separator')),
        );
        final inset = limited && viewport.width > 825
            ? (viewport.width - 825) / 2
            : 0.0;
        expect(before.left, closeTo(viewport.left + inset + 16, 1));
        expect(before.right, closeTo(viewport.right - inset - 16, 1));
        expect(summary.left, closeTo(viewport.left + inset + 16, 1));
        expect(summary.right, closeTo(viewport.right - inset - 16, 1));
        expect(divider.left, closeTo(viewport.left + inset + 16, 1));
        expect(divider.right, closeTo(viewport.right - inset - 16, 1));
        final postBody = tester.getRect(find.byType(CookedHtml).first);
        expect(postBody.left, closeTo(viewport.left + inset + 16 + 39, 1));
        expect(postBody.right, closeTo(viewport.right - inset - 16, 1));
        expect(before.left, closeTo(title.left, 1));
        expect(before.top, greaterThan(title.bottom));
        _readerScroll(tester).jumpTo(300);
        await tester.pumpAndSettle();
        final after = tester.getRect(taxonomy);
        expect(after.left, before.left);
        expect(after.width, before.width);
        expect(after.top, before.top);
        expect(
          tester.getRect(
            find.byKey(const ValueKey('topic-header-common-actions')),
          ),
          close,
        );
        expect(_compactHeader, findsOneWidget);
        expect(tester.takeException(), isNull);
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
        final title = _compactHeader;
        final category = find.byKey(const ValueKey('topic-header-category'));
        final parent = find.byKey(
          const ValueKey('topic-header-parent-category'),
        );
        expect(
          tester.getRect(parent).left,
          closeTo(
            tester
                .getRect(find.byKey(const ValueKey('topic-header-taxonomy')))
                .left,
            1,
          ),
        );
        expect(
          tester.getRect(parent).right,
          lessThan(tester.getRect(category).left),
        );
        for (final id in [_parent.id, _child.id]) {
          final browse = find.byKey(
            ValueKey('topic-header-browse-category-$id'),
          );
          if (browse.evaluate().isNotEmpty) {
            expect(browse.hitTestable(), findsOneWidget);
            // Native touch controls retain their 48px target.
            expect(tester.getSize(browse).width, 48);
          } else {
            expect(
              find
                  .byTooltip(
                    id == _parent.id
                        ? 'Edit topic category'
                        : 'Edit topic subcategory',
                  )
                  .hitTestable(),
              findsOneWidget,
            );
          }
        }
        expect(tester.getRect(title).right, lessThan(width));
        final tags = find.byKey(const ValueKey('topic-header-tags'));
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
        for (final key in ['topic-status-button']) {
          expect(
            tester.getCenter(find.byKey(ValueKey(key))).dy,
            closeTo(
              tester.getRect(header).top + 4 + DSpacing.touchTarget / 2,
              1,
            ),
          );
        }
        expect(
          tester.getRect(tags).top,
          greaterThanOrEqualTo(tester.getRect(header).bottom),
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
        for (final width in [1200.0, 780.0, 600.0, 390.0]) {
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
          expect(
            find.byKey(const ValueKey('topic-close-reader')),
            findsOneWidget,
          );
          final category = compact
              ? find.byKey(const ValueKey('topic-header-category'))
              : find.byTooltip('Edit topic category');
          final overflow = find.byKey(const ValueKey('topic-header-more-tags'));
          final status = find.byKey(const ValueKey('topic-status-button'));
          expect(
            tester.getRect(category).right,
            lessThan(tester.getRect(overflow).left),
          );
          expect(
            tester.getCenter(category).dy,
            closeTo(tester.getCenter(overflow).dy, 1),
          );
          final title = find.byKey(const ValueKey('topic-header-title-field'));
          final parent = compact
              ? find.byKey(const ValueKey('topic-header-parent-category'))
              : category;
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
            closeTo(
              tester
                  .getRect(find.byKey(const ValueKey('topic-header-taxonomy')))
                  .left,
              1,
            ),
          );
          if (compact) {
            expect(
              tester.getRect(title).right,
              lessThan(tester.getRect(status).left),
            );
          }
          if (!compact) {
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('topic-header-activity')))
                  .top,
              greaterThan(tester.getRect(category).bottom),
            );
          }
          for (final control in [status, if (compact) title]) {
            expect(
              tester.getCenter(control).dy,
              closeTo(tester.getCenter(status).dy, 1),
            );
          }
          expect(
            find.byKey(const ValueKey('inbox-previous-topic')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('inbox-next-topic')), findsNothing);
          expect(find.byType(TopicShareButton), findsNothing);
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
    expect(properties.center.dy, closeTo(tag.center.dy, 1));
    final separator = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('topic-header-taxonomy')),
            matching: find.byType(DSeparator),
          )
          .last,
    );
    expect(separator.left, greaterThanOrEqualTo(editTagRect.right));
    expect(separator.right, lessThan(properties.left));
    expect(
      tester.getRect(find.byType(CookedHtml).first).left,
      closeTo(title.left + 39, 1),
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
    'closing a topic places a lock before its title aligned with the content',
    (tester) async {
      final setup = await _setup(
        tester,
        canCloseTopic: true,
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      );
      final shell = setup.controller;
      shell.openTopicFromList(setup.rows.first);
      await tester.pumpAndSettle();
      await _scrollReaderToTop(tester);
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      final lock = find.byKey(const ValueKey('topic-header-closed'));
      final titleRect = tester.getRect(title);
      expect(lock, findsNothing);

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-status-closed')));
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.closed, isTrue);
      expect(find.text('Closed'), findsNothing);
      expect(lock, findsOneWidget);
      expect(tester.widget<DIcon>(lock).icon, DIcons.lock);
      final lockRect = tester.getRect(lock);
      final closedTitleRect = tester.getRect(title);
      expect(lockRect.left, titleRect.left);
      expect(closedTitleRect.left, lockRect.right + DSpacing.sm);
      expect(closedTitleRect.top, titleRect.top);
      expect(closedTitleRect.right, titleRect.right);
      expect(
        lockRect.left,
        tester
            .getRect(find.byKey(const ValueKey('topic-header-activity')))
            .left,
      );
      expect(
        lockRect.left,
        closeTo(tester.getRect(find.byType(CookedHtml).first).left - 39, 1),
      );
      expect(
        lockRect.left,
        closeTo(tester.getRect(find.byTooltip('Edit topic category')).left, 1),
      );

      await tester.tap(title);
      await tester.pump();
      final frame = find.byKey(const ValueKey('topic-header-title-field'));
      expect(tester.widget<DInput>(frame).focusNode!.hasFocus, isTrue);
      expect(tester.getRect(lock).right, lessThan(tester.getRect(frame).left));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      expect(find.text('Open topic'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-status-closed')));
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.closed, isFalse);
      expect(lock, findsNothing);
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
            final lock = find.byKey(const ValueKey('topic-header-closed'));
            expect(find.text('Closed'), findsNothing);
            expect(find.bySemanticsLabel('Topic closed'), findsOneWidget);
            expect(find.byType(InlineTopicTitleEditor), findsNothing);
            final rect = tester.getRect(lock);
            final title = tester.getRect(
              find.byKey(const ValueKey('topic-header-compact-title')),
            );
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThan(width));
            expect(title.left, rect.right + DSpacing.sm);
            expect(rect.top, greaterThanOrEqualTo(title.top));
            final style = theme.textTheme.titleMedium!;
            final firstLineHeight = style.fontSize! * 2 * style.height!;
            expect(rect.center.dy, closeTo(title.top + firstLineHeight / 2, 1));
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'many tags stay beside categories and hidden tags can be removed on picker dismissal',
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
      expect(height, lessThanOrEqualTo(48));
      expect(
        tester.getCenter(overflow).dy,
        closeTo(tester.getCenter(parent).dy, 1),
      );
      expect(
        tester.getCenter(overflow).dy,
        closeTo(tester.getCenter(child).dy, 1),
      );
      expect(find.text('last activity 2m ago'), findsOneWidget);

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
      await tester.tap(find.byTooltip('Close').last);
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
        expect(tester.takeException(), isNull, reason: 'opening $width');
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
          tester
              .getRect(find.byKey(const ValueKey('topic-header-activity')))
              .left,
        );
        expect(tester.getRect(overflow).right, lessThan(width));
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'editing $width');
        final frame = tester.getRect(
          find.byKey(const ValueKey('topic-header-title-field')),
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
          final controls = DTokens.of(tester.element(control)).buttonTheme;
          expect(
            buttonSurface(tester, of: control).color,
            control == reply
                ? controls.primary.background
                : controls.outline.background,
          );
          expect(
            buttonSurface(tester, of: control).borderColor,
            control == reply
                ? controls.primary.border
                : controls.outline.border,
          );
          expect(tester.getSize(control).height, tester.getSize(reply).height);
        }
        expect(
          tester.getRect(bookmark).left - tester.getRect(reply).right,
          DSpacing.xs,
        );
        expect(
          tester.getRect(bookmark).right,
          tester.getRect(notifications).left,
        );
        expect(
          buttonSurface(tester, of: reply).borderRadius.topRight,
          Radius.circular(DTokens.of(tester.element(reply)).buttonTheme.radius),
        );
        expect(
          buttonSurface(tester, of: bookmark).borderRadius,
          BorderRadius.horizontal(
            left: Radius.circular(
              DTokens.of(tester.element(bookmark)).buttonTheme.radius,
            ),
          ),
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
            final controls = tokens.buttonTheme;
            final surface = buttonSurface(tester, of: bookmark);
            expect(surface.borderColor, controls.outline.border);
            expect(
              surface.color,
              saved ? controls.primary.background : controls.outline.background,
            );
            expect(
              surface.borderRadius,
              BorderRadius.horizontal(
                left: Radius.circular(tokens.buttonTheme.radius),
              ),
            );
            expect(
              buttonSurface(tester, of: notifications).color,
              controls.outline.background,
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
                controls.outline.background,
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
          DTokens.of(tester.element(hovered)).buttonTheme.outline.hover,
        );
        expect(
          buttonSurface(tester, of: other).color,
          DTokens.of(tester.element(other)).buttonTheme.outline.background,
        );
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
      expect(tester.getSize(list).width, 325 + workspacePanelGap);
      final row = find.byKey(const ValueKey('inbox-row-1'));
      expect(
        tester.getRect(row).left,
        greaterThanOrEqualTo(tester.getRect(list).left),
      );
      expect(
        tester.getRect(row).right,
        lessThanOrEqualTo(tester.getRect(list).right),
      );
      final timestamp = find.byKey(const ValueKey('inbox-row-time-1'));
      expect(timestamp, findsOneWidget);
      expect(find.text('First topic preview'), findsOneWidget);
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
      (widget) => widget is TopicListRow && widget.topic.id == 2,
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
      find.descendant(
        of: recommendations,
        matching: find.byKey(const ValueKey('topic-card-2')),
      ),
      findsOneWidget,
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

      await tester.tap(find.byTooltip('Back to topic list'));
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
      expect(tester.widget<Text>(heading).data, 'Latest topics');
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

  testWidgets('edits title inline and applies subcategory and tag changes', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final shell = setup.controller;
    shell.openTopicFromList(setup.rows.first);
    await tester.pumpAndSettle();
    await _scrollReaderToTop(tester);
    final title = find.byKey(const ValueKey('topic-header-title-field'));
    final frame = find.byKey(const ValueKey('topic-header-title-field'));
    final hint = find.text('Enter to save · Esc to cancel');
    expect(tester.widget<DInput>(frame).focusNode!.hasFocus, isFalse);
    expect(hint, findsNothing);
    await tester.tap(title);
    await tester.pump();
    expect(tester.widget<DInput>(frame).focusNode!.hasFocus, isTrue);
    expect(hint, findsNothing);
    expect(find.widgetWithText(DButton, 'Save'), findsNothing);
    await tester.enterText(title, 'A clearer topic title');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(shell.currentTopic?.title, 'A clearer topic title');
    expect(setup.api.topicsUpdated.last['title'], 'A clearer topic title');
    expect(tester.widget<DInput>(frame).focusNode!.hasFocus, isFalse);
    expect(hint, findsNothing);
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.enterText(title, 'Discard this title');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shell.currentTopic?.title, 'A clearer topic title');
    expect(setup.api.topicsUpdated, hasLength(1));
    expect(tester.widget<DInput>(frame).focusNode!.hasFocus, isFalse);
    expect(hint, findsNothing);

    await tester.tap(find.byTooltip('Edit topic subcategory'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-category-picker-option', 0))),
    );
    await tester.pumpAndSettle();
    expect(shell.currentTopic?.categoryId, _parent.id);
    expect(find.text('Done'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('topic-header-edit-tags')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-tag-picker-option', 'community'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(shell.currentTopic?.tags, isEmpty);
    expect(setup.api.topicTagsUpdated.single['tags'], isEmpty);
    expect(tester.takeException(), isNull);
  });

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
    expect(
      tester.getRect(edit).left,
      tester.getRect(reply).right + DSpacing.xs,
    );
    expect(
      tester.getRect(edit).center.dy,
      closeTo(tester.getRect(reply).center.dy, 1),
    );
    expect(bookmark.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(bookmark).left,
      tester.getRect(edit).right + DSpacing.xs,
    );
    expect(
      tester.getRect(bookmark).center.dy,
      closeTo(tester.getRect(reply).center.dy, 1),
    );
    final more = find.byKey(const ValueKey('post-more-actions-2'));
    expect(more.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(more).left,
      tester.getRect(bookmark).right + DSpacing.xs,
    );
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
      final jump = shell.jumpToCurrentTopicIndex(2);
      await tester.pumpAndSettle();
      await jump;
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
      final editOffset = editScroll.offset;
      final title = find.byKey(const ValueKey('topic-header-title-field'));
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      expect(editScroll.offset, closeTo(editOffset, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Future<void> _scrollReaderToTop(WidgetTester tester) async {
  final shell = ShellScope.read(tester.element(find.byType(TopicView)));
  final jump = shell.jumpToCurrentTopicIndex(0);
  await tester.pumpAndSettle();
  await jump;
}

Future<({ShellController controller, FakeDiscourseApi api, List<Topic> rows})>
_setup(
  WidgetTester tester, {
  ThemeData? theme,
  bool windowCorners = false,
  Completer<void>? topicGate,
  PluginRegistry registry = PluginRegistry.empty,
  bool recommendations = false,
  bool activityStats = false,
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
        plugins: registry.readTopic(topicPluginPayload, site.url),
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
    topicGate: topicGate,
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
    categorySearches: {'': categoryList},
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
            views: activityStats ? 61 : 0,
            likeCount: activityStats ? 29 : 0,
            wordCount: activityStats ? 2000 : 0,
            links: activityStats
                ? [
                    for (var i = 0; i < 5; i++)
                      TopicMapLink(url: 'https://example.com/$i'),
                  ]
                : const [],
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
    ContentSettingsScope(
      controller: shell.appSettings,
      child: ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: Scaffold(
            body: windowCorners
                ? TopicPresentationPreferences(
                    child: WorkspacePanelCorner(
                      radius: 10,
                      child: MainContent(
                        layout: ShellLayout.expanded,
                        registry: registry,
                      ),
                    ),
                  )
                : MainContent(layout: ShellLayout.expanded, registry: registry),
          ),
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
