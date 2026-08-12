import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('the like pill is a named 44 pixel keyboard target', (
    tester,
  ) async {
    final api = FakeDiscourseApi();
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(
          user: const DiscourseUser(username: 'reader', name: 'Reader'),
        ),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: PostLikes(
                  siteUrl: _siteUrl,
                  post: Post(
                    id: 1,
                    postNumber: 1,
                    username: 'author',
                    cooked: '<p>Post body</p>',
                    likeCount: 1,
                    canLike: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.descendant(
        of: find.byType(PostLikes),
        matching: find.byType(InkWell),
      );
      expect(target, findsOneWidget);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(target),
        isSemantics(
          label: '1 like, from someone else',
          onTapHint: 'like this post',
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(target),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a read-only like pill opens likers from the keyboard', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      likersById: const {
        1: [PostLiker(id: 2, username: 'sam', name: 'Sam Saffron')],
      },
    );
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(
          user: const DiscourseUser(username: 'reader', name: 'Reader'),
        ),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: PostLikes(
                  siteUrl: _siteUrl,
                  post: Post(
                    id: 1,
                    postNumber: 1,
                    username: 'author',
                    cooked: '<p>Post body</p>',
                    likeCount: 1,
                    canLike: false,
                    canUnlike: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.bySemanticsLabel('1 like, from someone else');
      expect(
        tester.getSemantics(target),
        isSemantics(
          label: '1 like, from someone else',
          onTapHint: 'show who liked this post',
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(target),
        isSemantics(isFocusable: true, isFocused: true),
      );
      expect(find.text('Sam Saffron'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(api.likersRequested, [1, 1]);
      expect(api.liked, isEmpty);
      expect(api.unliked, isEmpty);
    } finally {
      semantics.dispose();
    }
  });
}
