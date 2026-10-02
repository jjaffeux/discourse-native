import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example';
const _user = DiscourseUser(id: 7, username: 'reader');
const _markdown = '    code\n\nParagraph hard break  \nnext line  \n';

final class _RequestApi extends FakeDiscourseApi {
  _RequestApi(this.writer, String template)
    : super(
        user: _user,
        feeds: const {'/latest.json': <Topic>[]},
        pluginResponses: {
          'GET /groups/support.json': {
            'group': {
              'id': 4,
              'name': 'support',
              'full_name': 'Support',
              'allow_membership_requests': true,
              'membership_request_template': template,
            },
          },
        },
      );

  final DiscourseApi writer;

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => writer.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );
}

void main() {
  for (final entry in ['typed Markdown', 'prefilled Markdown', 'plain text']) {
    testWidgets('Native membership request preserves $entry through HTTP', (
      tester,
    ) async {
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response(jsonEncode({'success': 'OK'}), 200);
      });
      addTearDown(client.close);
      final template = entry == 'prefilled Markdown' ? _markdown : '';
      final raw = entry == 'plain text' ? 'I can help.' : _markdown;
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('forum.example').copyWith(user: _user),
        ]),
        api: _RequestApi(DiscourseApi(client: client), template),
        authenticator: FakeAuthenticator()..keys[_site] = 'secret',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.group(GroupRoute.detail('support')));
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
            builder: (context, child) => DToaster(child: child!),
            home: const Scaffold(body: MainContent(layout: ShellLayout.medium)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-request')));
      await tester.pumpAndSettle();
      final reason = find.descendant(
        of: find.byType(DTextarea),
        matching: find.byType(EditableText),
      );
      if (entry == 'prefilled Markdown') {
        expect(tester.widget<EditableText>(reason).controller.text, raw);
      } else {
        await tester.enterText(reason, '  \n\t ');
        await tester.pump();
        expect(
          tester
              .widget<DButton>(find.byKey(const ValueKey('send-group-request')))
              .onPressed,
          isNull,
        );
        expect(sent, isEmpty);
        await tester.enterText(reason, raw);
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('send-group-request')));
      await tester.pumpAndSettle();

      final write = sent.single;
      expect(write.method, 'POST');
      expect(write.url.path, '/groups/support/request_membership.json');
      expect(write.headers['user-api-key'], 'secret');
      final body = jsonDecode(write.body) as Map<String, dynamic>;
      expect(body['reason'], raw);
      expect(find.byKey(const ValueKey('group-request-dialog')), findsNothing);
      if (entry != 'plain text') {
        await tester.runAsync(() async {
          final service = OfflineCookingService();
          try {
            final cooked = await service.cook(
              CookingRequest(
                raw: body['reason']! as String,
                snapshot: CookingSnapshot(siteId: _site, accountId: '7'),
              ),
            );
            expect(cooked.failure, isNull);
            expect(cooked.html, contains('<pre><code>code\n</code></pre>'));
            expect(cooked.html, contains('Paragraph hard break<br>'));
          } finally {
            await service.dispose();
          }
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
}
