import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://team.discourse.org';
const _openingUser = DiscourseUser(id: 1, username: 'reader');
const _replacementUser = DiscourseUser(id: 2, username: 'replacement');
const _config = SiteConfig(minPersonalMessagePostLength: 10);
const _flag = PostFlagType(
  id: 3,
  nameKey: 'off_topic',
  name: 'Off-Topic',
  description: '',
  appliesTo: ['Post', 'Topic'],
);
const _messageFlag = PostFlagType(
  id: 6,
  nameKey: 'notify_moderators',
  name: 'Something Else',
  description: '',
  requireMessage: true,
  appliesTo: ['Post', 'Topic'],
);
const _catalog = SitePostActionCatalog(
  postFlags: [_flag, _messageFlag],
  topicFlags: [_flag, _messageFlag],
);
const _actions = [
  PostActionSummary(id: 3, canAct: true),
  PostActionSummary(id: 6, canAct: true),
];
const _openingMessage = 'The explanation written by the opening account.';
const _replacementMessage = 'A new explanation from the replacement account.';

void main() {
  for (final target in ['post', 'topic']) {
    for (final type in [_flag, _messageFlag]) {
      final action = type.requireMessage ? 'message' : 'flag';

      for (final disconnect in [false, true]) {
        final change = disconnect ? 'disconnect and reconnect' : 'reconnect';
        testWidgets(
          '$target $action rejects the opening account after $change',
          (tester) async {
            final api = _FlagApi();
            final auth = _CountingAuthenticator();
            final shell = await _loadShell(tester, api, auth);
            await _openSheet(tester, target);
            await _prepare(tester, type, _openingMessage);
            final editor = tester.state(find.byType(PostFlagEditor));

            if (disconnect) await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
            shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
            await tester.pumpAndSettle();

            expect(shell.currentInstance?.user, _replacementUser);
            expect(auth.keys[_site], 'replacement-key');
            final post = shell.store.read<Post>(_site, 42)!;
            final topic = shell.currentTopic!;
            expect(topic.id, 7);
            expect(topic.stream, [42]);
            expect(shell.availablePostFlagTypes(_site, post), contains(type));
            expect(shell.availableTopicFlagTypes(_site, topic), contains(type));
            expect(tester.state(find.byType(PostFlagEditor)), same(editor));
            // Finish the reader dwell before measuring the flag submission.
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pumpAndSettle();
            final keyReads = auth.keyReads.length;
            final clientReads = auth.clientReads;

            await _submit(tester);

            expect(api.writes, isEmpty);
            expect(auth.keyReads, hasLength(keyReads));
            expect(auth.clientReads, clientReads);
            expect(shell.store.read<Post>(_site, 42), same(post));
            expect(shell.currentTopic, same(topic));
            expect(
              find.text(
                'Your connection changed. Reopen the flag form and try again.',
              ),
              findsOneWidget,
            );
            expect(find.byType(PostFlagEditor), findsOneWidget);
            if (type.requireMessage) {
              expect(find.text(_openingMessage), findsOneWidget);
            }
            expect(shell.postWriteInFlight(42, siteUrl: _site), isFalse);
            expect(shell.topicFlagWriteInFlight(_site, 7), isFalse);

            await tester.tap(find.byTooltip('Close'));
            await tester.pumpAndSettle();
            expect(find.byType(PostFlagEditor), findsNothing);
            await _openSheet(tester, target);
            await _prepare(tester, type, _replacementMessage);
            await _submit(tester);

            expect(api.writes, [
              (
                target: target,
                siteUrl: _site,
                apiKey: 'replacement-key',
                id: target == 'post' ? 42 : 7,
                typeId: type.id,
                message: type.requireMessage ? _replacementMessage : null,
              ),
            ]);
            expect(find.byType(PostFlagEditor), findsNothing);
          },
        );
      }

      for (final otherSite in [false, true]) {
        final destination = otherSite ? 'another forum' : 'another topic';
        testWidgets(
          '$target $action keeps its opening target after visiting $destination',
          (tester) async {
            final api = _FlagApi();
            final auth = _CountingAuthenticator();
            final shell = await _loadShell(tester, api, auth);
            await _openSheet(tester, target);
            await _prepare(tester, type, _openingMessage);
            final siteUrl = otherSite ? _otherSite : _site;
            final topicId = otherSite ? 7 : 9;
            final postId = otherSite ? 42 : 84;

            shell.openTopicPost(
              siteUrl: siteUrl,
              topicId: topicId,
              postNumber: 1,
            );
            await tester.pumpAndSettle();
            expect(shell.currentInstance?.url, siteUrl);
            expect(shell.currentTopic?.id, topicId);
            final currentTopic = shell.currentTopic;
            final currentPost = shell.store.read<Post>(siteUrl, postId);
            expect(find.byType(PostFlagEditor), findsOneWidget);

            await _submit(tester);

            expect(api.writes, [
              (
                target: target,
                siteUrl: _site,
                apiKey: 'opening-key',
                id: target == 'post' ? 42 : 7,
                typeId: type.id,
                message: type.requireMessage ? _openingMessage : null,
              ),
            ]);
            expect(shell.currentTopic, same(currentTopic));
            expect(shell.store.read<Post>(siteUrl, postId), same(currentPost));
            expect(find.byType(PostFlagEditor), findsNothing);
            if (target == 'post') {
              expect(
                shell.store.read<Post>(_site, 42)!.actedFlagSummaries.single.id,
                type.id,
              );
            } else {
              expect(
                shell.store
                    .read<TopicDetail>(_site, 7)!
                    .topicActions
                    .where((action) => action.acted)
                    .single
                    .id,
                type.id,
              );
            }
          },
        );
      }
    }
  }
}

Future<ShellController> _loadShell(
  WidgetTester tester,
  _FlagApi api,
  _CountingAuthenticator auth,
) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    authenticator: auth
      ..keys[_site] = 'opening-key'
      ..keys[_otherSite] = 'other-key',
    instances: [
      instance(
        'meta.discourse.org',
      ).copyWith(user: _openingUser, config: _config),
      instance(
        'team.discourse.org',
      ).copyWith(user: _openingUser, config: _config),
    ],
  );
  await tester.tap(find.text('Opening topic'));
  await tester.pumpAndSettle();
  return ShellScope.read(tester.element(find.byType(MainContent)));
}

Future<void> _openSheet(WidgetTester tester, String target) async {
  if (target == 'post') {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    try {
      await pointer.moveTo(tester.getCenter(renderedText('Flaggable body')));
      await tester.pumpAndSettle();
      final flag = find.byTooltip('Privately flag this post for attention');
      if (flag.evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('post-more-actions-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Flag'));
      } else {
        await tester.tap(flag);
      }
    } finally {
      await pointer.removePointer();
    }
  } else {
    await tester.tap(find.byTooltip('More topic actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-flag-button')));
  }
  await tester.pumpAndSettle();
  expect(find.byType(PostFlagEditor), findsOneWidget);
}

Future<void> _prepare(
  WidgetTester tester,
  PostFlagType type,
  String message,
) async {
  await tester.tap(find.byKey(ValueKey('post-flag-reason-${type.id}')));
  await tester.pumpAndSettle();
  if (type.requireMessage) {
    await tester.enterText(
      find.byKey(const ValueKey('post-flag-message')),
      message,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _submit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('post-flag-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
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

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    keyReads.add(siteUrl);
    return super.apiKeyFor(siteUrl);
  }

  @override
  Future<String> clientId() {
    clientReads++;
    return super.clientId();
  }
}

Post _post(int id) => Post(
  id: id,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Flaggable body</p>',
  postActions: _actions,
);

class _FlagApi extends FakeDiscourseApi {
  _FlagApi()
    : super(
        feeds: const {
          '/latest.json': [
            Topic(id: 7, title: 'Opening topic', slug: 'opening'),
          ],
        },
        categoryPostActionCatalog: _catalog,
        siteConfigs: const {_site: _config, _otherSite: _config},
      );

  final writes =
      <
        ({
          String target,
          String siteUrl,
          String apiKey,
          int id,
          int typeId,
          String? message,
        })
      >[];

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
  }) async => topicPayload(
    id: id,
    title: id == 7 ? 'Opening topic' : 'Other topic',
    posts: [_post(id == 7 ? 42 : 84)],
    canFlagTopic: true,
    topicActions: _actions,
  );

  @override
  Future<Post> createPostFlag({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    writes.add((
      target: 'post',
      siteUrl: siteUrl,
      apiKey: apiKey,
      id: postId,
      typeId: postActionTypeId,
      message: message,
    ));
    return _post(postId).copyWith(
      postActions: [PostActionSummary(id: postActionTypeId, acted: true)],
    );
  }

  @override
  Future<void> createTopicFlag({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    writes.add((
      target: 'topic',
      siteUrl: siteUrl,
      apiKey: apiKey,
      id: topicId,
      typeId: postActionTypeId,
      message: message,
    ));
  }
}
