import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/content_navigation_controls.dart';
import 'package:discourse_native/src/shell/invite_list.dart';
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
import 'support/invite_fixtures.dart' show invitePage, inviteRow;

const _metaUrl = 'https://meta.discourse.org';
const _teamUrl = 'https://team.discourse.org';
const _metaUser = DiscourseUser(
  id: 1,
  username: 'meta-user',
  name: 'Meta User',
  hidePresence: false,
  canInviteToForum: true,
);
const _teamUser = DiscourseUser(
  id: 2,
  username: 'team-user',
  name: 'Team User',
  hidePresence: true,
  canInviteToForum: true,
);

const _metaNotification = DiscourseNotification.test(
  id: 11,
  typeId: NotificationTypeId(12),
  data: {
    'badge_id': 11,
    'badge_slug': 'meta-helper',
    'badge_name': 'Meta Helper',
  },
);

const _teamNotification = DiscourseNotification.test(
  id: 22,
  typeId: NotificationTypeId(12),
  data: {
    'badge_id': 22,
    'badge_slug': 'team-helper',
    'badge_name': 'Team Helper',
  },
);

const _metaReply = DiscourseNotification.test(
  id: 13,
  typeId: NotificationTypeId(2),
  topicId: 13,
  slug: 'meta-reply',
  title: 'Meta reply',
  data: {'display_username': 'alice'},
);

const _teamReply = DiscourseNotification.test(
  id: 24,
  typeId: NotificationTypeId(3),
  topicId: 24,
  slug: 'team-reply',
  title: 'Team reply',
  data: {'display_username': 'bob'},
);

const _metaBookmarkReminder = DiscourseNotification.test(
  id: 31,
  typeId: NotificationTypeId(24),
  title: 'Meta chat message',
  data: {'bookmarkable_url': '/chat/c/meta/1/31'},
);

const _teamBookmarkReminder = DiscourseNotification.test(
  id: 32,
  typeId: NotificationTypeId(24),
  title: 'Team chat message',
  data: {'bookmarkable_url': '/chat/c/team/2/32'},
);

void main() {
  group('invite section ownership', () {
    testWidgets(
      'replaces desktop invites when the selected site changes',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
        await _openInviteSection(tester);
        expect(find.text('meta-invite@example.com'), findsOneWidget);
        final shell = ShellScope.read(
          tester.element(find.byType(InviteSection)),
        );
        shell.selectInstance(1);
        await tester.pumpAndSettle();
        expect(find.text('meta-invite@example.com'), findsNothing);
        expect(find.text('team-invite@example.com'), findsOneWidget);
        expect(fixture.api.inviteSites, [_metaUrl, _teamUrl]);
      }),
    );

    testWidgets(
      'reloads mobile invites when the selected site changes',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        final launched = _watchBrowser(tester);
        await _openInviteSection(tester);
        final shell = ShellScope.read(
          tester.element(find.byType(InviteSection)),
        );
        shell.selectInstance(1);
        await tester.pumpAndSettle();
        expect(find.text('meta-invite@example.com'), findsNothing);
        expect(find.text('team-invite@example.com'), findsOneWidget);
        final manage = find.text('Manage invites in browser');
        await tester.ensureVisible(manage);
        await tester.pumpAndSettle();
        await tester.tap(manage);
        await tester.pumpAndSettle();
        expect(launched, ['$_teamUrl/u/team-user/invited/pending']);
        expect(fixture.api.inviteSites, [_metaUrl, _teamUrl]);
      }),
    );
  });

  group('menu controls', () {
    testWidgets(
      'expose labeled toggle state with keyboard actions on pointer platforms',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (_) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.tap(find.byKey(UserMenuButton.bellKey));
          await tester.pumpAndSettle();

          final notifications = _desktopFilter('all');
          final bookmarks = _desktopFilter('bookmarks');
          final replies = _desktopFilter('replies');

          for (final tab in [notifications, bookmarks, replies]) {
            expect(
              tester.getSize(tab).height,
              greaterThanOrEqualTo(
                DToggle.visualDimensionFor(DToggleSize.small),
              ),
            );
            expect(tester.widget<DToggle>(tab).size, DToggleSize.small);
          }
          expect(
            tester.getSemantics(_toggleSemantics(notifications)),
            isSemantics(
              label: 'All',
              isButton: true,
              hasToggledState: true,
              isToggled: true,
              hasTapAction: true,
            ),
          );
          await _focusTab(tester, bookmarks);
          expect(bookmarks.hitTestable(), findsOneWidget);
          expect(
            tester.getSemantics(_toggleSemantics(bookmarks)),
            isSemantics(
              label: 'Bookmarks',
              isButton: true,
              hasToggledState: true,
              isToggled: false,
              hasTapAction: true,
            ),
          );

          expect(
            tester.getSemantics(_toggleSemantics(bookmarks)),
            isSemantics(isFocusable: true, isFocused: true),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();

          expect(find.byType(BookmarkSection), findsOneWidget);
          expect(
            tester.getSemantics(_toggleSemantics(bookmarks)),
            isSemantics(hasToggledState: true, isToggled: true),
          );
          await tester.ensureVisible(notifications);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(_toggleSemantics(notifications)),
            isSemantics(hasToggledState: true, isToggled: false),
          );

          await _focusTab(tester, replies);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();

          expect(find.byType(RepliesSection), findsOneWidget);
          expect(
            tester.getSemantics(_toggleSemantics(replies)),
            isSemantics(hasToggledState: true, isToggled: true),
          );
        } finally {
          semantics.dispose();
        }
      }),
    );

    testWidgets(
      'pause and resume notifications accessibly from the keyboard',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
        final semantics = tester.ensureSemantics();
        try {
          final avatar = tester
              .widget<DButton>(find.byKey(UserMenuButton.avatarKey))
              .focusNode!;
          var row = find.byKey(const ValueKey('pause-notifications-row'));
          Future<void> choosePause() async {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            for (var step = 0; step < 20 && !_focusWithin(row); step++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pump();
            }
            expect(_focusWithin(row), isTrue);
            expect(
              tester.widget<DDropdownMenuCheckboxItem>(row).checked,
              isFalse,
            );
            expect(
              tester.widget<DDropdownMenuCheckboxItem>(row).onChanged,
              isNotNull,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
          }

          avatar.requestFocus();
          await tester.pump();
          await choosePause();
          expect(find.byType(UserMenuPanel), findsNothing);
          expect(find.text('Pause notifications for…'), findsOneWidget);
          final focused = FocusManager.instance.primaryFocus!.context!;
          expect(ModalRoute.of(focused), isA<DialogRoute<void>>());

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Pause notifications for…'), findsNothing);
          expect(avatar.hasPrimaryFocus, isTrue);

          await choosePause();
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

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            _focusWithin(find.byKey(const ValueKey('do-not-disturb-halfHour'))),
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();

          expect(fixture.api.doNotDisturbDurations, [
            const DoNotDisturbDuration.minutes(30),
          ]);
          expect(find.text('Pause notifications for…'), findsNothing);

          await tester.tap(find.byKey(UserMenuButton.avatarKey));
          await tester.pumpAndSettle();
          row = find.byKey(const ValueKey('pause-notifications-row'));
          expect(
            tester.getSemantics(row),
            isSemantics(
              label: 'Pause notifications',
              hasTapAction: true,
              hasCheckedState: true,
              isChecked: true,
            ),
          );
          expect(tester.getSemantics(row).value, startsWith('On, until'));
          expect(find.text('30m'), findsNothing);

          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(fixture.api.doNotDisturbResumes, [_metaUrl]);
          expect(
            tester.getSemantics(row),
            isSemantics(hasCheckedState: true, isChecked: false),
          );
        } finally {
          semantics.dispose();
        }
      }),
    );

    testWidgets(
      'close both touch sheets before showing pause choices',
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
      'link pause choices to the source account notification schedule',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (_) async {
        final launched = _watchBrowser(tester);
        await tester.tap(find.byKey(UserMenuButton.avatarKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pause-notifications-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Set a notification schedule'));
        await tester.pumpAndSettle();

        expect(launched, ['$_metaUrl/u/meta-user/preferences/notifications']);
      }),
    );

    testWidgets(
      'custom status dismisses the touch dropdown before editing and saving',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        await _openNestedSection(tester, 'Profile');
        await tester.tap(
          find.byKey(const ValueKey('user-menu-row-user-status')),
        );
        await tester.pumpAndSettle();

        final editor = find.byKey(const ValueKey('user-status-editor'));
        expect(editor, findsOneWidget);
        expect(
          find
              .descendant(of: editor, matching: find.byTooltip('Close'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Save').hitTestable(), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Available');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(fixture.api.userStatusesSet.single.description, 'Available');
        expect(editor, findsNothing);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(tester.takeException(), isNull);
      }),
    );

    testWidgets(
      'open the custom-status editor from the profile row',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (_) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.tap(find.byKey(UserMenuButton.avatarKey));
          await tester.pumpAndSettle();

          final status = find.byKey(
            const ValueKey('user-menu-row-user-status'),
          );
          expect(status, findsOneWidget);

          await tester.tap(status);
          await tester.pumpAndSettle();

          expect(find.text('Set custom status'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('What’s your status')),
            findsOneWidget,
          );
          expect(find.text('Clear after'), findsOneWidget);
        } finally {
          semantics.dispose();
        }
      }),
    );
  });

  group('site-scoped menu content', () {
    testWidgets(
      'held desktop controls do not activate for the next selected site',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        final shell = ShellScope.read(
          tester.element(find.byType(UserMenuPanel)),
        );
        final markAllRead = find.widgetWithText(DButton, 'Mark all read');
        final heldAction = await tester.startGesture(
          tester.getCenter(markAllRead),
        );

        shell.selectInstance(1);
        await tester.pumpAndSettle();
        await heldAction.up();
        await tester.pumpAndSettle();

        expect(find.byType(UserMenuPanel), findsOneWidget);
        expect(find.textContaining('Team Helper'), findsOneWidget);
        expect(fixture.api.markedTypesRead, isEmpty);

        final replies = _desktopFilter('replies');
        await tester.ensureVisible(replies);
        await tester.pumpAndSettle();
        final heldFilter = await tester.startGesture(tester.getCenter(replies));

        shell.selectInstance(0);
        await tester.pumpAndSettle();
        await heldFilter.up();
        await tester.pumpAndSettle();

        expect(find.byType(NotificationSection), findsOneWidget);
        expect(find.textContaining('Meta Helper'), findsOneWidget);
        expect(fixture.api.replySites, isEmpty);
        await tester.tap(markAllRead);
        await tester.pumpAndSettle();
        expect(fixture.api.markedTypesRead, hasLength(1));
      }),
    );

    testWidgets(
      'reloads each selected activity section when an open popover changes sites',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
        final api = fixture.api;

        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();

        expect(api.notificationSites, [_metaUrl]);
        expect(find.textContaining('Meta Helper'), findsOneWidget);

        final shell = ShellScope.read(
          tester.element(find.byType(UserMenuPanel)),
        );
        shell.selectInstance(1);
        await tester.pumpAndSettle();

        expect(find.byType(UserMenuPanel), findsOneWidget);
        expect(api.notificationSites, [_metaUrl, _teamUrl]);
        expect(find.textContaining('Team Helper'), findsOneWidget);

        await _tapDesktopFilter(tester, 'replies');
        expect(api.replySites, [_teamUrl]);
        expect(find.textContaining('Team reply'), findsOneWidget);

        shell.selectInstance(0);
        await tester.pumpAndSettle();

        expect(api.replySites, [_teamUrl, _metaUrl]);
        expect(find.textContaining('Meta reply'), findsOneWidget);

        await _tapDesktopFilter(tester, 'bookmarks');
        expect(api.bookmarkSites, [_metaUrl]);
        expect(
          find.descendant(
            of: find.byType(BookmarkSection),
            matching: find.textContaining('Meta chat message'),
          ),
          findsOneWidget,
        );

        shell.selectInstance(1);
        await tester.pumpAndSettle();

        expect(api.bookmarkSites, [_metaUrl, _teamUrl]);
        expect(
          find.descendant(
            of: find.byType(BookmarkSection),
            matching: find.textContaining('Team chat message'),
          ),
          findsOneWidget,
        );
      }),
    );

    testWidgets(
      'mobile notification actions follow the displayed site',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        final launched = _watchBrowser(tester);
        final api = fixture.api;

        await _openNestedSection(tester, 'Notifications');
        final section = find.byType(NotificationSection);
        final shell = ShellScope.read(tester.element(section));

        shell.selectInstance(1);
        await tester.pumpAndSettle();

        expect(find.textContaining('Team Helper'), findsOneWidget);
        expect(api.notificationSites, [_metaUrl, _teamUrl]);

        await tester.tap(find.textContaining('Team Helper'));
        await tester.pumpAndSettle();

        expect(launched, isEmpty);
        expect(shell.currentInstance?.url, _teamUrl);
        expect(shell.currentContent?.badgeRoute?.badgeId, 22);
        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.text('Recently awarded'), findsOneWidget);
        expect(api.badgeSites, [_teamUrl, _teamUrl]);
        expect(api.readSites, [(siteUrl: _teamUrl, id: 22)]);
      }),
    );

    testWidgets(
      'reloads the mobile Replies tab when the selected site changes',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        final api = fixture.api;

        await _openNestedSection(tester, 'Replies');
        final section = find.byType(RepliesSection);
        final shell = ShellScope.read(tester.element(section));

        shell.selectInstance(1);
        await tester.pumpAndSettle();

        expect(find.textContaining('Team reply'), findsOneWidget);
        expect(api.replySites, [_metaUrl, _teamUrl]);
      }),
    );

    testWidgets(
      'mobile bookmark reminder actions follow the displayed site',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        final launched = _watchBrowser(tester);
        final api = fixture.api;

        await _openNestedSection(tester, 'Bookmarks');
        final section = find.byType(BookmarkSection);
        final shell = ShellScope.read(tester.element(section));

        shell.selectInstance(1);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(BookmarkSection),
            matching: find.textContaining('Team chat message'),
          ),
          findsOneWidget,
        );
        expect(api.bookmarkSites, [_metaUrl, _teamUrl]);

        await tester.tap(
          find.descendant(
            of: find.byType(BookmarkSection),
            matching: find.textContaining('Team chat message'),
          ),
        );
        await tester.pumpAndSettle();

        expect(launched, ['$_teamUrl/chat/c/team/2/32']);
        expect(api.readSites, [(siteUrl: _teamUrl, id: 32)]);
      }),
    );
  });

  group('preferences navigation', () {
    testWidgets(
      'closes the pointer menu and restores prior content on Back',
      (tester) => _withMenu(tester, TargetPlatform.macOS, (fixture) async {
        await tester.tap(find.byKey(UserMenuButton.avatarKey));
        await tester.pumpAndSettle();

        final panel = find.byType(DDropdownMenuContent);
        final preferences = find.descendant(
          of: panel,
          matching: find.byKey(const ValueKey('user-menu-row-preferences')),
        );

        final shell = ShellScope.read(tester.element(panel));
        final priorRoute = shell.currentContent;
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
        expect(fixture.api.userPreferenceLoads, [
          (siteUrl: _metaUrl, username: 'meta-user', clientId: 'test-client'),
        ]);

        // Preferences has no page header; Back is the desktop chrome control.
        await tester.tap(find.byKey(ContentNavigationControls.backKey));
        await tester.pumpAndSettle();

        expect(find.byType(PreferencesPage), findsNothing);
        expect(shell.currentContent, priorRoute);
      }),
    );

    testWidgets(
      'touch profile follows the selected account before opening preferences',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        await _openNestedSection(tester, 'Profile');
        final preferences = find.byKey(
          const ValueKey('user-menu-row-preferences'),
        );
        final shell = ShellScope.read(tester.element(preferences));
        shell.selectInstance(1);
        await tester.pumpAndSettle();
        expect(shell.currentInstance?.url, _teamUrl);
        expect(find.text('Team User'), findsOneWidget);

        await tester.tap(preferences);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('user-menu-sheet')), findsNothing);
        expect(find.byType(PreferencesPage), findsOneWidget);
        expect(
          tester.widget<PreferencesPage>(find.byType(PreferencesPage)).siteUrl,
          _teamUrl,
        );
        expect(shell.currentInstance?.url, _teamUrl);
        expect(shell.currentContent?.isPreferences, isTrue);
        expect(fixture.api.userPreferenceLoads, [
          (siteUrl: _teamUrl, username: 'team-user', clientId: 'test-client'),
        ]);
      }),
    );
  });

  group('profile source actions', () {
    testWidgets(
      'disconnect the visible touch profile account and retain the other account',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        await _openNestedSection(tester, 'Profile');
        final shell = ShellScope.read(tester.element(find.text('Disconnect')));
        shell.selectInstance(1);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();

        expect(fixture.auth.disconnected, [_teamUrl]);
        expect(shell.currentUserFor(_teamUrl), isNull);
        expect(shell.currentUserFor(_metaUrl), _metaUser);
      }),
    );

    testWidgets(
      'load the visible touch profile account for Activity',
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
        final surface = find
            .ancestor(
              of: find.byType(UserActivityView),
              matching: find.byType(DPageSurface),
            )
            .first;
        expect(tester.widget<DPageSurface>(surface).header, isNull);
        expect(
          find.descendant(
            of: find.byType(UserActivityView),
            matching: find.text('Activity'),
          ),
          findsOneWidget,
        );
        expect(shell.currentInstance?.url, _teamUrl);
        expect(shell.currentContent?.id, 'activity');
        expect(api.userActivitySites, [_teamUrl]);
        expect(api.userActivityUsers, ['team-user']);
      }),
    );

    testWidgets(
      'change presence only for the visible touch profile account',
      (tester) => _withMenu(tester, TargetPlatform.android, (fixture) async {
        final api = fixture.api;

        await _openNestedSection(tester, 'Profile');
        final shell = ShellScope.read(tester.element(find.text('Online')));
        shell.selectInstance(1);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Online'));
        await tester.pumpAndSettle();

        expect(api.presenceUpdates, [
          (siteUrl: _teamUrl, username: 'team-user', hidePresence: false),
        ]);
        expect(shell.hidePresenceFor(_metaUrl), isFalse);
        expect(shell.hidePresenceFor(_teamUrl), isFalse);
      }),
    );
  });
}

bool _focusWithin(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: finder,
        matching: find.byElementPredicate(
          (element) => identical(element, focused),
        ),
      )
      .evaluate()
      .isNotEmpty;
}

Future<void> _focusTab(WidgetTester tester, Finder tab) async {
  final focus = tester.widget<DToggle>(tab).focusNode!;
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
}

Finder _desktopFilter(String id) => find.ancestor(
  of: find.byKey(ValueKey('user-menu-tab-$id')),
  matching: find.byType(DToggle),
);

Finder _toggleSemantics(Finder filter) => find.descendant(
  of: filter,
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.toggled != null,
  ),
);

Future<void> _tapDesktopFilter(WidgetTester tester, String id) async {
  final filter = _desktopFilter(id);
  await tester.ensureVisible(filter);
  await tester.pumpAndSettle();
  expect(filter.hitTestable(), findsOneWidget);
  await tester.tap(filter);
  await tester.pumpAndSettle();
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
  final api = _SiteMenuApi(
    doNotDisturbUntil: DateTime.now().add(const Duration(minutes: 30)),
  );
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
  await tester.tap(
    find.byKey(
      label == 'Profile' ? UserMenuButton.avatarKey : UserMenuButton.bellKey,
    ),
  );
  await tester.pumpAndSettle();
  if (label == 'Profile') return;
  final panel = find.byType(UserMenuPanel);
  final menu = panel.evaluate().isNotEmpty
      ? panel
      : find.byKey(const ValueKey('user-menu-sheet'));
  final tab = find.descendant(of: menu, matching: find.text(label)).last;
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _openInviteSection(WidgetTester tester) async {
  final context = tester.element(find.byType(UserMenuButton).first);
  final shell = ShellScope.read(context);
  unawaited(
    showDDialog<void>(
      context: context,
      builder: (context, dialog) => ShellScope(
        controller: shell,
        child: DDialogContent(
          maxWidth: 500,
          children: [
            ShellSelector<String?>(
              select: (controller) => controller.currentInstance?.url,
              builder: (context, siteUrl, _) =>
                  InviteSection(siteUrl: siteUrl!, onOpened: dialog.close),
            ),
          ],
        ),
      ),
    ),
  );
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
  _SiteMenuApi({required DateTime doNotDisturbUntil})
    : super(
        doNotDisturbUntil: doNotDisturbUntil,
        siteConfigs: const {
          _metaUrl: SiteConfig(userStatusEnabled: true),
          _teamUrl: SiteConfig(userStatusEnabled: true),
        },
      );

  final List<String> notificationSites = [];
  final List<String> badgeSites = [];
  final List<String> replySites = [];
  final List<String> bookmarkSites = [];
  final List<String> inviteSites = [];
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
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final badgeId = siteUrl == _metaUrl ? 11 : 22;
    if (path == '/badges/$badgeId.json') {
      badgeSites.add(siteUrl);
      return {
        'badge': {
          'id': badgeId,
          'name': siteUrl == _metaUrl ? 'Meta Helper' : 'Team Helper',
        },
      };
    }
    if (path == '/user_badges.json?badge_id=$badgeId&offset=0') {
      badgeSites.add(siteUrl);
      return const {
        'user_badge_info': {'user_badges': <Map<String, dynamic>>[]},
      };
    }
    if (Uri.parse(path).path.endsWith('/invited.json')) {
      inviteSites.add(siteUrl);
      return invitePage([
        inviteRow(
          1,
          email: siteUrl == _metaUrl
              ? 'meta-invite@example.com'
              : 'team-invite@example.com',
        ),
      ]);
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
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
      reminders: [
        siteUrl == _metaUrl ? _metaBookmarkReminder : _teamBookmarkReminder,
      ],
      bookmarks: const <Bookmark>[],
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
