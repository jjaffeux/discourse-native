import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

/// A stable, plugin-owned namespace for one kind of emoji usage.
///
/// Context identity is the pair of [owner] and [name]. The resulting [id] is
/// suitable for persistence and keeps independently installed plugins from
/// displacing each other's recent emoji. [legacyStorageKey] lets a context
/// adopt one unnamespaced key written by an older application version without
/// making that compatibility name part of its identity.
@immutable
final class EmojiUsageContext {
  const EmojiUsageContext({
    required this.owner,
    required this.name,
    this.legacyStorageKey,
  }) : assert(name != ''),
       assert(legacyStorageKey != '');

  final PluginId owner;
  final String name;
  final String? legacyStorageKey;

  String get id => '${owner.value}/$name';

  /// Whether this value is a well-formed context owned by [expectedOwner].
  ///
  /// Contexts cross a plugin authority boundary as ordinary Dart values, so
  /// the receiving host must validate both ownership and persistence-safe
  /// names rather than trusting a caller-supplied namespace.
  bool isValidFor(PluginId expectedOwner) {
    final legacyKey = legacyStorageKey;
    return owner == expectedOwner &&
        owner.value.trim().isNotEmpty &&
        name == name.trim() &&
        name.isNotEmpty &&
        !name.contains('/') &&
        (legacyKey == null ||
            (legacyKey == legacyKey.trim() &&
                legacyKey.isNotEmpty &&
                !legacyKey.contains('/')));
  }

  @override
  bool operator ==(Object other) =>
      other is EmojiUsageContext && other.owner == owner && other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => id;
}

/// Emoji usage contexts owned by the core writing and account surfaces.
abstract final class CoreEmojiUsageContexts {
  static const topic = EmojiUsageContext(
    owner: PluginId('core'),
    name: 'topic',
    legacyStorageKey: 'topic',
  );

  static const userStatus = EmojiUsageContext(
    owner: PluginId('core'),
    name: 'user-status',
    legacyStorageKey: 'userStatus',
  );
}
