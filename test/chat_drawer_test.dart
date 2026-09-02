import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer_preferences_store.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('closing the drawer tolerates a deactivated primary focus', (
    tester,
  ) async {
    final fixture = await _pumpDrawer(tester);
    fixture.forumFocus.requestFocus();
    await tester.pump();
    expect(fixture.forumFocus.hasPrimaryFocus, isTrue);

    fixture.showForumFocus.value = false;
    fixture.shell.closeDrawer();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
    expect(fixture.forumFocus.hasFocus, isFalse);
  });

  testWidgets('closing the drawer releases focus from its retained content', (
    tester,
  ) async {
    final fixture = await _pumpDrawer(tester);
    fixture.drawerFocus.requestFocus();
    await tester.pump();
    expect(fixture.drawerFocus.hasPrimaryFocus, isTrue);

    fixture.shell.closeDrawer();
    await tester.pumpAndSettle();

    expect(fixture.drawerFocus.hasFocus, isFalse);
    expect(
      find.byKey(ChatDrawerOverlay.drawerKey, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('closing the drawer preserves focus in the forum', (
    tester,
  ) async {
    final fixture = await _pumpDrawer(tester);
    fixture.forumFocus.requestFocus();
    await tester.pump();
    expect(fixture.forumFocus.hasPrimaryFocus, isTrue);

    fixture.shell.closeDrawer();
    await tester.pumpAndSettle();

    expect(fixture.forumFocus.hasPrimaryFocus, isTrue);
    expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
  });
}

Future<
  ({
    ChatShellService shell,
    FocusNode drawerFocus,
    FocusNode forumFocus,
    ValueNotifier<bool> showForumFocus,
  })
>
_pumpDrawer(WidgetTester tester) async {
  const siteUrl = 'https://meta.discourse.org';
  const user = DiscourseUser(id: 7, username: 'reader');
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await const ChatDrawerPreferencesStore().writePreferredDisplayMode(
    ChatPreferredDisplayMode.drawer,
  );
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: siteUrl,
        title: 'Meta',
        user: user,
        notificationTotals: chatNotificationTotals(),
      ),
    ]),
    api: FakeDiscourseApi(totals: chatNotificationTotals(), user: user),
    authenticator: FakeAuthenticator()..keys[siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  final shell = controller.pluginSession.require(chatShellService);
  await shell.openShortcut(drawerAvailable: true);
  final drawerFocus = FocusNode();
  final forumFocus = FocusNode();
  final showForumFocus = ValueNotifier(true);
  addTearDown(drawerFocus.dispose);
  addTearDown(forumFocus.dispose);
  addTearDown(showForumFocus.dispose);
  final drawer = ChatDrawerOverlay(
    contentBuilder: (_, _) =>
        Focus(focusNode: drawerFocus, child: const Text('Chat content')),
    headerActionsBuilder: (_, _) => const [],
    headerLeadingBuilder: (_, _) => null,
    headerTitleTrailingBuilder: (_, _) => null,
    headerTitleActionBuilder: (_, _) => null,
    showFooterForRoute: (_) => false,
  );
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: showForumFocus,
              builder: (_, showFocus, _) => Stack(
                fit: StackFit.expand,
                children: [
                  if (showFocus)
                    Focus(
                      focusNode: forumFocus,
                      child: const Text('Forum content'),
                    )
                  else
                    const SizedBox.shrink(),
                  drawer,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);
  return (
    shell: shell,
    drawerFocus: drawerFocus,
    forumFocus: forumFocus,
    showForumFocus: showForumFocus,
  );
}
