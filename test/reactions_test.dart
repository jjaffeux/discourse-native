import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// A post payload as a reactions site serializes one.
Map<String, dynamic> payload({
  List<Map<String, dynamic>>? reactions,
  Map<String, dynamic>? mine,
  bool usedMain = false,
  int userCount = 0,
  bool canAct = true,
  bool canUndo = false,
  bool acted = false,
  int likeCount = 0,
}) => {
  'id': 1,
  'post_number': 1,
  'username': 'sam',
  'cooked': '<p>Hi</p>',
  'actions_summary': [
    {
      'id': 2,
      'count': likeCount,
      if (acted) 'acted': true,
      if (canAct) 'can_act': true,
      if (canUndo) 'can_undo': true,
    },
  ],
  'reactions': ?reactions,
  'current_user_reaction': ?mine,
  'current_user_used_main_reaction': usedMain,
  'reaction_users_count': userCount,
};

Map<String, dynamic> entry(String id, int count) => {
  'id': id,
  'type': 'emoji',
  'count': count,
};

Post postFrom(Map<String, dynamic> json) =>
    Post.fromJson(json, 'https://meta.discourse.org');

Reactions reactionsOf(Map<String, dynamic> json) => postFrom(json).reactions!;

void main() {
  group('reading a post', () {
    test('says nothing at all when the site did not mention reactions', () {
      // The load-bearing default, and it holds by construction rather than by
      // discipline: a disabled plugin's serializer attributes are absent, so
      // there is no key to read and no value to invent.
      final post = postFrom({
        'id': 1,
        'post_number': 1,
        'username': 'sam',
        'cooked': '<p>Hi</p>',
      });

      expect(post.reactions, isNull);
      expect(post.hasReactions, isFalse);
      expect(post.canReact, isFalse);
    });

    test('distinguishes a site with reactions from a post with none', () {
      // `[]` and absent are different answers: one is "nobody reacted", the
      // other is "this site does not do reactions".
      final post = postFrom(payload(reactions: []));

      expect(post.hasReactions, isTrue);
      expect(post.reactions!.isEmpty, isTrue);
    });

    test('reads the row, the reader and the count', () {
      final reactions = reactionsOf(
        payload(
          reactions: [entry('heart', 5), entry('clap', 2)],
          mine: {'id': 'clap', 'type': 'emoji', 'can_undo': true},
          userCount: 7,
        ),
      );

      expect(reactions.entries.map((e) => e.id), ['heart', 'clap']);
      expect(reactions.entries.first.count, 5);
      expect(reactions.mine?.id, 'clap');
      expect(reactions.mine?.canUndo, isTrue);
      expect(reactions.userCount, 7);
    });

    test('a plain like reads as the main reaction, because it is one', () {
      // The site sets `current_user_reaction` to the main reaction for a reader
      // who has only liked, so there is nothing to reconcile here.
      final reactions = reactionsOf(
        payload(
          reactions: [entry('heart', 1)],
          mine: {'id': 'heart', 'type': 'emoji', 'can_undo': true},
          usedMain: true,
          userCount: 1,
        ),
      );

      expect(reactions.mine?.id, 'heart');
      expect(reactions.usedMainReaction, isTrue);
    });
  });

  group('canReact', () {
    test('needs the site to have said this reader may act', () {
      // The toggle route gates on exactly `post_can_act?(post, :like)`, which
      // already carries ownership, silencing and archived topics.
      expect(postFrom(payload(reactions: [])).canReact, isTrue);
      expect(postFrom(payload(reactions: [], canAct: false)).canReact, isFalse);
    });

    test('refuses a reaction past its own undo window', () {
      // A second clock, separate from the like's: `mine.canUndo` can be false
      // while `can_act` is still true.
      final expired = postFrom(
        payload(
          reactions: [entry('clap', 1)],
          mine: {'id': 'clap', 'type': 'emoji'},
          canAct: false,
          canUndo: false,
          acted: true,
        ),
      );

      expect(expired.canReact, isFalse);
    });

    test('is false on a site without the plugin, whatever the like says', () {
      final post = postFrom({
        'id': 1,
        'post_number': 1,
        'username': 'sam',
        'cooked': '<p>Hi</p>',
        'actions_summary': [
          {'id': 2, 'can_act': true},
        ],
      });

      expect(post.canToggleLike, isTrue);
      expect(post.canReact, isFalse);
    });
  });

  group('withToggled', () {
    test('gives a first reaction and counts the reader', () {
      final next = const Reactions().withToggled('clap');

      expect(next.entries, [const Reaction(id: 'clap', count: 1)]);
      expect(next.mine?.id, 'clap');
      expect(next.mine?.canUndo, isTrue);
      expect(next.userCount, 1);
    });

    test('takes one back and stops counting the reader', () {
      final held = reactionsOf(
        payload(
          reactions: [entry('clap', 1)],
          mine: {'id': 'clap', 'type': 'emoji', 'can_undo': true},
          userCount: 1,
        ),
      );

      final next = held.withToggled('clap');

      expect(next.entries, isEmpty);
      expect(next.mine, isNull);
      expect(next.userCount, 0);
    });

    test('a swap moves the counts but not the reader', () {
      // They were already being counted; only which emoji changed.
      final held = reactionsOf(
        payload(
          reactions: [entry('heart', 5), entry('clap', 2)],
          mine: {'id': 'clap', 'type': 'emoji', 'can_undo': true},
          userCount: 7,
        ),
      );

      final next = held.withToggled('heart');

      expect(next.entries, [
        const Reaction(id: 'heart', count: 6),
        const Reaction(id: 'clap', count: 1),
      ]);
      expect(next.mine?.id, 'heart');
      expect(next.userCount, 7);
    });

    test('keeps the order the site sorts in', () {
      // Count descending, then id ascending — so an emoji overtaking another
      // moves ahead of it rather than staying put.
      final held = reactionsOf(
        payload(reactions: [entry('heart', 2), entry('clap', 2)], userCount: 4),
      );

      final next = held.withToggled('clap');

      expect(next.entries.map((e) => e.id), ['clap', 'heart']);
    });

    test('drops an emoji nobody is left giving', () {
      final held = reactionsOf(
        payload(
          reactions: [entry('heart', 3), entry('clap', 1)],
          mine: {'id': 'clap', 'type': 'emoji', 'can_undo': true},
          userCount: 4,
        ),
      );

      expect(held.withToggled('heart').entries.map((e) => e.id), ['heart']);
    });

    test('floors the counts at zero', () {
      // Numbers the site sent, and a count read a moment before somebody
      // else's undo would otherwise draw -1.
      final stale = const Reactions(
        entries: [],
        mine: Reaction(id: 'clap', canUndo: true),
      );

      final next = stale.withToggled('clap');

      expect(next.entries, isEmpty);
      expect(next.userCount, 0);
    });
  });

  group('withMineOf', () {
    test('takes the reader and leaves the counts alone', () {
      // The answer to a write is built by a different code path from a topic
      // read, and drops reactions whose emoji no longer exists — so its counts
      // are not to be trusted, and only what it says about this reader is.
      final held = reactionsOf(
        payload(reactions: [entry('heart', 5)], userCount: 5),
      );
      final answered = reactionsOf(
        payload(
          reactions: [entry('heart', 1)],
          mine: {'id': 'heart', 'type': 'emoji', 'can_undo': true},
          usedMain: true,
          userCount: 1,
        ),
      );

      final next = held.withMineOf(answered);

      expect(next.entries.first.count, 5);
      expect(next.userCount, 5);
      expect(next.mine?.id, 'heart');
      expect(next.usedMainReaction, isTrue);
    });
  });

  group('withMainReaction', () {
    test('presses the heart only for the reaction that is a like', () {
      final held = const Reactions(mine: Reaction(id: 'heart', canUndo: true));

      expect(held.withMainReaction('heart').usedMainReaction, isTrue);
      expect(held.withMainReaction('+1').usedMainReaction, isFalse);
      // Unknown means unknown: nothing is guessed either way.
      expect(held.withMainReaction(null).usedMainReaction, isFalse);
    });
  });
}
