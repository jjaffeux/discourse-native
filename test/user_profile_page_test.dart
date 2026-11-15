import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_profile.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_profile_page.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' as harness;

const _site = 'https://meta.example';
const _me = DiscourseUser(id: 1, username: 'reader');

final _profile = UserProfile(
  card: UserCard(
    id: 2,
    username: 'sam',
    name: 'Sam Example',
    title: 'Community guide',
    bioExcerpt: '<p>Short excerpt.</p>',
    location: 'Paris',
    website: 'https://sam.example/blog',
    websiteName: 'sam.example',
    createdAt: DateTime.utc(2013, 2, 1),
    lastPostedAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  bioCooked: '<p>The whole biography, second paragraph included.</p>',
  lastSeenAt: DateTime.now().subtract(const Duration(hours: 5)),
);

final _summary = UserSummary(
  canSeeSummaryStats: true,
  likesGiven: 7,
  likesReceived: 8,
  daysVisited: 11,
  topicCount: 2,
  postCount: 3,
);

final _rows = [
  UserActivityItem(
    actionType: UserActivityItem.topicActionType,
    topicId: 12,
    postNumber: 1,
    title: 'A topic Sam started',
    slug: 'topic',
    username: 'sam',
    excerpt: 'Opening words',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  ),
];

final _page = find.byType(UserProfilePage);

Finder _within(Finder matching) =>
    find.descendant(of: _page, matching: matching);

Future<(ShellController, FakeDiscourseApi)> _pump(
  WidgetTester tester, {
  Size size = harness.desktop,
  bool signedIn = true,
  Future<UserProfile> Function(String siteUrl, String username)? profile,
  UserSummary? summary,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = FakeDiscourseApi(
    user: signedIn ? _me : null,
    summary: summary ?? _summary,
    userActivityItems: _rows,
  )..userProfileHandler = profile ?? (_, _) async => _profile;
  await harness.pumpShell(
    tester,
    size,
    instances: [instance('meta.example', user: signedIn ? _me : null)],
    api: api,
    authenticator: signedIn
        ? (FakeAuthenticator()..keys[_site] = 'key')
        : FakeAuthenticator(),
  );
  final shell = ShellScope.read(tester.element(find.byType(MainContent).first));
  return (shell, api);
}

void _open(ShellController shell) =>
    shell.openUserProfile(_site, username: 'sam', displayName: 'Sam Example');

void _desktopTest(String name, WidgetTesterCallback body) => testWidgets(
  name,
  body,
  variant: TargetPlatformVariant.only(TargetPlatform.linux),
);

void main() {
  _desktopTest('a profile loads behind a labelled skeleton', (tester) async {
    final semantics = tester.ensureSemantics();
    final gate = Completer<UserProfile>();
    final (shell, api) = await _pump(tester, profile: (_, _) => gate.future);

    _open(shell);
    await tester.pump();
    await tester.pump();

    expect(api.profilesRequested, ['sam']);
    expect(_within(find.byType(DSkeletonRegion)), findsOneWidget);
    expect(find.bySemanticsLabel('Loading profile'), findsOneWidget);
    expect(_within(find.text('Summary')), findsNothing);

    gate.complete(_profile);
    await tester.pumpAndSettle();

    expect(_within(find.bySemanticsLabel('Loading profile')), findsNothing);
    expect(_within(find.text('Sam Example')), findsWidgets);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  _desktopTest('a loaded profile shows the person, then their summary', (
    tester,
  ) async {
    final launched = harness.watchBrowser(tester);
    final (shell, api) = await _pump(tester);

    _open(shell);
    await tester.pumpAndSettle();

    expect(_within(find.text('@sam')), findsOneWidget);
    expect(_within(find.text('Community guide')), findsOneWidget);
    expect(
      _within(harness.renderedText('The whole biography')),
      findsOneWidget,
      reason: 'the full bio, which the card endpoint cuts short',
    );
    expect(_within(harness.renderedText('Short excerpt')), findsNothing);
    expect(_within(find.text('Paris')), findsOneWidget);
    expect(_within(harness.renderedText('Joined Feb 2013')), findsOneWidget);
    expect(_within(harness.renderedText('Last seen 5h')), findsOneWidget);
    expect(_within(harness.renderedText('Last post 3d')), findsOneWidget);

    expect(_within(find.byType(UserSummaryPanel)), findsOneWidget);
    expect(api.userSummaryRequests.single.username, 'sam');
    expect(_within(find.text('Highlights')), findsOneWidget);
    expect(_within(find.text('Likes received')), findsOneWidget);
    expect(
      _within(find.text('No highlights yet.')),
      findsOneWidget,
      reason: 'another person is not addressed as "you"',
    );

    await tester.tap(_within(find.text('sam.example')));
    await tester.pump();
    expect(launched, ['https://sam.example/blog']);
    expect(tester.takeException(), isNull);
  });

  _desktopTest('the section switch shows activity and is remembered', (
    tester,
  ) async {
    final (shell, api) = await _pump(tester);
    _open(shell);
    await tester.pumpAndSettle();

    await tester.tap(_within(find.text('Activity')));
    await tester.pumpAndSettle();

    expect(_within(find.byType(UserSummaryPanel)), findsNothing);
    expect(_within(find.byType(UserActivityView)), findsOneWidget);
    expect(_within(find.text('A topic Sam started')), findsOneWidget);
    expect(api.userActivityRequests.last.username, 'sam');

    shell.pushContent(ContentRoute.forumAbout());
    await tester.pumpAndSettle();
    expect(_page, findsNothing);
    shell.handleBack();
    await tester.pumpAndSettle();
    expect(
      _within(find.text('A topic Sam started')),
      findsOneWidget,
      reason: 'the section a reader chose survives leaving the page',
    );

    await tester.tap(_within(find.text('A topic Sam started')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 12);
    expect(tester.takeException(), isNull);
  });

  _desktopTest('a hidden profile shows who it is and nothing else', (
    tester,
  ) async {
    final (shell, api) = await _pump(
      tester,
      profile: (_, _) async => const UserProfile(
        card: UserCard(id: 2, username: 'sam', name: 'Sam Example'),
        hidden: true,
      ),
    );

    _open(shell);
    await tester.pumpAndSettle();

    expect(_within(find.text('@sam')), findsOneWidget);
    expect(
      _within(find.text('This person has hidden their public profile.')),
      findsOneWidget,
    );
    expect(_within(find.text('Summary')), findsNothing);
    expect(_within(find.text('Activity')), findsNothing);
    expect(api.userSummaryRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  _desktopTest('a person the site does not have is said to be missing', (
    tester,
  ) async {
    final (shell, _) = await _pump(
      tester,
      profile: (siteUrl, _) async => throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        statusCode: 404,
      ),
    );

    _open(shell);
    await tester.pumpAndSettle();

    expect(
      _within(
        find.text("This profile doesn't exist or isn't available to you."),
      ),
      findsOneWidget,
    );
    expect(_within(find.text('Try again')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _desktopTest('a refusal says the profile cannot be seen', (tester) async {
    final (shell, _) = await _pump(
      tester,
      profile: (siteUrl, _) async => throw SiteLookupException(
        SiteLookupFailure.notDiscourse,
        siteUrl,
        statusCode: 403,
      ),
    );

    _open(shell);
    await tester.pumpAndSettle();

    expect(_within(find.text("Couldn't see that profile.")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _desktopTest('a failed load offers a retry that loads the profile', (
    tester,
  ) async {
    var attempts = 0;
    final (shell, api) = await _pump(
      tester,
      profile: (siteUrl, _) async => ++attempts == 1
          ? throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl)
          : _profile,
    );

    _open(shell);
    await tester.pumpAndSettle();
    expect(_within(find.text("Couldn't reach meta.example.")), findsOneWidget);

    await tester.tap(_within(find.text('Try again')));
    await tester.pumpAndSettle();

    expect(api.profilesRequested, ['sam', 'sam']);
    expect(_within(find.text('@sam')), findsOneWidget);
    expect(_within(find.text("Couldn't reach meta.example.")), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _desktopTest('a visitor reads the profile and is asked to connect for more', (
    tester,
  ) async {
    final (shell, api) = await _pump(tester, signedIn: false);

    _open(shell);
    await tester.pumpAndSettle();

    expect(_within(find.text('@sam')), findsOneWidget);
    expect(
      _within(harness.renderedText('The whole biography')),
      findsOneWidget,
    );
    expect(
      _within(find.text('Connect this account to see its summary')),
      findsOneWidget,
    );
    expect(api.userSummaryRequests, isEmpty);

    await tester.tap(_within(find.text('Activity')));
    await tester.pumpAndSettle();
    expect(
      _within(find.text('Connect this account to see its activity')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  _desktopTest('the title is a heading and the sections are reachable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (shell, _) = await _pump(tester);
    _open(shell);
    await tester.pumpAndSettle();

    expect(
      find.semantics.byPredicate(
        (node) => node.flagsCollection.isHeader && node.label == 'Sam Example',
      ),
      findsOne,
    );

    final activity = tester.getSemantics(
      _within(find.bySemanticsLabel('Activity')).first,
    );
    expect(activity.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    final summary = tester.getSemantics(
      _within(find.bySemanticsLabel('Summary')).first,
    );
    expect(summary.flagsCollection.isSelected, Tristate.isTrue);
    semantics.dispose();
  });

  for (final (size, platform) in [
    (harness.phone, TargetPlatform.iOS),
    (harness.desktop, TargetPlatform.linux),
  ]) {
    testWidgets('fits ${size.width}px at twice the text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (shell, _) = await _pump(tester, size: size);

      _open(shell);
      await tester.pumpAndSettle();
      expect(_within(find.text('@sam')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Centred, so the floating page header does not cover the switch.
      await Scrollable.ensureVisible(
        tester.element(_within(find.text('Activity'))),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(_within(find.text('Activity')));
      await tester.pumpAndSettle();
      expect(_within(find.text('A topic Sam started')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  group('links', () {
    for (final path in ['/u/sam', '/u/sam/summary']) {
      _desktopTest('$path opens the profile in the app', (tester) async {
        final launched = harness.watchBrowser(tester);
        final (shell, _) = await _pump(tester);

        expect(await shell.openInAppLink('$_site$path'), isTrue);
        await tester.pumpAndSettle();

        expect(_page, findsOneWidget);
        expect(_within(find.text('@sam')), findsOneWidget);
        expect(launched, isEmpty);

        expect(await shell.openInAppLink('$_site/u/SAM'), isTrue);
        await tester.pumpAndSettle();
        expect(_page, findsOneWidget, reason: 'the same person, already open');
        shell.handleBack();
        await tester.pumpAndSettle();
        expect(_page, findsNothing);
      });
    }

    _desktopTest('an activity link opens that person\'s activity page', (
      tester,
    ) async {
      final (shell, _) = await _pump(tester);

      expect(
        await shell.openInAppLink('$_site/u/sam/activity/replies'),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(
        shell.currentContent!.sameDestinationAs(
          ContentRoute.userActivity(username: 'sam'),
        ),
        isTrue,
      );
      expect(find.text('A topic Sam started'), findsOneWidget);
    });

    _desktopTest('a new tab and a second panel open the profile too', (
      tester,
    ) async {
      final (shell, _) = await _pump(tester);

      expect(shell.openLinkInNewTab('$_site/u/sam'), TabOpenResult.opened);
      await tester.pumpAndSettle();
      expect(_page, findsNothing, reason: 'a new tab opens behind this one');

      expect(
        shell.openLinkInPanel(
          '$_site/u/sam/summary',
          panel: ForumPanel.secondary,
        ),
        TabOpenResult.opened,
      );
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget);
      expect(_within(find.text('@sam')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _desktopTest('a page of a person the app has not built stays a web link', (
      tester,
    ) async {
      final (shell, _) = await _pump(tester);

      expect(await shell.openInAppLink('$_site/u/sam/preferences'), isFalse);
      expect(await shell.openInAppLink('$_site/u/sam/badges'), isFalse);
      expect(_page, findsNothing);
    });
  });

  _desktopTest('refreshing the tab asks for the profile again', (tester) async {
    final (shell, api) = await _pump(tester);
    _open(shell);
    await tester.pumpAndSettle();

    await tester.runAsync(shell.refreshCurrentTab);
    await tester.pumpAndSettle();

    expect(api.profilesRequested, ['sam', 'sam']);
    expect(api.userSummaryRequests.map((request) => request.username), [
      'sam',
      'sam',
    ]);
    expect(_within(find.text('@sam')), findsOneWidget);
  });
}
