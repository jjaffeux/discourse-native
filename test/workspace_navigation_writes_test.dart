import 'dart:convert';

import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

final class _CountingTabs implements ForumTabPersistence {
  String? value;
  int writes = 0;
  int bytes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    writes++;
    bytes += utf8.encode(value).length;
    this.value = value;
    return true;
  }
}

void main() {
  test('a phone writes its workspace once per navigation', () async {
    final persistence = _CountingTabs();
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: ForumTabStore(persistence: persistence),
      mobileNavigationEnabled: true,
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpEventQueue();

    final writesBefore = persistence.writes;
    final bytesBefore = persistence.bytes;
    for (var topic = 1; topic <= 5; topic++) {
      shell.pushContent(
        ContentRoute.topic(topicId: topic, slug: 't$topic', title: 'T$topic'),
      );
      await pumpEventQueue();
      shell.handleBack();
      await pumpEventQueue();
    }
    final writes = persistence.writes - writesBefore;
    final bytes = persistence.bytes - bytesBefore;

    debugPrint('PERF_PROOF workspace-navigation writes_10_navigations=$writes');
    debugPrint('PERF_PROOF workspace-navigation bytes_10_navigations=$bytes');
    expect(writes, 10);

    final last = ContentRoute.topic(topicId: 6, slug: 't6', title: 'T6');
    shell.pushContent(last);
    await pumpEventQueue();
    final saved = await ForumTabStore(persistence: persistence).load();
    final workspace = saved.workspaces.single;
    expect(workspace.activeTab.currentContent.id, last.id);
    expect(workspace.mobile, shell.mobileNavigation.state);
  });
}
