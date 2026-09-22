import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/post_action.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('constructs plugin actions once and preserves live updates', (
    tester,
  ) async {
    final version = ValueNotifier(0);
    addTearDown(version.dispose);
    final plugin = _CountingMenuPlugin(version);
    final installed = PluginInstaller.install(
      PluginManifest([_MenuModule(plugin)]),
    );
    addTearDown(installed.close);
    final controller = ShellController(
      plugins: installed,
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final theme = AppTheme.light;

    Future<void> pumpPost(int id) => tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: PluginScope(
          session: controller.pluginSession,
          registry: installed.registry,
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: PostActions(
                siteUrl: 'https://meta.example',
                post: Post(id: id, postNumber: id, username: 'sam', cooked: ''),
                persistent: true,
                child: const PostActionsFooter(child: Text('Post body')),
              ),
            ),
          ),
        ),
      ),
    );

    await pumpPost(1);
    await tester.pumpAndSettle();
    expect(plugin.builds, 1);
    expect(find.text('Action 1:0'), findsOneWidget);

    version.value = 1;
    await tester.pumpAndSettle();
    expect(plugin.builds, 2);
    expect(find.text('Action 1:0'), findsNothing);
    expect(find.text('Action 1:1'), findsOneWidget);

    // A parent update supplies a new initial snapshot to the existing listener.
    await pumpPost(2);
    await tester.pumpAndSettle();
    expect(plugin.builds, 3);
    expect(find.text('Action 2:1'), findsOneWidget);

    version.value = 2;
    await tester.pumpAndSettle();
    expect(plugin.builds, 4);
    expect(find.text('Action 2:2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    version.value = 3;
    await tester.pump();
    expect(plugin.builds, 4);
    expect(tester.takeException(), isNull);
  });
}

class _MenuModule implements PluginModule {
  _MenuModule(this.plugin);

  final SitePlugin plugin;

  @override
  PluginDescriptor get descriptor =>
      PluginDescriptor(id: PluginId(plugin.name));

  @override
  void register(PluginRegistrar registrar) => registrar.addCapability(plugin);
}

class _CountingMenuPlugin implements SitePlugin, PostMenuPlugin {
  _CountingMenuPlugin(this.version);

  final ValueNotifier<int> version;
  int builds = 0;

  @override
  String get name => 'counting-menu';

  @override
  PostMenuContribution postMenu(PostMenuContext context) {
    builds++;
    final label = 'Action ${context.post.id}:${version.value}';
    return PostMenuContribution(
      rebuildOn: version,
      entries: [
        PostAction(
          icon: DIcons.reply,
          label: label,
          tooltip: label,
          placement: PostActionPlacement.trailing,
          showLabelInFooter: true,
          onInvoke: () {},
        ),
      ],
    );
  }
}
