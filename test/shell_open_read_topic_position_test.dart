import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(id: 1, username: 'reader');

const _docsId = 7;
const _chatterId = 8;

Topic _topic({
  required int id,
  required int categoryId,
  required int lastRead,
  int highest = 5,
}) => Topic(
  id: id,
  title: 'Topic $id',
  slug: 'topic-$id',
  categoryId: categoryId,
  highestPostNumber: highest,
  lastReadPostNumber: lastRead,
);

Future<ShellController> _shell() async {
  SharedPreferences.setMockInitialValues({});
  final categories = [
    TopicCategory.fromJson(const {
      'id': _docsId,
      'name': 'Docs',
      'color': '0088CC',
      'slug': 'docs',
      'navigate_to_first_post_after_read': true,
    }),
    TopicCategory.fromJson(const {
      'id': _chatterId,
      'name': 'Chatter',
      'color': '0088CC',
      'slug': 'chatter',
      'navigate_to_first_post_after_read': false,
    }),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _reader),
    ]),
    api: FakeDiscourseApi(
      user: _reader,
      feeds: const {'/latest.json': []},
      feedCategoriesByPath: {'/latest.json': categories},
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.loadFeed('latest');
  return shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fully read topic in a first-post category opens at post 1', () async {
    final shell = await _shell();

    shell.openTopicFromList(_topic(id: 1, categoryId: _docsId, lastRead: 5));

    expect(shell.currentContent?.postNumber, 1);
  });

  test(
    'a fully read topic in an ordinary category opens at its last post',
    () async {
      final shell = await _shell();

      shell.openTopicFromList(
        _topic(id: 2, categoryId: _chatterId, lastRead: 5),
      );

      expect(shell.currentContent?.postNumber, 5);
    },
  );

  test(
    'a partly read topic in a first-post category resumes at its first unread post',
    () async {
      final shell = await _shell();

      shell.openTopicFromList(_topic(id: 3, categoryId: _docsId, lastRead: 2));

      expect(shell.currentContent?.postNumber, 3);
    },
  );
}
