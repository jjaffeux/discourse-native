import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_about.dart';
import 'package:discourse_native/src/shell/forum_about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/skeleton_expectations.dart';

const about = ForumAbout(
  title: 'Garden community',
  description: 'A welcoming place to discuss gardens and share what you grow.',
  extendedDescription: 'Learn, ask questions and meet other gardeners.',
  stats: {
    'users_count': 1200,
    'topics_7_days': 34,
    'posts_last_day': 10,
    'active_users_7_days': 80,
    'users_7_days': 3,
    'likes_count': 20000,
    'voice_users_7_days': 21,
  },
);

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

void main() {
  for (final size in [const Size(390, 844), const Size(1100, 900)]) {
    testWidgets(
      'About renders and scrolls at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var opened = false;
        await tester.pumpWidget(
          host(
            ForumAboutPage(
              load: () async => about,
              voiceEnabled: true,
              onOpenFullPage: () => opened = true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Garden community'), findsOneWidget);
        expect(find.text('1,200 members'), findsOneWidget);
        expect(find.text('Forum activity'), findsOneWidget);
        final cards = find.byType(DCard);
        final identityBounds = tester.getRect(cards.at(0));
        final activityBounds = tester.getRect(cards.at(1));
        if (size.width >= 680) {
          expect(identityBounds.right, lessThan(activityBounds.left));
          expect(activityBounds.right, lessThanOrEqualTo(size.width - 16));
          expect(
            activityBounds.right - identityBounds.left,
            lessThanOrEqualTo(825),
          );
        } else {
          expect(identityBounds.bottom, lessThan(activityBounds.top));
        }
        expect(find.text('21 voice participants'), findsOneWidget);
        await tester.ensureVisible(find.text('21 voice participants'));
        await tester.pumpAndSettle();
        expect(
          find.text('21 voice participants').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.text('Open full About page'));
        expect(opened, isTrue);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(
        size.width < 600 ? TargetPlatform.iOS : TargetPlatform.linux,
      ),
    );
  }

  testWidgets('narrow large text wraps and keeps actions usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        ForumAboutPage(
          load: () async => about,
          voiceEnabled: true,
          onOpenFullPage: () {},
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('21 voice participants'));
    await tester.pumpAndSettle();
    expect(find.text('21 voice participants').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('forum-about-browser')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('pending load covers the viewport with visible skeletons', (
    tester,
  ) async {
    final load = Completer<ForumAbout>();
    await tester.pumpWidget(
      host(ForumAboutPage(load: () => load.future, onOpenFullPage: () {})),
    );
    await tester.pump();
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expectSkeletonFillsViewport(
      tester,
      label: 'Loading forum information',
      bottom: tester.getRect(find.byType(DSkeletonRegion)).bottom,
    );
    expect(
      tester.getSize(find.byType(DSkeletonRegion)).height,
      greaterThan(350),
    );
    expect(find.text('0 voice participants'), findsNothing);
    load.complete(about);
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
  });

  testWidgets('retry recovers, older data and disabled Voice have no row', (
    tester,
  ) async {
    var requests = 0;
    final page = ForumAboutPage(
      load: () async {
        if (++requests == 1) throw const FormatException('offline');
        return about;
      },
      onOpenFullPage: () {},
    );
    await tester.pumpWidget(host(page));
    await tester.pumpAndSettle();
    expect(
      find.text('Couldn’t load information about this forum.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Garden community'), findsOneWidget);
    expect(find.text('21 voice participants'), findsNothing);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private anonymous About does not load', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      host(
        ForumAboutPage(
          loginRequired: true,
          load: () async {
            requests++;
            return about;
          },
          onOpenFullPage: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(
      find.text('Sign in to view information about this forum.'),
      findsOneWidget,
    );
    expect(find.byType(DSkeleton), findsNothing);
  });

  testWidgets('a new owner ignores the previous request', (tester) async {
    final old = Completer<ForumAbout>();
    await tester.pumpWidget(
      host(
        ForumAboutPage(
          requestIdentity: 'old-session',
          load: () => old.future,
          onOpenFullPage: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      host(
        ForumAboutPage(
          requestIdentity: 'new-session',
          load: () async => const ForumAbout(title: 'New forum'),
          onOpenFullPage: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    old.complete(about);
    await tester.pumpAndSettle();
    expect(find.text('New forum'), findsOneWidget);
    expect(find.text('Garden community'), findsNothing);
  });
}
