import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_services.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
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
    'reaction picker',
  ]) {
    testWidgets(
      '$surface use the full mobile sheet and one scrolling body',
      (tester) async {
        tester.view.physicalSize = _phone;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
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
          siteConfigs: {
            _siteUrl: SiteConfig(
              plugins: PluginData.none.withValue(
                reactionsSettingsDataKey,
                const ReactionsSettings(
                  mainReaction: 'heart',
                  offeredReactions: ['heart', 'clap'],
                ),
              ),
            ),
          },
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
          instanceStore: FakeInstanceStore([
            instance(
              'meta.example',
            ).copyWith(user: const DiscourseUser(username: 'reader')),
          ]),
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
        await reactions.allowsAnyEmoji(_siteUrl);
        final post = Post(
          id: 1,
          postNumber: 1,
          username: 'author',
          cooked: '<p>Post</p>',
          canLike: true,
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
            emoji: controller.pluginSession.require(reactionsEmojiHostService),
          ),
          'reaction picker' => Builder(
            builder: (context) => DButton(
              label: const Text('React'),
              onPressed: () =>
                  showReactionPicker(context, reactions, _siteUrl, post),
            ),
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
        } else if (surface == 'reaction picker') {
          await tester.tap(find.text('React'));
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
        expect(bounds.bottom, _phone.height - 34 - DSpacing.md);
        final body = find.byType(DSheetBody);
        final scrolling = find.descendant(
          of: body,
          matching: find.byType(Scrollable),
        );
        expect(scrolling, findsOneWidget);
        final close = find.byTooltip('Close');
        if (surface == 'post reactions' ||
            surface == 'reaction pill' ||
            surface == 'reaction picker') {
          final button = tester.widget<DButton>(
            find.ancestor(of: close, matching: find.byType(DButton)).first,
          );
          expect(button.shape, DButtonShape.pill);
          expect(button.variant, DButtonVariant.secondary);
        }
        if (surface == 'post reactions') {
          final filter = find.byKey(
            const ValueKey('post-reaction-filter-heart'),
          );
          final react = find.descendant(
            of: sheet,
            matching: find.byType(PostReactionButton),
          );
          expect(tester.getSize(filter).height, 30);
          expect(tester.getSize(react).height, tester.getSize(filter).height);
        }
        final closeBounds = tester.getRect(close);
        if (surface == 'reaction picker') {
          expect(find.byType(ReactionGrid), findsOneWidget);
          final cells = find.descendant(
            of: find.byType(ReactionGrid),
            matching: find.byType(DToggle),
          );
          expect(cells, findsNWidgets(2));
          for (final cell in cells.evaluate()) {
            expect(
              tester.getSize(find.byWidget(cell.widget)),
              const Size.square(30),
            );
          }
          expect(tester.takeException(), isNull);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(api.reacted, isEmpty);
          await tester.tap(find.text('React'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(ReactionGrid),
              matching: find.byWidgetPredicate(
                (widget) => widget is DToggle && widget.semanticLabel == 'clap',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(api.reacted, [(postId: 1, reaction: 'clap')]);
          expect(api.liked, isEmpty);
          return;
        }
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
