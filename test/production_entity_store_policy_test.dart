import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production shell and Chat stores have explicit scoped policies',
    () async {
      final shell = ShellController(
        instanceStore: FakeInstanceStore(const [_site]),
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);

      final shellPolicy = shell.store.statisticsForTesting.policy;
      expect(shellPolicy, isNotNull);
      expect(shellPolicy!.maxEntriesPerSite, isNotNull);
      expect(shellPolicy.maxEntriesPerSiteAndType, isNotNull);

      final partitionLimit = shellPolicy.maxEntriesPerSiteAndType!;
      for (var id = 0; id <= partitionLimit; id++) {
        shell.store.put(
          _site.url,
          Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
        );
      }
      expect(
        shell.store.statisticsForTesting.entriesFor<Topic>(_site.url),
        partitionLimit,
      );
      expect(shell.store.read<Topic>(_site.url, 0), isNull);
      expect(shell.store.read<Topic>(_site.url, partitionLimit), isNotNull);

      await shell.load();
      final chat = shell.pluginSession.require(chatControllerService);
      final chatPolicy = chat.cachePolicyForTesting;
      expect(chatPolicy, isNotNull);
      expect(chatPolicy!.maxEntriesPerSite, isNotNull);
      expect(chatPolicy.maxEntriesPerSiteAndType, isNotNull);
    },
  );
}

const _site = DiscourseInstance(
  url: 'https://one.example',
  title: 'One',
  user: DiscourseUser(username: 'sam'),
);
