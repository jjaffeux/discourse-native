import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mobile_shell_test.dart' show pumpMobileShellFixture;
import 'fakes.dart';

Future<ShellController> pumpTopicSheetScrollFixture(WidgetTester tester) async {
  final shell = await pumpMobileShellFixture(
    tester,
    topics: [
      for (var id = 1; id <= 60; id++)
        Topic(
          id: id,
          title: 'Discussion $id about scrolling',
          slug: 'topic-$id',
        ),
    ],
    topic: topicPayload(
      id: 7,
      title: 'Reading a rich discussion in a sheet',
      canCreatePost: true,
      posts: [
        for (var id = 1; id <= 60; id++)
          Post(
            id: id,
            postNumber: id,
            username: 'reader',
            createdAt: DateTime.utc(2026, 10, 1, 0, id),
            cooked:
                '<p>Reply $id: scrolling through a rich discussion.</p>'
                '<blockquote><p>A previous reply with <strong>formatted text</strong>.</p></blockquote>'
                '<p>The reader handles <code>input</code>, <em>emphasis</em>, '
                'and an <a href="https://example.com/">ordinary link</a>.</p>'
                '<p>Scroll down and back through these replies while preserving '
                'the same reading position and the source list.</p>',
          ),
      ],
    ),
  );
  shell.openTopic(
    const Topic(
      id: 7,
      title: 'Reading a rich discussion in a sheet',
      slug: 'topic-7',
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}
