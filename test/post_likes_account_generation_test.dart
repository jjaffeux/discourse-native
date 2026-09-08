import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _signedInUser = DiscourseUser(id: 9, username: 'reader');
const _publicLikers = PostLikers(
  postId: 1,
  likers: [PostLiker(id: 2, username: 'public', name: 'Public liker')],
);
const _accountLikers = PostLikers(
  postId: 1,
  likers: [PostLiker(id: 3, username: 'account', name: 'Account liker')],
);

void main() {
  testWidgets('a loaded touch likes sheet reloads after pending sign-in', (
    tester,
  ) async {
    final api = _LikersApi();
    final auth = _PendingAuthenticator();
    final shell = await _openDuringSignIn(tester, api, auth);
    final sheetContext = tester.element(find.text('2 likes'));
    final route = ModalRoute.of(sheetContext)!;
    final navigator = Navigator.of(sheetContext);

    api.responses.single.complete(_publicLikers);
    await _pumpFrames(tester);
    expect(find.text('Public liker'), findsOneWidget);
    expect(find.text('and 1 other'), findsOneWidget);
    expect(_sheetIndicators, findsNothing);

    await _completeSignIn(tester, shell, api, auth);
    expect(ModalRoute.of(tester.element(find.text('2 likes'))), same(route));
    expect(Navigator.of(tester.element(find.text('2 likes'))), same(navigator));
    expect(find.text('Public liker'), findsNothing);
    expect(_sheetIndicators, findsOneWidget);

    api.responses.last.complete(_accountLikers);
    await tester.pumpAndSettle();
    expect(find.text('Account liker'), findsOneWidget);
    expect(find.text('and 1 other'), findsOneWidget);
    expect(_sheetIndicators, findsNothing);
    expect(api.apiKeys, [null, 'account-key']);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final oldCompletesFirst in [true, false]) {
    testWidgets(
      'pending public likers cannot replace the account result when completing '
      '${oldCompletesFirst ? 'first' : 'last'}',
      (tester) async {
        final api = _LikersApi();
        final auth = _PendingAuthenticator();
        final shell = await _openDuringSignIn(tester, api, auth);
        expect(_sheetIndicators, findsOneWidget);

        await _completeSignIn(tester, shell, api, auth);
        expect(_sheetIndicators, findsOneWidget);
        if (oldCompletesFirst) {
          api.responses.first.complete(_publicLikers);
          await _pumpFrames(tester);
          expect(shell.likers(1, siteUrl: _site), isNull);
          expect(find.text('Public liker'), findsNothing);
          expect(_sheetIndicators, findsOneWidget);
        }

        api.responses.last.complete(_accountLikers);
        await tester.pumpAndSettle();
        if (!oldCompletesFirst) {
          api.responses.first.complete(_publicLikers);
          await tester.pumpAndSettle();
        }

        expect(shell.likers(1, siteUrl: _site), _accountLikers);
        expect(find.text('Account liker'), findsOneWidget);
        expect(find.text('Public liker'), findsNothing);
        expect(_sheetIndicators, findsNothing);
        expect(api.apiKeys, [null, 'account-key']);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('the replacement liker request can finish with an error', (
    tester,
  ) async {
    final api = _LikersApi();
    final auth = _PendingAuthenticator();
    final shell = await _openDuringSignIn(tester, api, auth);
    api.responses.single.complete(_publicLikers);
    await _pumpFrames(tester);

    await _completeSignIn(tester, shell, api, auth);
    api.responses.last.completeError(
      const SiteLookupException(SiteLookupFailure.unreachable, _site),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reach meta.discourse.org."), findsOneWidget);
    expect(find.text('Public liker'), findsNothing);
    expect(_sheetIndicators, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

Finder get _sheetIndicators =>
    find.descendant(of: find.byType(BottomSheet), matching: activityIndicators);

Future<ShellController> _openDuringSignIn(
  WidgetTester tester,
  _LikersApi api,
  _PendingAuthenticator auth,
) async {
  await pumpShell(
    tester,
    laptop,
    api: api,
    authenticator: auth,
    instances: [instance('meta.discourse.org', title: 'Meta')],
  );
  await tester.tap(find.text('Public topic'));
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(find.byType(MainContent)));
  expect(shell.currentInstance?.isConnected, isFalse);
  expect(shell.currentContent?.topicId, 7);

  // Authorization includes push registration, key generation and the browser
  // callback. The public topic remains usable while that future is pending.
  await tester.tap(find.byKey(UserMenuButton.signInKey));
  await tester.pump();
  expect(auth.started, isTrue);
  expect(shell.connecting, isTrue);
  expect(renderedText('Public post body'), findsOneWidget);

  final count = find.descendant(
    of: find.byType(PostLikes),
    matching: find.text('2'),
  );
  await tester.longPress(count);
  await _pumpFrames(tester);
  expect(find.text('2 likes'), findsOneWidget);
  expect(api.likersRequested, [1]);
  expect(api.apiKeys, [null]);
  expect(shell.connecting, isTrue);
  return shell;
}

Future<void> _completeSignIn(
  WidgetTester tester,
  ShellController shell,
  _LikersApi api,
  _PendingAuthenticator auth,
) async {
  final lease = shell.lifecycle.capture(_site);
  auth.authorization.complete();
  await _pumpFrames(tester);
  expect(shell.currentInstance?.user, _signedInUser);
  expect(shell.connecting, isFalse);
  expect(lease.isCurrent, isFalse);
  expect(ShellScope.read(tester.element(find.text('2 likes'))), same(shell));
  expect(api.likersRequested, [1, 1]);
  expect(api.apiKeys, [null, 'account-key']);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Both sign-in and liker loading can keep activity indicators animating.
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

class _PendingAuthenticator extends FakeAuthenticator {
  _PendingAuthenticator()
    : super(
        credentials: const UserApiCredentials(
          key: 'account-key',
          apiVersion: 4,
          push: false,
        ),
      );

  final authorization = Completer<void>();
  bool started = false;

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    started = true;
    await authorization.future;
    return super.authorize(siteUrl);
  }
}

class _LikersApi extends FakeDiscourseApi {
  _LikersApi()
    : super(
        user: _signedInUser,
        feeds: const {
          '/latest.json': [
            Topic(id: 7, title: 'Public topic', slug: 'public-topic'),
          ],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Public topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'author',
                cooked: '<p>Public post body</p>',
                likeCount: 2,
                canLike: false,
                canUnlike: false,
              ),
            ],
            stream: const [1],
            postsCount: 1,
          ),
        },
      );

  final apiKeys = <String?>[];
  final responses = <Completer<PostLikers>>[];

  @override
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) {
    expect(siteUrl, _site);
    likersRequested.add(postId);
    apiKeys.add(apiKey);
    final response = Completer<PostLikers>();
    responses.add(response);
    return response.future;
  }
}
