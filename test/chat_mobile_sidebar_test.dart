import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

final _inbox = find.byType(ChatMobileSidebar);
final _title = find.descendant(
  of: _inbox,
  matching: find.byKey(const ValueKey('chat-inbox-title')),
);
final _navigation = find.byKey(const ValueKey('chat-inbox-activity-filter'));

void _mobileTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: const TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  }),
);

/// The production mobile shell on its Chat tab, with more conversations than
/// a phone shows at once.
Future<void> _pumpChatInbox(WidgetTester tester, Size size) async {
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(
        chatEnabled: true,
        publicChannelsEnabled: true,
        threadsEnabled: true,
      ),
    ),
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: _user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: _user,
      totals: chatNotificationTotals(),
      siteConfigs: {_site: config},
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: ChatChannels(
          hasThreads: true,
          public: [
            for (var id = 1; id <= 20; id++)
              ChatChannel(
                id: id,
                title: 'Channel $id',
                kind: ChatChannelKind.category,
                membership: const ChatMembership(following: true),
                tracking: const ChatTracking(),
              ),
          ],
          direct: const [],
        ),
      },
    ),
  );
  final shell = ShellScope.read(tester.element(find.byType(Scaffold).first));
  await shell.forumSettings.setShared(
    const SharedAppearance(
      font: ForumFont.openSans,
      interfaceFont: ForumFont.openSans,
    ),
  );
  await tester.pumpAndSettle();
  // Enlarged text on a narrow phone moves Chat into the dock's More menu.
  final dockTab = find.byKey(const ValueKey('mobile-mode-panel/chat'));
  if (dockTab.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DDropdownMenuItem),
        matching: find.text('Chat'),
      ),
    );
  } else {
    await tester.tap(dockTab);
  }
  await tester.pumpAndSettle();
  expect(_inbox, findsOneWidget);
}

Future<void> _scrollInboxTo(
  WidgetTester tester,
  Finder row,
  double delta,
) async {
  for (
    var attempt = 0;
    attempt < 100 && row.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    final viewport = find
        .descendant(of: _inbox, matching: find.byType(Scrollable))
        .last;
    // The dock overlays the viewport's lower part. Swipe its visible top edge.
    await tester.dragFrom(
      tester.getTopLeft(viewport) + const Offset(10, 10),
      Offset(0, delta),
    );
    await tester.pumpAndSettle();
  }
  expect(row.hitTestable(), findsOneWidget);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  setUpAll(() async {
    await (FontLoader(
      'Open Sans',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });
  _mobileTest('scrolling hides the chat title and keeps the activity filter', (
    tester,
  ) async {
    await _pumpChatInbox(tester, phone);
    final navigation = tester.getRect(_navigation);
    final list = find.descendant(of: _inbox, matching: find.byType(ListView));
    await tester.drag(list, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(_title.hitTestable(), findsNothing);
    expect(_navigation.hitTestable(), findsOneWidget);
    expect(tester.getRect(_navigation).top, lessThan(navigation.top));
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'keyboard and large text keep navigation and conversations reachable',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpChatInbox(tester, const Size(320, 720));
      addTearDown(tester.view.resetViewInsets);
      for (final bottom in [280.0, 340.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottom);
        await tester.pumpAndSettle();
        await _scrollInboxTo(
          tester,
          find.byKey(const ValueKey('chat-inbox-channel-20')),
          -100,
        );
        expect(
          find.byKey(const ValueKey('chat-inbox-channel-20')).hitTestable(),
          findsOneWidget,
        );
        await _scrollInboxTo(
          tester,
          find.byKey(const ValueKey('chat-inbox-channel-1')),
          100,
        );
        await _scrollInboxTo(tester, _title, 150);
        expect(_title.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'dismissing the keyboard restores the title and filters after scrolling',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpChatInbox(tester, const Size(320, 1000));
      tester.view.viewInsets = const FakeViewPadding(bottom: 540);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _scrollInboxTo(
        tester,
        find.byKey(const ValueKey('chat-inbox-channel-20')),
        -150,
      );
      expect(
        find.byKey(const ValueKey('chat-inbox-channel-20')).hitTestable(),
        findsOneWidget,
      );
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await _scrollInboxTo(
        tester,
        find.byKey(const ValueKey('chat-inbox-channel-1')),
        150,
      );
      await _scrollInboxTo(tester, _title, 150);
      expect(_title.hitTestable(), findsOneWidget);
      expect(_navigation.hitTestable(), findsOneWidget);
      final list = find.descendant(of: _inbox, matching: find.byType(ListView));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(list, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(_title.hitTestable(), findsNothing);
      expect(_navigation.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
