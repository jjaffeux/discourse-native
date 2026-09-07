import 'dart:convert';

import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_inbox_row.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void main() {
  const siteUrl = 'https://meta.example';
  for (final hasAvatar in [true, false]) {
    testWidgets('last poster uses server avatar (available: $hasAvatar)', (
      tester,
    ) async {
      final requests = <Uri>[];
      installTestMediaPipeline(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
              'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
            ),
            200,
          );
        }),
      );
      final controller = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      final topic = TopicList.fromJson({
        'users': [
          const {
            'id': 1,
            'username': 'author',
            'avatar_template': '/author/{size}.png',
          },
          if (hasAvatar)
            {'id': 2, 'username': 'sam', 'avatar_template': '/sam/{size}.png'},
        ],
        'topic_list': const {
          'topics': [
            {
              'id': 1,
              'title': 'Topic',
              'slug': 'topic',
              'last_poster_username': 'Sam',
              'posters': [
                {'user_id': 1},
                {'user_id': 2},
              ],
            },
          ],
        },
      }, siteUrl).topics.single;
      expect(
        topic.copyWith(markRead: true).lastPosterAvatarUrl,
        topic.lastPosterAvatarUrl,
      );
      expect(
        topic.withPlugins(topic.plugins).lastPosterAvatarUrl,
        topic.lastPosterAvatarUrl,
      );
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TopicInboxRow(topic: topic, siteUrl: siteUrl, onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avatar = find.byType(AvatarImage);
      expect(avatar, findsOneWidget);
      expect(
        tester.widget<AvatarImage>(avatar).url,
        hasAvatar ? '$siteUrl/sam/90.png' : null,
      );
      expect(
        requests,
        hasAvatar ? [Uri.parse('$siteUrl/sam/90.png')] : isEmpty,
      );
      expect(
        find.descendant(of: avatar, matching: find.byType(Image)),
        hasAvatar ? findsOneWidget : findsNothing,
      );
      expect(find.text('S'), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final emoji in const [
    SiteEmoji(
      name: 'information_source',
      url: '/images/emoji/twitter/information_source.png',
    ),
    SiteEmoji(name: 'discourse2', url: '/uploads/default/discourse2.png'),
  ]) {
    testWidgets(
      'condensed preview renders :${emoji.name}: in a single truncated line',
      (tester) async {
        final artworkRequests = <Uri>[];
        installTestMediaPipeline(
          client: MockClient((request) async {
            artworkRequests.add(request.url);
            return http.Response.bytes(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
                'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
              ),
              200,
            );
          }),
        );
        final controller = ShellController(
          instanceStore: FakeInstanceStore([instance('meta.example')]),
          api: FakeDiscourseApi(
            emojisBySite: {
              siteUrl: [emoji],
            },
            customEmojisBySite: const {
              siteUrl: {'discourse2': '/uploads/default/discourse2.png'},
            },
          ),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        final excerpt =
            ':${emoji.name}: Preview with enough text to extend beyond '
            'the narrow topic list and leave room for the reply count.';
        final topic = Topic.fromJson(
          {
            'id': 1,
            'title': 'Topic preview',
            'slug': 'topic-preview',
            'excerpt': excerpt,
            'posts_count': 74,
          },
          const {},
          siteUrl,
        );

        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 325,
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

        final artwork = find.byType(EmojiImage);
        expect(artwork, findsOneWidget);
        expect(artworkRequests, [Uri.parse(siteUrl).resolve(emoji.url)]);
        expect(
          find.descendant(of: artwork, matching: find.byType(Image)),
          findsOneWidget,
        );
        expect(find.text(':${emoji.name}:'), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(excerpt))),
          findsOneWidget,
        );
        final preview = tester.renderObject<RenderParagraph>(
          find.ancestor(of: artwork, matching: find.byType(RichText)),
        );
        expect(preview.maxLines, 1);
        expect(preview.overflow, TextOverflow.ellipsis);
        expect(preview.didExceedMaxLines, isTrue);
        final replies = tester.getRect(find.text('73'));
        expect(preview.paintBounds.height, lessThan(30));
        expect(
          preview.localToGlobal(Offset(preview.size.width, 0)).dx,
          lessThan(replies.left),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
