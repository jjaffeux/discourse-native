import 'package:shared_preferences/shared_preferences.dart';

import 'store_diagnostics.dart';

/// How a preference kept per forum is named in `shared_preferences`: [prefix],
/// the forum URL percent-encoded, then its [tail].
///
/// Percent-encoding leaves `.` alone, so a key does not always split back into
/// one forum: `https://a.b` followed by the name `c.d` spells the same key as
/// `https://a.b.c` followed by `d`. [sitesIn] answers every forum a key can be
/// read as, and [ForgottenSites] drops a key only while none of them is kept.
final class SitePreferenceKey {
  const SitePreferenceKey(
    this.prefix, {
    this.tail = SitePreferenceTail.none,
    this.onForget,
    this._spelling,
  });

  final String prefix;
  final SitePreferenceTail tail;

  /// Retires pending operations for the forgotten forums before their cached
  /// and stored values leave. Account changes do not invoke this callback.
  final void Function(ForgottenSites sites)? onForget;
  final String Function(String siteUrl)? _spelling;

  /// The key for [siteUrl], before its [tail].
  String of(String siteUrl) => '$prefix.${Uri.encodeComponent(spell(siteUrl))}';

  /// [siteUrl] as these keys write it.
  String spell(String siteUrl) => _spelling?.call(siteUrl) ?? siteUrl;

  /// Every forum [key] can be read as, as these keys write it; empty when
  /// [key] is not one of these keys.
  List<String> sitesIn(String key) {
    final start = '$prefix.';
    if (!key.startsWith(start)) return const [];
    final sites = <String>[];
    for (var end = start.length + 1; end <= key.length; end++) {
      if (end < key.length && key.codeUnitAt(end) != _dot) continue;
      if (!tail._follows(key.substring(end))) continue;
      try {
        sites.add(Uri.decodeComponent(key.substring(start.length, end)));
      } on ArgumentError {
        continue;
      } on FormatException {
        continue;
      }
    }
    return sites;
  }

  static const _dot = 0x2E;
}

/// What follows the forum in a [SitePreferenceKey].
enum SitePreferenceTail {
  /// Nothing: one value per forum.
  none,

  /// A percent-encoded name, such as a username, which may contain dots.
  name,

  /// An id, such as a user's.
  id,

  /// Two ids, such as a room's and then a user's.
  idPair;

  static final _id = RegExp(r'^\.-?\d+$');
  static final _idPair = RegExp(r'^\.-?\d+\.-?\d+$');

  bool _follows(String tail) => switch (this) {
    none => tail.isEmpty,
    name => tail.length > 1 && tail.startsWith('.'),
    id => _id.hasMatch(tail),
    idPair => _idPair.hasMatch(tail),
  };
}

/// Forums whose preferences are dropped because they left the rail for good.
final class ForgottenSites {
  /// The forum at [siteUrl], once its removal is saved. [keeping] is every
  /// forum that still keeps its preferences.
  ForgottenSites.removed(String siteUrl, {required Iterable<String> keeping})
    : _only = siteUrl,
      _keeping = Set.unmodifiable(keeping);

  /// Every forum but [keeping].
  ForgottenSites.except(Iterable<String> keeping)
    : _only = null,
      _keeping = Set.unmodifiable(keeping);

  final String? _only;
  final Set<String> _keeping;

  /// Whether the preferences of [siteUrl], as [key] writes it, go.
  bool includes(String siteUrl, [SitePreferenceKey? key]) =>
      _forgets(siteUrl, key) && !_keeps(siteUrl, key);

  /// Whether the stored [storedKey], one of [key], goes: a forgotten forum
  /// could have written it, and no forum that is kept could have.
  bool covers(SitePreferenceKey key, String storedKey) {
    final sites = key.sitesIn(storedKey);
    return sites.isNotEmpty &&
        !sites.any((site) => _keeps(site, key)) &&
        sites.any((site) => _forgets(site, key));
  }

  bool _forgets(String site, SitePreferenceKey? key) {
    final only = _only;
    return only == null || site == (key?.spell(only) ?? only);
  }

  bool _keeps(String site, SitePreferenceKey? key) =>
      _keeping.any((kept) => site == (key?.spell(kept) ?? kept));
}

/// Removes every stored value of [keys] that the forgotten sites cover.
///
/// [sites] is asked once storage is open, so a removal that a re-add has
/// overtaken meanwhile can still answer null and remove nothing. The values it
/// covers leave the preferences' cache in the same turn, so a caller that drops
/// its own copies in [sites] cannot read the stored ones back afterwards.
Future<void> forgetSitePreferences(
  Iterable<SitePreferenceKey> keys,
  ForgottenSites? Function() sites,
) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    final forgotten = sites();
    if (forgotten == null) return;
    for (final key in keys) {
      key.onForget?.call(forgotten);
    }
    final removals = [
      for (final stored in preferences.getKeys())
        if (keys.any((key) => forgotten.covers(key, stored)))
          preferences.remove(stored),
    ];
    if ((await Future.wait(removals)).contains(false)) {
      throw StateError('Could not remove a forgotten forum\'s preferences.');
    }
  } catch (error, stackTrace) {
    reportStorageFailure(error, stackTrace, 'sitePreferences.forget');
  }
}
