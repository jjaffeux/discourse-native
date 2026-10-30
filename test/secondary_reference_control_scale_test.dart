import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/plugins/boards/boards_directory.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/message_inbox_page.dart';
import 'package:discourse_native/src/shell/message_inbox_title.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/event_fixtures.dart';
import 'support/fakes.dart';

const _site = 'https://forum.example';
const _user = DiscourseUser(id: 1, username: 'reader');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final screen in [
    'bookmarks',
    'activity',
    'messages',
    'inbox selector',
    'boards',
    'calendar',
  ]) {
    for (final (appScale, accessibility, height, textSize) in [
      (1.0, 1.0, 44.0, 16.0),
      (1.25, 2.0, 80.0, 40.0),
    ]) {
      testWidgets(
        '$screen controls exclude reading uplift at app zoom $appScale and accessibility $accessibility',
        (tester) async {
          tester.view.physicalSize = const Size(900, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final api = FakeDiscourseApi(
            user: _user,
            bookmarkList: const [],
            userActivityItems: const [
              UserActivityItem(
                actionType: UserActivityItem.topicActionType,
                topicId: 1,
                postNumber: 1,
                title: 'An activity topic',
                slug: 'activity',
                username: 'reader',
                excerpt: '',
              ),
            ],
          );
          final shell = ShellController(
            instanceStore: FakeInstanceStore([
              instance('forum.example').copyWith(user: _user),
            ]),
            api: api,
            authenticator: FakeAuthenticator()..keys[_site] = 'key',
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            updater: FakeUpdater(),
            updateStore: FakeUpdateStore(),
          );
          addTearDown(shell.dispose);
          await shell.load();
          shell.selectDestination(
            const SidebarDestination(
              id: 'messages',
              label: 'Messages',
              icon: DIcons.inbox,
            ),
          );
          final ports = EventTestPorts();
          addTearDown(ports.close);
          final page = switch (screen) {
            'bookmarks' => BookmarkSection(
              siteUrl: _site,
              page: true,
              onOpened: () {},
            ),
            'activity' => const UserActivityView(siteUrl: _site),
            'messages' => const MessageInboxPage(feed: TopicFeed(loaded: true)),
            'inbox selector' => const MessageInboxSelector(
              selectedGroup: null,
              useSelect: true,
            ),
            'boards' => BoardsDirectory(
              site: _site,
              boards: const [],
              categories: const {},
              loaded: true,
              error: null,
              onRefresh: () async {},
              onOpen: (_) {},
            ),
            _ => EventCalendar(
              page: EventCalendarPage(
                EventCalendarView.month,
                DateTime.utc(2026, 9, 8),
              ),
              events: const [],
              location: ports.zones.location('Europe/Paris')!,
              onPageChanged: (_) {},
              onOpen: (_) {},
              mine: false,
              onMineChanged: (_) {},
              status: const Text('Calendar status'),
              clock: eventTestNow,
            ),
          };
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: AppTextScaler(
                      platformScaler: TextScaler.linear(accessibility),
                      appScale: appScale,
                      baselineScale: 17 / 14,
                    ),
                  ),
                  child: child!,
                ),
                home: Scaffold(body: page),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final heading = screen == 'calendar'
              ? find.byKey(const ValueKey('event-calendar-header'))
              : find.byType(DPageSurface);
          final controls = screen == 'inbox selector'
              ? find.byKey(const ValueKey('message-inbox-selector'))
              : find.descendant(
                  of: heading,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is DSelect && widget.size == DControlSize.filter,
                  ),
                );
          expect(controls, findsWidgets);
          for (final control in controls.evaluate()) {
            final finder = find.byWidget(control.widget);
            expect(tester.getSize(finder).height, height);
            final text = find
                .descendant(of: finder, matching: find.byType(Text))
                .first;
            final context = tester.element(text);
            final size = DefaultTextStyle.of(context).style.fontSize!;
            expect(MediaQuery.textScalerOf(context).scale(size), textSize);
          }
          if (screen == 'calendar') {
            final context = tester.element(find.text('Calendar status'));
            expect(
              MediaQuery.textScalerOf(context).scale(14),
              17 * appScale * accessibility,
            );
          }
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}
