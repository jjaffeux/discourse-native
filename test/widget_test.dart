import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/right_sidebar.dart';
import 'package:discourse_native/src/shell/user_bar.dart';

import 'support/fakes.dart';

/// Sizes chosen to sit either side of the shell's breakpoints (768 / 1200).
const Size phone = Size(390, 844);
const Size laptop = Size(1000, 800);
const Size desktop = Size(1440, 900);

final List<DiscourseInstance> twoSites = [
  instance('meta.discourse.org', title: 'Discourse Meta'),
  instance('team.discourse.org', title: 'Discourse Team'),
];

Future<void> pumpShell(
  WidgetTester tester,
  Size size, {
  List<DiscourseInstance>? instances,
  FakeDiscourseApi? api,
  FakeInstanceStore? store,
  FakeAuthenticator? authenticator,
  Key? key,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    DiscourseApp(
      key: key,
      store: store ?? FakeInstanceStore(instances ?? twoSites),
      api: api ?? FakeDiscourseApi(),
      authenticator: authenticator ?? FakeAuthenticator(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('compact', () {
    testWidgets('shows the rail and the sidebar, but no main content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
      expect(find.byType(RightSidebar), findsNothing);
    });

    testWidgets('selecting a destination replaces the sidebar with content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();

      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      // The rail never goes away.
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('back returns from content to the sidebar', (tester) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
    });

    testWidgets('back unwinds the content stack before the sidebar', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace with deeper view'));
      await tester.pumpAndSettle();

      expect(find.text('Topic 1'), findsWidgets);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // First back pops the stack; the sidebar is still not showing.
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
    });

    testWidgets('the right sidebar is never used', (tester) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();

      expect(find.byType(RightSidebar), findsNothing);
    });

    testWidgets('the user bar card is inset further on iOS', (tester) async {
      await pumpShell(tester, phone, key: const ValueKey('default'));
      final byDefault = tester.getRect(find.byKey(UserBar.cardKey));

      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        // A distinct key rebuilds the tree against the platform in effect.
        await pumpShell(tester, phone, key: const ValueKey('ios'));
        final onIos = tester.getRect(find.byKey(UserBar.cardKey));

        expect(onIos.width, lessThan(byDefault.width));
        expect(onIos.left, UserBar.iosHorizontalMargin);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('the user bar yields the height to the main content', (
      tester,
    ) async {
      await pumpShell(tester, phone);
      expect(find.byType(UserBar), findsOneWidget);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();

      expect(find.byType(UserBar), findsNothing);
    });
  });

  group('medium', () {
    testWidgets('shows rail, sidebar and content together', (tester) async {
      await pumpShell(tester, laptop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(RightSidebar), findsNothing);
    });
  });

  group('expanded', () {
    testWidgets('adds the right sidebar', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(RightSidebar), findsOneWidget);
    });

    testWidgets('the user bar spans the rail and the sidebar', (tester) async {
      await pumpShell(tester, desktop);

      final railLeft = tester.getTopLeft(find.byType(InstanceRail)).dx;
      final sidebarRight = tester
          .getBottomRight(find.byType(InstanceSidebar))
          .dx;
      final bar = tester.getRect(find.byType(UserBar));

      expect(bar.left, railLeft);
      expect(bar.right, sidebarRight);
      // ...and stops short of the main content.
      expect(
        bar.right,
        lessThan(tester.getTopLeft(find.byType(MainContent)).dx + 1),
      );
    });

    testWidgets('the user bar floats over the columns', (tester) async {
      await pumpShell(tester, desktop);

      final rail = tester.getRect(find.byType(InstanceRail));
      final sidebar = tester.getRect(find.byType(InstanceSidebar));
      final bar = tester.getRect(find.byType(UserBar));

      // Both columns run to the bottom edge behind the bar rather than being
      // pushed up by it — that is what makes the bar read as floating.
      expect(rail.bottom, bar.bottom);
      expect(sidebar.bottom, bar.bottom);
      expect(sidebar.top, lessThan(bar.top));
    });

    testWidgets('the right sidebar can be collapsed', (tester) async {
      await pumpShell(tester, desktop);

      await tester.tap(find.byIcon(Icons.view_sidebar));
      await tester.pumpAndSettle();

      expect(find.byType(RightSidebar), findsNothing);
      expect(find.byType(MainContent), findsOneWidget);
    });
  });

  testWidgets('switching instance swaps the sidebar contents', (tester) async {
    await pumpShell(tester, desktop);

    expect(find.text('Discourse Meta'), findsOneWidget);

    // Second entry in the rail.
    await tester.tap(find.text('DT'));
    await tester.pumpAndSettle();

    expect(find.text('Discourse Team'), findsOneWidget);
    expect(find.text('Discourse Meta'), findsNothing);
  });

  group('adding a site', () {
    testWidgets('shows the empty state with nothing connected', (tester) async {
      await pumpShell(tester, desktop, instances: const []);

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      // The rail is still there, holding the add button.
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('a looked-up site lands in the rail and is persisted', (
      tester,
    ) async {
      final store = FakeInstanceStore(const []);
      final api = FakeDiscourseApi(
        results: {
          'meta.discourse.org': instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ),
        },
      );

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.text('Add a site'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'meta.discourse.org');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(api.lookups, ['meta.discourse.org']);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.text('Discourse Meta'), findsOneWidget);
      expect(store.saveCount, 1);
    });

    testWidgets('a failed lookup reports why and adds nothing', (tester) async {
      final store = FakeInstanceStore(const []);
      final api = FakeDiscourseApi(failure: SiteLookupFailure.notDiscourse);

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.text('Add a site'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is not a Discourse forum'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(store.saveCount, 0);
    });

    testWidgets('the same site cannot be added twice', (tester) async {
      final existing = instance('meta.discourse.org', title: 'Discourse Meta');
      final store = FakeInstanceStore([existing]);
      final api = FakeDiscourseApi(
        results: {'https://meta.discourse.org/': existing},
      );

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'https://meta.discourse.org/');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already in your list'), findsOneWidget);
      expect(store.saveCount, 0);
    });
  });

  group('connecting', () {
    testWidgets('the bar invites you to connect until you do', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Tap to connect'), findsOneWidget);
    });

    testWidgets('connecting records the account against the site', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, store: store, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      // Authorized against the selected site, not some other one.
      expect(auth.connected, ['https://meta.discourse.org']);
      expect(find.text('Joffrey'), findsOneWidget);
      expect(find.text('meta.discourse.org'), findsWidgets);
      expect(store.saveCount, 1);
    });

    testWidgets('backing out of the browser is not an error', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.cancelled);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      expect(find.text('Tap to connect'), findsOneWidget);
      expect(find.textContaining('could not be verified'), findsNothing);
    });

    testWidgets('an unverifiable reply is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.badReply);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be verified'), findsOneWidget);
    });

    testWidgets('disconnecting forgets the key and the account', (tester) async {
      final auth = FakeAuthenticator();
      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();
      expect(find.text('Joffrey'), findsOneWidget);

      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(auth.disconnected, ['https://meta.discourse.org']);
      expect(find.text('Not signed in'), findsOneWidget);
    });
  });
}
