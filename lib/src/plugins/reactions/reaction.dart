import 'package:flutter/foundation.dart';

import '../../models/post.dart';
import '../../plugin_api/plugin_data.dart';

const reactionsDataKey = PluginDataKey<Reactions>(
  owner: 'discourse-reactions',
  name: 'post',
);

extension PostReactions on Post {
  /// Payload presence is the feature gate; settings cannot select a safe write path.
  Reactions? get reactions => plugins.get(reactionsDataKey);

  bool get hasReactions => reactions != null;

  /// Reaction and like undo windows are separate, so both checks are required.
  bool get canReact =>
      hasReactions && canToggleLike && (reactions!.mine?.canUndo ?? true);
}

@immutable
class Reaction {
  const Reaction({required this.id, this.count = 0, this.canUndo = false});

  final String id;

  final int count;

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

@immutable
class Reactions {
  const Reactions({
    this.entries = const [],
    this.mine,
    this.usedMainReaction = false,
    this.userCount = 0,
  });

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

  /// Includes plain likes folded into the site's main reaction.
  final List<Reaction> entries;

  /// Core reports a plain like as the site's main reaction here.
  final Reaction? mine;

  /// Not derivable from [mine], because excluded reactions do not shadow likes.
  final bool usedMainReaction;

  /// Can exceed the visible entries when a used emoji has since been deleted.
  final int userCount;

  bool get isEmpty => entries.isEmpty;

  static int _compareReaction(Reaction left, Reaction right) {
    final byCount = right.count.compareTo(left.count);
    return byCount == 0 ? left.id.compareTo(right.id) : byCount;
  }

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

    final sorted = next.values.toList()..sort(_compareReaction);

    return Reactions(
      entries: List.unmodifiable(sorted),
      // Match the web client's optimistic undo assumption.
      mine: removing ? null : Reaction(id: id, canUndo: true),
      usedMainReaction: false,
      userCount: switch ((held != null, removing)) {
        (true, false) => userCount,
        (true, true) => userCount > 0 ? userCount - 1 : 0,
        _ => userCount + 1,
      },
    );
  }

  /// Write responses are authoritative for the reader, but not for counts:
  /// toggle serialization filters deleted emoji while topic reads do not.
  Reactions withMineOf(Reactions other) => Reactions(
    entries: entries,
    mine: other.mine,
    usedMainReaction: other.usedMainReaction,
    userCount: userCount,
  );

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
