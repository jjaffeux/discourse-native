import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_mutation_outcome.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _staff = DiscourseUser(id: 9, username: 'moderator', staff: true);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));
  for (final remove in [false, true]) {
    testWidgets(
      'accepted notice ${remove ? 'removal' : 'save'} offers read-only recovery when repair fails',
      (tester) async {
        final api = _NoticeWireApi(raw: 'Original notice');
        await _openEditor(tester, api);
        const draft = '    New confirmed notice\n\nHard break  \n';
        if (!remove) {
          await tester.enterText(
            find.byKey(const ValueKey('post-notice-text')),
            draft,
          );
          await tester.pump();
        }
        await tester.tap(
          find.byKey(ValueKey('post-notice-${remove ? 'delete' : 'save'}')),
        );
        await tester.pumpAndSettle();
        final shell = ShellScope.read(tester.element(primaryMainContent));
        expect(api.requests, hasLength(1));
        expect(api.raw, remove ? isNull : draft);
        expect(
          shell.store.read<Post>(_site, 1)?.notice?.raw,
          'Original notice',
        );
        expect(
          find.byKey(const ValueKey('post-notice-dialog')),
          findsOneWidget,
        );
        expect(
          find.text(
            'The change was saved, but this view could not be refreshed. Refresh to see the latest state.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<DButton>(find.byKey(const ValueKey('post-notice-save')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<DButton>(find.byKey(const ValueKey('post-notice-delete')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<DTextarea>(find.byKey(const ValueKey('post-notice-text')))
              .enabled,
          isFalse,
        );
        await tester.tap(find.byKey(const ValueKey('post-mutation-refresh')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            "Couldn't refresh the view. Refresh again to check its saved state.",
          ),
          findsOneWidget,
        );
        expect(api.requests, hasLength(1));
        api.failReads = false;
        await tester.tap(find.byKey(const ValueKey('post-mutation-refresh')));
        await tester.pumpAndSettle();
        expect(api.requests, hasLength(1));
        expect(
          shell.store.read<Post>(_site, 1)?.notice?.raw,
          remove ? isNull : draft,
        );
        expect(find.byKey(const ValueKey('post-notice-dialog')), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
  for (final notSent in [false, true]) {
    testWidgets(
      '${notSent ? 'not sent' : 'refused'} notice retains its draft and permits a new attempt',
      (tester) async {
        final api = _NoticeWireApi(raw: 'Original notice')
          ..notSent = notSent
          ..refused = !notSent;
        await _openEditor(tester, api);
        await tester.enterText(
          find.byKey(const ValueKey('post-notice-text')),
          'Retry draft',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('post-notice-save')));
        await tester.pumpAndSettle();
        expect(api.raw, 'Original notice');
        expect(api.reads, 0);
        expect(find.byKey(const ValueKey('post-notice-error')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('post-mutation-refresh')),
          findsNothing,
        );
        expect(
          tester
              .widget<DTextarea>(find.byKey(const ValueKey('post-notice-text')))
              .controller!
              .text,
          'Retry draft',
        );
        expect(
          tester
              .widget<DButton>(find.byKey(const ValueKey('post-notice-save')))
              .onPressed,
          isNotNull,
        );
        api
          ..notSent = false
          ..refused = false
          ..failReads = false;
        await tester.tap(find.byKey(const ValueKey('post-notice-save')));
        await tester.pumpAndSettle();
        expect(api.attempts, 2);
        expect(api.raw, 'Retry draft');
        expect(find.byKey(const ValueKey('post-notice-dialog')), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'uncertain notice reconciles by reading and requires fresh write intent',
    (tester) async {
      final api = _NoticeWireApi(raw: 'Original notice')..loseResponse = true;
      await _openEditor(tester, api);
      await tester.enterText(
        find.byKey(const ValueKey('post-notice-text')),
        'Unconfirmed notice',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('post-notice-save')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Couldn't confirm whether the change was saved. Refresh to check before taking another action.",
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('post-notice-save')))
            .onPressed,
        isNull,
      );
      final shell = ShellScope.read(tester.element(primaryMainContent));
      final retry = await shell.setPostNotice(
        shell.capturePostNoticeTarget(siteUrl: _site, topicId: 7, postId: 1),
        'Original notice',
      );
      expect(retry, isA<PostMutationNotSent>());
      expect((retry as PostMutationNotSent).recovery, isNotNull);
      expect(api.attempts, 1);
      api.failReads = false;
      await tester.tap(find.byKey(const ValueKey('post-mutation-refresh')));
      await tester.pumpAndSettle();
      expect(
        shell.store.read<Post>(_site, 1)?.notice?.raw,
        'Unconfirmed notice',
      );
      expect(find.byKey(const ValueKey('post-notice-dialog')), findsOneWidget);
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('post-notice-save')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('post-notice-delete')))
            .onPressed,
        isNull,
      );
      expect(find.widgetWithText(DButton, 'Close'), findsOneWidget);
      expect(api.attempts, 1);
      expect(api.requests, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('notice recovery cannot publish into a retired account', (
    tester,
  ) async {
    final api = _NoticeWireApi(raw: 'Original notice');
    await _openEditor(tester, api);
    await tester.enterText(
      find.byKey(const ValueKey('post-notice-text')),
      'Accepted notice',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('post-notice-save')));
    await tester.pumpAndSettle();
    final shell = ShellScope.read(tester.element(primaryMainContent));
    final pending = Completer<List<Post>>();
    api.nextRead = pending;
    await tester.tap(find.byKey(const ValueKey('post-mutation-refresh')));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(api.nextRead, isNull);
    await shell.disconnectCurrentInstance();
    final replacement = api.post.copyWith(
      notice: const PostNotice(type: 'custom', raw: 'Successor notice'),
    );
    shell.store.put(_site, replacement);
    pending.complete([api.post]);
    await tester.pumpAndSettle();
    expect(shell.store.read<Post>(_site, 1), same(replacement));
    expect(
      find.text(
        'Your connection changed. Reopen the post notice and try again.',
      ),
      findsOneWidget,
    );
    expect(api.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

Future<void> _openEditor(WidgetTester tester, _NoticeWireApi api) async {
  await pumpShell(
    tester,
    defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
    api: api,
    instances: [
      instance('meta.discourse.org', title: 'Meta').copyWith(user: _staff),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'staff-key',
  );
  if (find.byKey(const ValueKey('mobile-mode-topics')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
    await tester.pumpAndSettle();
  }
  await tester.tap(topicListTitle('A real topic'));
  await tester.pumpAndSettle();
  await hoverPost(tester, body: 'Noticeable body');
  await tapPostAction(
    tester,
    api.raw == null
        ? 'Add a staff notice above this post'
        : 'Change or remove the staff notice',
  );
  await tester.pumpAndSettle();
}

class _NoticeWireApi extends FakeDiscourseApi {
  _NoticeWireApi({this.raw})
    : super(
        user: _staff,
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A real topic', slug: 'topic')],
        },
      );

  String? raw;
  bool failReads = true;
  bool refused = false;
  bool notSent = false;
  bool loseResponse = false;
  int attempts = 0;
  int reads = 0;
  Completer<List<Post>>? nextRead;
  final requests = <http.Request>[];
  String get cookedNotice => raw!.startsWith('    ') || raw!.startsWith('\t')
      ? '<pre><code>${const HtmlEscape().convert(raw!.trim())}</code></pre>'
      : '<p>${const HtmlEscape().convert(raw!.trim())}</p>';

  late final wire = DiscourseApi(
    client: MockClient((request) async {
      requests.add(request);
      if (refused) return http.Response('{"errors":["Notice refused"]}', 403);
      raw =
          (jsonDecode(request.body) as Map<String, dynamic>)['notice']
              as String?;
      if (loseResponse) throw http.ClientException('Lost accepted PUT reply');
      return http.Response(
        jsonEncode({
          'success': 'OK',
          'cooked_notice': raw == null ? null : cookedNotice,
        }),
        200,
      );
    }),
  );

  Post get post => Post.fromJson({
    'id': 1,
    'post_number': 1,
    'user_id': 7,
    'username': 'author',
    'cooked': '<p>Noticeable body</p>',
    if (raw != null)
      'notice': {'type': 'custom', 'raw': raw, 'cooked': cookedNotice},
  }, _site);

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async => topicPayload(
    id: id,
    title: 'A real topic',
    posts: [post],
    canEditStaffNotes: true,
  );

  @override
  Future<void> updatePostNotice({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? notice,
    String? clientId,
  }) {
    attempts++;
    if (notSent) {
      throw const WriteException(WriteFailure.unreachable, notSent: true);
    }
    return wire.updatePostNotice(
      siteUrl: siteUrl,
      apiKey: apiKey,
      postId: postId,
      notice: notice,
      clientId: clientId,
    );
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    reads++;
    final pending = nextRead;
    if (pending != null) {
      nextRead = null;
      return pending.future;
    }
    if (failReads) {
      throw StateError('Transient read failure after accepted PUT');
    }
    return [post];
  }
}
