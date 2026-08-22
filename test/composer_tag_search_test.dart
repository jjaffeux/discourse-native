import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

/// `/tags/filter/search.json` validates the requested page against the site's
/// `max_tag_search_results` and answers 400 — "Limit is invalid" — for anything
/// larger. That setting defaults to 5, so a client picking its own page size
/// makes the tag picker fail on an ordinary site rather than on an unusual one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asks for the page the site says it will accept', () async {
    final api = _api(SiteConfig.fromSettings(const {}));
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    await shell.searchComposerTags(_openReply(shell), 'des');

    expect(api.topicTagSearchLimits, [5]);
  });

  test('never asks for more than it would render', () async {
    // A site may raise the setting to 1000; the parser keeps only the first
    // page either way, so asking for the rest would be dead payload.
    final api = _api(
      SiteConfig.fromSettings(const {'max_tag_search_results': 1000}),
    );
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    await shell.searchComposerTags(_openReply(shell), 'des');

    expect(api.topicTagSearchLimits, [TopicTagSearch.maximumResults]);
  });
}

FakeDiscourseApi _api(SiteConfig config) => FakeDiscourseApi(
  feeds: const {'/latest.json': <Topic>[]},
  siteConfigs: {_site: config},
);

Future<ShellController> _loadShell(FakeDiscourseApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

ComposerController _openReply(ShellController shell) {
  shell.store.put(
    _site,
    const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  shell.openReply();
  return shell.visibleComposer!;
}
