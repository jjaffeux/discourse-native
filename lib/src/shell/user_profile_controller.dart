import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/site_lookup_failure.dart';
import '../data/user_profiles_api.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/user_profile.dart';

/// What the app holds about one person's profile on one account session.
sealed class UserProfileState {
  const UserProfileState();
}

final class UserProfileLoading extends UserProfileState {
  const UserProfileLoading();
}

final class UserProfileLoaded extends UserProfileState {
  const UserProfileLoaded(this.profile);
  final UserProfile profile;
}

/// The person hid their public profile; [profile] carries identity only.
final class UserProfileHidden extends UserProfileState {
  const UserProfileHidden(this.profile);
  final UserProfile profile;
}

/// The site has no such person, or none this reader may know of.
final class UserProfileMissing extends UserProfileState {
  const UserProfileMissing();
}

/// The site refused this reader, as a login-required site refuses a visitor.
final class UserProfileForbidden extends UserProfileState {
  const UserProfileForbidden();
}

final class UserProfileFailed extends UserProfileState {
  const UserProfileFailed(this.message);
  final String message;
}

final class _ProfileEntry {
  UserProfileState? state;
  Object? request;
}

final class _ProfileAccount {
  _ProfileAccount(this.lease);

  final SiteLease lease;
  final Map<String, _ProfileEntry> entries = {};
  void Function()? detach;

  void dispose() {
    detach?.call();
    detach = null;
    entries.clear();
  }
}

/// Profiles by site, then by lowercased username, for the account session
/// that asked: a profile's contents depend on who is reading it.
final class UserProfileController extends FrameSafeNotifier {
  UserProfileController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final UserProfilesApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;

  final Map<String, _ProfileAccount> _accounts = {};

  _ProfileAccount? _accountFor(String siteUrl) {
    final account = _accounts[siteUrl];
    return account?.lease.isCurrent == true ? account : null;
  }

  _ProfileAccount _ensureAccount(String siteUrl) {
    final held = _accountFor(siteUrl);
    if (held != null) return held;
    final account = _ProfileAccount(lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      final owned = identical(_accounts[siteUrl], account);
      if (owned) _accounts.remove(siteUrl);
      account.dispose();
      if (owned) notifySafely();
    });
    return account;
  }

  /// Null until the current account session has asked for this profile.
  UserProfileState? stateFor(String siteUrl, String username) =>
      _accountFor(siteUrl)?.entries[username.toLowerCase()]?.state;

  /// A reader with no key still asks: a public site answers a visitor.
  Future<void> load(
    DiscourseInstance instance,
    String username, {
    bool refresh = false,
  }) async {
    if (isDisposed || username.isEmpty) return;
    final siteUrl = instance.url;
    final account = _ensureAccount(siteUrl);
    final entry = account.entries.putIfAbsent(
      username.toLowerCase(),
      _ProfileEntry.new,
    );
    if (entry.request != null || (!refresh && entry.state != null)) return;

    final request = Object();
    entry.request = request;
    if (!_showsProfile(entry.state)) {
      entry.state = const UserProfileLoading();
      notifySafely();
    }
    if (!_isCurrent(siteUrl, account, entry, request)) return;

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        account.lease,
      ).keyCredentials(credentials);
      if (!_isCurrent(siteUrl, account, entry, request)) return;
      final profile = await auth.run(
        () => api.userProfile(
          siteUrl: siteUrl,
          username: username,
          apiKey: auth.apiKey,
        ),
      );
      _commit(siteUrl, account, entry, request, () {
        entry.state = profile.hidden
            ? UserProfileHidden(profile)
            : UserProfileLoaded(profile);
      });
    } on SiteLookupException catch (error) {
      _commit(siteUrl, account, entry, request, () {
        entry.state = switch (error) {
          SiteLookupException(statusCode: 404) => const UserProfileMissing(),
          SiteLookupException(failure: SiteLookupFailure.notDiscourse) =>
            const UserProfileForbidden(),
          // A refresh that could not reach the site leaves the page it had.
          _ when _showsProfile(entry.state) => entry.state,
          _ => UserProfileFailed(appL10n.couldnTReach(instance.host)),
        };
      });
    } catch (_) {
      _commit(siteUrl, account, entry, request, () {
        if (_showsProfile(entry.state)) return;
        entry.state = UserProfileFailed(
          appL10n.couldnTLoadShellcontroller(username),
        );
      });
    } finally {
      if (identical(entry.request, request)) entry.request = null;
    }
  }

  static bool _showsProfile(UserProfileState? state) =>
      state is UserProfileLoaded || state is UserProfileHidden;

  bool _isCurrent(
    String siteUrl,
    _ProfileAccount account,
    _ProfileEntry entry,
    Object request,
  ) =>
      !isDisposed &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account) &&
      identical(entry.request, request);

  void _commit(
    String siteUrl,
    _ProfileAccount account,
    _ProfileEntry entry,
    Object request,
    VoidCallback mutation,
  ) {
    if (!_isCurrent(siteUrl, account, entry, request)) return;
    account.lease.commit(() {
      mutation();
      notifySafely();
    });
  }

  @override
  void dispose() {
    for (final account in _accounts.values) {
      account.dispose();
    }
    _accounts.clear();
    super.dispose();
  }
}
