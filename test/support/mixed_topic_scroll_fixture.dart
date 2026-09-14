import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';

import 'fakes.dart';

/// Ordinary rich replies, including the quotes and code absent from the
/// original long-paragraph benchmark. Pages arrive while the reader scrolls.
Future<ShellController> mixedTopicScrollController({
  FakeDiscourseApi? api,
  int firstLoaded = 1,
  int? initialPostNumber,
}) async {
  final posts = [
    for (var id = 1; id <= 114; id++)
      Post(
        id: id,
        postNumber: id,
        username: 'reader',
        createdAt: DateTime.utc(2026, 8, 1 + id ~/ 8),
        cooked: [
          '<p>Post $id: scrolling through an ordinary rich discussion.</p>',
          if (id % 3 == 0)
            '<blockquote><p>A previous reply with <strong>formatted text</strong> '
                'and a question about the implementation.</p></blockquote>',
          for (var paragraph = 0; paragraph < 2 + id % 5; paragraph++)
            '<p>The worker handles <code>input</code> and returns a result. '
                'This paragraph includes <strong>important details</strong>, '
                '<em>emphasis</em>, and an <a href="https://example.com/">'
                'ordinary link</a>. Moving through these replies should keep '
                'the reader at the same position without rebuilding content.</p>',
          if (id % 4 == 0)
            '<pre><code class="lang-ruby">def process(input)\n'
                '  result = worker.call(input)\n  result\nend\n</code></pre>',
          if (id % 5 == 0)
            '<ul><li>Measure the first render.</li><li>Scroll back through '
                'the same replies.</li><li>Preserve selection and edits.</li></ul>',
        ].join(),
      ),
  ];
  final resolvedApi = api ?? FakeDiscourseApi(topics: {}, postsById: {});
  resolvedApi.topics[7] = topicPayload(
    id: 7,
    title: 'Ordinary rich topic scrolling',
    posts: posts.skip(firstLoaded - 1).take(20).toList(),
    stream: posts.map((post) => post.id).toList(),
    postsCount: posts.length,
  );
  resolvedApi.postsById.addAll({for (final post in posts) post.id: post});
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('scroll.example')]),
    api: resolvedApi,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(
      topicId: 7,
      slug: 'ordinary-rich-topic',
      title: 'Ordinary rich topic scrolling',
      postNumber: initialPostNumber,
    ),
  );
  await controller.loadTopic(
    7,
    'ordinary-rich-topic',
    postNumber: initialPostNumber,
  );
  return controller;
}
