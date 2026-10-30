import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';
import 'support/topic_post_list.dart';

void main() => mobileReactionScrollTests();

void mobileReactionScrollTests({bool native = false}) {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        );
  });
  for (final picker in ['compact', 'double tap']) {
    testWidgets(
      'reacting with $picker on mobile preserves the topic reading position',
      (tester) async {
        const site = 'https://meta.discourse.org';
        final config = installedPlugins.models.siteConfig({
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': '+1|clap',
        }, site);
        final posts = [
          for (var id = 1; id <= 30; id++)
            Post.fromJson(
              {
                'id': id,
                'post_number': id,
                'username': 'sam',
                'cooked': List.filled(
                  id == 4 ? 450 : 3,
                  '<p>Post $id discusses sailing and the community.</p>',
                ).join(),
                'actions_summary': const [
                  {'id': 2, 'can_act': true},
                ],
                'reactions': const <Object>[],
                'reaction_users_count': 0,
              },
              site,
              extensions: pluginRegistry,
            ),
        ];
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          reactionGate: gate,
          feeds: const {
            '/latest.json': [
              Topic(id: 7, title: 'Discussion', slug: 'discussion'),
            ],
          },
          topics: {7: topicPayload(id: 7, title: 'Discussion', posts: posts)},
          siteConfigs: {site: config},
        );
        await pumpShell(
          tester,
          phone,
          instances: [
            instance(
              'meta.discourse.org',
            ).copyWith(user: const DiscourseUser(username: 'reader')),
          ],
          api: api,
          authenticator: FakeAuthenticator()..keys[site] = 'key',
        );
        final shell = tester
            .widget<ShellScope>(find.byType(ShellScope))
            .notifier!;
        shell.openTopicPost(siteUrl: site, topicId: 7, postNumber: 4);
        await _settle(tester);
        final scroll = topicPostList(tester).controller!;
        final button = find.byKey(const ValueKey('post-reaction-button-4'));
        await tester.ensureVisible(button);
        await _settle(tester);
        scroll.jumpTo(scroll.offset + tester.getTopLeft(button).dy - 600);
        await _settle(tester);
        final offset = scroll.offset;
        final bounds = tester.getRect(button);
        debugPrint('REACTION before offset=$offset button=$bounds');
        if (picker == 'double tap') {
          final point = tester.getCenter(button) - const Offset(0, 100);
          await tester.tapAt(point);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(point);
        } else {
          await tester.tap(button);
          await _settle(tester);
          expect(find.byType(ReactionGrid), findsOneWidget);
          await tester.tap(
            find.descendant(
              of: find.byType(ReactionGrid),
              matching: find.bySemanticsLabel('clap'),
            ),
          );
        }
        await _settle(tester);
        final pendingOffset = scroll.offset;
        gate.complete();
        await _settle(tester);
        debugPrint('REACTION after offset=${scroll.offset}');
        expect(api.reacted, [
          (postId: 4, reaction: picker == 'double tap' ? 'heart' : 'clap'),
        ]);
        expect(scroll.offset, closeTo(offset, 1));
        expect(pendingOffset, closeTo(offset, 1));
        expect(tester.getRect(button).top, closeTo(bounds.top, 1));
        expect(tester.takeException(), isNull);
      },
      variant: native
          ? TargetPlatformVariant.only(TargetPlatform.iOS)
          : const TargetPlatformVariant({
              TargetPlatform.iOS,
              TargetPlatform.android,
            }),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 300; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('The mobile reader did not settle');
}
