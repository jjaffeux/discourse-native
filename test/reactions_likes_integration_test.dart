import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

import 'support/shell_test_harness.dart';

void main() {
  _registerReactionAndLikeTests();
}

void _registerReactionAndLikeTests() {
  group('likes', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    Post post({
      int likeCount = 0,
      bool liked = false,
      bool canLike = true,
      bool canUnlike = false,
    }) => Post(
      id: 1,
      postNumber: 1,
      username: 'sam',
      cooked: '<p>First post body</p>',
      likeCount: likeCount,
      liked: liked,
      canLike: canLike,
      canUnlike: canUnlike,
    );

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required Post first,
      Map<int, List<PostLiker>> likersById = const {},
      Map<int, Post> likeResponses = const {},
      Map<int, Post> postsById = const {},
      WriteException? likeFailure,
      Completer<void>? likerGate,
      Completer<void>? likeGate,
    }) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [first],
            stream: const [1],
            postsCount: 1,
          ),
        },
        postsById: postsById,
        likersById: likersById,
        likeResponses: likeResponses,
        likeFailure: likeFailure,
        likerGate: likerGate,
        likeGate: likeGate,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return api;
    }

    Finder count(String value) =>
        find.descendant(of: find.byType(PostLikes), matching: find.text(value));

    testWidgets('a post nobody has liked says so by saying nothing', (
      tester,
    ) async {
      await openTopic(tester, first: post());

      expect(find.byType(PostLikes), findsOneWidget);
      expect(count('0'), findsNothing);

      await hoverPost(tester);
      expect(find.byTooltip('Like this post'), findsOneWidget);
    });

    testWidgets(
      'liking from the menu draws the count before the site answers',
      (tester) async {
        final api = await openTopic(tester, first: post());

        await hoverPost(tester);
        await tester.tap(find.byTooltip('Like this post'));
        await tester.pumpAndSettle();

        expect(api.liked, [1]);
        expect(count('1'), findsOneWidget);
      },
    );

    testWidgets('a like of your own is the heart that takes it back', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false, canUnlike: true),
      );

      await hoverPost(tester);

      expect(find.byTooltip('Remove your like'), findsOneWidget);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('a like past the undo window leaves nothing to press', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false),
      );

      await hoverPost(tester);

      expect(count('1'), findsOneWidget);
      expect(find.byTooltip('Remove your like'), findsNothing);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('the site has the last word on the count', (tester) async {
      await openTopic(
        tester,
        first: post(),
        likeResponses: {
          1: post(likeCount: 3, liked: true, canLike: false, canUnlike: true),
        },
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(count('3'), findsOneWidget);
    });

    testWidgets('tapping a like of your own takes it back', (tester) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false, canUnlike: true),
      );

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.unliked, [1]);
      expect(api.liked, isEmpty);
      expect(find.byType(PostLikes), findsOneWidget);
      expect(count('1'), findsNothing);
    });

    testWidgets('tapping somebody else\'s adds yours to it', (tester) async {
      final api = await openTopic(tester, first: post(likeCount: 1));

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(count('2'), findsOneWidget);
    });

    testWidgets('a refused like says why and puts the count back', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 1),
        likeFailure: const WriteException(WriteFailure.rateLimited),
      );

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(find.textContaining('Too fast'), findsOneWidget);
      expect(count('1'), findsOneWidget);
      expect(count('2'), findsNothing);
    });

    testWidgets('a post you may not like still shows what others thought', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 2, canLike: false),
      );

      expect(count('2'), findsOneWidget);

      await hoverPost(tester);
      expect(find.byTooltip('Like this post'), findsNothing);

      await tester.tap(count('2'));
      await tester.pumpAndSettle();
      expect(api.liked, isEmpty);
    });

    testWidgets('resting on the count says who liked it', (tester) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 2),
        likersById: {
          1: const [
            PostLiker(id: 3, username: 'sam', name: 'Sam Saffron'),
            PostLiker(id: 4, username: 'codinghorror'),
          ],
        },
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(count('2')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.likersRequested, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(api.likersRequested, [1]);
      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(find.text('codinghorror'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsNothing);
    });

    testWidgets('a failed liker lookup explains that names are unavailable', (
      tester,
    ) async {
      await openTopic(tester, first: post(likeCount: 2));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(count('2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't reach"), findsOneWidget);
    });

    testWidgets('on a touch screen the names arrive as a sheet', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1),
        likersById: {
          1: const [PostLiker(id: 3, username: 'sam', name: 'Sam Saffron')],
        },
      );

      await tester.longPress(count('1'));
      await tester.pumpAndSettle();

      expect(find.text('1 like'), findsOneWidget);
      expect(find.text('Sam Saffron'), findsOneWidget);
    });

    testWidgets('liking with the panel open leaves it saying something true', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 2),
        likersById: {
          1: const [
            PostLiker(id: 3, username: 'sam', name: 'Sam Saffron'),
            PostLiker(id: 4, username: 'codinghorror'),
          ],
        },
        likeFailure: const WriteException(WriteFailure.rateLimited),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final pill = tester.getCenter(count('2'));
      await gesture.moveTo(pill);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsOneWidget);

      await gesture.down(pill);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('Too fast'), findsOneWidget);
      expect(count('2'), findsOneWidget);
      expect(activityIndicators, findsNothing);
      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(api.likersRequested, [1, 1]);
    });

    testWidgets('a double tap does not send two contradicting writes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        first: post(likeCount: 1),
        likeGate: gate,
      );

      // Twice, before the first has come back. The second reads the guess the
      // first wrote, so unguarded it would send an undo of a like the site has
      // not recorded yet — and whichever answer landed last would win.
      await tester.tap(count('1'));
      await tester.pump();
      await tester.tap(count('2'));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(api.unliked, isEmpty);
      expect(count('2'), findsOneWidget);
    });

    testWidgets('editing a post you liked leaves the like alone', (
      tester,
    ) async {
      // `PostsController#update` serializes without the reader's own post
      // actions, so the edit comes back claiming the post is unliked and
      // likeable — on a post they have in fact already liked.
      final api = await openTopic(
        tester,
        first: const Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
          canEdit: true,
          likeCount: 3,
          liked: true,
          canUnlike: true,
        ),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'sam',
            cooked: '<p>First post body</p>',
            canEdit: true,
            raw: 'First post body',
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'First post body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(renderedText('First post body!'), findsOneWidget);
      expect(count('3'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(renderedText('First post body!')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove your like'), findsOneWidget);
    });
  });

  group('reactions', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');
    const site = 'https://meta.discourse.org';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    final configured = installedPlugins.models.siteConfig(const {
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_enabled_reactions': '+1|clap',
    }, site);

    Post post({
      int id = 1,
      List<({String id, int count})> reactions = const [],
      String? mine,
      int userCount = 0,
      bool canAct = true,
      bool canUndo = false,
      bool plugin = true,
      bool canEdit = false,
    }) => Post.fromJson(
      {
        'id': id,
        'post_number': id,
        'username': 'sam',
        'cooked': id == 1 ? '<p>First post body</p>' : '<p>Post $id body</p>',
        if (canEdit) 'can_edit': true,
        'actions_summary': [
          {
            'id': 2,
            if (canAct) 'can_act': true,
            if (canUndo) 'can_undo': true,
            if (mine != null) 'acted': true,
          },
        ],
        if (plugin) ...{
          'reactions': [
            for (final r in reactions)
              {'id': r.id, 'type': 'emoji', 'count': r.count},
          ],
          'current_user_reaction': ?(mine == null
              ? null
              : {'id': mine, 'type': 'emoji', 'can_undo': true}),
          'reaction_users_count': userCount,
        },
      },
      site,
      extensions: pluginRegistry,
    );

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required List<Post> posts,
      SiteConfig? config,
      Map<String, String> customEmojis = const {},
      List<SiteEmoji> emojis = const [],
      Map<String, PostReactors> reactorsById = const {},
      Map<int, Post> postsById = const {},
      Map<int, Post> reactionResponses = const {},
      WriteException? reactionFailure,
      Completer<void>? reactionGate,
      Completer<void>? siteConfigGate,
    }) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: posts,
            stream: [for (final p in posts) p.id],
            postsCount: posts.length,
          ),
        },
        siteConfigs: config == null ? const {} : {site: config},
        siteConfigGate: siteConfigGate,
        customEmojisBySite: customEmojis.isEmpty
            ? const {}
            : {site: customEmojis},
        emojisBySite: emojis.isEmpty ? const {} : {site: emojis},
        postsById: postsById,
        reactorsById: reactorsById,
        reactionResponses: reactionResponses,
        reactionFailure: reactionFailure,
        reactionGate: reactionGate,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return api;
    }

    Finder pill(String value) => find.descendant(
      of: find.byType(ReactionsRow),
      matching: find.text(value),
    );

    testWidgets('a site with reactions draws them where the likes were', (
      tester,
    ) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'heart', count: 5), (id: 'clap', count: 2)],
            userCount: 7,
          ),
        ],
      );

      expect(find.byType(ReactionsRow), findsOneWidget);
      // Not both: the like count on a reactions site is inflated by the shadow
      // likes reacting leaves behind, so drawing it would say 7 hearts.
      expect(find.byType(PostLikes), findsNothing);
      expect(pill('5'), findsOneWidget);
      expect(pill('2'), findsOneWidget);
      // And no grand total beside them — it is not their sum and can exceed it.
      expect(pill('7'), findsNothing);
    });

    testWidgets('an existing reaction row offers another configured reaction', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );
      final semantics = tester.ensureSemantics();
      try {
        final launcher = find.bySemanticsLabel('Add reaction');
        expect(launcher, findsOneWidget);
        expect(tester.getSize(launcher), const Size.square(44));
        expect(
          tester.getSemantics(launcher),
          isSemantics(isButton: true, isFocusable: true, hasTapAction: true),
        );

        await tester.tap(launcher);
        await tester.pumpAndSettle();

        expect(find.byType(ReactionGrid), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('+1'));
        await tester.pumpAndSettle();

        expect(api.reacted, [(postId: 1, reaction: '+1')]);
        expect(find.bySemanticsLabel('1 +1 reaction'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('an any-emoji post reaction row opens the full picker', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pumpAndSettle();

      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'wave')]);
      expect(find.bySemanticsLabel('1 wave reaction'), findsOneWidget);
    });

    testWidgets('the post picker waits for the site reaction policy', (
      tester,
    ) async {
      final gate = Completer<void>();
      await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
        siteConfigGate: gate,
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pump();
      expect(find.byType(ReactionGrid), findsNothing);
      expect(find.byType(EmojiPicker), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ReactionGrid), findsNothing);
      expect(find.byType(EmojiPicker), findsOneWidget);
    });

    testWidgets('a picker cannot react after the post loses permission', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );
      final controller = ShellScope.read(
        tester.element(find.byType(ReactionsRow)),
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pumpAndSettle();
      controller.store.put(
        site,
        post(reactions: [(id: 'clap', count: 2)], userCount: 2, canAct: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReactionPickerButton), findsNothing);
      expect(find.byType(EmojiPicker), findsOneWidget);

      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.reacted, isEmpty);
    });

    testWidgets('the full picker survives its last post pill disappearing', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 1)], userCount: 1),
        ],
      );
      final controller = ShellScope.read(
        tester.element(find.byType(ReactionsRow)),
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pumpAndSettle();
      controller.store.put(site, post());
      await tester.pumpAndSettle();

      expect(find.byType(ReactionPickerButton), findsNothing);
      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'wave')]);
    });

    testWidgets('a post nobody has reacted to says so by saying nothing', (
      tester,
    ) async {
      await openTopic(tester, config: configured, posts: [post()]);

      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(pill('0'), findsNothing);
      expect(find.byType(ReactionPickerButton), findsNothing);
    });

    testWidgets('clicking an existing reaction adds the reader to it', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
        reactorsById: {
          '1:clap': const PostReactors(
            postId: 1,
            filter: 'clap',
            total: 2,
            reactors: [
              PostReactor(id: 3, username: 'sam', reaction: 'clap'),
              PostReactor(id: 4, username: 'ada', reaction: 'clap'),
            ],
          ),
        },
      );
      final semantics = tester.ensureSemantics();
      final target = find.bySemanticsLabel('2 clap reactions');
      final semanticTarget = find.semantics.byLabel('2 clap reactions');

      expect(
        tester.getSemantics(target).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      tester.semantics.tap(semanticTarget);
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
      expect(find.byType(ReactorList), findsNothing);
      expect(pill('3'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a read-only reaction still opens its reactor list', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 2)],
            userCount: 2,
            canAct: false,
          ),
        ],
        reactorsById: {
          '1:clap': const PostReactors(
            postId: 1,
            filter: 'clap',
            total: 2,
            reactors: [
              PostReactor(id: 3, username: 'sam', reaction: 'clap'),
              PostReactor(id: 4, username: 'ada', reaction: 'clap'),
            ],
          ),
        },
      );

      await tester.tap(find.bySemanticsLabel('2 clap reactions'));
      await tester.pumpAndSettle();

      expect(find.byType(ReactorList), findsOneWidget);
      expect(find.byType(ReactionPickerButton), findsNothing);
      expect(api.reactorsRequested, [(postId: 1, filter: 'clap')]);
      expect(api.reacted, isEmpty);
    });

    testWidgets('a touch long press opens reactors without changing reaction', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final api = await openTopic(
          tester,
          config: configured,
          posts: [
            post(reactions: [(id: 'clap', count: 2)], userCount: 2),
          ],
          reactorsById: {
            '1:clap': const PostReactors(
              postId: 1,
              filter: 'clap',
              total: 2,
              reactors: [
                PostReactor(id: 3, username: 'sam', reaction: 'clap'),
                PostReactor(id: 4, username: 'ada', reaction: 'clap'),
              ],
            ),
          },
        );

        await tester.longPress(find.bySemanticsLabel('2 clap reactions'));
        await tester.pumpAndSettle();

        expect(find.byType(ReactorList), findsOneWidget);
        expect(api.reactorsRequested, [(postId: 1, filter: 'clap')]);
        expect(api.reacted, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('clicking another reaction changes the one the reader holds', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'heart', count: 2), (id: 'clap', count: 1)],
            mine: 'heart',
            userCount: 3,
            canAct: false,
            canUndo: true,
          ),
        ],
      );

      await tester.tap(find.bySemanticsLabel('1 clap reaction'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
      expect(pill('1'), findsOneWidget);
      expect(pill('2'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
        isSemantics(isSelected: true),
      );
    });

    testWidgets('clicking the highlighted reaction removes it', (tester) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canAct: false,
            canUndo: true,
          ),
        ],
      );

      await tester.tap(find.bySemanticsLabel('1 clap reaction'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(pill('1'), findsNothing);
    });

    testWidgets('a post on a site without the plugin keeps its likes', (
      tester,
    ) async {
      await openTopic(tester, posts: [post(plugin: false)]);

      expect(find.byType(PostLikes), findsOneWidget);
      expect(find.byType(ReactionsRow), findsNothing);
    });

    testWidgets('a custom emoji is drawn from its upload, not the set', (
      tester,
    ) async {
      // Custom emoji are uploads: they 404 at the set's address, which is
      // what used to leave the pill drawing its name as text. The site's own
      // map is what knows where they live.
      const upload = 'https://meta.discourse.org/uploads/default/party.png';
      await openTopic(
        tester,
        config: configured,
        customEmojis: const {'party_blob': upload},
        posts: [
          post(reactions: [(id: 'party_blob', count: 1)], userCount: 1),
        ],
      );

      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is EmojiImage && widget.url == upload,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EmojiImage && widget.url.contains('/images/emoji/'),
        ),
        findsNothing,
      );
    });

    testWidgets('the menu offers a reaction and never a like', (tester) async {
      // Offering Like here would write /post_actions, which on a post the
      // reader reacted to destroys the shadow like and orphans the reaction.
      await openTopic(tester, config: configured, posts: [post()]);
      await hoverPost(tester);

      expect(find.byTooltip('Like this post'), findsOneWidget);
      expect(find.byTooltip('Remove your like'), findsNothing);
    });

    testWidgets('the menu names the reaction the reader actually gave', (
      tester,
    ) async {
      // A reader who clapped has a shadow like, so `can_act` is true and the
      // naive label would read "Like this post" — on a tap that replaces their
      // clap.
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canUndo: true,
            canAct: false,
          ),
        ],
      );
      await hoverPost(tester);

      expect(find.byTooltip('Remove your clap reaction'), findsOneWidget);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('reacting draws the row before the site answers', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        config: configured,
        posts: [post()],
        reactionGate: gate,
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pump();

      expect(api.reacted, [(postId: 1, reaction: 'heart')]);
      expect(pill('1'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a refused reaction says why and puts the row back', (
      tester,
    ) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'heart', count: 2)], userCount: 2),
        ],
        reactionFailure: const WriteException(
          WriteFailure.rateLimited,
          statusCode: 429,
        ),
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(pill('2'), findsOneWidget);
      expect(find.textContaining('Too fast'), findsOneWidget);
    });

    testWidgets('a reaction the site no longer has drops that row alone', (
      tester,
    ) async {
      // A 404 means the plugin went away *or* the post did, and the route
      // answers the same bytes for both. Emptying every footer in the topic
      // because a moderator deleted one post would be the wrong guess.
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'heart', count: 1)], userCount: 1),
          post(id: 2, reactions: [(id: 'clap', count: 3)], userCount: 3),
        ],
        reactionFailure: const WriteException(
          WriteFailure.validation,
          statusCode: 404,
        ),
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(pill('3'), findsOneWidget);
      expect(pill('1'), findsNothing);
    });

    testWidgets('a double tap does not send two contradicting writes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        config: configured,
        posts: [post()],
        reactionGate: gate,
      );

      await hoverPost(tester);
      // Tapped by position, because the first tap relabels the entry the
      // instant it is pressed — the row is drawn before the site answers.
      final target = tester.getCenter(find.byTooltip('Like this post'));
      await tester.tapAt(target);
      await tester.pump();
      await tester.tapAt(target);
      await tester.pump();

      expect(api.reacted, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a site that has not said which reaction is a like is asked', (
      tester,
    ) async {
      // `heart` is not in the default enabled list, and the setting is enum
      // constrained — so a guess earns a 422 saying only "Sorry, an error has
      // occurred". The picker is the honest answer instead.
      final api = await openTopic(tester, posts: [post()]);
      await hoverPost(tester);

      expect(find.byTooltip('React to this post'), findsOneWidget);
      await tester.tap(find.byTooltip('React to this post'));
      await tester.pumpAndSettle();

      expect(api.reacted, isEmpty);
      expect(
        find.textContaining('which reactions this site allows'),
        findsOneWidget,
      );
    });

    testWidgets('the picker offers what the site allows', (tester) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canUndo: true,
            canAct: false,
          ),
        ],
        reactorsById: const {},
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Remove your clap reaction'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
    });

    testWidgets('a reaction can be picked from the grid', (tester) async {
      final api = await openTopic(tester, config: configured, posts: [post()]);

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Pick a reaction'));
      await tester.pumpAndSettle();

      final cells = find.descendant(
        of: find.byType(ReactionGrid),
        matching: find.byType(InkWell),
      );
      expect(cells, findsNWidgets(3));

      await tester.tap(cells.at(1));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: '+1')]);
      expect(pill('1'), findsOneWidget);
    });

    testWidgets('an any-emoji site opens the full picker from the toolbar', (
      tester,
    ) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = await openTopic(
          tester,
          config: installedPlugins.models.siteConfig(const {
            'discourse_reactions_enabled': true,
            'discourse_reactions_reaction_for_like': 'heart',
            'discourse_reactions_enabled_reactions': 'clap',
            'discourse_reactions_allow_any_emoji': true,
          }, site),
          emojis: const [
            SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
          ],
          posts: [post()],
        );

        await hoverPost(tester);
        final launcherRect = tester.getRect(find.byTooltip('Pick a reaction'));
        await tester.tap(find.byTooltip('Pick a reaction'));
        await tester.pumpAndSettle();

        expect(find.byType(ReactionGrid), findsNothing);
        expect(find.byType(EmojiPicker), findsOneWidget);
        final pickerRect = tester.getRect(
          find.byKey(const ValueKey('emoji-picker-desktop-popover')),
        );
        expect(pickerRect.top, closeTo(launcherRect.bottom + 8, 0.01));
        expect(
          launcherRect.center.dx,
          inInclusiveRange(pickerRect.left, pickerRect.right),
        );

        await tester.tap(find.byTooltip(':wave:'));
        await tester.pumpAndSettle();

        expect(api.reacted, [(postId: 1, reaction: 'wave')]);
        expect(find.bySemanticsLabel('1 wave reaction'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });

    testWidgets('the write answer updates the reader and not the counts', (
      tester,
    ) async {
      // The plugin builds `reactions` one way for a read and another for a
      // write, and the write's copy drops reactions whose emoji no longer
      // exists — so its counts are not the row's. Only what the answer says
      // about this reader is taken.
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'heart', count: 2)], userCount: 2),
        ],
        reactionResponses: {
          1: post(
            reactions: [(id: 'heart', count: 9)],
            mine: 'heart',
            userCount: 9,
            canUndo: true,
            canAct: false,
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'heart')]);
      expect(pill('3'), findsOneWidget);
      expect(pill('9'), findsNothing);

      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove your heart reaction'), findsOneWidget);
    });

    testWidgets('editing a post you reacted to leaves the reaction alone', (
      tester,
    ) async {
      // The edit answer is serialized without the reader's post actions, and
      // for the plugin that means the reaction itself: taken literally it
      // would swap the footer back to the like one — whose heart writes
      // through a route that destroys the reaction.
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canUndo: true,
            canAct: false,
            canEdit: true,
          ),
        ],
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'sam',
            cooked: '<p>First post body</p>',
            canEdit: true,
            raw: 'First post body',
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'First post body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(renderedText('First post body!'), findsOneWidget);
      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(pill('1'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(renderedText('First post body!')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove your clap reaction'), findsOneWidget);
    });

    testWidgets('resting on a pill says who gave that one', (tester) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
        reactorsById: {
          '1:clap': const PostReactors(
            postId: 1,
            filter: 'clap',
            total: 2,
            reactors: [
              PostReactor(id: 3, username: 'sam', reaction: 'clap'),
              PostReactor(id: 4, username: 'codinghorror', reaction: 'clap'),
            ],
          ),
        },
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(pill('2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(api.reactorsRequested, [(postId: 1, filter: 'clap')]);
      final named = find.descendant(
        of: find.byType(ReactorList),
        matching: find.text('sam'),
      );
      expect(named, findsOneWidget);
      expect(find.text('codinghorror'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ReactorList),
          matching: find.byType(SiteEmojiImage),
        ),
        findsNothing,
      );
    });

    testWidgets('somebody else reacting arrives without a refresh', (
      tester,
    ) async {
      // The channel carries which emoji changed and no counts at all, so it is
      // an invalidation hint — the post is read again through the route whose
      // numbers agree with what the row was drawn from.
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 1)], userCount: 1),
        ],
        postsById: {
          1: post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        },
      );

      final tracker = FakeSiteTracker.built.last;
      expect(tracker.watchedTopic, 7);
      expect(tracker.watchedChannels, [
        '/topic/7',
        '/topic/7/reactions',
        '/polls/7',
        '/staff/topic-assignment',
      ]);

      tracker.deliverTopicMessage('/topic/7/reactions', {
        'post_id': 1,
        'reactions': ['clap', null],
      });
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [1],
      ]);
      expect(pill('2'), findsOneWidget);
    });

    testWidgets('leaving the topic stops listening to it', (tester) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 1)], userCount: 1),
        ],
      );
      expect(FakeSiteTracker.built.last.watchedTopic, 7);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built.last.watchedTopic, isNull);
    });

    testWidgets("a write of this reader's own is not read back over", (
      tester,
    ) async {
      // The echo of their own reaction arrives while their request is still in
      // flight. Reading the post again would land the site's answer on top of
      // a guess the site has not seen yet.
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        config: configured,
        posts: [post()],
        reactionGate: gate,
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pump();

      FakeSiteTracker.built.last.deliverTopicMessage('/topic/7/reactions', {
        'post_id': 1,
        'reactions': ['heart', null],
      });
      await tester.pump();

      expect(api.postFetches, isEmpty);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a failed reactor lookup explains that names are unavailable', (
      tester,
    ) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(pill('2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining('who reacted'), findsOneWidget);
    });
  });
}
