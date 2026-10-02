import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show replaceEmojiCache;

const _site = 'https://meta.discourse.org';
const _alreadyPerformed =
    'Oops! You already performed this action. Can you try refreshing the page?';
const _reader = DiscourseUser(id: 9, username: 'reader');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final control in ['count', 'menu']) {
    testWidgets(
      '$control does not repeat a completed like before repaint',
      (tester) async {
        final fixture = await _Fixture.open(tester);
        final controlFinder = await _likeControl(tester, control);
        await _tapWithoutFrame(tester, controlFinder);
        expect(fixture.api.serverLiked, isTrue);
        expect(fixture.shell.postWriteInFlight(1), isFalse);
        expect(fixture.shell.store.read<Post>(_site, 1)!.liked, isTrue);
        expect(fixture.api.requests, hasLength(1));
        // The visible old Like/count callback still describes the unliked post.
        expect(controlFinder.hitTestable(), findsOneWidget);
        await _tapWithoutFrame(tester, controlFinder);
        expect(fixture.shell.store.read<Post>(_site, 1)!.liked, isTrue);
        expect(fixture.api.requests, hasLength(1));
        expect(fixture.api.serverLiked, isTrue);
        expect(fixture.shell.store.read<Post>(_site, 1)!.liked, isTrue);
        expect(fixture.shell.store.read<Post>(_site, 1)!.likeCount, 2);
        await tester.pumpAndSettle();
        expect(find.text(_alreadyPerformed), findsNothing);
        expect(_count('2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }
  testWidgets(
    'a repainted like can normally be undone',
    (tester) async {
      final fixture = await _Fixture.open(tester);
      await _tapWithoutFrame(tester, _count('1'));
      await tester.pumpAndSettle();
      expect(_count('2'), findsOneWidget);
      await _tapWithoutFrame(tester, _count('2'));
      await tester.pumpAndSettle();
      expect(fixture.api.requests.map((request) => request.method), [
        'POST',
        'DELETE',
      ]);
      expect(fixture.api.serverLiked, isFalse);
      expect(fixture.shell.store.read<Post>(_site, 1)!.liked, isFalse);
      expect(_count('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );
  testWidgets(
    'an accepted like preserves its intent through credential lookup',
    (tester) async {
      final fixture = await _Fixture.open(tester);
      final gate = Completer<String?>();
      fixture.auth.nextRead = gate;
      fixture.api.emptyResponse = true;
      await _tapWithoutFrame(tester, _count('1'));
      expect(fixture.auth.nextRead, isNull);
      expect(fixture.api.requests, isEmpty);
      final held = fixture.shell.store.read<Post>(_site, 1)!;
      // A later read can update counts/permissions during credential lookup.
      // The Like was already eligible when the click was accepted.
      fixture.shell.store.put(
        _site,
        held.copyWith(likeCount: 5, canLike: false),
      );
      gate.complete('api-key');
      await tester.runAsync(() => pumpEventQueue());
      expect(fixture.api.requests.single.method, 'POST');
      expect(fixture.shell.store.read<Post>(_site, 1)!.liked, isTrue);
      expect(fixture.shell.store.read<Post>(_site, 1)!.likeCount, 6);
      await tester.pumpAndSettle();
      expect(_count('6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );
}

Finder _count(String value) =>
    find.descendant(of: find.byType(PostLikes), matching: find.text(value));

Future<Finder> _likeControl(WidgetTester tester, String control) async {
  if (control == 'count') return _count('1');
  await tester.tap(find.byKey(const ValueKey('post-more-actions-1')));
  await tester.pumpAndSettle();
  return find.widgetWithText(DDropdownMenuItem, 'Like');
}

Future<void> _tapWithoutFrame(WidgetTester tester, Finder control) =>
    tester.runAsync(() async {
      await tester.tap(control);
      await pumpEventQueue();
    });

class _Fixture {
  _Fixture(this.shell, this.api, this.auth);
  final ShellController shell;
  final _Api api;
  final _Auth auth;
  static Future<_Fixture> open(WidgetTester tester) async {
    final api = _Api();
    final auth = _Auth()..keys[_site] = 'api-key';
    final shell = ShellController(
      api: api,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: _reader),
      ]),
      authenticator: auth,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    addTearDown(api.httpApi.close);
    await tester.runAsync(shell.load);
    shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
    await tester.runAsync(() => pumpEventQueue());
    final width = defaultTargetPlatform == TargetPlatform.iOS ? 390.0 : 1000.0;
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    replaceEmojiCache(MockClient((_) async => http.Response('', 404)));
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
          builder: (_, child) => DToaster(child: child!),
          home: Scaffold(
            body: MainContent(layout: ShellLayout.forWidth(width)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_count('1'), findsOneWidget);
    return _Fixture(shell, api, auth);
  }
}

Map<String, Object?> _postJson(bool liked) => {
  'id': 1,
  'post_number': 1,
  'username': 'author',
  'cooked': '<p>Post body</p>',
  'actions_summary': [
    {
      'id': 2,
      'count': liked ? 2 : 1,
      'acted': liked,
      'can_act': !liked,
      'can_undo': liked,
    },
  ],
};

class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        user: _reader,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [Post.fromJson(_postJson(false), _site)],
          ),
        },
      );
  bool serverLiked = false;
  bool emptyResponse = false;
  final requests = <http.Request>[];
  late final httpApi = DiscourseApi(
    client: MockClient((request) async {
      requests.add(request);
      expect(request.headers['User-Api-Key'], 'api-key');
      if (request.method == 'POST') {
        expect(request.url.path, '/post_actions.json');
        expect(jsonDecode(request.body), {'id': 1, 'post_action_type_id': 2});
        if (serverLiked) {
          return http.Response(
            jsonEncode({
              'errors': [_alreadyPerformed],
            }),
            403,
          );
        }
        serverLiked = true;
      } else {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/post_actions/1.json');
        expect(request.url.queryParameters['post_action_type_id'], '2');
        serverLiked = false;
      }
      return emptyResponse
          ? http.Response('', 204)
          : http.Response(jsonEncode(_postJson(serverLiked)), 200);
    }),
  );

  @override
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) => httpApi.likePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<Post?> unlikePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) => httpApi.unlikePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );
}

class _Auth extends FakeAuthenticator {
  Completer<String?>? nextRead;
  @override
  Future<String?> apiKeyFor(String siteUrl) {
    final held = nextRead;
    if (held == null) return super.apiKeyFor(siteUrl);
    nextRead = null;
    return held.future;
  }
}
