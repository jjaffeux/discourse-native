import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart'
    show InstalledPlugins, PluginInstaller, PluginManifest;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_module.dart';
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
  _Api(this.writer, InstalledPlugins plugins)
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
                'topic_id': 7,
                'post_number': 1,
                'username': 'author',
                'cooked': '<p>First post body</p>',
                'actions_summary': [
                  {'id': 2, 'can_act': true},
                ],
                'reactions': [
                  {'id': 'heart', 'type': 'emoji', 'count': 1},
                ],
                'reaction_users_count': 1,
              }, _site),
            ],
            stream: const [1],
            postsCount: 1,
          ),
        },
        siteConfigs: {
          _site: plugins.models.siteConfig(const {
            'discourse_reactions_enabled': true,
            'discourse_reactions_reaction_for_like': 'heart',
            'discourse_reactions_enabled_reactions': '+1|clap',
          }, _site),
        },
        reactorsById: const {
          '1': PostReactors(
            postId: 1,
            total: 1,
            reactors: [PostReactor(id: 3, username: 'sam', reaction: 'heart')],
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
  for (final (transition, framed) in [
    ('unchanged', false),
    ('reconnect', true),
    ('rollback', true),
    ('reconnect', false),
    ('rollback', false),
  ]) {
    testWidgets('Native reaction summary owns its opening account after '
        '$transition ${framed ? 'with a frame' : 'before a frame'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final plugins = PluginInstaller.install(
        const PluginManifest([ReactionsModule()]),
      );
      addTearDown(plugins.close);
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response(jsonEncode({}), 200);
      });
      addTearDown(client.close);
      final auth = _Authenticator(rollback: transition == 'rollback')
        ..keys[_site] = 'old-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('forum.example').copyWith(user: _user),
        ]),
        api: _Api(DiscourseApi(client: client), plugins),
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
            home: const Scaffold(body: MainContent(layout: ShellLayout.medium)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-reaction-summary-1')));
      await tester.pumpAndSettle();
      final summary = tester.element(find.byType(DSheetContent));
      if (transition != 'unchanged') {
        await shell.connectCurrentInstance();
        await shell.loadTopic(7, _topic.slug, force: true);
        if (framed) await tester.pumpAndSettle();
        expect(
          auth.keys[_site],
          transition == 'rollback' ? 'old-key' : 'replacement-key',
        );
        expect(
          shell.currentInstance?.user,
          transition == 'rollback' ? _user : _replacement,
        );
        expect(summary.mounted, !framed);
      }
      if (!framed) {
        await tester.tap(
          find.descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(PostReactionButton),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (transition == 'unchanged') {
        expect(sent.single.method, 'PUT');
        expect(
          sent.single.url.path,
          '/discourse-reactions/posts/1/custom-reactions/heart/toggle.json',
        );
        expect(sent.single.headers['user-api-key'], 'old-key');
      } else {
        expect(sent, isEmpty);
        expect(find.byType(DSheetContent), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
