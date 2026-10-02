import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/plugins/poll/poll_module.dart';
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
const _replacement = DiscourseUser(id: 8, username: 'replacement');
const _topic = Topic(id: 7, title: 'A real topic', slug: 'a-real-topic');

Map<String, dynamic> _pollWire({required bool multiple}) => {
  'id': 1,
  'name': 'poll',
  'type': multiple ? 'multiple' : 'regular',
  'status': 'open',
  'results': 'always',
  'chart_type': 'bar',
  'min': 1,
  'max': 2,
  'voters': 0,
  'options': [
    {'id': 'a', 'html': 'Alpha', 'votes': 0},
    {'id': 'b', 'html': 'Beta', 'votes': 0},
  ],
};

final class _Authenticator extends FakeAuthenticator {
  _Authenticator({required this.rollback})
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );
  final bool rollback;

  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    if (rollback) throw StateError('Keychain refused replacement credential');
    await super.persistCredentials(siteUrl, credentials);
  }
}

final class _Api extends FakeDiscourseApi {
  _Api(this.writer, InstalledPlugins plugins, String action)
    : super(
        user: _user,
        feeds: const {
          '/latest.json': [_topic],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: _topic.title,
            posts: [
              plugins.models.post({
                'id': 1,
                'post_number': 1,
                'username': 'author',
                'cooked': '<div class="poll" data-poll-name="poll"></div>',
                'polls': [_pollWire(multiple: action.endsWith('draft'))],
                if (action == 'remove')
                  'polls_votes': {
                    'poll': ['a'],
                  },
              }, _site),
            ],
          ),
        },
      ) {
    accounts['replacement-key'] = _replacement;
  }
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
  for (final action in ['vote', 'remove', 'draft', 'framed draft']) {
    for (final transition in ['unchanged', 'reconnect', 'rollback']) {
      final multiple = action.endsWith('draft');
      final framed = action == 'framed draft';
      if (framed && transition == 'unchanged') continue;
      testWidgets('Native poll $action belongs to its displayed account after '
          '$transition', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final plugins = PluginInstaller.install(
          const PluginManifest([pollModule]),
        );
        addTearDown(plugins.close);
        final sent = <http.Request>[];
        final client = MockClient((request) async {
          sent.add(request);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'poll': _pollWire(multiple: multiple),
              if (request.method != 'DELETE') 'vote': body['options'],
            }),
            200,
          );
        });
        addTearDown(client.close);
        final auth = _Authenticator(rollback: transition == 'rollback')
          ..keys[_site] = 'old-key';
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('forum.example').copyWith(user: _user),
          ]),
          api: _Api(DiscourseApi(client: client), plugins, action),
          authenticator: auth,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          plugins: plugins,
        );
        addTearDown(shell.dispose);
        await shell.load();
        shell.openTopic(_topic);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
              builder: (context, child) => DToaster(child: child!),
              home: const Scaffold(
                body: MainContent(layout: ShellLayout.medium),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byType(PollCard);
        expect(card, findsOneWidget);
        final originalState = tester.state(card);
        final option = find.byKey(const ValueKey('poll-poll-option-a'));
        final cast = find.byKey(const ValueKey('poll-poll-cast'));
        if (multiple) {
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(tester.widget<DButton>(cast).onPressed, isNotNull);
          expect(sent, isEmpty);
        }
        if (transition != 'unchanged') {
          await shell.connectCurrentInstance();
          await shell.loadTopic(7, _topic.slug, force: true);
          expect(
            auth.keys[_site],
            transition == 'rollback' ? 'old-key' : 'replacement-key',
          );
          expect(
            shell.currentInstance?.user,
            transition == 'rollback' ? _user : _replacement,
          );
          if (framed) {
            await tester.pumpAndSettle();
            expect(originalState.mounted, isFalse);
          } else {
            expect(tester.state(card), same(originalState));
          }
        }
        if (!framed) {
          await tester.tap(multiple ? cast : option);
          await tester.pumpAndSettle();
        }
        if (transition == 'unchanged') {
          expect(sent.single.method, action == 'remove' ? 'DELETE' : 'PUT');
          expect(sent.single.url.path, '/polls/vote.json');
          expect(sent.single.headers['user-api-key'], 'old-key');
          expect(jsonDecode(sent.single.body), {
            'post_id': 1,
            'poll_name': 'poll',
            if (action != 'remove') 'options': ['a'],
          });
        } else {
          expect(sent, isEmpty);
          shell.openTopic(_topic);
          await shell.loadTopic(7, _topic.slug, force: true);
          await tester.pumpAndSettle();
          expect(tester.state(card), isNot(same(originalState)));
          if (multiple) {
            final checkbox = find.descendant(
              of: option,
              matching: find.byType(DCheckbox),
            );
            expect(tester.widget<DCheckbox>(checkbox).value, isFalse);
            expect(tester.widget<DButton>(cast).onPressed, isNull);
            await tester.tap(find.byKey(const ValueKey('poll-poll-option-b')));
            await tester.pumpAndSettle();
            await tester.tap(cast);
          } else {
            await tester.tap(option);
          }
          await tester.pumpAndSettle();
          expect(sent.single.method, action == 'remove' ? 'DELETE' : 'PUT');
          expect(sent.single.url.path, '/polls/vote.json');
          expect(sent.single.headers['user-api-key'], auth.keys[_site]);
          expect(jsonDecode(sent.single.body), {
            'post_id': 1,
            'poll_name': 'poll',
            if (action != 'remove') 'options': [multiple ? 'b' : 'a'],
          });
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
