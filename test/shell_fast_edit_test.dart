import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fast edit fetches raw, replaces once, and preserves reader state',
    () async {
      const bookmark = Bookmark(
        id: 9,
        bookmarkableId: 22,
        bookmarkableType: 'Post',
        postNumber: 2,
      );
      final plugins = PluginData.none.withValue(
        reactionsDataKey,
        const Reactions(
          entries: [Reaction(id: 'heart', count: 2)],
          mine: Reaction(id: 'heart', count: 2, canUndo: true),
          userCount: 2,
        ),
      );
      final post = Post(
        id: 22,
        postNumber: 2,
        username: 'author',
        cooked: '<p>Before selected after</p>',
        raw: 'Before selected after',
        canEdit: true,
        likeCount: 4,
        liked: true,
        canUnlike: true,
        postActions: const [
          PostActionSummary(id: 3, count: 1, acted: true, canUndo: true),
        ],
        bookmark: bookmark,
        plugins: plugins,
      );
      final api = FakeDiscourseApi(postsById: {22: post});
      final shell = await _shell(api, post);
      addTearDown(shell.dispose);
      shell.openReply();
      final reply = shell.visibleComposer;
      reply!.text.text = 'Unfinished reply';

      final error = await shell.saveFastEdit(
        siteUrl: _siteUrl,
        topicId: 7,
        post: post,
        selectedMarkdown: 'selected',
        replacement: 'changed',
      );

      expect(error, isNull);
      expect(api.postFetches, [
        [22],
      ]);
      expect(api.postFetchIncludesRaw, [isTrue]);
      expect(api.updated.single['raw'], 'Before changed after');
      expect(api.updated.single['originalText'], 'Before selected after');
      final stored = shell.store.read<Post>(_siteUrl, 22)!;
      expect(stored.raw, 'Before changed after');
      expect(stored.likeCount, 4);
      expect(stored.liked, isTrue);
      expect(stored.canUnlike, isTrue);
      expect(stored.postActions, post.postActions);
      expect(stored.bookmark, bookmark);
      expect(stored.plugins, plugins);
      expect(shell.visibleComposer, same(reply));
      expect(shell.visibleComposer?.raw, 'Unfinished reply');
    },
  );

  test('fast edit rejects missing and ambiguous source text', () async {
    for (final raw in ['Before something else', 'selected then selected']) {
      final post = Post(
        id: 22,
        postNumber: 2,
        username: 'author',
        cooked: '<p>$raw</p>',
        raw: raw,
        canEdit: true,
      );
      final api = FakeDiscourseApi(postsById: {22: post});
      final shell = await _shell(api, post);

      final error = await shell.saveFastEdit(
        siteUrl: _siteUrl,
        topicId: 7,
        post: post,
        selectedMarkdown: 'selected',
        replacement: 'changed',
      );

      expect(error, 'The selected text could not be matched safely.');
      expect(api.updated, isEmpty);
      expect(shell.postWriteInFlight(22), isFalse);
      shell.dispose();
    }
  });

  test('fast edit matches the latest raw case-sensitively', () async {
    const post = Post(
      id: 22,
      postNumber: 2,
      username: 'author',
      cooked: '<p>Selected then selected</p>',
      raw: 'Selected then selected',
      canEdit: true,
    );
    final api = FakeDiscourseApi(postsById: const {22: post});
    final shell = await _shell(api, post);
    addTearDown(shell.dispose);

    final error = await shell.saveFastEdit(
      siteUrl: _siteUrl,
      topicId: 7,
      post: post,
      selectedMarkdown: 'Selected',
      replacement: 'Changed',
    );

    expect(error, isNull);
    expect(api.updated.single['raw'], 'Changed then selected');
  });

  test('fast edit returns write failures and releases its post lock', () async {
    const post = Post(
      id: 22,
      postNumber: 2,
      username: 'author',
      cooked: '<p>selected</p>',
      raw: 'selected',
      canEdit: true,
    );
    final api = FakeDiscourseApi(
      postsById: const {22: post},
      writeFailure: const WriteException(WriteFailure.conflict),
    );
    final shell = await _shell(api, post);
    addTearDown(shell.dispose);

    final error = await shell.saveFastEdit(
      siteUrl: _siteUrl,
      topicId: 7,
      post: post,
      selectedMarkdown: 'selected',
      replacement: 'changed',
    );

    expect(error, 'Someone else changed that first.');
    expect(shell.postWriteInFlight(22), isFalse);
  });

  test('fast edit refuses a concurrent write on the same post', () async {
    const post = Post(
      id: 22,
      postNumber: 2,
      username: 'author',
      cooked: '<p>selected</p>',
      raw: 'selected',
      canEdit: true,
    );
    final gate = Completer<void>();
    final api = FakeDiscourseApi(postsById: const {22: post}, postGate: gate);
    final shell = await _shell(api, post);
    addTearDown(shell.dispose);

    final first = shell.saveFastEdit(
      siteUrl: _siteUrl,
      topicId: 7,
      post: post,
      selectedMarkdown: 'selected',
      replacement: 'first',
    );
    await pumpEventQueue();
    expect(shell.postWriteInFlight(22), isTrue);

    final second = await shell.saveFastEdit(
      siteUrl: _siteUrl,
      topicId: 7,
      post: post,
      selectedMarkdown: 'selected',
      replacement: 'second',
    );
    expect(second, 'Another action on this post is still being saved.');

    gate.complete();
    expect(await first, isNull);
    expect(api.updated.single['raw'], 'first');
    expect(shell.postWriteInFlight(22), isFalse);
  });

  test(
    'fast edit ignores an update response after the route changes',
    () async {
      const post = Post(
        id: 22,
        postNumber: 2,
        username: 'author',
        cooked: '<p>selected</p>',
        raw: 'selected',
        canEdit: true,
      );
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        postsById: const {22: post},
        updatePostGate: gate,
      );
      final shell = await _shell(api, post);
      addTearDown(shell.dispose);

      final saving = shell.saveFastEdit(
        siteUrl: _siteUrl,
        topicId: 7,
        post: post,
        selectedMarkdown: 'selected',
        replacement: 'changed',
      );
      await pumpEventQueue();
      expect(api.updated, hasLength(1));
      shell.replaceCurrentContent(
        ContentRoute.topic(topicId: 8, slug: 'other', title: 'Other'),
      );
      gate.complete();

      expect(await saving, 'The topic changed before the edit could be saved.');
      expect(shell.store.read<Post>(_siteUrl, 22)?.raw, 'selected');
      expect(shell.postWriteInFlight(22, siteUrl: _siteUrl), isFalse);
    },
  );

  test('fallback edit focuses the first matching raw line', () async {
    const raw = 'intro\nline with selected text\nlast';
    const post = Post(
      id: 22,
      postNumber: 2,
      username: 'author',
      cooked: '<p>intro</p><p>line with selected text</p><p>last</p>',
      raw: raw,
      canEdit: true,
    );
    final shell = await _shell(FakeDiscourseApi(), post);
    addTearDown(shell.dispose);

    shell.openEdit(post, focusText: 'selected text');

    expect(shell.visibleComposer?.raw, raw);
    expect(shell.visibleComposer?.text.selection.baseOffset, 6);
  });

  test('fallback edit focuses the body start when no line matches', () async {
    const post = Post(
      id: 22,
      postNumber: 2,
      username: 'author',
      cooked: '<p>body</p>',
      raw: 'body',
      canEdit: true,
    );
    final shell = await _shell(FakeDiscourseApi(), post);
    addTearDown(shell.dispose);

    shell.openEdit(post, focusText: 'missing');

    expect(shell.visibleComposer?.text.selection.baseOffset, 0);
  });
}

Future<ShellController> _shell(FakeDiscourseApi api, Post post) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  shell.store.put(
    _siteUrl,
    const TopicDetail(
      id: 7,
      title: 'Topic',
      stream: [22],
      postsCount: 1,
      canCreatePost: true,
    ),
  );
  shell.store.put(_siteUrl, post);
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  return shell;
}
