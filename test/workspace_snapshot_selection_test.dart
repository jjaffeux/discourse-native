import 'dart:async';

import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup keeps selection from its loaded workspace document', () async {
    SharedPreferences.setMockInitialValues({});
    final sites = [instance('one.example'), instance('two.example')];
    final persistence = MemoryForumTabPersistence();
    final tabs = ForumTabStore(persistence: persistence);
    await tabs.save([], selectedSiteUrl: sites.first.url);
    final instances = _DelayedInstances(sites);
    final shell = ShellController(
      instanceStore: instances,
      forumTabs: tabs,
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      forumTabsEnabled: true,
    );
    addTearDown(shell.dispose);
    final startup = shell.load();
    await pumpEventQueue();
    // Another writer changes storage after this startup read has completed,
    // while the shell is still waiting for its independent instance read.
    await tabs.save([], selectedSiteUrl: sites.last.url);
    instances.ready.complete();
    await startup;
    expect(shell.currentInstance?.url, sites.first.url);
  });
}

final class _DelayedInstances extends FakeInstanceStore {
  _DelayedInstances(super.instances);

  final ready = Completer<void>();

  @override
  Future<List<DiscourseInstance>> load() async {
    await ready.future;
    return super.load();
  }
}
