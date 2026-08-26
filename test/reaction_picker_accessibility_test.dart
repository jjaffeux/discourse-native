import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('reaction cell has one exact name and native keyboard action', (
    tester,
  ) async {
    final previousEmojiCache = EmojiCache.instance;
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(() {
      EmojiCache.instance.clear();
      EmojiCache.instance = previousEmojiCache;
    });

    const config = SiteConfig(mainReaction: 'clap', offeredReactions: ['clap']);
    final site = instance('meta.example').copyWith(
      user: const DiscourseUser(username: 'reader'),
      config: config,
    );
    final api = FakeDiscourseApi();
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);

    final post = Post.fromJson(
      const {
        'id': 1,
        'post_number': 1,
        'username': 'author',
        'cooked': '<p>Post</p>',
        'actions_summary': [
          {'id': Post.likeActionId, 'can_act': true},
        ],
        'reactions': [
          {'id': 'clap', 'count': 1},
        ],
        'current_user_reaction': {'id': 'clap', 'can_undo': true},
        'reaction_users_count': 1,
      },
      _siteUrl,
      extensions: pluginRegistry,
    );

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: ReactionGrid(
                siteUrl: _siteUrl,
                post: post,
                onPicked: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The failed artwork keeps its visible shortcode fallback, while the
      // cell itself owns one concise name rather than "clap, :clap:".
      expect(find.text(':clap:'), findsOneWidget);
      final target = find.bySemanticsLabel('clap');
      expect(target, findsOneWidget);
      expect(tester.getSize(target), const Size.square(ReactionGrid.cell));
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: target, matching: find.byType(InkWell)),
            )
            .mouseCursor,
        SystemMouseCursors.click,
      );
      expect(
        tester.getSemantics(target),
        isSemantics(
          label: 'clap',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.getSemantics(target),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
    } finally {
      semantics.dispose();
    }
  });
}
