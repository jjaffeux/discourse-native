import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('opening the current Resenha room twice needs only one Back', (
    tester,
  ) async {
    final site = instance('voice.example');
    final authenticator = FakeAuthenticator()..keys[site.url] = 'key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    addTearDown(shell.dispose);
    await shell.load();
    final destination = shell.currentContent;
    const room = ContentRoute(
      id: 'resenha-room-7',
      title: 'Watercooler',
      icon: DIcons.microphoneLines,
    );

    final resenha = shell.pluginSession.require(resenhaShellService);
    expect(resenha.host, isNot(isA<ShellController>()));
    resenha.openRoom(siteUrl: site.url, route: room);
    resenha.openRoom(siteUrl: site.url, route: room);

    expect(shell.contentStack, hasLength(2));
    expect(shell.currentContent?.id, room.id);
    expect(shell.handleBack(canReturnToSidebar: false), isTrue);
    expect(shell.currentContent?.id, destination?.id);
  });
}
