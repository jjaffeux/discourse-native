import 'package:flutter/foundation.dart';

import '../../models/post.dart';

/// What a post looks like to the reactions plugin.
///
/// An extension rather than fields on [Post], so the vocabulary of an optional
/// feature stays in the module that owns it and core keeps one generic bag.
extension PostReactions on Post {
  /// What the site said about reactions on this post, or null on a site that
  /// did not mention them.
  ///
  /// **This is the gate.** Every reactions affordance keys off it and none of
  /// them key off site config, so a settings fetch still in flight can never
  /// route a write down the like path on a post that has reactions — which is
  /// the mistake that orphans a `ReactionUser` server side.
  Reactions? get reactions => plugins.get<Reactions>();

  bool get hasReactions => reactions != null;

  /// Whether tapping a reaction would do anything.
  ///
  /// [canToggleLike] is the permission, and it is the right one: the toggle
  /// route gates on exactly `post_can_act?(post, :like)`, so the guardian has
  /// already weighed ownership, silencing, archived topics and the like undo
  /// window. `mine.canUndo` narrows it further, because a reaction's own undo
  /// window is a separate clock and can expire while the like's has not.
  bool get canReact =>
      hasReactions && canToggleLike && (reactions!.mine?.canUndo ?? true);
}

/// One emoji on a post: a row in the count, or the one this reader gave.
@immutable
class Reaction {
  const Reaction({required this.id, this.count = 0, this.canUndo = false});

  /// The emoji's name, as the site names it — `heart`, `+1`, `clap`, or a
  /// custom emoji's own name.
  final String id;

  /// How many people gave it. Zero on [Reactions.mine], which is one person by
  /// definition and carries no count.
  final int count;

  /// Whether it can still be taken back. Only meaningful on [Reactions.mine].
  ///
  /// Two different clocks answer this server side — `ReactionUser#can_undo?`
  /// for a reaction, and the guardian's own check for a plain like, which also
  /// weighs whether the topic is archived. See `Post.canReact`.
  final bool canUndo;

  static Reaction? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return Reaction(
      id: id,
      count: switch (json['count']) {
        final num n => n.toInt(),
        _ => 0,
      },
      canUndo: json['can_undo'] == true,
    );
  }

  Reaction copyWith({int? count}) =>
      Reaction(id: id, count: count ?? this.count, canUndo: canUndo);

  @override
  bool operator ==(Object other) =>
      other is Reaction &&
      other.id == id &&
      other.count == count &&
      other.canUndo == canUndo;

  @override
  int get hashCode => Object.hash(id, count, canUndo);

  @override
  String toString() => 'Reaction($id, count: $count, canUndo: $canUndo)';
}

/// Everything the reactions plugin says about one post.
///
/// One object rather than four fields on [Post], because the four arrive and
/// leave together: null is the whole answer to "this site does not have the
/// plugin", and a rollback is one assignment.
@immutable
class Reactions {
  const Reactions({
    this.entries = const [],
    this.mine,
    this.usedMainReaction = false,
    this.userCount = 0,
  });

  /// Null when the payload carried no `reactions` key at all.
  ///
  /// That is exactly what a site without the plugin — or with it switched off —
  /// serializes, because `add_to_serializer` defaults `respect_plugin_enabled`
  /// to true and hides every attribute a disabled plugin registered. There is
  /// no default here and no way for a fake to invent one, which is what makes
  /// "a post on a plain site draws the like it always drew" true by
  /// construction rather than by discipline.
  static Reactions? fromJson(Map<String, dynamic> json) {
    final raw = json['reactions'];
    if (raw is! List) return null;

    return Reactions(
      entries: raw
          .map(Reaction.fromJson)
          .whereType<Reaction>()
          .toList(growable: false),
      mine: Reaction.fromJson(json['current_user_reaction']),
      usedMainReaction: json['current_user_used_main_reaction'] == true,
      userCount: switch (json['reaction_users_count']) {
        final num n => n.toInt(),
        _ => 0,
      },
    );
  }

  /// Every emoji given to the post, as the site sorted them: count descending,
  /// then id ascending.
  ///
  /// Plain likes are in here too. The site folds them into the main reaction's
  /// entry, so on a default site the heart's count is the like count and there
  /// is nothing to reconcile.
  final List<Reaction> entries;

  /// What this reader gave, or null.
  ///
  /// When they have only *liked*, the site sets this to the main reaction —
  /// so a like and a heart-reaction are indistinguishable here, deliberately.
  final Reaction? mine;

  /// Whether the heart should read as pressed.
  ///
  /// Not derivable from [mine]: an excluded reaction leaves no like behind, and
  /// a stray like can outlive the reaction that shadowed it, so the two can
  /// disagree. Where they do, what a tap will *do* comes from [mine] and what
  /// the reader already did comes from here.
  final bool usedMainReaction;

  /// How many distinct accounts liked **or** reacted.
  ///
  /// Deliberately never drawn beside [entries], because it is not their sum and
  /// provably can exceed it: a reaction whose emoji has since been deleted is
  /// dropped from the list and still counted here. A total that does not add up
  /// is worse than no total — the reactor list's own `total_rows` is what the
  /// panel counts with.
  final int userCount;

  bool get isEmpty => entries.isEmpty;

  /// The site's reaction order: count descending, then id ascending.
  static int _compareReaction(Reaction left, Reaction right) {
    final byCount = right.count.compareTo(left.count);
    return byCount == 0 ? left.id.compareTo(right.id) : byCount;
  }

  /// This reader's reaction given, moved or taken back — the post as the site
  /// will have it a moment from now.
  ///
  /// Drawn before the request is sent, so a tap is answered by the row rather
  /// than by the network, and overwritten by the site's answer either way. The
  /// branches mirror the plugin's own `toggleReaction`: what they held is
  /// decremented or dropped, what they tapped is incremented or inserted, and
  /// [userCount] only moves when they gained or lost a reaction — never on a
  /// swap, where they were already being counted.
  ///
  /// Counts are floored at zero, which upstream does not bother with and which
  /// matters here because a count read a moment before someone else's undo
  /// would otherwise draw -1.
  Reactions withToggled(String id) {
    final held = mine;
    final removing = held != null && held.id == id;

    final next = <String, Reaction>{
      for (final entry in entries) entry.id: entry,
    };

    void step(String key, int by) {
      final entry = next[key];
      final count = (entry?.count ?? 0) + by;
      if (count <= 0) {
        next.remove(key);
        return;
      }
      next[key] = entry == null
          ? Reaction(id: key, count: count)
          : entry.copyWith(count: count);
    }

    if (held != null) step(held.id, -1);
    if (!removing) step(id, 1);

    // A site with arbitrary emoji enabled can have a long distinct-reaction
    // row. One sort keeps this rebuild O(n log n) rather than repeatedly
    // scanning the already sorted prefix for every entry.
    final sorted = next.values.toList()..sort(_compareReaction);

    return Reactions(
      entries: List.unmodifiable(sorted),
      // A reaction just given can be taken back; one just taken back leaves
      // nothing to undo. The same guess the plugin's own client makes.
      mine: removing ? null : Reaction(id: id, canUndo: true),
      usedMainReaction: false,
      userCount: switch ((held != null, removing)) {
        // Swapped one for another: they were already counted.
        (true, false) => userCount,
        (true, true) => userCount > 0 ? userCount - 1 : 0,
        _ => userCount + 1,
      },
    );
  }

  /// This, but with what [other] says about *this reader* and nothing else.
  ///
  /// For the answer to a write, whose counts are not to be trusted: the plugin
  /// computes `reactions` one way for a topic read — raw SQL, unfiltered — and
  /// another for a toggle or an edit response, which drops reactions whose
  /// emoji no longer exists. Taking the counts from the second would bump a
  /// pill and leave it wrong until the topic was read again. What that payload
  /// *is* right about is the reader, because it was serialized for them.
  Reactions withMineOf(Reactions other) => Reactions(
    entries: entries,
    mine: other.mine,
    usedMainReaction: other.usedMainReaction,
    userCount: userCount,
  );

  /// [usedMainReaction] recomputed against a site whose main reaction is known.
  ///
  /// Only for the optimistic guess: after a toggle the site has not said yet,
  /// and the heart has to know whether to read as pressed.
  Reactions withMainReaction(String? mainReaction) => Reactions(
    entries: entries,
    mine: mine,
    usedMainReaction: mainReaction != null && mine?.id == mainReaction,
    userCount: userCount,
  );

  @override
  bool operator ==(Object other) =>
      other is Reactions &&
      other.mine == mine &&
      other.usedMainReaction == usedMainReaction &&
      other.userCount == userCount &&
      listEquals(other.entries, entries);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(entries), mine, usedMainReaction, userCount);

  @override
  String toString() => 'Reactions($entries, mine: $mine, users: $userCount)';
}
