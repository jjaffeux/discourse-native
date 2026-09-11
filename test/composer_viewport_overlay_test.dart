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

  testWidgets(
    'topic composer docks inside content without covering navigation',
    (tester) async {
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
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await controller.openNewTopicFromSidebar();
      await tester.pumpAndSettle();

      final panel = find.byType(ComposerPanel);
      expect(panel, findsOneWidget);
      final sidebarRect = tester.getRect(find.byType(InstanceSidebar));
      final railRect = tester.getRect(find.byType(InstanceRail));

      final docked = tester.getRect(panel);
      expect(docked.overlaps(sidebarRect), isFalse);
      expect(docked.overlaps(railRect), isFalse);
      expect(find.byKey(const ValueKey('composer-drag-handle')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('full mobile shell fits above the keyboard and safe area', (
    tester,
  ) async {
    const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(
        user: user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = FakeViewPadding(
      bottom: 336 * tester.view.devicePixelRatio,
    );
    tester.view.padding = FakeViewPadding(
      top: 59 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: const AdaptiveShell(),
        ),
      ),
    );
    await controller.openNewTopicFromSidebar();
    await tester.pumpAndSettle();
    expect(find.byType(ComposerPanel), findsOneWidget);
    expect(
      tester.getRect(find.byType(ComposerPanel)).bottom,
      lessThanOrEqualTo(844 - 336),
    );
    expect(find.text('Create topic'), findsOneWidget);
    expect(find.byTooltip('Composer options'), findsNothing);
    expect(find.text('Dock side'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
