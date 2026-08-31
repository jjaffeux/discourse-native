import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

/// [legacyStorageKey] adopts one old unnamespaced key without making it part of
/// the owner-scoped identity.
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

  /// Contexts cross a plugin authority boundary as ordinary Dart values, so
  /// the host validates ownership and persistence-safe names.
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
