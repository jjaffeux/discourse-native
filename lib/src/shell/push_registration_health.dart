import 'package:flutter/foundation.dart';

import '../data/push_registration.dart';
import '../data/push_registration_ledger.dart';
import '../foundation/frame_safe_notifier.dart';

typedef PushAccount = ({String siteUrl, String username});

/// One account whose forum no longer reaches this device, awaiting the user.
@immutable
final class PushReauthorizationPrompt {
  const PushReauthorizationPrompt({
    required this.siteUrl,
    required this.username,
    required this.drift,
    required this.fingerprint,
  });

  final String siteUrl;
  final String username;
  final PushRegistrationDrift drift;

  /// The current token's fingerprint: a dismissal holds until it changes.
  final String fingerprint;

  @override
  bool operator ==(Object other) =>
      other is PushReauthorizationPrompt &&
      other.siteUrl == siteUrl &&
      other.username == username &&
      other.drift == drift &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(siteUrl, username, drift, fingerprint);
}

/// Notices when the token a forum pushes to is no longer this device's.
///
/// Discourse binds the push URL when a user API key is created, so only a new
/// authorization can repair a registration. This owner never starts one: it
/// publishes a prompt and leaves the decision to the user.
final class PushRegistrationHealth extends FrameSafeNotifier {
  PushRegistrationHealth({
    required this._current,
    required this._lastAuthorizedClientId,
    required this._accounts,
    this._ledger = const PushRegistrationLedger(),
  });

  final Future<PushRegistration?> Function() _current;
  final Future<String?> Function() _lastAuthorizedClientId;
  final Iterable<PushAccount> Function() _accounts;
  final PushRegistrationLedger _ledger;

  Map<String, PushReauthorizationPrompt> _prompts = const {};
  Object? _check;
  final Map<String, Object> _answers = {};

  List<PushReauthorizationPrompt> get prompts {
    final signedIn = _accountKeys(_accounts());
    return [
      for (final prompt in _prompts.values)
        if (signedIn.contains(_key(prompt.siteUrl, prompt.username))) prompt,
    ];
  }

  /// Compares every signed-in account with the token held now. A later check,
  /// or an authorization that lands meanwhile, outranks this one's answer.
  Future<void> check() async {
    if (isDisposed) return;
    final check = _check = Object();
    final accounts = _accounts().toList();
    final answers = Map.of(_answers);
    bool current() => !isDisposed && identical(_check, check);
    bool unchanged(PushAccount account) =>
        identical(_answers[account.siteUrl], answers[account.siteUrl]) &&
        _accountKeys(
          _accounts(),
        ).contains(_key(account.siteUrl, account.username));

    final String? fingerprint;
    try {
      final registration = accounts.isEmpty ? null : await _current();
      fingerprint = switch (registration) {
        final held? => pushTokenFingerprint(held.clientId),
        null => null,
      };
    } catch (_) {
      return;
    }
    if (!current()) return;

    final next = <String, PushReauthorizationPrompt>{};
    if (fingerprint != null) {
      for (final account in accounts) {
        final PushReauthorizationPrompt? prompt;
        try {
          prompt = await _evaluate(account, fingerprint, () {
            return current() && unchanged(account);
          });
        } catch (_) {
          continue;
        }
        if (!current()) return;
        if (prompt != null) next[account.siteUrl] = prompt;
      }
    }
    // An answer given while a later account was being read still stands.
    _publish({
      for (final account in accounts)
        if (next[account.siteUrl] case final prompt? when unchanged(account))
          account.siteUrl: prompt,
    });
  }

  Future<PushReauthorizationPrompt?> _evaluate(
    PushAccount account,
    String fingerprint,
    bool Function() stillOwned,
  ) async {
    final (:siteUrl, :username) = account;
    var record = await _ledger.read(siteUrl, username);
    if (!stillOwned()) return null;
    if (record == null) {
      final legacy = await _lastAuthorizedClientId();
      if (!stillOwned()) return null;
      record = PushRegistrationRecord(
        fingerprint: legacy == null ? null : pushTokenFingerprint(legacy),
        accepted: true,
      );
      await _ledger.write(siteUrl, username, record);
      if (!stillOwned()) return null;
    }
    final drift = pushRegistrationDrift(record, fingerprint);
    if (drift == PushRegistrationDrift.none) return null;
    final dismissed = await _ledger.dismissed(siteUrl, username);
    if (dismissed == fingerprint) return null;
    return PushReauthorizationPrompt(
      siteUrl: siteUrl,
      username: username,
      drift: drift,
      fingerprint: fingerprint,
    );
  }

  /// Records what a completed sign-in registered. A check still reading the
  /// platform cannot bring back a prompt this authorization answered.
  Future<void> authorized(
    String siteUrl,
    String username,
    PushAuthorization authorization,
  ) {
    if (isDisposed) return Future.value();
    _answer(siteUrl);
    return _ledger.write(
      siteUrl,
      username,
      PushRegistrationRecord.authorized(authorization),
    );
  }

  /// Hides [prompt] until this device's token changes again.
  Future<void> dismiss(PushReauthorizationPrompt prompt) {
    if (isDisposed) return Future.value();
    if (_prompts[prompt.siteUrl] == prompt) _answer(prompt.siteUrl);
    return _ledger.dismiss(prompt.siteUrl, prompt.username, prompt.fingerprint);
  }

  /// Withdraws the site's prompt and outranks any check still reading for it.
  void _answer(String siteUrl) {
    _answers[siteUrl] = Object();
    if (!_prompts.containsKey(siteUrl)) return;
    _publish(Map.of(_prompts)..remove(siteUrl));
  }

  void _publish(Map<String, PushReauthorizationPrompt> next) {
    if (mapEquals(_prompts, next)) return;
    _prompts = next;
    notifySafely();
  }

  static String _key(String siteUrl, String username) =>
      '$siteUrl\n${username.toLowerCase()}';

  static Set<String> _accountKeys(Iterable<PushAccount> accounts) => {
    for (final account in accounts) _key(account.siteUrl, account.username),
  };
}
