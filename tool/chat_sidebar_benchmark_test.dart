// flutter test --no-pub tool/chat_sidebar_benchmark_test.dart
// Synchronous debug-mode diagnostic, not a native frame-rate benchmark.
import 'dart:convert';

import 'package:discourse_native/src/models/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';
import '../test/support/shell_test_harness.dart';

void main() {
  testWidgets('measure complete chat sidebar section generation', (
    tester,
  ) async {
    // This widget test lives under tool/ so timing runs remain opt-in.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(const {});
    const site = 'https://meta.discourse.org';
    final now = DateTime.utc(2026, 9, 22);
    final user = DiscourseUser(
      id: 7,
      username: 'reader',
      plugins: PluginData.none.withValue(
        chatCurrentUserDataKey,
        ChatCurrentUser(
          canChat: true,
          canDirectMessage: true,
          hasChatEnabled: true,
          channelListPreferences: ChatChannelListPreferences.read({
            for (final section in ChatChannelListSection.values) ...{
              section.filterField: 'all',
              section.sortField: 'priority',
            },
          }),
        ),
      ),
    );
    ChatChannel channel(int id, {bool direct = false}) => ChatChannel(
      id: id,
      title: 'Channel $id',
      slug: 'channel-$id',
      kind: direct ? ChatChannelKind.directMessage : ChatChannelKind.category,
      membership: ChatMembership(
        following: true,
        starred: id % 4 == 0,
        lastViewedAt: now,
      ),
      threadingEnabled: true,
      unreadThreadOverview: {for (var i = 0; i < 32; i++) i: now},
      lastMessageId: id,
      lastMessageAt: now.subtract(Duration(minutes: (id * 17) % 175)),
    );
    final api = FakeDiscourseApi(
      user: user,
      totals: chatNotificationTotals(),
      chatChannelsBySite: {
        site: ChatChannels(
          public: [for (var i = 1; i <= 100; i++) channel(i)],
          direct: [for (var i = 101; i <= 175; i++) channel(i, direct: true)],
        ),
      },
    );
    await pumpShell(
      tester,
      desktop,
      api: api,
      instances: [
        instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
      ],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
    );
    final context = tester.element(
      find.byType(InstanceSidebar, skipOffstage: false).first,
    );
    final shell = ShellScope.read(context);
    await shell.pluginSession.require(chatControllerService).loadChannels(site);
    await tester.pumpAndSettle();
    final registry = PluginScope.of(context).registry;
    var destinations = 0;
    void generate() {
      destinations = registry
          .sidebarSections(
            context,
            includeOwner: (owner) => owner.value == 'chat',
          )
          .fold(0, (count, section) => count + section.destinations.length);
    }

    for (var i = 0; i < 100; i++) {
      generate();
    }
    final samples = <double>[];
    for (var batch = 0; batch < 50; batch++) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        generate();
      }
      samples.add(watch.elapsedMicroseconds / 20);
    }
    samples.sort();
    expect(destinations, greaterThan(100));
    // ignore: avoid_print
    print(
      'CHAT_SIDEBAR_BENCHMARK ${jsonEncode({'mode': 'debug', 'channels': 175, 'threadsPerChannel': 32, 'destinations': destinations, 'medianUs': samples[25], 'p95Us': samples[47]})}',
    );
  });
}
