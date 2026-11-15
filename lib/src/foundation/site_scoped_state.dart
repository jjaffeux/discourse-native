/// State an owner keeps per forum.
///
/// The shell registers every such owner once, in the order they retire, and
/// walks that one list whenever a forum leaves the rail or its account
/// session rotates. An owner that is not registered keeps the former
/// account's state for the next one, so
/// `test/site_state_registration_test.dart` fails on any that is missing.
abstract interface class SiteScopedState {
  /// A step that has no owner class of its own.
  factory SiteScopedState.step(void Function(String siteUrl) forget) =
      _SiteStep;

  /// Drops everything held for [siteUrl].
  void forget(String siteUrl);
}

/// Per-forum state that belongs to the signed-in account rather than to the
/// forum, so it must not reach a different account accepted under the same
/// site lease.
abstract mixin class AccountScopedState implements SiteScopedState {
  /// A step that has no owner class of its own.
  factory AccountScopedState.step(void Function(String siteUrl) forget) =
      _AccountStep;

  /// Another account was accepted for [siteUrl] without its lease rotating.
  /// Override when part of the state is the same for every account.
  void accountChanged(String siteUrl) => forget(siteUrl);
}

final class _SiteStep implements SiteScopedState {
  _SiteStep(this._forget);
  final void Function(String siteUrl) _forget;

  @override
  void forget(String siteUrl) => _forget(siteUrl);
}

final class _AccountStep with AccountScopedState {
  _AccountStep(this._forget);
  final void Function(String siteUrl) _forget;

  @override
  void forget(String siteUrl) => _forget(siteUrl);
}

/// The ordered list of per-forum owners behind one shell.
final class SiteStateRegistry {
  final List<({SiteScopedState owner, bool removalOnly})> _entries = [];

  Iterable<SiteScopedState> get owners => _entries.map((entry) => entry.owner);

  void register(SiteScopedState owner) {
    assert(!owners.any((held) => identical(held, owner)));
    _entries.add((owner: owner, removalOnly: false));
  }

  /// A step for a forum that leaves the rail, skipped when only its account
  /// session rotates.
  void registerRemovalStep(void Function(String siteUrl) step) {
    _entries.add((owner: SiteScopedState.step(step), removalOnly: true));
  }

  /// Retires [siteUrl] from every owner in registration order.
  void forget(String siteUrl, {required bool siteRemoved}) {
    for (final entry in _entries) {
      if (entry.removalOnly && !siteRemoved) continue;
      entry.owner.forget(siteUrl);
    }
  }

  /// Retires the former account of [siteUrl] from every account-scoped owner.
  ///
  /// An owner may notify listeners that sign out or remove the forum, so
  /// [stillOwned] is asked after each one. Answers false once it says no,
  /// leaving the remaining owners to the retirement that took over.
  bool accountChanged(String siteUrl, {required bool Function() stillOwned}) {
    for (final entry in _entries) {
      final owner = entry.owner;
      if (owner is! AccountScopedState) continue;
      owner.accountChanged(siteUrl);
      if (!stillOwned()) return false;
    }
    return true;
  }
}
