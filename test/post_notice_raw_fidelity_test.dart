import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _staff = DiscourseUser(id: 9, username: 'moderator', staff: true);

void main() {
  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? 'editing' : 'adding'} a staff notice preserves raw Markdown through the real PUT',
      (tester) async {
        final api = _NoticeWireApi(
          raw: editing ? '    original code\n\n' : null,
        );
        await _openEditor(tester, api);
        final field = find.byKey(const ValueKey('post-notice-text'));
        final input = tester.widget<DTextarea>(field);
        expect(input.controller!.text, api.raw ?? '');
        const draft = '    updated code\n\nParagraph with a hard break  \n';
        await tester.enterText(field, draft);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('post-notice-save')));
        await tester.pumpAndSettle();

        expect(api.requests.single.method, 'PUT');
        expect(api.requests.single.url.path, '/posts/1/notice.json');
        expect(jsonDecode(api.requests.single.body), {'notice': draft});
        final shell = ShellScope.read(tester.element(primaryMainContent));
        final saved = shell.store.read<Post>(_site, 1)?.notice;
        expect(saved?.raw, draft);
        expect(saved?.cooked, contains('<pre><code>'));
        expect(find.byKey(const ValueKey('post-notice-dialog')), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: _platforms,
    );
  }

  testWidgets(
    'adding Markdown indentation is an editable change to a staff notice',
    (tester) async {
      final api = _NoticeWireApi(raw: 'staff code');
      await _openEditor(tester, api);
      const draft = '    staff code';
      await tester.enterText(
        find.byKey(const ValueKey('post-notice-text')),
        draft,
      );
      await tester.pump();
      final save = find.byKey(const ValueKey('post-notice-save'));
      expect(tester.widget<DButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(jsonDecode(api.requests.single.body), {'notice': draft});
      final shell = ShellScope.read(tester.element(primaryMainContent));
      expect(
        shell.store.read<Post>(_site, 1)?.notice?.cooked,
        '<pre><code>staff code</code></pre>',
      );
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );

  testWidgets('unchanged raw Markdown and blank drafts keep Save disabled', (
    tester,
  ) async {
    final api = _NoticeWireApi(raw: '\tstaff code\n');
    await _openEditor(tester, api);
    final field = find.byKey(const ValueKey('post-notice-text'));
    final save = find.byKey(const ValueKey('post-notice-save'));
    expect(tester.widget<DTextarea>(field).controller!.text, api.raw);
    expect(tester.widget<DButton>(save).onPressed, isNull);
    await tester.enterText(field, ' \t\n ');
    await tester.pump();
    expect(tester.widget<DButton>(save).onPressed, isNull);
    await tester.tap(find.widgetWithText(DButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
    expect(find.byKey(const ValueKey('post-notice-dialog')), findsNothing);
  }, variant: _platforms);
}

const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
  TargetPlatform.macOS,
});

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
  final requests = <http.Request>[];
  // The fixture follows the server's raw -> PrettyText.cook contract for these
  // indented-code examples. Request bytes and model decoding use the real SDK.
  String get cookedNotice => raw!.startsWith('    ') || raw!.startsWith('\t')
      ? '<pre><code>${const HtmlEscape().convert(raw!.trim())}</code></pre>'
      : '<p>${const HtmlEscape().convert(raw!.trim())}</p>';

  late final wire = DiscourseApi(
    client: MockClient((request) async {
      requests.add(request);
      raw =
          (jsonDecode(request.body) as Map<String, dynamic>)['notice']
              as String?;
      return http.Response('{"success":"OK"}', 200);
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
  }) => wire.updatePostNotice(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    notice: notice,
    clientId: clientId,
  );

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async => [post];
}
