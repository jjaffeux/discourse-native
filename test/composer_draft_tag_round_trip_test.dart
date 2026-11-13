import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/topic_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restored draft tags retain their slug and selection metadata', () {
    const draft = ComposerDraft(
      reply: 'Draft body',
      tags: [
        TopicTag(
          id: 7,
          name: 'Announcements',
          slug: 'news',
          pmOnly: true,
          count: 5,
          disabled: true,
          disabledReason: 'Tag is unavailable',
        ),
      ],
    );

    const local = LocalComposerDraft(draft: draft, sequence: 4);
    final restored = LocalComposerDraft.decode(local.encode());
    final tag = restored!.draft.tags.single;
    expect(tag.slug, 'news');
    expect(tag, draft.tags.single);
    expect(restored.sequence, 4);
  });
}
