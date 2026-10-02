import 'dart:async';
import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/assign/assign_services.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  for (final prefix in ['    ', '\t']) {
    final note = '${prefix}puts "hi"\n\nFollow up  \nNext line\n';
    for (final source in [
      'new topic',
      'new post',
      'topic',
      'post',
      'indirect post',
    ]) {
      testWidgets(
        '$source assignment keeps ${prefix == '\t' ? 'tab' : 'space'} Markdown note through Native sheet and HTTP',
        (tester) async {
          final (shell, writes, existing, target) = await _fixture(
            tester,
            source,
            note,
          );
          addTearDown(shell.dispose);
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: AppTheme.light,
                home: Scaffold(
                  body: PluginUiScope.own(
                    assignPluginId,
                    Builder(
                      builder: (context) => DButton(
                        label: const Text('Open assignment'),
                        onPressed: () => unawaited(
                          showAssignmentEditor(
                            context: context,
                            siteUrl: _site,
                            target: target,
                            existing: existing,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('Open assignment'));
            await pumpEventQueue();
          });
          await tester.pumpAndSettle();
          if (existing == null) {
            await tester.tap(find.byKey(const Key('assignment-note-toggle')));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const Key('assignment-note')),
              note,
            );
            await tester.pump();
          }
          final openedNote = tester
              .widget<DTextarea>(find.byKey(const Key('assignment-note')))
              .controller!
              .text;
          // Editing only the assignee must retain an existing note's Markdown.
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.ensureVisible(
            find.byKey(const Key('assignment-assignee-user:alice')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('assignment-assignee-user:alice')),
          );
          await tester.pump();
          await tester.runAsync(() async {
            await tester.tap(find.byKey(const Key('assignment-save')));
            await pumpEventQueue();
          });
          await tester.pumpAndSettle();

          expect(writes, hasLength(1));
          final body = jsonDecode(writes.single.body) as Map<String, dynamic>;
          expect(body['note'], note);
          expect(openedNote, note);
          expect(body['target_id'], target.id);
          expect(body['target_type'], target.type.wireName);
          expect(body['username'], 'alice');
          expect(find.byType(AssignmentEditor), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    test(
      'decoded assignment note still cooks indented code and Markdown hard breaks',
      () async {
        final assignment = Assignments.fromTopicJson({
          'assigned_to_user': {'username': 'sam'},
          'assignment_note': note,
        }, _site)!.direct!;
        final cooker = OfflineCookingService();
        addTearDown(cooker.dispose);
        final cooked = await cooker.cook(
          CookingRequest(
            raw: assignment.note!,
            snapshot: CookingSnapshot(siteId: _site, accountId: 'reader'),
          ),
        );
        expect(cooked.failure, isNull);
        final document = html.parse(cooked.html);
        expect(document.querySelector('pre code')?.text, 'puts "hi"\n');
        expect(document.querySelector('p br'), isNotNull);
      },
    );
  }
}

Future<(ShellController, List<http.Request>, Assignment?, AssignmentTarget)>
_fixture(WidgetTester tester, String source, String note) async {
  final writes = <http.Request>[];
  final assignment = <String, Object?>{
    'assigned_to_user': {'username': 'sam'},
    'assignment_note': note,
    'assignment_status': 'Open',
  };
  final topicJson = <String, Object?>{
    'id': 7,
    'title': 'Topic',
    'can_assign': true,
    'posts_count': 2,
    if (source == 'topic') ...assignment,
    if (source == 'indirect post')
      'indirectly_assigned_to': {
        '12': {
          'assigned_to': {'username': 'sam'},
          'assignment_note': note,
          'post_number': 2,
          'assignment_status': 'Open',
        },
      },
    'post_stream': {
      'stream': [12],
      'posts': [
        {
          'id': 12,
          'post_number': 2,
          'username': 'author',
          'cooked': '<p>Reply</p>',
          'can_assign': true,
          if (source == 'post') ...assignment,
        },
      ],
    },
  };
  final wire = DiscourseApi(
    models: installedPlugins.models,
    client: MockClient((request) async {
      if (request.method == 'PUT') {
        expect(request.url.path, '/assign/assign.json');
        writes.add(request);
        return http.Response('{"success":"OK"}', 200);
      }
      if (request.url.path == '/assign/suggestions.json') {
        return http.Response(
          jsonEncode({
            'suggestions': [
              {'username': 'sam'},
              {'username': 'alice'},
            ],
          }),
          200,
        );
      }
      expect(request.url.path, '/t/7.json');
      return http.Response(jsonEncode(topicJson), 200);
    }),
  );
  addTearDown(wire.close);
  const user = DiscourseUser(username: 'reader');
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: _WireAssignmentApi(wire),
    authenticator: FakeAuthenticator()..keys[_site] = 'synthetic-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await tester.runAsync(() async {
    await shell.load();
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    await shell.loadTopic(7, 'topic');
    await pumpEventQueue();
  });
  final target = source.endsWith('post')
      ? const AssignmentTarget.post(12, topicId: 7)
      : const AssignmentTarget.topic(7);
  final topicAssignments = shell.store
      .read<TopicDetail>(_site, 7)!
      .plugins
      .get(assignmentsDataKey)!;
  final existing = switch (source) {
    'topic' => topicAssignments.direct,
    'post' =>
      shell.store
          .read<Post>(_site, 12)!
          .plugins
          .get(assignmentsDataKey)!
          .direct,
    'indirect post' => topicAssignments.forPost(12),
    _ => null,
  };
  return (shell, writes, existing, target);
}

/// Unrelated bootstrap reads stay local; topic decoding and all Assign requests
/// use production codecs and HTTP encoding.
final class _WireAssignmentApi extends FakeDiscourseApi {
  _WireAssignmentApi(this.wire) : super(feeds: const {'/latest.json': []});
  final DiscourseApi wire;

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
  }) => wire.topic(
    siteUrl: siteUrl,
    slug: slug,
    id: id,
    postNumber: postNumber,
    summary: summary,
    apiKey: apiKey,
    clientId: clientId,
    abortTrigger: abortTrigger,
  );

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => wire.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => wire.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );
}
