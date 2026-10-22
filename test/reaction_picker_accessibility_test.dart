import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_services.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _siteUrl = 'https://meta.example';

void main() {
  for (final dark in [false, true]) {
    testWidgets('unknown reaction choices use skeleton cells dark=$dark', (
      tester,
    ) async {
      final site = instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(username: 'reader'));
      final shell = ShellController(
        plugins: installedPlugins,
        instanceStore: FakeInstanceStore([site]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );
      await shell.load();
      addTearDown(shell.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: ReactionGrid(
                controller: shell.pluginSession.require(
                  reactionsControllerService,
                ),
                siteUrl: _siteUrl,
                post: const Post(
                  id: 1,
                  postNumber: 1,
                  username: 'author',
                  cooked: '<p>Post</p>',
                ),
                onPicked: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final region = find.byType(DSkeletonRegion);
      expect(region, findsOneWidget);
      const label = 'Still finding out which reactions this site allows.';
      expect(tester.widget<DSkeletonRegion>(region).semanticsLabel, label);
      expect(find.text(label), findsNothing);
      expect(find.byType(DSkeleton), findsWidgets);
      expect(find.byType(DToggle), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('reaction cell has one exact name and native keyboard action', (
    tester,
  ) async {
    installTestMediaPipeline(
      client: MockClient((_) async => http.Response('', 404)),
    );

    final config = SiteConfig(
      plugins: PluginData.none.withValue(
        reactionsSettingsDataKey,
        const ReactionsSettings(
          mainReaction: 'clap',
          offeredReactions: ['clap'],
        ),
      ),
    );
    final site = instance('meta.example').copyWith(
      user: const DiscourseUser(username: 'reader'),
      config: config,
    );
    final api = FakeDiscourseApi();
    final controller = ShellController(
      plugins: installedPlugins,
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
    final reactions = controller.pluginSession.require(
      reactionsControllerService,
    );

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
                controller: reactions,
                siteUrl: _siteUrl,
                post: post,
                onPicked: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(':clap:'), findsOneWidget);
      final target = find.bySemanticsLabel('clap');
      expect(target, findsOneWidget);
      expect(
        tester.getSize(target),
        Size.square(DToggle.visualDimensionFor(DToggleSize.post)),
      );
      expect(
        tester
            .widget<FocusableActionDetector>(
              find.descendant(
                of: target,
                matching: find.byType(FocusableActionDetector),
              ),
            )
            .mouseCursor,
        SystemMouseCursors.click,
      );
      expect(
        tester.getSemantics(target),
        isSemantics(
          label: 'clap',
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
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
