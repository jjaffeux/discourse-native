import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _firstSite = 'https://one.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;

  setUp(() async {
    shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('one.example', title: 'One'),
        instance('two.example', title: 'Two'),
      ]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()..keys[_firstSite] = 'api-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.loadFeed('latest');
    await shell.openNewTopic();
  });

  test('keeps the same composer visible while its tab changes route', () {
    final composer = shell.visibleComposer!;
    composer.text.text = 'An unfinished topic';

    shell.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'first-topic', title: 'First topic'),
    );

    expect(shell.visibleComposer, same(composer));
    expect(shell.visibleComposer?.raw, 'An unfinished topic');

    shell.handleBack();

    expect(shell.visibleComposer, same(composer));
  });

  test('hides the composer in another tab and restores it on return', () {
    final sourceTabId = shell.activeTabId!;
    final composer = shell.visibleComposer!;

    shell.createTab();

    expect(shell.visibleComposer, isNull);

    shell.selectTab(sourceTabId);

    expect(shell.visibleComposer, same(composer));
  });

  test('hides the composer in another forum and restores it on return', () {
    final composer = shell.visibleComposer!;

    shell.selectInstance(1);

    expect(shell.visibleComposer, isNull);

    shell.selectInstance(0);

    expect(shell.visibleComposer, same(composer));
  });

  test('hides the composer in Aggregate and restores it on return', () {
    final composer = shell.visibleComposer!;

    shell.selectAggregate();

    expect(shell.visibleComposer, isNull);

    shell.selectInstance(0);

    expect(shell.visibleComposer, same(composer));
  });

  test('preserves the composer while Settings is open and restores it', () {
    final composer = shell.visibleComposer!;
    composer.text.text = 'Keep this app settings draft';

    shell.selectSettings();

    expect(shell.rootMode, ShellRootMode.settings);
    expect(shell.visibleComposer, isNull);
    expect(shell.handleBack(), isTrue);
    expect(shell.rootMode, ShellRootMode.forum);
    expect(shell.visibleComposer, same(composer));
    expect(shell.visibleComposer?.raw, 'Keep this app settings draft');
  });
}
