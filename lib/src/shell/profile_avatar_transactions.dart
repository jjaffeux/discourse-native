import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/user_avatar_api.dart';
import '../data/write_failure.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/site_scoped_state.dart';
import '../models/composer_upload.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';

/// Where one account's picture change stands.
sealed class ProfileAvatarState {
  const ProfileAvatarState();

  bool get busy => switch (this) {
    ProfileAvatarUploading() || ProfileAvatarSaving() => true,
    ProfileAvatarIdle() || ProfileAvatarFailed() => false,
  };
}

final class ProfileAvatarIdle extends ProfileAvatarState {
  const ProfileAvatarIdle();
}

/// The image is on its way to the site and is not yet anyone's picture.
final class ProfileAvatarUploading extends ProfileAvatarState {
  const ProfileAvatarUploading();
}

/// The site is being told which picture to use, or the app is reading the
/// account back so every avatar it draws is the new one.
final class ProfileAvatarSaving extends ProfileAvatarState {
  const ProfileAvatarSaving();
}

final class ProfileAvatarFailed extends ProfileAvatarState {
  const ProfileAvatarFailed(this.message);
  final String message;
}

/// Told once the site has accepted a picture, with the upload it now draws
/// from: null for the letter avatar.
typedef ProfileAvatarChanged =
    void Function(DiscourseInstance instance, int? uploadId);

/// Reads the account back and answers it as accepted, or null when the read
/// was dropped.
typedef ProfileAvatarUserRefresh =
    Future<DiscourseUser?> Function(
      String siteUrl,
      String apiKey,
      SiteLease lease,
    );

/// Told once the account has been read back, with the avatar template it
/// drew from when the change began and the one it draws from now.
typedef ProfileAvatarReplaced =
    void Function(
      String siteUrl,
      SiteLease lease, {
      required String username,
      required String? previous,
      required String? current,
    });

final class _AvatarWrite {
  final Completer<void> abort = Completer<void>();
}

final class _AvatarAccount {
  _AvatarAccount(this.lease);

  final SiteLease lease;
  ProfileAvatarState state = const ProfileAvatarIdle();
  _AvatarWrite? write;
  void Function()? detach;

  void retire() {
    detach?.call();
    detach = null;
    final abort = write?.abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    write = null;
  }
}

/// Changes the signed-in reader's picture.
///
/// It stands beside [ProfileWriteTransactions] and not inside it: that owner
/// publishes through the shell, and a picture's upload and save steps would
/// redraw the whole shell twice for a row only Preferences shows. A picture is
/// also two requests through its own port, where a status is one.
final class ProfileAvatarTransactions extends FrameSafeNotifier
    with AccountScopedState {
  ProfileAvatarTransactions({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.refreshCurrentUser,
    this.onChanged,
    this.onReplaced,
  });

  final UserAvatarApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final ProfileAvatarUserRefresh refreshCurrentUser;
  final ProfileAvatarChanged? onChanged;
  final ProfileAvatarReplaced? onReplaced;

  final Map<String, _AvatarAccount> _accounts = {};

  ProfileAvatarState stateFor(String siteUrl) =>
      _existing(siteUrl)?.state ?? const ProfileAvatarIdle();

  _AvatarAccount? _existing(String siteUrl) {
    final account = _accounts[siteUrl];
    return account != null && _owns(account, siteUrl) ? account : null;
  }

  bool _owns(_AvatarAccount account, String siteUrl) =>
      !isDisposed &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account);

  _AvatarAccount _accountFor(String siteUrl) {
    final held = _existing(siteUrl);
    if (held != null) return held;
    _accounts.remove(siteUrl)?.retire();
    final account = _AvatarAccount(lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      final owned = identical(_accounts[siteUrl], account);
      if (owned) _accounts.remove(siteUrl);
      account.retire();
      if (owned && !isDisposed) notifySafely();
    });
    return account;
  }

  /// Uploads [file] and makes it the reader's picture.
  Future<bool> upload(DiscourseInstance instance, ComposerUploadFile file) =>
      _write(
        instance,
        const ProfileAvatarUploading(),
        (request, write) => api.uploadAvatar(
          siteUrl: instance.url,
          apiKey: request.apiKey!,
          clientId: request.clientId,
          file: file,
          abortTrigger: write.abort.future,
        ),
      );

  /// Returns the reader to the letter avatar the site draws.
  Future<bool> useDefault(DiscourseInstance instance) =>
      _write(instance, const ProfileAvatarSaving(), (_, _) async => null);

  Future<bool> _write(
    DiscourseInstance instance,
    ProfileAvatarState started,
    Future<int?> Function(AccountRequestCredentials request, _AvatarWrite write)
    upload,
  ) async {
    final username = instance.user?.username;
    if (isDisposed || username == null) return false;
    final siteUrl = instance.url;
    final account = _accountFor(siteUrl);
    // The site applies picks in the order they arrive, so a second one waits
    // for the first to settle instead of racing it there.
    if (account.write != null) return false;
    final write = _AvatarWrite();
    account.write = write;
    bool owns() => _owns(account, siteUrl) && identical(account.write, write);
    void publish(ProfileAvatarState state) {
      if (!owns()) return;
      account.state = state;
      notifySafely();
    }

    publish(started);
    try {
      final request = await AccountRequestSession(
        siteUrl,
        account.lease,
      ).credentials(credentials);
      if (!owns()) return false;
      final apiKey = request.apiKey;
      if (apiKey == null) {
        publish(
          ProfileAvatarFailed(
            const WriteException(WriteFailure.forbidden).message,
          ),
        );
        return false;
      }
      final uploadId = await request.run(() => upload(request, write));
      if (!owns()) return false;
      publish(const ProfileAvatarSaving());
      await request.run(
        () => api.pickAvatar(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: request.clientId,
          username: username,
          uploadId: uploadId,
        ),
      );
      if (!owns()) return false;
      account.lease.commit(() => onChanged?.call(instance, uploadId));
      DiscourseUser? fresh;
      try {
        fresh = await refreshCurrentUser(siteUrl, apiKey, account.lease);
      } catch (_) {
        // The site has the new picture; the next account read shows it.
      }
      if (fresh != null && owns()) {
        onReplaced?.call(
          siteUrl,
          account.lease,
          username: fresh.username,
          previous: instance.user?.avatarTemplate,
          current: fresh.avatarTemplate,
        );
      }
      publish(const ProfileAvatarIdle());
      return owns();
    } on ComposerUploadException catch (error) {
      publish(ProfileAvatarFailed(error.displayMessage));
      return false;
    } on WriteException catch (error) {
      // Core refuses a pick it does not allow with a bare 422, which the
      // transport cannot tell from an answer that never arrived.
      publish(
        ProfileAvatarFailed(
          error.errors.isEmpty && error.statusCode == 422
              ? appL10n.thisSiteDidnTAcceptThatPicture
              : error.message,
        ),
      );
      return false;
    } on AccountRequestRetiredException {
      return false;
    } catch (_) {
      publish(
        ProfileAvatarFailed(
          const WriteException(WriteFailure.unreachable).message,
        ),
      );
      return false;
    } finally {
      if (identical(account.write, write)) account.write = null;
    }
  }

  @override
  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    if (account == null) return;
    account.retire();
    if (!isDisposed) notifySafely();
  }

  @override
  void dispose() {
    for (final account in _accounts.values.toList()) {
      account.retire();
    }
    _accounts.clear();
    super.dispose();
  }
}
