import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void main() {
  testWidgets('suggested and related titles render world map emoji', (
    tester,
  ) async {
    final site = instance('meta.example');
    installTestMediaPipeline(
      client: MockClient((_) async => http.Response('', 404)),
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        emojisBySite: {
          site.url: const [
            SiteEmoji(
              name: 'world_map',
              url: '/images/emoji/twitter/world_map.png',
            ),
          ],
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        const TopicDetail(
          id: 1,
          title: 'Topic',
          stream: [1],
          postsCount: 1,
          recommendations: TopicRecommendations(
            sources: [
              TopicRecommendationSource(
                definition: coreSuggestedTopicRecommendationSource,
                topics: [
                  Topic(
                    id: 2,
                    title: ':world_map: Weekly product updates',
                    slug: 'suggested',
                  ),
                ],
              ),
              TopicRecommendationSource(
                definition: discourseAiRelatedTopicRecommendationSource,
                topics: [
                  Topic(
                    id: 3,
                    title: ':world_map: Related updates',
                    slug: 'related',
                  ),
                ],
              ),
            ],
          ),
        ),
      )
      ..putAll(site.url, const [
        Post(id: 1, postNumber: 1, username: 'sam', cooked: '<p>Post</p>'),
      ]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'topic', title: 'Topic'),
    );
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: TopicView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final suggested = find.byWidgetPredicate(
      (widget) => widget is TopicListRow && widget.topic.id == 2,
    );
    await tester.ensureVisible(suggested);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SiteEmojiImage>(
            find.descendant(
              of: suggested,
              matching: find.byType(SiteEmojiImage),
            ),
          )
          .name,
      'world_map',
    );
    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    final related = find.byWidgetPredicate(
      (widget) => widget is TopicListRow && widget.topic.id == 3,
    );
    expect(
      tester
          .widget<SiteEmojiImage>(
            find.descendant(of: related, matching: find.byType(SiteEmojiImage)),
          )
          .name,
      'world_map',
    );
    expect(tester.takeException(), isNull);
  });
}
