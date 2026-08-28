import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _metaUrl = 'https://meta.discourse.org';
const _teamUrl = 'https://team.discourse.org';
const _metaUser = DiscourseUser(
  id: 1,
  username: 'meta-user',
  name: 'Meta User',
  hidePresence: false,
);
const _teamUser = DiscourseUser(
  id: 2,
  username: 'team-user',
  name: 'Team User',
  hidePresence: true,
);

const _metaNotification = DiscourseNotification(
  id: 11,
  kind: NotificationKind.grantedBadge,
  badgeName: 'Meta Helper',
  path: '/badges/11/meta-helper',
);

const _teamNotification = DiscourseNotification(
  id: 22,
  kind: NotificationKind.grantedBadge,
  badgeName: 'Team Helper',
  path: '/badges/22/team-helper',
);

const _metaReply = DiscourseNotification(
  id: 13,
  kind: NotificationKind.replied,
  actor: 'alice',
  title: 'Meta reply',
  path: '/t/meta-reply/13',
);

const _teamReply = DiscourseNotification(
  id: 24,
  kind: NotificationKind.quoted,
  actor: 'bob',
  title: 'Team reply',
  path: '/t/team-reply/24',
);

const _metaBookmark = Bookmark(
  id: 31,
  title: 'Meta chat message',
  author: 'alice',
  path: '/chat/c/meta/1/31',
);

const _teamBookmark = Bookmark(
  id: 32,
  title: 'Team chat message',
  author: 'bob',
  path: '/chat/c/team/2/32',
);

void main() {
  testWidgets(
    'pointer tabs expose 44 pixel selected controls with keyboard actions',
    (tester) => _withMenu(tester, TargetPlatform.macOS, (_) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.tap(find.byKey(UserMenuButton.avatarKey));
        await tester.pumpAndSettle();

        final notifications = find.byKey(const ValueKey('user-menu-tab-all'));
        final bookmarks = find.byKey(const ValueKey('user-menu-tab-bookmarks'));
        final replies = find.byKey(const ValueKey('user-menu-tab-replies'));

        for (final tab in [notifications, bookmarks, replies]) {
          expect(tester.getSize(tab), const Size.square(44));
        }
        expect(
          tester.getSemantics(notifications),
          isSemantics(
            label: 'Notifications',
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(bookmarks),
          isSemantics(
            label: 'Bookmarks',
            isButton: true,
            hasSelectedState: true,
            isSelected: false,
            hasTapAction: true,
          ),
        );

        await _focusTab(tester, bookmarks);
        expect(
          tester.getSemantics(bookmarks),
          isSemantics(isFocusable: true, isFocused: true),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.byType(BookmarkSection), findsOneWidget);
        expect(
          tester.getSemantics(bookmarks),
          isSemantics(hasSelectedState: true, isSelected: true),
        );
        expect(
          tester.getSemantics(notifications),
          isSemantics(hasSelectedState: true, isSelected: false),
        );

        await _focusTab(tester, replies);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();

        expect(find.byType(RepliesSection), findsOneWidget);
        expect(
          tester.getSemantics(replies),
          isSemantics(hasSelectedState: true, isSelected: true),
        );
      } finally {
        semantics.dispose();
      }
    }),
  );

  testWidgets(
    'pause notifications is an accessible keyboard control that can resume',
    (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.tap(find.byKey(UserMenuButton.avatarKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();

        var row = find.byKey(const ValueKey('pause-notifications-row'));
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
        expect(
          tester.getSemantics(row),
          isSemantics(
            label: 'Pause notifications',
            value: 'Off',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ),
        );

        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.text('Pause notifications for…'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('do-not-disturb-halfHour')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('do-not-disturb-oneHour')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('do-not-disturb-twoHours')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('do-not-disturb-tomorrow')),
          findsOneWidget,
        );

        final halfHour = find.byKey(const ValueKey('do-not-disturb-halfHour'));
        final focusChild = find
            .descendant(of: halfHour, matching: find.byType(MouseRegion))
            .first;
        Focus.of(tester.element(focusChild)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(fixture.api.doNotDisturbDurations.single.wireValue, 30);
        expect(find.text('Pause notifications for…'), findsNothing);

        await tester.tap(find.byKey(UserMenuButton.avatarKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();
        row = find.byKey(const ValueKey('pause-notifications-row'));
        expect(
          tester.getSemantics(row),
          isSemantics(
            label: 'Pause notifications',
            isButton: true,
            hasToggledState: true,
            isToggled: true,
          ),
        );
        expect(find.text('30m'), findsOneWidget);

        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(fixture.api.doNotDisturbResumes, [_metaUrl]);
        expect(
          tester.getSemantics(row),
          isSemantics(hasToggledState: true, isToggled: false),
        );
      } finally {
        semantics.dispose();
      }
    }),
  );

  testWidgets(
    'touch profile closes both sheets before showing pause choices',
    (tester) => _withMenu(tester, TargetPlatform.android, (_) async {
      await _openNestedSection(tester, 'Profile');
      await tester.tap(find.byKey(const ValueKey('pause-notifications-row')));
      await tester.pumpAndSettle();

      expect(find.text('Pause notifications for…'), findsOneWidget);
      expect(find.text('Profile'), findsNothing);
      expect(find.text('Meta User'), findsNothing);
    }),
  );

  testWidgets(
    'pause choices link to the account notification schedule',
    (tester) => _withMenu(tester, TargetPlatform.macOS, (_) async {
      final launched = _watchBrowser(tester);
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      final shell = ShellScope.read(tester.element(find.byType(UserMenuPanel)));
      final username = shell.currentInstance!.user!.username;

      await tester.tap(find.byKey(const ValueKey('pause-notifications-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set a notification schedule'));
      await tester.pumpAndSettle();

      expect(launched, [
        '$_metaUrl/u/${Uri.encodeComponent(username)}/preferences/notifications',
      ]);
    }),
  );

  testWidgets(
    'an open popover requests activity for each selected site',
    (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
      final api = fixture.api;

      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();

      expect(api.notificationSites, [_metaUrl]);
      expect(find.textContaining('Meta Helper'), findsOneWidget);

      final shell = ShellScope.read(tester.element(find.byType(UserMenuPanel)));
      shell.selectInstance(1);
      await tester.pumpAndSettle();

      expect(find.byType(UserMenuPanel), findsOneWidget);
      expect(api.notificationSites, [_metaUrl, _teamUrl]);
      expect(find.textContaining('Team Helper'), findsOneWidget);

      await tester.tap(find.byTooltip('Replies'));
      await tester.pumpAndSettle();
      expect(api.replySites, [_teamUrl]);
      expect(find.textContaining('Team reply'), findsOneWidget);

      shell.selectInstance(0);
      await tester.pumpAndSettle();

      expect(api.replySites, [_teamUrl, _metaUrl]);
      expect(find.textContaining('Meta reply'), findsOneWidget);

      await tester.tap(find.byTooltip('Bookmarks'));
      await tester.pumpAndSettle();
      expect(api.bookmarkSites, [_metaUrl]);
      expect(find.textContaining('Meta chat message'), findsOneWidget);

      shell.selectInstance(1);
      await tester.pumpAndSettle();

      expect(api.bookmarkSites, [_metaUrl, _teamUrl]);
      expect(find.textContaining('Team chat message'), findsOneWidget);
    }),
  );

  testWidgets(
    'a nested notification section keeps its source site',
    (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
      final launched = _watchBrowser(tester);
      final api = fixture.api;

      await _openNestedSection(tester, 'Notifications');
      final section = find.byType(NotificationSection);
      final shell = ShellScope.read(tester.element(section));

      shell.selectInstance(1);
      await tester.pumpAndSettle();

      expect(find.textContaining('Meta Helper'), findsOneWidget);
      expect(api.notificationSites, [_metaUrl]);

      await tester.tap(find.textContaining('Meta Helper'));
      await tester.pumpAndSettle();

      expect(launched, ['$_metaUrl/badges/11/meta-helper']);
      expect(api.readSites, [(siteUrl: _metaUrl, id: 11)]);
    }),
  );

  testWidgets(
    'a nested Replies section keeps its source site',
    (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
      final api = fixture.api;

      await _openNestedSection(tester, 'Replies');
      final section = find.byType(RepliesSection);
      final shell = ShellScope.read(tester.element(section));

      shell.selectInstance(1);
      await tester.pumpAndSettle();

      expect(find.textContaining('Meta reply'), findsOneWidget);
      expect(api.replySites, [_metaUrl]);
    }),
  );

  testWidgets(
    'a nested bookmark section keeps its source site',
    (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
      final launched = _watchBrowser(tester);
      final api = fixture.api;

      await _openNestedSection(tester, 'Bookmarks');
      final section = find.byType(BookmarkSection);
      final shell = ShellScope.read(tester.element(section));

      shell.selectInstance(1);
      await tester.pumpAndSettle();

      expect(find.textContaining('Meta chat message'), findsOneWidget);
      expect(api.bookmarkSites, [_metaUrl]);

      await tester.tap(find.textContaining('Meta chat message'));
      await tester.pumpAndSettle();

      expect(launched, ['$_metaUrl/chat/c/meta/1/31']);
    }),
  );

  testWidgets(
    'a nested profile disconnects its source account',
    (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
      final auth = fixture.auth;

      await _openNestedSection(tester, 'Profile');
      final shell = ShellScope.read(tester.element(find.text('Disconnect')));
      shell.selectInstance(1);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(auth.disconnected, [_metaUrl]);
      expect(shell.currentInstance?.url, _teamUrl);
      expect(shell.currentInstance?.user, isNotNull);
    }),
  );

  testWidgets(
    'pointer Preferences closes the menu and Back restores prior content',
    (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();

      final panel = find.byType(UserMenuPanel);
      final drafts = find.descendant(
        of: panel,
        matching: find.byKey(const ValueKey('user-menu-row-drafts')),
      );
      final status = find.descendant(
        of: panel,
        matching: find.byKey(const ValueKey('user-menu-row-user-status')),
      );
      final preferences = find.descendant(
        of: panel,
        matching: find.byKey(const ValueKey('user-menu-row-preferences')),
      );
      expect(drafts, findsOneWidget);
      expect(status, findsOneWidget);
      expect(tester.widget<InkWell>(drafts).onTap, isNotNull);
      expect(tester.widget<InkWell>(status).onTap, isNotNull);

      final shell = ShellScope.read(tester.element(panel));
      final priorRoute = shell.currentContent;
      final sourceUsername = shell.currentInstance!.user!.username;
      await tester.tap(preferences);
      await tester.pumpAndSettle();

      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byType(PreferencesPage), findsOneWidget);
      expect(
        tester.widget<PreferencesPage>(find.byType(PreferencesPage)).siteUrl,
        _metaUrl,
      );
      expect(shell.currentInstance?.url, _metaUrl);
      expect(shell.currentContent?.isPreferences, isTrue);
      expect(fixture.api.userPreferenceLoads.single.siteUrl, _metaUrl);
      expect(fixture.api.userPreferenceLoads.single.username, sourceUsername);
      expect(fixture.api.userPreferenceLoads.single.clientId, 'test-client');

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(PreferencesPage), findsNothing);
      expect(shell.currentContent, priorRoute);
    }),
  );

  testWidgets(
    'touch Preferences closes both sheets and keeps its source account',
    (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
      await _openNestedSection(tester, 'Profile');
      final preferences = find.byKey(
        const ValueKey('user-menu-row-preferences'),
      );
      final shell = ShellScope.read(tester.element(preferences));
      final sourceUsername = shell.instanceFor(_metaUrl)!.user!.username;

      shell.selectInstance(1);
      await tester.pumpAndSettle();
      expect(shell.currentInstance?.url, _teamUrl);

      await tester.tap(preferences);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('shell-sheet-keyboard-inset')),
        findsNothing,
      );
      expect(find.byType(PreferencesPage), findsOneWidget);
      expect(
        tester.widget<PreferencesPage>(find.byType(PreferencesPage)).siteUrl,
        _metaUrl,
      );
      expect(shell.currentInstance?.url, _metaUrl);
      expect(shell.currentContent?.isPreferences, isTrue);
      expect(fixture.api.userPreferenceLoads.single.siteUrl, _metaUrl);
      expect(fixture.api.userPreferenceLoads.single.username, sourceUsername);
      expect(fixture.api.userPreferenceLoads.single.clientId, 'test-client');
    }),
  );

  testWidgets(
    'profile Activity returns to and loads its source account',
    (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
      final api = fixture.api;

      await _openNestedSection(tester, 'Profile');
      final shell = ShellScope.read(tester.element(find.text('Disconnect')));
      shell.selectInstance(1);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('user-menu-row-activity')));
      await tester.pumpAndSettle();

      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byType(UserActivityView), findsOneWidget);
      expect(shell.currentInstance?.url, _metaUrl);
      expect(shell.currentContent?.id, 'activity');
      expect(api.userActivitySites, [_metaUrl]);
      expect(api.userActivityUsers, ['meta-user']);
    }),
  );

  testWidgets(
    'a nested profile changes presence only for its source account',
    (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
      final api = fixture.api;

      await _openNestedSection(tester, 'Profile');
      final shell = ShellScope.read(tester.element(find.text('Online')));
      shell.selectInstance(1);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      expect(api.presenceUpdates, [
        (siteUrl: _metaUrl, username: 'meta-user', hidePresence: true),
      ]);
      expect(shell.hidePresenceFor(_metaUrl), isTrue);
      expect(shell.hidePresenceFor(_teamUrl), isTrue);
    }),
  );
}

Future<void> _focusTab(WidgetTester tester, Finder tab) async {
  final inkWell = find.descendant(of: tab, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
}

typedef _MenuFixture = ({FakeAuthenticator auth, _SiteMenuApi api});

Future<void> _withMenu(
  WidgetTester tester,
  TargetPlatform platform,
  Future<void> Function(_MenuFixture fixture) body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body(await _pumpMenu(tester));
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

Future<_MenuFixture> _pumpMenu(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final instances = <DiscourseInstance>[
    instance('meta.discourse.org', title: 'Discourse Meta').copyWith(
      user: _metaUser,
      config: const SiteConfig(userStatusEnabled: true),
    ),
    instance('team.discourse.org', title: 'Discourse Team').copyWith(
      user: _teamUser,
      config: const SiteConfig(userStatusEnabled: true),
    ),
  ];
  final api = _SiteMenuApi();
  final auth = FakeAuthenticator()
    ..keys[_metaUrl] = 'meta-key'
    ..keys[_teamUrl] = 'team-key';
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore(instances),
      api: api,
      authenticator: auth,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, auth: auth);
}

Future<void> _openNestedSection(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(UserMenuButton.avatarKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

List<String> _watchBrowser(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return launched;
}

final class _SiteMenuApi extends FakeDiscourseApi {
  _SiteMenuApi()
    : super(
        siteConfigs: const {
          _metaUrl: SiteConfig(userStatusEnabled: true),
          _teamUrl: SiteConfig(userStatusEnabled: true),
        },
      );

  final List<String> notificationSites = [];
  final List<String> replySites = [];
  final List<String> bookmarkSites = [];
  final List<String> userActivitySites = [];
  final List<String> userActivityUsers = [];
  final List<({String siteUrl, int id})> readSites = [];
  final List<({String siteUrl, String username, bool hidePresence})>
  presenceUpdates = [];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => siteUrl == _metaUrl ? _metaUser : _teamUser;

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) async {
    if (filterByTypes.isNotEmpty) {
      replySites.add(siteUrl);
      return [siteUrl == _metaUrl ? _metaReply : _teamReply];
    }
    notificationSites.add(siteUrl);
    return [siteUrl == _metaUrl ? _metaNotification : _teamNotification];
  }

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    bookmarkSites.add(siteUrl);
    return (
      reminders: const <DiscourseNotification>[],
      bookmarks: [siteUrl == _metaUrl ? _metaBookmark : _teamBookmark],
    );
  }

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async {
    readSites.add((siteUrl: siteUrl, id: id));
  }

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    userActivitySites.add(siteUrl);
    userActivityUsers.add(username);
    return const UserActivityPage();
  }

  @override
  Future<void> updateHidePresence({
    required String siteUrl,
    required String apiKey,
    required String username,
    required bool hidePresence,
    String? clientId,
  }) async {
    presenceUpdates.add((
      siteUrl: siteUrl,
      username: username,
      hidePresence: hidePresence,
    ));
  }
}
