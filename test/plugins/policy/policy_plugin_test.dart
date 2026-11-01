import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/policy/policy_card.dart';
import 'package:discourse_native/src/plugins/policy/policy_composer.dart';
import 'package:discourse_native/src/plugins/policy/policy_data.dart';
import 'package:discourse_native/src/plugins/policy/policy_groups.dart';
import 'package:discourse_native/src/plugins/policy/policy_module.dart';
import 'package:discourse_native/src/plugins/policy/policy_plugin.dart';
import 'package:discourse_native/src/plugins/policy/policy_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const _site = 'https://forum.example';

void main() {
  test('Policy installs alone and core ignores its optional schemas', () async {
    final plugins = PluginInstaller.install(
      const PluginManifest([policyModule]),
    );
    addTearDown(plugins.close);
    final wire = {
      'id': 7,
      'post_number': 1,
      'username': 'author',
      'policy_can_accept': true,
      'policy_can_revoke': false,
      'policy_accepted': false,
      'policy_revoked': false,
    };
    expect(plugins.models.post(wire, _site).plugins.policy!.canAccept, isTrue);
    expect(
      const DiscourseModelCodec.core().post(wire, _site).plugins.policy,
      isNull,
    );
    expect(plugins.descriptors.single.dependencies, isEmpty);
  });

  test(
    'real host installs Policy services without requests when disabled',
    () async {
      final transport = RecordingPluginTransport();
      final host = await PluginHostHarness.open(
        transport: transport,
        manifest: const PluginManifest([policyModule]),
        sites: const [PluginHostSite(url: _site)],
      );
      addTearDown(host.close);
      expect(host.require(policyControllerService).canCreate(_site), isFalse);
      expect(host.require(policyGroupsService), isA<PolicyGroups>());
      expect(transport.reads, isEmpty);
      expect(transport.writes, isEmpty);
    },
  );

  test('Policy live updates select only valid post refreshes', () {
    const plugin = PolicyPlugin();
    expect(plugin.topicChannels(9), ['/topic/9']);
    expect(plugin.stalePosts('/topic/9', {'id': 7, 'type': 'policy_change'}), [
      7,
    ]);
    for (final message in [
      {'id': 7, 'type': 'edited'},
      {'id': 0, 'type': 'policy_change'},
      {'id': 'bad', 'type': 'policy_change'},
    ]) {
      expect(plugin.stalePosts('/topic/9', message), isEmpty);
    }
    expect(
      plugin.stalePosts('/unrelated', {'id': 7, 'type': 'policy_change'}),
      isEmpty,
    );
  });

  testWidgets(
    'only first unquoted Policy receives post authority across sibling roots',
    (tester) async {
      final fragment = html.parseFragment('''
      <aside class="quote"><div class="policy">Quoted</div></aside>
      <blockquote><div class="policy">Also quoted</div></blockquote>
      <div class="policy">Authoritative</div>
      <div class="policy">Additional</div>
    ''');
      final elements = fragment.querySelectorAll('.policy');
      final results = <Widget>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              for (final element in elements) {
                results.add(
                  const PolicyPlugin().postBodyElement(
                    PluginPostBodyContext(
                      buildContext: context,
                      siteUrl: _site,
                      post: const Post(
                        id: 7,
                        postNumber: 1,
                        username: 'author',
                        cooked: '',
                      ),
                    ),
                    element,
                  )!,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(results[0], isA<PolicyCard>());
      expect(results[1], isA<PolicyCard>());
      expect(results[2], isNot(isA<PolicyCard>()));
      expect(results[3], isA<PolicyCard>());
    },
  );

  test(
    'group lookup uses credentials and discards retired responses',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final transport = RecordingPluginTransport(
        responders: {'GET /groups/search.json': (_) => gate.future},
      );
      final requests = PluginTestRequestHost(apiKeys: {_site: 'key'});
      final groups = PolicyGroups(transport, requests);
      final pending = groups.load(_site);
      await Future<void>.delayed(Duration.zero);
      requests.forget(_site);
      gate.complete({
        'groups': [
          {'id': 41, 'name': 'crew', 'automatic': false},
        ],
      });
      expect(await pending, isEmpty);
      expect(transport.reads.single.path, '/groups/search.json');
      expect(transport.reads.single.apiKey, 'key');
    },
  );
}
