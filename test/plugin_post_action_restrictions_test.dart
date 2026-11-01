import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_module.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final reverse in [false, true]) {
    testWidgets(
      'reaction restriction applies independently of contribution order $reverse',
      (tester) async {
        final installed = PluginInstaller.install(
          PluginManifest([
            if (!reverse) const _RestrictionModule(),
            reactionsModule,
            if (reverse) const _RestrictionModule(),
          ]),
        );
        addTearDown(installed.close);
        final shell = ShellController(
          plugins: installed,
          instanceStore: FakeInstanceStore([instance('forum.example')]),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        final models = DiscourseModelCodec(extensions: installed.registry);
        Post post(int id) => models.post({
          'id': id,
          'post_number': id,
          'username': 'sam',
          'cooked': '<p>Body</p>',
          'reactions': <Object?>[],
          'actions_summary': [
            {'id': 2, 'can_act': true, 'count': 0},
          ],
        }, 'https://forum.example');
        late PostMenuContribution allowed;
        late PostMenuContribution restricted;
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: PluginScope(
              session: shell.pluginSession,
              registry: installed.registry,
              child: Builder(
                builder: (context) {
                  allowed = installed.registry.postMenu(
                    context,
                    'https://forum.example',
                    post(1),
                    topic: null,
                    currentUser: null,
                  );
                  restricted = installed.registry.postMenu(
                    context,
                    'https://forum.example',
                    post(2),
                    topic: null,
                    currentUser: null,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(
          allowed.entries.where(
            (action) => action.role == PostActionRole.reaction,
          ),
          hasLength(1),
        );
        expect(allowed.quickReaction, isNotNull);
        expect(
          restricted.entries.where(
            (action) => action.role == PostActionRole.reaction,
          ),
          isEmpty,
        );
        expect(restricted.quickReaction, isNull);
        expect(restricted.replacesLike, isTrue);
        expect(restricted.replacesReply, isTrue);
      },
    );
  }
}

final class _RestrictionModule implements PluginModule {
  const _RestrictionModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('restrictions-fixture'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const _Restriction());
}

final class _Restriction implements SitePlugin, PostMenuPlugin {
  const _Restriction();
  @override
  String get name => 'restrictions-fixture';
  @override
  PostMenuContribution postMenu(PostMenuContext context) => context.post.id == 2
      ? const PostMenuContribution(
          suppressesReactions: true,
          replacesReply: true,
        )
      : PostMenuContribution.none;
}
