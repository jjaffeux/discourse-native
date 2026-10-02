import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/assign/assign_module.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void main() {
  for (final width in [280.0, 500.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('sparse cards hug content at $width/$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Future<void> render(List<TopicTag> tags) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: TopicListRow(
                    topic: Topic(
                      id: 1,
                      title: 'Short title',
                      slug: 'short',
                      replyCount: 2,
                      tags: tags,
                    ),
                    siteUrl: 'https://compact.example',
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await render(const []);
        final titleBottom = tester.getBottomLeft(find.byType(TopicTitle)).dy;
        final repliesTop = tester.getTopLeft(find.text('2 replies')).dy;
        expect(repliesTop - titleBottom, lessThanOrEqualTo(12));
        final sparseHeight = tester
            .getSize(find.byKey(const ValueKey('topic-card-1')))
            .height;
        await render(const [TopicTag(name: 'design')]);
        if (width >= 600 && scale == 1) {
          expect(
            tester.getSize(find.byKey(const ValueKey('topic-card-1'))).height,
            lessThanOrEqualTo(sparseHeight + 8),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('topic metadata is visible by default', (tester) async {
    await _setup(tester, enableEvents: true);
    final row = find.byKey(const ValueKey('topic-card-1'));
    final tag = find.descendant(of: row, matching: find.text('design'));
    final assignments = find.descendant(
      of: row,
      matching: find.text('Assigned to'),
    );
    expect(tag, findsOneWidget);
    expect(assignments, findsOneWidget);
    final poster = find.descendant(
      of: row,
      matching: find.text('Last post by sam · '),
    );
    final avatar = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is DAvatar && widget.dimension == 22,
      ),
    );
    expect(poster, findsOneWidget);
    expect(avatar, findsOneWidget);
  });

  for (final (width, scale, direction, dark) in [
    (1200.0, 1.0, TextDirection.ltr, false),
    (390.0, 1.0, TextDirection.ltr, true),
    (280.0, 2.0, TextDirection.rtl, false),
  ]) {
    testWidgets(
      'topic lists show five tags then a remaining count at $width/$scale/$direction',
      (tester) async {
        final shell = await _setup(
          tester,
          width: width,
          scale: scale,
          direction: direction,
          dark: dark,
          enableAssignments: false,
        );
        final semantics = tester.ensureSemantics();
        try {
          final siteUrl = shell.currentInstance!.url;
          final topic = shell.store.read<Topic>(siteUrl, 1)!;
          final row = find.byKey(const ValueKey('topic-card-1'));
          Finder within(Finder finder) =>
              find.descendant(of: row, matching: finder);
          final mouse = width >= 600
              ? await tester.createGesture(kind: PointerDeviceKind.mouse)
              : null;
          if (mouse != null) {
            addTearDown(mouse.removePointer);
            await mouse.addPointer(location: Offset.zero);
          }

          for (final count in [0, 5, 6, 23, 5]) {
            final tags = [
              for (var index = 1; index <= count; index++)
                TopicTag(name: 'tag-$index'),
            ];
            shell.store.put(siteUrl, topic.copyWith(tags: tags));
            await tester.pumpAndSettle();
            final visibleTags = tester
                .widgetList<Text>(within(find.byType(Text)))
                .map((text) => text.data)
                .where((label) => label?.startsWith('tag-') ?? false);
            expect(visibleTags, tags.take(5).map((tag) => tag.name));
            final overflow = within(
              find.byKey(const ValueKey('topic-row-tag-overflow')),
            );
            if (count <= 5) {
              expect(overflow, findsNothing);
            } else {
              final remaining = count - 5;
              expect(within(find.text('+$remaining')), findsOneWidget);
              expect(
                tester.getSemantics(overflow).label,
                contains('$remaining more ${remaining == 1 ? 'tag' : 'tags'}'),
              );
              final badge = tester.widget<DBadge>(overflow);
              final firstTag = tester.widget<DBadge>(
                within(
                  find.ancestor(
                    of: within(find.text('tag-1')),
                    matching: find.byType(DBadge),
                  ),
                ),
              );
              expect(badge.size, firstTag.size);
              expect(badge.backgroundColor, firstTag.backgroundColor);
              expect(badge.foregroundColor, firstTag.foregroundColor);
              final rowBounds = tester.getRect(row);
              expect(
                rowBounds.contains(tester.getRect(overflow).topLeft),
                isTrue,
              );
              expect(
                rowBounds.contains(tester.getRect(overflow).bottomRight),
                isTrue,
              );

              if (count == 23) {
                final message = tags
                    .skip(5)
                    .map((tag) => '#${tag.name}')
                    .join(', ');
                expect(within(find.byTooltip(message)), findsOneWidget);
                await tester.ensureVisible(overflow);
                await tester.pumpAndSettle();
                if (width < 600) {
                  await tester.longPress(overflow);
                } else {
                  await mouse!.moveTo(tester.getCenter(overflow));
                  await tester.pump(const Duration(milliseconds: 300));
                }
                await tester.pump(const Duration(milliseconds: 160));
                expect(find.text(message), findsOneWidget);
                tester
                    .state<DTooltipState>(within(find.byTooltip(message)))
                    .hide();
                await mouse?.moveTo(Offset.zero);
                await tester.pumpAndSettle();
                expect(shell.currentContent?.topicId, isNull);
              }
            }
            expect(tester.takeException(), isNull);
          }
          final lastTag = within(find.text('tag-5'));
          await tester.ensureVisible(lastTag);
          await tester.pumpAndSettle();
          await tester.tap(lastTag);
          await tester.pumpAndSettle();
          expect(shell.currentContent?.tagName, 'tag-5');
          expect(shell.currentContent?.topicId, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final (width, scale) in [(780.0, 1.0), (1200.0, 1.0), (1200.0, 2.0)]) {
    testWidgets('topic category and tags share a baseline at $width/$scale', (
      tester,
    ) async {
      await _setup(tester, width: width, scale: scale);
      final header = find.byKey(const ValueKey('compact-topic-list-header'));
      expect(
        find.descendant(of: header, matching: find.text('Category')),
        findsNothing,
      );
      final row = find.byKey(const ValueKey('topic-card-1'));
      final category = find.descendant(
        of: row,
        matching: find.text('Community'),
      );
      final tag = find.descendant(of: row, matching: find.text('design'));
      double baseline(Finder finder) {
        final box = tester.renderObject<RenderBox>(finder);
        return box.localToGlobal(Offset.zero).dy +
            box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
      }

      expect(baseline(category), closeTo(baseline(tag), 0.01));
      expect(
        tester.getRect(category).right,
        lessThan(tester.getRect(tag).left),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in TopicListDisplayMode.values) {
    testWidgets('topic titles render site emoji in $mode', (tester) async {
      installTestMediaPipeline(
        client: MockClient(
          (_) async => http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
              'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
            ),
            200,
          ),
        ),
      );
      final shell = await _setup(
        tester,
        mode: mode,
        emojis: const [
          SiteEmoji(name: 'information_source', url: '/emoji/info.png'),
          SiteEmoji(name: 'discourse2', url: '/uploads/custom-discourse.png'),
        ],
        customEmojis: const {
          'discourse2': 'https://compact.example/uploads/custom-discourse.png',
        },
      );
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TopicListRow(
                topic: const Topic(
                  id: 100,
                  title: 'Welcome :information_source: :discourse2:',
                  slug: 'welcome',
                  excerpt: ':information_source: Help from :discourse2:',
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
            .map((emoji) => emoji.name),
        [
          'information_source',
          'discourse2',
          'information_source',
          'discourse2',
        ],
      );
      expect(
        tester
            .widgetList<EmojiImage>(find.byType(EmojiImage))
            .map((emoji) => emoji.url),
        [
          'https://compact.example/images/emoji/twitter/information_source.png',
          'https://compact.example/uploads/custom-discourse.png',
          'https://compact.example/images/emoji/twitter/information_source.png',
          'https://compact.example/uploads/custom-discourse.png',
        ],
      );
      expect(find.byType(Image), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [280.0, 640.0, 1200.0]) {
    testWidgets('one topic layout ignores legacy mode at $width', (
      tester,
    ) async {
      await _setup(tester, width: width);
      final row = find.byKey(const ValueKey('topic-card-1'));
      expect(tester.getRect(row).left, width < 600 ? 16 : 0);
      expect(tester.getRect(row).width, width < 600 ? width - 32 : width);
      expect(find.byType(DTable), findsNothing);
      expect(find.byKey(const ValueKey('topic-list-display')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0]) {
    testWidgets('mobile cards place age above wrapping footer at $width', (
      tester,
    ) async {
      final shell = await _setup(tester, width: width, enableEvents: true);
      final card = find.byKey(const ValueKey('topic-card-1'));
      Finder within(Finder finder) =>
          find.descendant(of: card, matching: finder);
      final title = within(
        find.text('Topic 1: a conversation about improving our community'),
      );
      final date = within(find.byKey(const ValueKey('event-schedule-summary')));
      final author = within(find.textContaining('Last post by sam'));
      final replies = within(find.textContaining('24 replies'));
      final age = within(find.byKey(const ValueKey('inbox-row-time-1')));
      final tags = within(find.text('mobile'));
      final avatar = within(
        find.byWidgetPredicate(
          (widget) => widget is DAvatar && widget.dimension == 22,
        ),
      );
      expect(find.byKey(const ValueKey('event-calendar-stamp')), findsNothing);
      expect(
        tester.getRect(date).top,
        greaterThanOrEqualTo(tester.getRect(title).bottom),
      );
      expect(find.text('Wed, Oct 14 · 8:00 PM'), findsOneWidget);
      expect(
        tester.getRect(avatar).top,
        greaterThan(tester.getRect(tags).bottom),
      );
      expect(
        tester.getRect(replies).top,
        greaterThanOrEqualTo(tester.getRect(author).top),
      );
      expect(tester.getRect(age).top, closeTo(tester.getRect(title).top, 1));
      expect(tester.getRect(age).top, lessThan(tester.getRect(tags).top));
      expect(tester.getRect(age).right, closeTo(width - 16, 1));
      expect(within(find.textContaining('24 replies')), findsOneWidget);
      await tester.tap(date);
      await tester.pumpAndSettle();
      expect(find.text('Event schedule'), findsNothing);
      expect(shell.currentContent?.topicId, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, sharesLine) in [(390.0, false), (590.0, true)]) {
    testWidgets('mobile footer follows available width at $width', (
      tester,
    ) async {
      final shell = await _setup(
        tester,
        width: width,
        enableAssignments: false,
      );
      final site = shell.currentInstance!.url;
      final topic = shell.store.read<Topic>(site, 1)!;
      shell.store.put(site, topic.copyWith(tags: const []));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('topic-card-1'));
      final category = find.descendant(
        of: card,
        matching: find.text('Community'),
      );
      final avatar = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) => widget is DAvatar && widget.dimension == 22,
        ),
      );
      final categoryRect = tester.getRect(category);
      final avatarRect = tester.getRect(avatar);
      if (sharesLine) {
        expect(avatarRect.center.dy, closeTo(categoryRect.center.dy, 8));
      } else {
        expect(avatarRect.top, greaterThan(categoryRect.bottom));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale, direction) in [
    (1200.0, 1.0, TextDirection.ltr),
    (390.0, 1.0, TextDirection.ltr),
    (320.0, 2.0, TextDirection.rtl),
  ]) {
    testWidgets(
      'conversation rows keep title, excerpt and metadata at $width/$scale/$direction',
      (tester) async {
        await _setup(
          tester,
          width: width,
          scale: scale,
          direction: direction,
          mode: TopicListDisplayMode.card,
          enableEvents: true,
          nestedCategories: true,
        );
        final card = find.byKey(const ValueKey('topic-card-1'));
        expect(
          find.descendant(of: card, matching: find.text('Category')),
          findsNothing,
        );
        final category = find.descendant(
          of: card,
          matching: find.text('Features'),
        );
        final tag = find.descendant(of: card, matching: find.text('design'));
        final title = find.descendant(
          of: card,
          matching: find.text(
            'Topic 1: a conversation about improving our community',
          ),
        );
        expect(
          tester.getRect(tag).top,
          greaterThan(tester.getRect(title).bottom),
        );
        if (width == 1200) {
          double baseline(Finder finder) {
            final box = tester.renderObject<RenderBox>(finder);
            return box.localToGlobal(Offset.zero).dy +
                box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
          }

          expect(baseline(tag), closeTo(baseline(category), 0.01));
          final secondTag = find.descendant(
            of: card,
            matching: find.text('mobile'),
          );
          expect(baseline(secondTag), closeTo(baseline(tag), 0.01));
          expect(
            tester.getRect(secondTag).left - tester.getRect(tag).right,
            lessThanOrEqualTo(14),
          );
          expect(
            tester.getRect(tag).left,
            greaterThan(tester.getRect(category).right),
          );
        }
        expect(
          find.descendant(of: card, matching: find.byType(DCardFooter)),
          findsNothing,
        );
        expect(
          find.ancestor(of: card, matching: find.byType(DCard)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('24 replies'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Excerpt 1')),
          findsOneWidget,
        );
        final replies = find.descendant(
          of: card,
          matching: find.textContaining('24 replies'),
        );
        expect(
          tester.getRect(replies).width,
          closeTo(tester.getSize(replies).width, .01),
          reason: 'Inline metadata must apply text scaling only once.',
        );
        expect(tester.getRect(card).width, width < 600 ? width - 32 : width);
        expect(tester.getRect(card).width, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    for (final mode in TopicListDisplayMode.values) {
      testWidgets('topic tags retain their outline on hover in $mode/$dark', (
        tester,
      ) async {
        await _setup(tester, dark: dark, mode: mode, focusPolicy: true);
        final row = find.byKey(const ValueKey('topic-card-1'));
        final tag = find.descendant(of: row, matching: find.text('design'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        for (final hovering in [true, false]) {
          await mouse.moveTo(
            hovering ? tester.getCenter(tag) : const Offset(1300, 800),
          );
          await tester.pump();
          for (final elapsed in [0, 50, 100, 150]) {
            await tester.pump(Duration(milliseconds: elapsed));
            final surface =
                tester
                        .renderObject<RenderDecoratedBox>(
                          find
                              .ancestor(
                                of: tag,
                                matching: find.byWidgetPredicate(
                                  (widget) =>
                                      widget is DecoratedBox &&
                                      widget.decoration is BoxDecoration,
                                ),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration;
            expect(surface.border!.top.color.a, greaterThan(0));
            final rowSurface = tester.widget<Container>(
              find
                  .descendant(
                    of: row,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Container &&
                          widget.decoration is BoxDecoration,
                    ),
                  )
                  .first,
            );
            expect(
              (rowSurface.decoration! as BoxDecoration).color,
              hovering
                  ? DTokens.of(
                      tester.element(row),
                    ).primary.withValues(alpha: .06)
                  : Colors.transparent,
            );
            expect(
              find.descendant(of: row, matching: find.byType(DTable)),
              findsNothing,
            );
            expect(
              find.descendant(of: row, matching: find.byType(DCardFooter)),
              findsNothing,
            );
          }
        }
      });
    }
  }

  for (final (width, scale, direction) in [
    (1200.0, 1.0, TextDirection.ltr),
    (780.0, 1.0, TextDirection.ltr),
    (390.0, 1.0, TextDirection.ltr),
    (320.0, 2.0, TextDirection.rtl),
  ]) {
    testWidgets('category names stay on one line at $width/$scale/$direction', (
      tester,
    ) async {
      await _setup(
        tester,
        width: width,
        scale: scale,
        direction: direction,
        nestedCategories: true,
      );
      final row = find.byKey(const ValueKey('topic-card-1'));
      Finder within(Finder finder) =>
          find.descendant(of: row, matching: finder);
      final parent = within(find.text('Discourse Native App'));
      final child = within(find.text('Features'));
      for (final label in [parent, child]) {
        expect(
          tester.getSize(label).height,
          closeTo(((width < 600 ? 16.5 : 21) * scale).ceilToDouble(), .01),
        );
      }
      final chevron = within(
        find.byKey(const ValueKey(('topic-row-category-chevron', 1, 2))),
      );
      expect(
        tester.getCenter(chevron).dy,
        closeTo(tester.getCenter(child).dy, .01),
      );
      expect(
        within(find.bySemanticsLabel('Parent category: Discourse Native App')),
        findsOneWidget,
      );
      expect(
        within(find.bySemanticsLabel('Category: Features')),
        findsOneWidget,
      );
      if (tester.renderObject<RenderParagraph>(parent).didExceedMaxLines) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        final labelsBeforeHover = find
            .text('Discourse Native App')
            .evaluate()
            .length;
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(parent));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(
          find.text('Discourse Native App'),
          findsNWidgets(labelsBeforeHover + 1),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in TopicListDisplayMode.values) {
    testWidgets('$mode keeps event stamps and assignments together', (
      tester,
    ) async {
      final shell = await _setup(tester, mode: mode, enableEvents: true);
      expect(
        find.byKey(const ValueKey('event-calendar-stamp')),
        findsOneWidget,
      );
      expect(find.text('joffrey'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^.* · 8:00 PM$')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-schedule-summary')));
      await tester.pumpAndSettle();
      expect(find.text('Event schedule'), findsNothing);
      expect(shell.currentContent?.topicId, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'legacy list settings preserve the lazy viewport and visible topic',
    (tester) async {
      final shell = await _setup(tester, mode: TopicListDisplayMode.card);
      final list = find.byType(SuperListView);
      final scroll = tester.widget<SuperListView>(list).controller!;
      await tester.drag(list, const Offset(0, -700));
      await tester.pumpAndSettle();
      final visible =
          find
                  .byType(DItem)
                  .evaluate()
                  .where((element) {
                    final bounds = tester.getRect(
                      find.byWidget(element.widget),
                    );
                    return bounds.top >= 0 && bounds.bottom < 680;
                  })
                  .first
                  .widget
                  .key
              as ValueKey<String>;
      final id = visible.value.split('-').last;

      await shell.appSettings.setTopicListMode(TopicListDisplayMode.compact);
      await tester.pumpAndSettle();
      expect(tester.widget<SuperListView>(list).controller, same(scroll));
      expect(
        find.byKey(ValueKey('topic-card-$id')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('topic-card-60')), findsNothing);
      expect(
        find.byKey(const ValueKey('compact-topic-list-header')),
        findsNothing,
      );

      await shell.appSettings.setTopicListMode(TopicListDisplayMode.card);
      await tester.pumpAndSettle();
      expect(tester.widget<SuperListView>(list).controller, same(scroll));
      expect(
        find.byKey(ValueKey('topic-card-$id')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sparse assignments follow the metadata without reserving a column',
    (tester) async {
      await _setup(tester);
      final header = find.byKey(const ValueKey('compact-topic-list-header'));
      expect(
        find.descendant(of: header, matching: find.text('Assigned to')),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.byType(DTableHead)),
        findsNothing,
      );
      final assigned = find.byKey(const ValueKey('topic-card-1'));
      final unassigned = find.byKey(const ValueKey('topic-card-2'));
      expect(
        find.descendant(of: assigned, matching: find.text('Assigned to')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unassigned, matching: find.text('Assigned to')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Assigned to: none'), findsNothing);
      final tag = find.descendant(of: assigned, matching: find.text('mobile'));
      final person = find.text('joffrey');
      expect(
        tester.getRect(person).top,
        greaterThan(tester.getRect(tag).bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale, direction, dark) in [
    (1200.0, 1.0, TextDirection.ltr, false),
    (390.0, 1.0, TextDirection.ltr, true),
    (320.0, 2.0, TextDirection.rtl, false),
  ]) {
    testWidgets(
      'full names and post assignments wrap at $width/$scale/$direction',
      (tester) async {
        final shell = await _setup(
          tester,
          width: width,
          scale: scale,
          direction: direction,
          dark: dark,
        );
        final site = shell.currentInstance!.url;
        final topic = shell.store.read<Topic>(site, 1)!;
        const name = 'Finance operations and customer success';
        shell.store.put(
          site,
          topic.copyWith(
            tags: const [],
            plugins: const PluginRegistry([AssignPlugin()]).readTopic(const {
              'can_assign': false,
              'indirectly_assigned_to': {
                '108': {
                  'post_number': 22,
                  'assigned_to': {
                    'name': 'finance-operations',
                    'full_name': name,
                  },
                },
                '109': {
                  'post_number': 26,
                  'assigned_to': {
                    'username': 'michael',
                    'name': 'Michael Fitz-Payne',
                  },
                },
              },
            }, site),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(name), findsOneWidget);
        expect(find.text('#22'), findsOneWidget);
        expect(find.text('+1'), findsOneWidget);
        final text = tester.renderObject<RenderParagraph>(find.text(name));
        expect(text.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
        final disclosure = find.bySemanticsLabel(
          'Open topic to view all 2 assignments',
        );
        await tester.ensureVisible(disclosure);
        await tester.pumpAndSettle();
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('topic assignment disclosure opens the owning topic', (
    tester,
  ) async {
    final shell = await _setup(tester);
    expect(find.text('Assigned to'), findsOneWidget);
    expect(find.text('Excerpt 1'), findsOneWidget);
    expect(find.text('joffrey'), findsOneWidget);
    final disclosure = find.bySemanticsLabel(
      'Open topic to view all 2 assignments',
    );
    expect(disclosure, findsOneWidget);
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 1);
    expect(
      shell.consumeTopicProperty(shell.currentInstance!.url, 1, 'Assignments'),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('topic-card-2')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 2);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale, direction) in [
    (390.0, 1.0, TextDirection.ltr),
    (320.0, 2.0, TextDirection.rtl),
    (780.0, 1.0, TextDirection.rtl),
  ]) {
    testWidgets(
      'topic rows retain metadata at width $width scale $scale $direction',
      (tester) async {
        await _setup(tester, width: width, scale: scale, direction: direction);
        expect(find.text('Assigned to'), findsOneWidget);
        expect(find.text('joffrey'), findsOneWidget);
        expect(find.text('Excerpt 1'), findsOneWidget);
        expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('assignment metadata requires serializer evidence', (
    tester,
  ) async {
    await _setup(tester, enableAssignments: false);
    expect(find.text('Assigned to'), findsNothing);
    expect(find.text('Assigned to '), findsNothing);
    expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic assignment metadata updates with its topic record', (
    tester,
  ) async {
    final shell = await _setup(tester);
    final siteUrl = shell.currentInstance!.url;
    final topic = shell.store.read<Topic>(siteUrl, 1)!;
    shell.store.put(
      siteUrl,
      topic.copyWith(
        plugins: const PluginRegistry([AssignPlugin()]).readTopic(const {
          'assigned_to_group': {'name': 'support'},
        }, siteUrl),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('joffrey'), findsNothing);
    expect(
      find.bySemanticsLabel('topic assigned to support, group @support'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Open topic to view all 2 assignments'),
      findsNothing,
    );
    shell.store.put(
      siteUrl,
      topic.copyWith(
        plugins: const PluginRegistry([
          AssignPlugin(),
        ]).readTopic(const {'can_assign': false}, siteUrl),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assigned to'), findsNothing);
    expect(find.text('support'), findsNothing);
    final second = shell.store.read<Topic>(siteUrl, 2)!;
    shell.store.put(
      siteUrl,
      second.copyWith(
        plugins: const PluginRegistry([AssignPlugin()]).readTopic(const {
          'assigned_to_user': {
            'username': 'michael',
            'name': 'Michael Fitz-Payne',
          },
        }, siteUrl),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assigned to'), findsOneWidget);
    expect(find.text('Michael Fitz-Payne'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic keyboard navigation opens the selected topic', (
    tester,
  ) async {
    final shell = await _setup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone topic rows ignore legacy display preferences', (
    tester,
  ) async {
    final shell = await _setup(tester, mode: TopicListDisplayMode.card);
    final topic = shell.store.read<Topic>(shell.currentInstance!.url, 1)!;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TopicListRow(topic: topic, onTap: () {}),
          ),
        ),
      ),
    );
    expect(find.text('Excerpt 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
    await shell.appSettings.setTopicListMode(TopicListDisplayMode.compact);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
    expect(find.text('Excerpt 1'), findsOneWidget);
    expect(find.text('joffrey'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<ShellController> _setup(
  WidgetTester tester, {
  double width = 1200,
  bool enableAssignments = true,
  bool enableEvents = false,
  bool nestedCategories = false,
  bool dark = false,
  bool focusPolicy = false,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  TopicListDisplayMode mode = TopicListDisplayMode.compact,
  List<SiteEmoji> emojis = const [],
  Map<String, String> customEmojis = const {},
}) async {
  await tester.binding.setSurfaceSize(Size(width, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const user = DiscourseUser(id: 7, username: 'sam', timezone: 'Europe/Paris');
  final site = instance('compact.example').copyWith(
    user: user,
    config: SiteConfig(
      plugins: PluginData.none.withValue(
        eventSettingsKey,
        const EventSettings(enabled: true),
      ),
    ),
  );
  const registry = PluginRegistry([AssignPlugin(), EventTopicPlugin()]);
  final rows = [
    for (var id = 1; id <= 60; id++)
      Topic(
        id: id,
        title: 'Topic $id: a conversation about improving our community',
        slug: 'topic-$id',
        categoryId: nestedCategories ? 2 : 1,
        postsCount: 25,
        replyCount: 24,
        unreadPosts: id == 1 ? 4 : 0,
        lastPosterUsername: 'sam',
        bumpedAt: DateTime.now().subtract(Duration(minutes: id)),
        tags: const [
          TopicTag(name: 'design'),
          TopicTag(name: 'mobile'),
        ],
        excerpt: 'Excerpt $id',
        plugins: registry.readTopic({
          if (enableEvents && id == 1) ...{
            'event_starts_at': '2026-10-14T20:00:00+02:00',
            'event_ends_at': '2026-10-14T21:00:00+02:00',
            'event_timezone': 'Europe/Paris',
          },
          ...(!enableAssignments
              ? const {}
              : id == 1
              ? const {
                  'can_assign': false,
                  'assigned_to_user': {'username': 'joffrey'},
                  'indirectly_assigned_to': {
                    '108': {
                      'post_number': 8,
                      'assigned_to': {'name': 'design'},
                    },
                  },
                }
              : const {'can_assign': false}),
        }, site.url),
      ),
  ];
  final plugins = PluginInstaller.install(
    const PluginManifest([assignModule, discourseEventsModule]),
  );
  final shell = ShellController(
    plugins: plugins,
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      user: user,
      feeds: {'/latest.json': rows},
      emojisBySite: {site.url: emojis},
      customEmojisBySite: {site.url: customEmojis},
      categoryList: nestedCategories
          ? const [
              TopicCategory(
                id: 1,
                name: 'Discourse Native App',
                color: 'A787CB',
                styleType: 'icon',
                icon: 'folder',
                readRestricted: true,
              ),
              TopicCategory(
                id: 2,
                parentCategoryId: 1,
                name: 'Features',
                color: '53A7C5',
                styleType: 'icon',
                icon: 'lightbulb',
                readRestricted: true,
              ),
            ]
          : const [TopicCategory(id: 1, name: 'Community', color: 'A787CB')],
    ),
    authenticator: FakeAuthenticator()..keys[site.url] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    appSettingsStore: AppSettingsStore(
      persistence: MemoryAppSettingsPersistence(topicListMode: mode.name),
    ),
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
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: focusPolicy
            ? (_, child) => DFocusHighlight(child: child!)
            : null,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: ListenableBuilder(
                listenable: shell,
                builder: (_, _) =>
                    TopicListView(feed: shell.currentFeed!, inbox: true),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}
