import 'dart:async';

import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_revision.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _otherSite = 'https://team.example';
const _openingUser = DiscourseUser(id: 1, username: 'reader');
const _replacementUser = DiscourseUser(id: 2, username: 'replacement');
const _connectionChanged =
    'Your connection changed. Reopen edit history and try again.';
const _post = Post(
  id: 42,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Post body</p>',
  version: 4,
  canViewEditHistory: true,
);
typedef _PostTarget = ({String siteUrl, Post post});
typedef _RevisionRequest = ({
  String siteUrl,
  int postId,
  int? revision,
  String? apiKey,
});

void main() {
  for (final disconnect in [false, true]) {
    testWidgets(
      'history navigation refuses ${disconnect ? 'disconnect and reconnect' : 'account replacement'} before credentials',
      (tester) async {
        final fixture = await _mount(tester);
        await fixture.open(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Previous'));
        await tester.pumpAndSettle();
        expect(find.text('Comparing version 2 to 3 of 4'), findsOneWidget);

        await fixture.reconnect(tester, disconnect: disconnect);
        final requests = fixture.api.requests.toList();
        final reads = fixture.auth.keyReads.toList();
        final clientReads = fixture.auth.clientReads;

        for (final action in ['Next', 'Previous', 'First', 'Latest']) {
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();

          expect(fixture.api.requests, requests, reason: action);
          expect(fixture.auth.keyReads, reads, reason: action);
          expect(fixture.auth.clientReads, clientReads, reason: action);
          expect(find.text(_connectionChanged), findsOneWidget);
          expect(find.text('Comparing version 2 to 3 of 4'), findsOneWidget);
        }

        await fixture.reopen(tester);
        expect(fixture.api.requests.last, (
          siteUrl: _site,
          postId: 42,
          revision: null,
          apiKey: 'replacement-key',
        ));
        expect(find.text('replacement-editor'), findsOneWidget);
        expect(find.text(_connectionChanged), findsNothing);
        await tester.tap(find.text('Previous'));
        await tester.pumpAndSettle();
        expect(fixture.api.requests.last.apiKey, 'replacement-key');
        expect(fixture.api.requests.last.revision, 3);
        expect(find.text('Comparing version 2 to 3 of 4'), findsOneWidget);
      },
    );
  }

  testWidgets('Retry refuses a replacement account before credentials', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final pending = fixture.api.gateNext();
    await fixture.open(tester);
    expect(fixture.api.requests, hasLength(1));
    pending.completeError(StateError('Revision unavailable'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load edit history."), findsOneWidget);

    await fixture.reconnect(tester);
    final reads = fixture.auth.keyReads.toList();
    final clientReads = fixture.auth.clientReads;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fixture.api.requests, hasLength(1));
    expect(fixture.auth.keyReads, reads);
    expect(fixture.auth.clientReads, clientReads);
    expect(find.text(_connectionChanged), findsOneWidget);
    await fixture.reopen(tester);
    expect(fixture.api.requests.last.apiKey, 'replacement-key');
    expect(find.text('replacement-editor'), findsOneWidget);
  });

  for (final initial in [true, false]) {
    for (final fails in [false, true]) {
      testWidgets(
        '${initial ? 'opening' : 'Previous'} ${fails ? 'failure' : 'result'} after reconnect reports the ended account',
        (tester) async {
          final fixture = await _mount(tester);
          if (!initial) {
            await fixture.open(tester);
            await tester.pumpAndSettle();
          }
          final pending = fixture.api.gateNext();
          if (initial) {
            await fixture.open(tester);
          } else {
            await tester.tap(find.text('Previous'));
            await tester.pump();
          }
          expect(fixture.api.requests.last.apiKey, 'opening-key');
          expect(fixture.api.nextResult, isNull);

          // Do not settle an indeterminate loading indicator before releasing
          // the revision request. Account replacement itself is fully awaited.
          await fixture.reconnect(tester, settle: false);
          final reads = fixture.auth.keyReads.toList();
          final requests = fixture.api.requests.toList();
          if (fails) {
            pending.completeError(StateError('Old account request failed'));
          } else {
            pending.complete(_revision(3, editor: 'stale-editor'));
          }
          await tester.pumpAndSettle();

          expect(find.text(_connectionChanged), findsOneWidget);
          expect(find.text('stale-editor'), findsNothing);
          expect(find.text("Couldn't load edit history."), findsNothing);
          expect(fixture.api.requests, requests);
          expect(fixture.auth.keyReads, reads);
          if (initial) {
            await tester.tap(find.text('Retry'));
          } else {
            expect(find.text('Comparing version 3 to 4 of 4'), findsOneWidget);
            await tester.tap(find.text('Previous'));
          }
          await tester.pumpAndSettle();
          expect(fixture.api.requests, requests);
          expect(fixture.auth.keyReads, reads);
          await fixture.reopen(tester);
          expect(find.text('replacement-editor'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('reconnect during a credential read never dispatches history', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final credential = Completer<String?>();
    fixture.auth.nextRead = credential;
    await fixture.open(tester);
    expect(fixture.auth.nextRead, isNull);
    expect(fixture.api.requests, isEmpty);

    await fixture.reconnect(tester, settle: false);
    final reads = fixture.auth.keyReads.toList();
    credential.complete('replacement-key');
    await tester.pumpAndSettle();

    expect(fixture.api.requests, isEmpty);
    expect(fixture.auth.keyReads, reads);
    expect(find.text(_connectionChanged), findsOneWidget);
    await fixture.reopen(tester);
    expect(fixture.api.requests.single.apiKey, 'replacement-key');
    expect(find.text('replacement-editor'), findsOneWidget);
  });

  for (final removeOrigin in [false, true]) {
    testWidgets(
      'history keeps its opening site and post when navigation ${removeOrigin ? 'removes' : 'reuses'} PostActions',
      (tester) async {
        final fixture = await _mount(tester);
        final origin = tester.state(find.byType(PostActions));
        final pending = fixture.api.gateNext();
        await fixture.open(tester);

        fixture.controller.openTopicPost(
          siteUrl: _otherSite,
          topicId: 9,
          postNumber: 1,
        );
        fixture.target.value = removeOrigin
            ? null
            : (siteUrl: _otherSite, post: _otherPost);
        await tester.pump();
        if (removeOrigin) {
          expect(origin.mounted, isFalse);
        } else {
          expect(tester.state(find.byType(PostActions)), same(origin));
          expect(
            tester.widget<PostActions>(find.byType(PostActions)).siteUrl,
            _otherSite,
          );
        }
        expect(fixture.controller.currentInstance?.url, _otherSite);
        pending.complete(_revision(4));
        await tester.pumpAndSettle();
        _expectOpeningCategories();

        final reads = fixture.auth.keyReads.length;
        await tester.tap(find.text('Previous'));
        await tester.pumpAndSettle();
        expect(fixture.api.requests.last, (
          siteUrl: _site,
          postId: 42,
          revision: 3,
          apiKey: 'opening-key',
        ));
        expect(fixture.auth.keyReads.skip(reads), [_site]);
        _expectOpeningCategories();
        expect(find.text(_connectionChanged), findsNothing);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(fixture.api.requests.last.siteUrl, _site);
        expect(fixture.api.requests.last.postId, 42);
        expect(fixture.api.requests.last.revision, 4);
        expect(find.text('Comparing version 3 to 4 of 4'), findsOneWidget);
      },
    );
  }

  testWidgets('Retry keeps the opening site after PostActions is reused', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final pending = fixture.api.gateNext();
    await fixture.open(tester);
    pending.completeError(StateError('Try again'));
    await tester.pumpAndSettle();

    fixture.controller.openTopicPost(
      siteUrl: _otherSite,
      topicId: 9,
      postNumber: 1,
    );
    fixture.target.value = (siteUrl: _otherSite, post: _otherPost);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fixture.api.requests.last, (
      siteUrl: _site,
      postId: 42,
      revision: null,
      apiKey: 'opening-key',
    ));
    _expectOpeningCategories();
    expect(find.text(_connectionChanged), findsNothing);
  });
}

const _otherPost = Post(
  id: 84,
  postNumber: 1,
  username: 'other-author',
  cooked: '<p>Other post</p>',
  version: 2,
  canViewEditHistory: true,
);

void _expectOpeningCategories() {
  expect(find.text('Opening category'), findsOneWidget);
  expect(find.text('Opening destination'), findsOneWidget);
  expect(find.text('Other category'), findsNothing);
  expect(find.text('Other destination'), findsNothing);
}

Future<_HistoryFixture> _mount(WidgetTester tester) async {
  final fixture = _HistoryFixture();
  addTearDown(fixture.controller.dispose);
  addTearDown(fixture.target.dispose);
  await fixture.controller.load();
  fixture.controller.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
  for (final (site, prefix) in [(_site, 'Opening'), (_otherSite, 'Other')]) {
    fixture.controller.store.put(
      site,
      TopicCategory(id: 2, name: '$prefix category', color: '0088CC'),
    );
    fixture.controller.store.put(
      site,
      TopicCategory(id: 3, name: '$prefix destination', color: '0088CC'),
    );
  }
  await tester.pumpWidget(
    ShellScope(
      controller: fixture.controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 100,
              child: ValueListenableBuilder<_PostTarget?>(
                valueListenable: fixture.target,
                builder: (context, target, child) => target == null
                    ? const SizedBox.shrink()
                    : PostActions(
                        siteUrl: target.siteUrl,
                        post: target.post,
                        child: const Center(child: Text('Post body')),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  fixture.pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await fixture.pointer.addPointer(location: Offset.zero);
  addTearDown(fixture.pointer.removePointer);
  return fixture;
}

class _HistoryFixture {
  final api = _RevisionApi();
  final auth = _CountingAuthenticator()
    ..keys[_site] = 'opening-key'
    ..keys[_otherSite] = 'other-key';
  final target = ValueNotifier<_PostTarget?>((siteUrl: _site, post: _post));
  late final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: _openingUser),
      instance('team.example').copyWith(user: _openingUser),
    ]),
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  late final TestGesture pointer;

  Future<void> open(WidgetTester tester) async {
    await pointer.moveTo(Offset.zero);
    await pointer.moveTo(tester.getCenter(find.text('Post body')));
    await tester.pump();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'View edit history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Edit history'), findsOneWidget);
  }

  Future<void> reconnect(
    WidgetTester tester, {
    bool disconnect = false,
    bool settle = true,
  }) async {
    if (disconnect) await controller.disconnectCurrentInstance();
    await controller.connectCurrentInstance();
    controller.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    expect(controller.currentInstance?.user, _replacementUser);
    expect(auth.keys[_site], 'replacement-key');
    expect(find.text('Edit history'), findsOneWidget);
  }

  Future<void> reopen(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.pumpAndSettle();
  }
}

class _CountingAuthenticator extends FakeAuthenticator {
  _CountingAuthenticator()
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );

  final keyReads = <String>[];
  var clientReads = 0;
  Completer<String?>? nextRead;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    keyReads.add(siteUrl);
    final pending = nextRead;
    if (pending == null) return super.apiKeyFor(siteUrl);
    nextRead = null;
    return pending.future;
  }

  @override
  Future<String> clientId() {
    clientReads++;
    return super.clientId();
  }
}

class _RevisionApi extends FakeDiscourseApi {
  final requests = <_RevisionRequest>[];
  Completer<PostRevision>? nextResult;

  Completer<PostRevision> gateNext() => nextResult = Completer<PostRevision>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == 'replacement-key' ? _replacementUser : _openingUser;

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async => topicPayload(id: id, posts: [id == 7 ? _post : _otherPost]);

  @override
  Future<PostRevision> postRevision({
    required String siteUrl,
    required int postId,
    int? revision,
    String? apiKey,
    String? clientId,
  }) async {
    requests.add((
      siteUrl: siteUrl,
      postId: postId,
      revision: revision,
      apiKey: apiKey,
    ));
    final pending = nextResult;
    nextResult = null;
    if (pending != null) return pending.future;
    return _revision(
      revision ?? 4,
      editor: apiKey == 'replacement-key' ? 'replacement-editor' : 'editor',
    );
  }
}

PostRevision _revision(int number, {String editor = 'editor'}) => PostRevision(
  postId: 42,
  currentRevision: number,
  currentVersion: number,
  versionCount: 4,
  firstRevision: 2,
  previousRevision: number > 2 ? number - 1 : null,
  nextRevision: number < 4 ? number + 1 : null,
  lastRevision: 4,
  username: editor,
  bodyChanges: PostRevisionDiff(inline: '<p>Revision $number</p>'),
  categoryIdChanges: const PostRevisionChange(previous: 2, current: 3),
);
