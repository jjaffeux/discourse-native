import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reader navigation stays in its selected but unfocused panel', () async {
    SharedPreferences.setMockInitialValues({});
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'reader.example',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      ]),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator()
        ..keys['https://reader.example'] = 'key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      forumTabsEnabled: true,
    );
    addTearDown(shell.dispose);
    await shell.load();
    shell.desktopTopicTabs = true;
    shell.openContentInPanel(
      ContentRoute.topic(topicId: 7, slug: 'first', title: 'First'),
      panel: ForumPanel.main,
    );
    final first = shell.selectedTabIn(ForumPanel.main)!;
    final reader = shell.createTopicReader(
      shell.tabContext(first.id),
      first.currentContent,
    );
    addTearDown(reader.close);
    shell.openContentInPanel(
      ContentRoute.topic(topicId: 8, slug: 'second', title: 'Second'),
      panel: ForumPanel.secondary,
    );
    final second = shell.selectedTabIn(ForumPanel.secondary)!;
    shell.selectTab(second.id);
    expect(reader.isCurrent, isTrue);
    expect(reader.foreground, isTrue);
    reader.navigate(postNumber: 33, query: 'sort=new', replace: true);
    expect(
      shell.selectedTabIn(ForumPanel.secondary)!.currentContent.topicId,
      8,
    );
    expect(shell.selectedTabIn(ForumPanel.main)!.currentContent.postNumber, 33);
  });
}
