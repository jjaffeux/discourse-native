import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_card_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://identity.example';
const _post = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Body</p>',
);
const _card = UserCard(id: 1, username: 'author', name: 'Member');
const _owner = PluginId('identity-sample');
const _service = PluginServiceKey<String>(owner: _owner, name: 'message');
const _foreign = PluginServiceKey<String>(
  owner: PluginId('foreign'),
  name: 'message',
);

void main() {
  testWidgets('absent contributions leave identities unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            expect(
              PluginRegistry.empty.postAuthorDecorations(context, _site, _post),
              isEmpty,
            );
            expect(
              PluginRegistry.empty.userCardIdentityDecorations(
                context,
                _site,
                _card,
              ),
              isEmpty,
            );
            return const UserCardHeader(siteUrl: _site, card: _card);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('@author'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mobile in [false, true]) {
    testWidgets('card identity scopes builders and widgets, mobile=$mobile', (
      tester,
    ) async {
      final plugin = _IdentityPlugin();
      final shell = await _controller(plugin);
      addTearDown(shell.dispose);
      await tester.pumpWidget(
        _host(
          shell,
          UserCardHeader(siteUrl: _site, card: _card, mobileSheet: mobile),
        ),
      );
      await tester.pumpAndSettle();
      expect(plugin.cardInput, (_site, _card));
      expect(find.text('card-owned'), findsOneWidget);
      await tester.tap(find.text('card-owned'));
      expect(plugin.activations, 1);
      expect(find.text('Member'), findsOneWidget);
      final name = tester.getRect(find.text('Member'));
      final decoration = tester.getRect(find.text('card-owned'));
      expect(decoration.left, greaterThan(name.right));
      expect(decoration.center.dy, closeTo(name.center.dy, 1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final pluginReader in [false, true]) {
    testWidgets(
      'shared post identity keeps caller badges and one contribution, pluginReader=$pluginReader',
      (tester) async {
        final plugin = _IdentityPlugin();
        final shell = await _controller(plugin);
        addTearDown(shell.dispose);
        final child = pluginReader
            ? PluginTopicPost(
                reader: _Reader(),
                postId: 1,
                layout: TopicPostLayout.compact,
                authorBadges: const [DBadge.inline(child: Text('caller'))],
              )
            : const TopicPostPresentation(
                siteUrl: _site,
                topicId: 7,
                postId: 1,
                authorBadges: [DBadge.inline(child: Text('caller'))],
              );
        await tester.pumpWidget(_host(shell, child));
        await tester.pumpAndSettle();
        expect(plugin.postInput, (_site, _post));
        expect(find.text('post-owned'), findsOneWidget);
        await tester.tap(find.text('post-owned'));
        expect(plugin.activations, 1);
        expect(find.text('caller'), findsOneWidget);
        expect(find.text('author'), findsOneWidget);
        expect(
          tester.getRect(find.text('post-owned')).left,
          greaterThan(tester.getRect(find.text('author')).right),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _host(ShellController shell, Widget child) => ShellScope(
  controller: shell,
  child: PluginScope(
    session: shell.pluginSession,
    registry: shell.plugins.registry,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

Future<ShellController> _controller(_IdentityPlugin plugin) async {
  final installed = PluginInstaller.install(
    PluginManifest([_IdentityModule(plugin)]),
  );
  addTearDown(installed.close);
  final shell = ShellController(
    plugins: installed,
    instanceStore: FakeInstanceStore([instance('identity.example')]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  shell.store.put(_site, const TopicDetail(id: 7, title: 'Topic', stream: [1]));
  shell.store.put(_site, _post);
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  return shell;
}

final class _IdentityModule implements PluginModule {
  const _IdentityModule(this.plugin);
  final _IdentityPlugin plugin;
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _owner);
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(plugin);
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _Lifecycle(),
        services: const [PluginService<Object>(_service, 'owned')],
      ),
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {}

final class _IdentityPlugin
    implements
        SitePlugin,
        PostAuthorDecorationPlugin,
        UserCardIdentityDecorationPlugin {
  int activations = 0;
  (String, Post)? postInput;
  (String, UserCard)? cardInput;
  @override
  String get name => _owner.value;
  void checkOwner(BuildContext context) {
    expect(PluginUiScope.ownerOf(context), _owner);
    expect(PluginUiScope.require(context, _service), 'owned');
    expect(() => PluginUiScope.require(context, _foreign), throwsStateError);
  }

  Widget decoration(String label, BuildContext callbackContext) => Builder(
    builder: (context) {
      checkOwner(context);
      return DButton(
        variant: DButtonVariant.inline,
        label: Text('$label-${PluginUiScope.require(context, _service)}'),
        onPressed: () {
          checkOwner(callbackContext);
          activations++;
        },
      );
    },
  );
  @override
  List<Widget> postAuthorDecorations(
    BuildContext context,
    String siteUrl,
    Post post,
  ) {
    checkOwner(context);
    postInput = (siteUrl, post);
    return [decoration('post', context)];
  }

  @override
  List<Widget> userCardIdentityDecorations(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) {
    checkOwner(context);
    cardInput = (siteUrl, user);
    return [decoration('card', context)];
  }
}

final class _Reader implements PluginTopicReader {
  @override
  bool get isCurrent => true;
  @override
  String get siteUrl => _site;
  @override
  int get topicId => 7;
  @override
  Post? post(int id) => id == 1 ? _post : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
