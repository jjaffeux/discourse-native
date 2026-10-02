import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_services.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _phone = Size(390, 844);

void main() {
  for (final surface in [
    'post reactions',
    'post likes',
    'post likes tap',
    'reaction pill',
  ]) {
    testWidgets(
      '$surface use the full mobile sheet and one scrolling body',
      (tester) async {
        tester.view.physicalSize = _phone;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final users = [
          for (var index = 0; index < 40; index++)
            PostReactor(
              id: index + 1,
              username: 'person$index',
              name: 'Person $index',
              reaction: index.isEven ? 'heart' : 'clap',
            ),
        ];
        final page = PostReactors(postId: 1, reactors: users, total: 40);
        final api = FakeDiscourseApi(
          reactorsById: {
            '1': page,
            '1:heart': PostReactors(
              postId: 1,
              filter: 'heart',
              reactors: users,
              total: 40,
            ),
            '1:clap': PostReactors(
              postId: 1,
              filter: 'clap',
              reactors: users.where((user) => user.reaction == 'clap').toList(),
              total: 20,
            ),
          },
          likersById: {
            1: [
              for (final user in users)
                PostLiker(
                  id: user.id,
                  username: user.username,
                  name: user.name,
                ),
            ],
          },
        );
        final controller = ShellController(
          plugins: installedPlugins,
          instanceStore: FakeInstanceStore([instance('meta.example')]),
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
        final post = Post(
          id: 1,
          postNumber: 1,
          username: 'author',
          cooked: '<p>Post</p>',
          plugins: PluginData.none.withValue(
            reactionsDataKey,
            const Reactions(
              entries: [
                Reaction(id: 'heart', count: 20),
                Reaction(id: 'clap', count: 20),
              ],
              userCount: 40,
            ),
          ),
        );
        final Widget child = switch (surface) {
          'post reactions' => ReactionsRow(
            siteUrl: _siteUrl,
            post: post,
            controller: reactions,
          ),
          'post likes' || 'post likes tap' => const PostLikes(
            siteUrl: _siteUrl,
            post: Post(
              id: 1,
              postNumber: 1,
              username: 'author',
              cooked: '<p>Post</p>',
              likeCount: 40,
            ),
          ),
          _ => ReactionPill(
            siteUrl: _siteUrl,
            reaction: 'heart',
            count: 40,
            selected: false,
            interactionOwner: reactions,
            loadReactors: () =>
                reactions.load(siteUrl: _siteUrl, postId: 1, filter: 'heart'),
            reactorsBuilder: (_) => ReactorList(
              siteUrl: _siteUrl,
              post: post,
              controller: reactions,
              filter: 'heart',
            ),
          ),
        };
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(body: Center(child: child)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (surface == 'post reactions') {
          await tester.tap(
            find.byKey(const ValueKey('post-reaction-summary-1')),
          );
        } else if (surface == 'post likes tap') {
          await tester.tap(find.byType(DToggle));
        } else {
          await tester.longPress(find.byType(DToggle));
        }
        await tester.pumpAndSettle();

        final sheet = find.byType(DSheetContent);
        expect(sheet, findsOneWidget);
        final bounds = tester.getRect(sheet);
        expect(bounds.height, greaterThan(_phone.height * .8));
        expect(bounds.left, greaterThan(0));
        expect(bounds.right, lessThan(_phone.width));
        final body = find.byType(DSheetBody);
        final scrolling = find.descendant(
          of: body,
          matching: find.byType(Scrollable),
        );
        expect(scrolling, findsOneWidget);
        final close = find.byTooltip('Close');
        final closeBounds = tester.getRect(close);
        await tester.scrollUntilVisible(
          find.text('Person 39'),
          400,
          scrollable: scrolling,
        );
        await tester.pumpAndSettle();
        expect(find.text('Person 39').hitTestable(), findsOneWidget);
        expect(tester.getRect(close), closeBounds);
        expect(tester.takeException(), isNull);

        if (surface == 'post reactions') {
          tester.state<ScrollableState>(scrolling).position.jumpTo(0);
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('post-reaction-filter-clap')),
          );
          await tester.pumpAndSettle();
          expect(api.reactorsRequested.last, (postId: 1, filter: 'clap'));
          expect(find.text('Person 0'), findsNothing);
          expect(find.text('Person 1'), findsOneWidget);
        }
        expect(api.reacted, isEmpty);
        expect(api.liked, isEmpty);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
