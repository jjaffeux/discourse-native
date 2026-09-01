import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('topic composer moves across the whole shell viewport', (
    tester,
  ) async {
    const user = DiscourseUser(
      id: 7,
      username: 'joffreyj',
      canCreateTopic: true,
    );
    final api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
    );
    final authenticator = FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'meta-key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.light, home: const AdaptiveShell()),
      ),
    );
    await tester.pumpAndSettle();

    await controller.openNewTopicFromSidebar();
    await tester.pumpAndSettle();

    final panel = find.byType(ComposerPanel);
    expect(panel, findsOneWidget);
    final sidebarRect = tester.getRect(find.byType(InstanceSidebar));
    final railRect = tester.getRect(find.byType(InstanceRail));

    await tester.drag(
      find.byKey(const ValueKey('composer-drag-handle')),
      const Offset(-1200, -1200),
    );
    await tester.pump();

    final moved = tester.getRect(panel);
    expect(moved.left, 16);
    expect(moved.top, 16);
    expect(moved.overlaps(sidebarRect), isTrue);
    expect(moved.overlaps(railRect), isTrue);
  });
}
