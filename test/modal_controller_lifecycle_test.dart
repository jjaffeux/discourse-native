import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_controller.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_services.dart';
import 'package:discourse_native/src/shell/instance_actions.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/shell_sheet.dart';
import 'package:discourse_native/src/shell/update_sheet.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('an open user card follows a replacement controller', (
    tester,
  ) async {
    final firstApi = _GatedCardApi();
    final secondApi = FakeDiscourseApi(
      cards: const {
        'reader': UserCard(username: 'reader', name: 'Replacement profile'),
      },
    );
    final first = await _loadedController(api: firstApi);
    final second = await _loadedController(api: secondApi);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      _host(
        first,
        (context) => showUserCard(
          context: context,
          username: 'reader',
          siteUrl: _siteUrl,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await firstApi.started.future;

    await tester.pumpWidget(
      _host(
        second,
        (context) => showUserCard(
          context: context,
          username: 'reader',
          siteUrl: _siteUrl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replacement profile'), findsOneWidget);

    firstApi.cardGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Replacement profile'), findsOneWidget);
    expect(find.text('Original profile'), findsNothing);
  });

  testWidgets('an open user card closes when its site disappears', (
    tester,
  ) async {
    final first = await _loadedController(
      api: FakeDiscourseApi(
        cards: const {
          'reader': UserCard(username: 'reader', name: 'Original profile'),
        },
      ),
    );
    final second = await _loadedController(
      api: FakeDiscourseApi(),
      instances: const [],
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      _host(
        first,
        (context) => showUserCard(
          context: context,
          username: 'reader',
          siteUrl: _siteUrl,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Original profile'), findsOneWidget);

    await tester.pumpWidget(_host(second, (_) async {}));
    await tester.pumpAndSettle();

    expect(find.text('Original profile'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('an open update sheet follows a replacement controller', (
    tester,
  ) async {
    final first = _controller(
      api: FakeDiscourseApi(),
      updater: FakeUpdater(isSupported: true),
      updateStore: FakeUpdateStore(
        rawChannel: 'canary',
        lastChecked: DateTime.now(),
      ),
    );
    final second = _controller(
      api: FakeDiscourseApi(),
      updater: FakeUpdater(isSupported: true),
      updateStore: FakeUpdateStore(
        rawChannel: 'stable',
        lastChecked: DateTime.now(),
      ),
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait([first.updates.load(), second.updates.load()]);

    await tester.pumpWidget(_host(first, showUpdateSheet));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Following the canary channel.'), findsOneWidget);

    await tester.pumpWidget(_host(second, showUpdateSheet));
    await tester.pumpAndSettle();
    expect(find.text('Following the stable channel.'), findsOneWidget);
    expect(find.text('Following the canary channel.'), findsNothing);
  });

  testWidgets('an open account sheet follows its source site by identity', (
    tester,
  ) async {
    const firstUser = DiscourseUser(username: 'first', name: 'First User');
    const secondUser = DiscourseUser(username: 'second', name: 'Second User');
    final first = await _loadedController(
      api: FakeDiscourseApi(user: firstUser),
      instances: [instance('meta.example').copyWith(user: firstUser)],
    );
    final second = await _loadedController(
      api: FakeDiscourseApi(user: secondUser),
      instances: [instance('meta.example').copyWith(user: secondUser)],
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(_host(first, showUserMenuSheet));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('@first · meta.example'), findsOneWidget);

    await tester.pumpWidget(_host(second, showUserMenuSheet));
    await tester.pumpAndSettle();
    expect(find.text('@second · meta.example'), findsOneWidget);
    expect(find.text('@first · meta.example'), findsNothing);
  });

  testWidgets('an open account sheet follows same-site account changes', (
    tester,
  ) async {
    const firstUser = DiscourseUser(username: 'first', name: 'First User');
    const secondUser = DiscourseUser(username: 'second', name: 'Second User');
    final controller = _controller(
      api: FakeDiscourseApi(user: secondUser),
      instances: [instance('meta.example').copyWith(user: firstUser)],
    );
    await controller.load();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller, showUserMenuSheet));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('@first · meta.example'), findsOneWidget);

    await controller.connectCurrentInstance();
    await tester.pumpAndSettle();
    expect(find.text('@second · meta.example'), findsOneWidget);
    expect(find.text('@first · meta.example'), findsNothing);

    await controller.disconnectCurrentInstance();
    await tester.pumpAndSettle();
    expect(find.text('This account is no longer connected.'), findsOneWidget);
    expect(find.text('@second · meta.example'), findsNothing);
  });

  testWidgets('a replaced controller ignores a stale connection error', (
    tester,
  ) async {
    final authenticator = _GatedAuthenticator(
      failure: UserApiAuthFailure.badReply,
    );
    final first = _controller(
      api: FakeDiscourseApi(),
      instances: [instance('meta.example')],
      authenticator: authenticator,
    );
    final second = _controller(
      api: FakeDiscourseApi(),
      instances: [instance('meta.example')],
    );
    await Future.wait([first.load(), second.load()]);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(_contentHost(first, const UserMenuButton()));
    await tester.tap(find.byKey(UserMenuButton.signInKey));
    await tester.pump();
    await authenticator.started.future;

    await tester.pumpWidget(_contentHost(second, const UserMenuButton()));
    authenticator.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a removal dialog ignores a replaced controller', (tester) async {
    final target = instance('meta.example');
    final first = await _loadedController(
      api: FakeDiscourseApi(),
      instances: [target],
    );
    final second = await _loadedController(
      api: FakeDiscourseApi(),
      instances: [target],
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    var active = first;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return ShellScope(
            controller: active,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              home: Scaffold(
                body: InstanceActions(
                  instance: target,
                  child: const Text('Site actions'),
                ),
              ),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('Site actions'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove forum'));
    await tester.pumpAndSettle();

    rebuild(() => active = second);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(first.instances, [target]);
    expect(second.instances, [target]);
  });

  testWidgets('an open liker sheet follows a replacement controller', (
    tester,
  ) async {
    const post = Post(
      id: 1,
      postNumber: 1,
      username: 'author',
      cooked: '',
      likeCount: 1,
    );
    final gate = Completer<void>();
    final firstApi = FakeDiscourseApi(
      likerGate: gate,
      likersById: const {
        1: [PostLiker(id: 1, username: 'old', name: 'Original liker')],
      },
    );
    final secondApi = FakeDiscourseApi(
      likersById: const {
        1: [PostLiker(id: 2, username: 'new', name: 'Replacement liker')],
      },
    );
    final first = await _loadedController(api: firstApi);
    final second = await _loadedController(api: secondApi);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      _contentHost(first, const PostLikes(siteUrl: _siteUrl, post: post)),
    );
    await tester.longPress(find.text('1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(firstApi.likersRequested, [1]);

    await tester.pumpWidget(
      _contentHost(second, const PostLikes(siteUrl: _siteUrl, post: post)),
    );
    await tester.pumpAndSettle();
    expect(secondApi.likersRequested, [1]);
    expect(find.text('Replacement liker'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Replacement liker'), findsOneWidget);
    expect(find.text('Original liker'), findsNothing);
  });

  testWidgets('an open reactor sheet follows a replacement controller', (
    tester,
  ) async {
    const post = Post(id: 1, postNumber: 1, username: 'author', cooked: '');
    final previousEmojiCache = EmojiCache.instance;
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(() {
      EmojiCache.instance.clear();
      EmojiCache.instance = previousEmojiCache;
    });

    final gate = Completer<void>();
    final firstApi = FakeDiscourseApi(
      reactorGate: gate,
      reactorsById: const {
        '1:clap': PostReactors(
          postId: 1,
          filter: 'clap',
          total: 1,
          reactors: [
            PostReactor(
              id: 1,
              username: 'old',
              name: 'Original reactor',
              reaction: 'clap',
            ),
          ],
        ),
      },
    );
    final secondApi = FakeDiscourseApi(
      reactorsById: const {
        '1:clap': PostReactors(
          postId: 1,
          filter: 'clap',
          total: 1,
          reactors: [
            PostReactor(
              id: 2,
              username: 'new',
              name: 'Replacement reactor',
              reaction: 'clap',
            ),
          ],
        ),
      },
    );
    final first = await _loadedController(api: firstApi);
    final second = await _loadedController(api: secondApi);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Future<void> openReactors(BuildContext context) {
      final reactions = _reactionsFor(context);
      unawaited(
        reactions.load(siteUrl: _siteUrl, postId: post.id, filter: 'clap'),
      );
      return showShellSheet<void>(
        context: context,
        title: '1 reaction',
        builder: (sheetContext) => ReactorList(
          controller: _reactionsFor(sheetContext),
          siteUrl: _siteUrl,
          post: post,
          filter: 'clap',
        ),
      );
    }

    await tester.pumpWidget(_reactionHost(first, openReactors));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(firstApi.reactorsRequested, [(postId: 1, filter: 'clap')]);

    await tester.pumpWidget(_reactionHost(second, openReactors));
    await tester.pumpAndSettle();
    expect(secondApi.reactorsRequested, [(postId: 1, filter: 'clap')]);
    expect(find.text('Replacement reactor'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Replacement reactor'), findsOneWidget);
    expect(find.text('Original reactor'), findsNothing);
  });

  testWidgets('a replaced controller cannot report a stale reaction error', (
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

    final config = installedPlugins.models.siteConfig(const {
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_enabled_reactions': 'heart',
    }, _siteUrl);
    final site = instance('meta.example').copyWith(config: config);
    final post = Post.fromJson(
      const {
        'id': 1,
        'post_number': 1,
        'username': 'author',
        'cooked': '',
        'actions_summary': [
          {'id': Post.likeActionId, 'can_act': true},
        ],
        'reactions': <Object>[],
        'reaction_users_count': 0,
      },
      _siteUrl,
      extensions: pluginRegistry,
    );
    final gate = Completer<void>();
    final firstApi = FakeDiscourseApi(
      reactionGate: gate,
      reactionFailure: const WriteException(WriteFailure.rateLimited),
    );
    final firstAuth = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final secondAuth = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final first = _controller(
      api: firstApi,
      instances: [site],
      authenticator: firstAuth,
    );
    final second = _controller(
      api: FakeDiscourseApi(),
      instances: [site],
      authenticator: secondAuth,
    );
    await Future.wait([first.load(), second.load()]);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Future<void> openPicker(BuildContext context) =>
        showReactionPicker(context, _reactionsFor(context), _siteUrl, post);

    await tester.pumpWidget(_reactionHost(first, openPicker));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final cell = find.descendant(
      of: find.byType(ReactionGrid),
      matching: find.byType(InkWell),
    );
    await tester.tap(cell);
    await tester.pump();
    expect(firstApi.reacted, [(postId: 1, reaction: 'heart')]);

    await tester.pumpWidget(_reactionHost(second, openPicker));
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Too fast'), findsNothing);
  });

  testWidgets('an open reaction picker cannot act after a session change', (
    tester,
  ) async {
    final api = FakeDiscourseApi();
    final auth = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final controller = _controller(
      api: api,
      instances: [instance('meta.example').copyWith(config: _reactionConfig())],
      authenticator: auth,
    );
    await controller.load();
    addTearDown(controller.dispose);

    Future<void> openPicker(BuildContext context) => showReactionPicker(
      context,
      _reactionsFor(context),
      _siteUrl,
      _reactablePost(),
    );

    await tester.pumpWidget(_reactionHost(controller, openPicker));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    controller.lifecycle.invalidate(_siteUrl);
    await tester.tap(
      find.descendant(
        of: find.byType(ReactionGrid),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.reacted, isEmpty);
  });

  testWidgets('a changed session cannot report a stale reaction error', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeDiscourseApi(
      reactionGate: gate,
      reactionFailure: const WriteException(WriteFailure.rateLimited),
    );
    final auth = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final controller = _controller(
      api: api,
      instances: [instance('meta.example').copyWith(config: _reactionConfig())],
      authenticator: auth,
    );
    await controller.load();
    addTearDown(controller.dispose);

    Future<void> openPicker(BuildContext context) => showReactionPicker(
      context,
      _reactionsFor(context),
      _siteUrl,
      _reactablePost(),
    );

    await tester.pumpWidget(_reactionHost(controller, openPicker));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ReactionGrid),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pump();
    expect(api.reacted, [(postId: 1, reaction: 'heart')]);

    controller.lifecycle.invalidate(_siteUrl);
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Too fast'), findsNothing);
  });

  testWidgets('a replaced controller cannot report a stale post error', (
    tester,
  ) async {
    const post = Post(
      id: 1,
      postNumber: 1,
      username: 'author',
      cooked: '',
      canLike: true,
    );
    final gate = Completer<void>();
    final firstApi = FakeDiscourseApi(
      likeGate: gate,
      likeFailure: const WriteException(WriteFailure.rateLimited),
    );
    final firstAuth = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final first = _controller(
      api: firstApi,
      instances: [instance('meta.example')],
      authenticator: firstAuth,
    );
    final second = _controller(
      api: FakeDiscourseApi(),
      instances: [instance('meta.example')],
    );
    await Future.wait([first.load(), second.load()]);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    const actions = PostActions(
      siteUrl: _siteUrl,
      post: post,
      child: Text('Post body'),
    );
    await tester.pumpWidget(_contentHost(first, actions));
    await tester.longPress(find.text('Post body'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Like'));
    await tester.pump();
    expect(firstApi.liked, [1]);

    await tester.pumpWidget(_contentHost(second, actions));
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Too fast'), findsNothing);
  });
}

typedef _OpenModal = Future<void> Function(BuildContext context);

ReactionsController _reactionsFor(BuildContext context) =>
    ShellScope.identityOf(
      context,
    ).pluginSession.require(reactionsControllerService);

Widget _host(ShellController controller, _OpenModal open) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () => unawaited(open(context)),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

Widget _reactionHost(ShellController controller, _OpenModal open) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: PluginUiScope.own(
        reactionsPluginId,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(open(context)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

Widget _contentHost(ShellController controller, Widget child) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
    home: Scaffold(body: Center(child: child)),
  ),
);

SiteConfig _reactionConfig() => installedPlugins.models.siteConfig(const {
  'discourse_reactions_enabled': true,
  'discourse_reactions_reaction_for_like': 'heart',
  'discourse_reactions_enabled_reactions': 'heart',
}, _siteUrl);

Post _reactablePost() => Post.fromJson(
  const {
    'id': 1,
    'post_number': 1,
    'username': 'author',
    'cooked': '',
    'actions_summary': [
      {'id': Post.likeActionId, 'can_act': true},
    ],
    'reactions': <Object>[],
    'reaction_users_count': 0,
  },
  _siteUrl,
  extensions: pluginRegistry,
);

Future<ShellController> _loadedController({
  required FakeDiscourseApi api,
  List<DiscourseInstance>? instances,
}) async {
  final controller = _controller(
    api: api,
    instances: instances ?? [instance('meta.example')],
  );
  await controller.load();
  return controller;
}

ShellController _controller({
  required FakeDiscourseApi api,
  List<DiscourseInstance> instances = const [],
  FakeAuthenticator? authenticator,
  FakeUpdater? updater,
  FakeUpdateStore? updateStore,
}) => ShellController(
  instanceStore: FakeInstanceStore(instances),
  api: api,
  authenticator: authenticator ?? FakeAuthenticator(),
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
  updater: updater ?? FakeUpdater(),
  updateStore: updateStore ?? FakeUpdateStore(),
  plugins: installedPlugins,
);

final class _GatedCardApi extends FakeDiscourseApi {
  final cardGate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    if (!started.isCompleted) started.complete();
    await cardGate.future;
    return const UserCard(username: 'reader', name: 'Original profile');
  }
}

final class _GatedAuthenticator extends FakeAuthenticator {
  _GatedAuthenticator({required super.failure});

  final gate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> connect(String siteUrl) async {
    started.complete();
    await gate.future;
    return super.connect(siteUrl);
  }
}
