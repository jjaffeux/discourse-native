import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart'
    show InstalledPlugins, PluginInstaller, PluginManifest;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
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
  _Authenticator({required this.transition})
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );

  final String transition;

  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    if (transition == 'connect rollback') {
      throw StateError('Keychain refused replacement credential');
    }
    await super.persistCredentials(siteUrl, credentials);
  }
}

final class _InstanceStore extends FakeInstanceStore {
  _InstanceStore() : super([instance('forum.example').copyWith(user: _user)]);

  bool rejectSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    if (rejectSignedOut && instances.any((site) => site.user == null)) {
      throw StateError('Preferences refused signed-out snapshot');
    }
    await super.save(instances);
  }
}

final class _Api extends FakeDiscourseApi {
  _Api(this.writer, InstalledPlugins plugins, {required bool mine})
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
                  {'id': 2, 'can_act': true, 'can_undo': mine, 'acted': mine},
                ],
                'reactions': [
                  {'id': 'heart', 'type': 'emoji', 'count': 1},
                ],
                'reaction_users_count': 1,
                if (mine)
                  'current_user_reaction': {
                    'id': 'heart',
                    'type': 'emoji',
                    'can_undo': true,
                  },
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
  for (final action in ['desktop count', 'add', 'remove', 'summary trigger']) {
    for (final transition in [
      'unchanged',
      'reconnect',
      'connect rollback',
      'disconnect rollback',
    ]) {
      testWidgets('Native rendered reaction $action owns its account after '
          '$transition', (tester) async {
        final desktop = action == 'desktop count';
        tester.view.physicalSize = desktop
            ? const Size(1200, 900)
            : const Size(390, 844);
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
        final auth = _Authenticator(transition: transition)
          ..keys[_site] = 'old-key';
        final instances = _InstanceStore();
        final shell = ShellController(
          instanceStore: instances,
          api: _Api(
            DiscourseApi(client: client),
            plugins,
            mine: action == 'remove',
          ),
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
              theme: AppTheme.light.copyWith(
                platform: desktop
                    ? TargetPlatform.macOS
                    : TargetPlatform.android,
              ),
              builder: (context, child) => DToaster(child: child!),
              home: const Scaffold(
                body: MainContent(layout: ShellLayout.medium),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final control = action == 'summary trigger'
            ? find.byKey(const ValueKey('post-reaction-summary-1'))
            : find.descendant(
                of: find.byKey(
                  ValueKey(
                    desktop
                        ? 'post-reaction-1-heart'
                        : 'post-reaction-button-1',
                  ),
                ),
                matching: find.byType(DToggle),
              );
        final originalControl = tester.element(control);
        if (transition != 'unchanged') {
          if (transition == 'disconnect rollback') {
            instances.rejectSignedOut = true;
            expect(await shell.disconnectInstance(_site), isFalse);
          } else {
            await shell.connectCurrentInstance();
          }
          await shell.loadTopic(7, _topic.slug, force: true);
          expect(
            auth.keys[_site],
            transition == 'reconnect' ? 'replacement-key' : 'old-key',
          );
          expect(
            shell.currentInstance?.user,
            transition == 'reconnect' ? _replacement : _user,
          );
          expect(tester.element(control), same(originalControl));
        }
        await tester.tap(control);
        await tester.pumpAndSettle();
        if (action == 'summary trigger') {
          final sheetButton = find.descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(PostReactionButton),
          );
          if (sheetButton.evaluate().isNotEmpty) {
            await tester.tap(sheetButton);
            await tester.pumpAndSettle();
          }
        }
        if (transition != 'unchanged') {
          expect(sent, isEmpty);
          if (action == 'summary trigger') {
            expect(find.byType(DSheetContent), findsNothing);
          }
          shell.openTopic(_topic);
          await shell.loadTopic(7, _topic.slug, force: true);
          await tester.pumpAndSettle();
          await tester.tap(control);
          await tester.pumpAndSettle();
          if (action == 'summary trigger') {
            await tester.tap(
              find.descendant(
                of: find.byType(DSheetContent),
                matching: find.byType(PostReactionButton),
              ),
            );
            await tester.pumpAndSettle();
          }
        }
        expect(sent.single.method, 'PUT');
        expect(
          sent.single.url.path,
          '/discourse-reactions/posts/1/custom-reactions/heart/toggle.json',
        );
        expect(sent.single.headers['user-api-key'], auth.keys[_site]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
