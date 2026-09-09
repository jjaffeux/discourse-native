import 'dart:async';

import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteUrl = 'https://meta.example';
const _publicCard = UserCard(username: 'author', name: 'Public profile');
const _connectedCard = UserCard(username: 'author', name: 'Connected profile');

Finder get _cardSurface => find.byKey(const ValueKey('user-card-surface'));

void main() {
  testWidgets('account replacement safely dismisses an open hover preview', (
    tester,
  ) async {
    final api = _CardApi();
    final auth = _GatedAuthenticator();
    await pumpShell(
      tester,
      desktop,
      api: api,
      authenticator: auth,
      instances: [instance('meta.example')],
    );
    await tester.tap(find.text('Public topic'));
    await tester.pumpAndSettle();
    final controller = ShellScope.read(
      tester.element(find.byType(UserMenuButton)),
    );
    await tester.tap(find.byKey(UserMenuButton.signInKey));
    await tester.pump();
    expect(controller.connecting, isTrue);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.widgetWithText(UserCardTarget, 'author')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(api.requests, hasLength(1));
    api.requests.single.response.complete(_publicCard);
    await tester.pump();
    expect(find.text('Public profile'), findsOneWidget);

    auth.gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(controller.currentInstance?.isConnected, isTrue);
    expect(controller.userCard('author', siteUrl: _siteUrl), isNull);
    expect(find.text('Public profile'), findsNothing);
    expect(find.byType(UserCardTarget), findsNothing);
    expect(api.requests.map((request) => request.apiKey), [null]);
  });

  testWidgets('a loaded card reloads when pending sign-in completes', (
    tester,
  ) async {
    final api = _CardApi();
    final auth = _GatedAuthenticator();
    final controller = await _openCardDuringSignIn(tester, api, auth);
    final route = ModalRoute.of(tester.element(_cardSurface));
    api.requests.single.response.complete(_publicCard);
    await tester.pump();
    expect(find.text('Public profile'), findsOneWidget);

    auth.gate.complete();
    await tester.pump();
    await tester.pump();

    expect(controller.currentInstance?.isConnected, isTrue);
    expect(_cardController(tester), same(controller));
    expect(ModalRoute.of(tester.element(_cardSurface)), same(route));
    expect(find.text('Public profile'), findsNothing);
    expect(api.requests.map((request) => request.apiKey), [null, 'api-key']);

    api.requests.last.response.complete(_connectedCard);
    await tester.pumpAndSettle();
    expect(find.text('Connected profile'), findsOneWidget);
    expect(activityIndicators, findsNothing);
  });

  for (final oldResponseFirst in [true, false]) {
    testWidgets('a pending card reloads when sign-in completes, old response '
        '${oldResponseFirst ? 'first' : 'last'}', (tester) async {
      final api = _CardApi();
      final auth = _GatedAuthenticator();
      final controller = await _openCardDuringSignIn(tester, api, auth);
      final oldRequest = api.requests.single;

      auth.gate.complete();
      await tester.pump();
      await tester.pump();

      expect(controller.currentInstance?.isConnected, isTrue);
      expect(_cardController(tester), same(controller));
      expect(api.requests.map((request) => request.apiKey), [null, 'api-key']);
      final replacement = api.requests.last;

      if (oldResponseFirst) {
        oldRequest.response.complete(_publicCard);
        await tester.pump();
        expect(find.text('Public profile'), findsNothing);
        expect(controller.userCard('author', siteUrl: _siteUrl), isNull);
        expect(activityIndicators, findsOneWidget);
      }

      replacement.response.complete(_connectedCard);
      await tester.pumpAndSettle();
      expect(find.text('Connected profile'), findsOneWidget);
      expect(activityIndicators, findsNothing);

      if (!oldResponseFirst) {
        oldRequest.response.complete(_publicCard);
        await tester.pumpAndSettle();
      }
      expect(controller.userCard('author', siteUrl: _siteUrl), _connectedCard);
      expect(find.text('Connected profile'), findsOneWidget);
      expect(find.text('Public profile'), findsNothing);
      expect(api.requests, hasLength(2));
    });
  }

  testWidgets('reloading a card preserves a newer overlaid dialog', (
    tester,
  ) async {
    final api = _CardApi();
    final auth = _GatedAuthenticator();
    await _openCardDuringSignIn(tester, api, auth);
    api.requests.single.response.complete(_publicCard);
    await tester.pump();

    final navigator = Navigator.of(tester.element(_cardSurface));
    final newerDialog = showDialog<void>(
      context: tester.element(_cardSurface),
      builder: (_) => const AlertDialog(title: Text('Newer dialog')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    auth.gate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Newer dialog'), findsOneWidget);
    expect(api.requests.map((request) => request.apiKey), [null, 'api-key']);
    api.requests.last.response.complete(_connectedCard);
    await tester.pumpAndSettle();
    expect(find.text('Newer dialog'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    await newerDialog;
    expect(find.text('Connected profile'), findsOneWidget);
    expect(activityIndicators, findsNothing);
  });

  testWidgets('a replacement card error waits for Retry before reloading', (
    tester,
  ) async {
    final api = _CardApi();
    final auth = _GatedAuthenticator();
    final controller = await _openCardDuringSignIn(tester, api, auth);
    api.requests.single.response.complete(_publicCard);
    await tester.pump();

    auth.gate.complete();
    await tester.pump();
    await tester.pump();
    expect(api.requests, hasLength(2));

    api.requests.last.response.completeError(StateError('Profile unavailable'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load @author."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    controller.setForeground(false);
    controller.setForeground(true);
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(2));

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(api.requests.map((request) => request.apiKey), [
      null,
      'api-key',
      'api-key',
    ]);
    api.requests.last.response.complete(_connectedCard);
    await tester.pumpAndSettle();
    expect(find.text('Connected profile'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(activityIndicators, findsNothing);
  });
}

ShellController _cardController(WidgetTester tester) =>
    ShellScope.read(tester.element(_cardSurface));

Future<ShellController> _openCardDuringSignIn(
  WidgetTester tester,
  _CardApi api,
  _GatedAuthenticator auth,
) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    authenticator: auth,
    instances: [instance('meta.example')],
  );
  await tester.tap(find.text('Public topic'));
  await tester.pumpAndSettle();
  final controller = ShellScope.read(
    tester.element(find.byType(UserMenuButton)),
  );

  await tester.tap(find.byKey(UserMenuButton.signInKey));
  await tester.pump();
  expect(auth.started.isCompleted, isTrue);
  expect(controller.connecting, isTrue);
  expect(controller.currentInstance?.isConnected, isFalse);

  await tester.tap(find.widgetWithText(UserCardTarget, 'author'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  expect(_cardSurface, findsOneWidget);
  expect(api.requests, hasLength(1));
  expect(api.requests.single.siteUrl, _siteUrl);
  expect(api.requests.single.username, 'author');
  expect(api.requests.single.apiKey, isNull);
  return controller;
}

final class _GatedAuthenticator extends FakeAuthenticator {
  final gate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    started.complete();
    await gate.future;
    return super.authorize(siteUrl);
  }
}

final class _CardApi extends FakeDiscourseApi {
  _CardApi()
    : super(
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
              ),
            ],
          ),
        },
      );

  final requests =
      <
        ({
          String siteUrl,
          String username,
          String? apiKey,
          Completer<UserCard> response,
        })
      >[];

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<UserCard>();
    requests.add((
      siteUrl: siteUrl,
      username: username,
      apiKey: apiKey,
      response: response,
    ));
    return response.future;
  }
}
