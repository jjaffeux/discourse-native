import 'package:discourse_native/discourse_plugin_sdk.dart'
    show Topic, TopicActivityState;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_reading_policy_fixture.dart';

void main() {
  const caughtUp = Topic(
    id: 1,
    title: 'A topic title',
    slug: 'topic',
    lastReadPostNumber: 10,
    highestPostNumber: 10,
  );
  final cases = [
    ('caught up', caughtUp, true),
    ('never read', const Topic(id: 1, title: 'New', slug: 'new'), false),
    ('new topic', caughtUp.copyWith(seen: false), false),
    ('unread replies', caughtUp.copyWith(unreadPosts: 2), false),
    ('new replies', caughtUp.copyWith(newPosts: 2), false),
    ('position behind', caughtUp.copyWith(highestPostNumber: 11), false),
    (
      'activity unread despite position',
      caughtUp.copyWith(plugins: activityTopicData()),
      false,
    ),
    (
      'activity caught up without position',
      const Topic(
        id: 1,
        title: 'Activity',
        slug: 'activity',
      ).copyWith(plugins: activityTopicData(TopicActivityState.caughtUp)),
      true,
    ),
    (
      'marked read after unseen replies',
      caughtUp.copyWith(seen: false, unreadPosts: 3).copyWith(markRead: true),
      true,
    ),
  ];

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('$name titles reflect read state without fading muted rows', (
      tester,
    ) async {
      final tokens = theme.extension<DTokens>()!;
      for (final (state, topic, read) in cases) {
        for (final muted in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: TopicListRow(
                  siteUrl: 'https://example.invalid',
                  topic: Topic(
                    id: topic.id,
                    title: topic.title,
                    slug: topic.slug,
                    lastReadPostNumber: topic.lastReadPostNumber,
                    highestPostNumber: topic.highestPostNumber,
                    seen: topic.seen,
                    unreadPosts: topic.unreadPosts,
                    newPosts: topic.newPosts,
                    plugins: topic.plugins,
                    muted: muted,
                  ),
                  onTap: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find.byType(TopicTitle),
                  matching: find.byType(RichText),
                )
                .first,
          );
          final style = paragraph.text.style!;
          final where = '$state, muted=$muted';
          expect(
            style.fontWeight,
            read ? FontWeight.w400 : FontWeight.w700,
            reason: where,
          );
          expect(
            style.color,
            read
                ? tokens.titleRead
                : muted
                ? tokens.mutedForeground
                : tokens.foreground,
            reason: where,
          );
          // Inspect the rendered opacity, so an ancestor cannot wash out the
          // title, metadata and controls after their colors were resolved.
          for (
            RenderObject? node = paragraph;
            node != null;
            node = node.parent
          ) {
            if (node is RenderOpacity) {
              expect(node.opacity, 1, reason: where);
            }
            if (node is RenderAnimatedOpacity) {
              expect(node.opacity.value, 1, reason: where);
            }
          }
          expect(tester.takeException(), isNull, reason: where);
        }
      }
    });
  }
}
