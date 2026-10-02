import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _raw = '    puts "hi"\n\nReply body';

Map<String, dynamic> _post({String? raw}) => {
  'id': 2,
  'post_number': 2,
  'username': 'author',
  'cooked': '<pre><code>puts "hi"\n</code></pre><p>Reply body</p>',
  'can_edit': true,
  'raw': ?raw,
};

void main() {
  for (final cachedRaw in [false, true]) {
    testWidgets(
      'the real edit composer preserves ${cachedRaw ? 'cached' : 'fetched'} '
      'include_raw Markdown through its save request',
      (tester) async {
        final sent = <http.Request>[];
        final wire = DiscourseApi(
          client: MockClient((request) async {
            sent.add(request);
            if (request.method == 'GET') {
              expect(request.url.path, '/t/7/posts.json');
              expect(request.url.queryParameters['include_raw'], 'true');
              return http.Response(
                jsonEncode({
                  'post_stream': {
                    'posts': [_post(raw: _raw)],
                  },
                }),
                200,
              );
            }
            expect(request.method, 'PUT');
            expect(request.url.path, '/posts/2.json');
            final body = (jsonDecode(request.body) as Map)['post'] as Map;
            // PostsController rejects an original_text unlike its stored raw.
            if (body['original_text'] != _raw) {
              return http.Response(
                jsonEncode({
                  'errors': ['Conflict'],
                }),
                409,
              );
            }
            return http.Response(
              jsonEncode({'post': _post(raw: body['raw'] as String)}),
              200,
            );
          }),
        );
        addTearDown(wire.close);
        final api = _WireEditApi(wire);
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
          ]),
          api: api,
          authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        shell.pushContent(
          ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
        );
        shell.store.put(
          _site,
          const TopicDetail(id: 7, title: 'Topic', stream: [2], postsCount: 2),
        );
        final post = cachedRaw
            ? (await wire.posts(
                siteUrl: _site,
                topicId: 7,
                ids: [2],
                includeRaw: true,
                apiKey: 'api-key',
              )).single
            : Post.fromJson(_post(), _site);
        shell.store.put(_site, post);
        await tester.runAsync(() async {
          shell.openEdit(post);
          await pumpEventQueue();
        });
        final composer = shell.visibleComposer!;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ShellScope(
              controller: shell,
              child: Scaffold(
                body: ListenableBuilder(
                  listenable: shell,
                  builder: (context, _) {
                    final current = shell.visibleComposer;
                    return current == null
                        ? const SizedBox.shrink()
                        : ComposerPanel(composer: current, height: 500);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(composer.originalRaw, isNotNull);
        final opened = composer.text.text;
        final input = find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.controller == composer.text,
        );
        expect(input, findsOneWidget);
        await tester.enterText(
          input,
          opened.replaceFirst('Reply body', 'Edited reply body'),
        );
        await tester.pumpAndSettle();
        expect(composer.canSubmit, isTrue);
        await tester.tap(find.byKey(const ValueKey('composer-submit')));
        await tester.pumpAndSettle();

        final write = sent.singleWhere((request) => request.method == 'PUT');
        final body = (jsonDecode(write.body) as Map)['post'] as Map;
        expect(body['original_text'], _raw);
        expect(body['raw'], '    puts "hi"\n\nEdited reply body');
        expect(opened, _raw);
        expect(shell.visibleComposer, isNull);
        expect(shell.store.read<Post>(_site, 2)!.raw, body['raw']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'post raw decoding retains Markdown whitespace for offline cooking',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final post = Post.fromJson(_post(raw: _raw), _site);
      final result = await service.cook(
        CookingRequest(
          raw: post.raw!,
          snapshot: CookingSnapshot(siteId: _site, accountId: '7'),
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, contains('<pre><code>'));
      expect(
        html.parse(result.html).querySelector('pre code')!.text,
        'puts "hi"\n',
      );
    },
  );

  test('post raw only defaults missing or non-string source to null', () {
    for (final raw in ['', '  ', '\tcode\r\n', '\n    code\n\n']) {
      expect(Post.fromJson(_post(raw: raw), _site).raw, raw);
    }
    for (final raw in [null, 42, true, <Object>[]]) {
      expect(Post.fromJson({..._post(), 'raw': raw}, _site).raw, isNull);
    }
  });
}

/// Keep unrelated shell reads fake while edit reads/writes use the real codec/API.
class _WireEditApi extends FakeDiscourseApi {
  _WireEditApi(this.wire) : super(feeds: const {'/latest.json': []});
  final DiscourseApi wire;

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) => wire.posts(
    siteUrl: siteUrl,
    topicId: topicId,
    ids: ids,
    includeRaw: includeRaw,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  }) => wire.updatePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    raw: raw,
    originalText: originalText,
    editReason: editReason,
    clientId: clientId,
  );
}
