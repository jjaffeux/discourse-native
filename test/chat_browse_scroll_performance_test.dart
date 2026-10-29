import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart'
    show primaryMainContent, phone, desktop;

const browseSite = 'https://meta.discourse.org';
final browseView = find.byType(ChatBrowseChannelsView);
final browseList = find.byKey(const PageStorageKey('chat-browse-channels'));
Finder get browseScrollable =>
    find.descendant(of: browseList, matching: find.byType(Scrollable));

Future<ShellController> pumpBrowseScrollFixture(WidgetTester tester) async {
  final user = DiscourseUser(
    id: 7,
    username: 'joffreyj',
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
    ),
  );
  final channels = List.generate(
    100,
    (i) => ChatChannel(
      id: i + 1,
      title: 'Channel ${i + 1}',
      kind: ChatChannelKind.category,
      canJoin: true,
      membership: ChatMembership(following: i.isEven),
    ),
  );
  await tester.pumpWidget(
    DiscourseApp(
      pluginManifest: bundledWidgetTestManifest,
      store: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user, config: config),
      ]),
      api: FakeDiscourseApi(
        user: user,
        totals: chatNotificationTotals(),
        siteConfigs: {browseSite: config},
        feeds: const {'/latest.json': []},
        chatChannelsBySite: {browseSite: ChatChannels(public: channels)},
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: channels,
          ),
        },
      ),
      authenticator: FakeAuthenticator()..keys[browseSite] = 'key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(primaryMainContent));
  shell.pluginSession.require(chatShellService).openBrowseChannels();
  await tester.pumpAndSettle();
  expect(browseView, findsOneWidget);
  return shell;
}

Set<RenderObject> _artwork(Finder root) {
  final objects = <RenderObject>{};
  void collect(RenderObject object) {
    if (!object.isRepaintBoundary) objects.add(object);
    object.visitChildren(collect);
  }

  for (final element in root.evaluate()) {
    collect(element.findRenderObject()!);
  }
  return objects;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'org.discourse.native/notification_opens',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
    () => messenger.setMockMethodCallHandler(notifications, (_) async => null),
  );
  tearDown(() => messenger.setMockMethodCallHandler(notifications, null));
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    if (platform != TargetPlatform.android && true) {
      continue;
    }
    testWidgets('channel scrolling caches fixed artwork ($platform flat)', (
      tester,
    ) async {
      tester.view.physicalSize = platform == TargetPlatform.macOS
          ? desktop
          : phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shell = await pumpBrowseScrollFixture(tester);
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(),
      );
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(browseScrollable).position;
      expect(position.maxScrollExtent, greaterThan(2000));
      position.jumpTo(1000);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(browseScrollable);
      final page = tester.widget<DPageSurface>(
        find
            .ancestor(of: browseList, matching: find.byType(DPageSurface))
            .first,
      );
      final titleHeight = tester.getSize(find.byWidget(page.header!)).height;
      final filters = find.byKey(const ValueKey('chat-browse-joined'));
      final controlsGap = viewport.top - tester.getRect(filters).bottom;
      final header = _artwork(find.byKey(const ValueKey('chat-browse-filter')))
        ..addAll(_artwork(find.byKey(const ValueKey('chat-inbox-back'))))
        ..addAll(_artwork(find.byKey(const ValueKey('chat-browse-status'))))
        ..addAll(_artwork(find.byKey(const ValueKey('chat-browse-joined'))));
      // Rows entering the viewport need their first paint. Track only
      // paragraphs that remain visible throughout this short gesture.
      final rows = _artwork(browseList).whereType<RenderParagraph>().where((
        row,
      ) {
        final rect = row.localToGlobal(Offset.zero) & row.size;
        return viewport.deflate(100).overlaps(rect);
      }).toSet();
      expect(rows, isNotEmpty);

      var headerPaints = 0, rowPaints = 0, totalPaints = 0;
      final previous = debugOnProfilePaint;
      debugOnProfilePaint = (object) {
        previous?.call(object);
        totalPaints++;
        if (header.contains(object)) headerPaints++;
        if (rows.contains(object)) rowPaints++;
      };
      try {
        final gesture = await tester.startGesture(
          tester.getCenter(browseScrollable),
        );
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        headerPaints = rowPaints = totalPaints = 0;
        for (var frame = 0; frame < 24; frame++) {
          final before = position.pixels;
          final delta = frame < 12 ? -4.0 : 4.0;
          await gesture.moveBy(Offset(0, delta));
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            position.pixels,
            delta < 0 ? greaterThan(before) : lessThan(before),
          );
          final currentViewport = tester.getRect(browseScrollable);
          expect(currentViewport.left, viewport.left);
          expect(currentViewport.right, viewport.right);
          expect(currentViewport.bottom, closeTo(viewport.bottom, .001));
          expect(
            currentViewport.top,
            inInclusiveRange(viewport.top - titleHeight, viewport.top),
          );
          expect(
            currentViewport.top - tester.getRect(filters).bottom,
            closeTo(controlsGap, .001),
          );
        }
        await gesture.cancel();
        await tester.pumpAndSettle();
        debugPrint(
          'BROWSE_SCROLL_PAINTS platform=$platform material=flat '
          'total=$totalPaints header=$headerPaints rows=$rowPaints',
        );
        expect(totalPaints, greaterThan(0));
        expect(headerPaints, 0);
        expect(rowPaints, 0);
        expect(tester.takeException(), isNull);
      } finally {
        debugOnProfilePaint = previous;
      }
    }, variant: TargetPlatformVariant.only(platform));
  }
}
