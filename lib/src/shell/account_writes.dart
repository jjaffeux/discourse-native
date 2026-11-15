import 'dart:async';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/write_failure.dart';
import '../models/discourse_instance.dart';

/// Where one account's immediate write stands. [T] names what is being
/// written: a username, an address, a device.
sealed class AccountWriteState<T> {
  const AccountWriteState();

  bool get busy => this is AccountWriteBusy<T>;
}

final class AccountWriteIdle<T> extends AccountWriteState<T> {
  const AccountWriteIdle();
}

final class AccountWriteBusy<T> extends AccountWriteState<T> {
  const AccountWriteBusy(this.subject);
  final T subject;
}

/// The site took the write. Kept until the next write or [AccountWrites.settle]
/// so a view can say what happened.
final class AccountWriteDone<T> extends AccountWriteState<T> {
  const AccountWriteDone(this.subject);
  final T subject;
}

final class AccountWriteFailed<T> extends AccountWriteState<T> {
  const AccountWriteFailed(this.subject, this.message);
  final T subject;
  final String message;
}

final class _WriteAccount<T> {
  _WriteAccount(this.lease);

  final SiteLease lease;
  AccountWriteState<T> state = const AccountWriteIdle();
  Object? write;
  void Function()? detach;

  void retire() {
    detach?.call();
    detach = null;
    write = null;
  }
}

/// One request at a time per signed-in account, for a write that is sent at
/// once and belongs to no preference draft.
///
/// An owner composes this with its own notifier, so each kind of write
/// redraws only the rows that show it. A second write is refused while one is
/// in flight, because the site applies them in the order they arrive. An
/// answer for a retired session or a forgotten site is dropped.
final class AccountWrites<T> {
  AccountWrites({
    required this.credentials,
    required this.lifecycle,
    required this.notify,
    required this.isDisposed,
  });

  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final void Function() notify;
  final bool Function() isDisposed;

  final Map<String, _WriteAccount<T>> _accounts = {};

  AccountWriteState<T> stateFor(String siteUrl) =>
      _existing(siteUrl)?.state ?? AccountWriteIdle<T>();

  _WriteAccount<T>? _existing(String siteUrl) {
    final account = _accounts[siteUrl];
    return account != null && _owns(account, siteUrl) ? account : null;
  }

  bool _owns(_WriteAccount<T> account, String siteUrl) =>
      !isDisposed() &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account);

  _WriteAccount<T> _accountFor(String siteUrl) {
    final held = _existing(siteUrl);
    if (held != null) return held;
    _accounts.remove(siteUrl)?.retire();
    final account = _WriteAccount<T>(lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      final owned = identical(_accounts[siteUrl], account);
      if (owned) _accounts.remove(siteUrl);
      account.retire();
      if (owned && !isDisposed()) notify();
    });
    return account;
  }

  /// Sends one write about [subject] and answers whether the site took it.
  ///
  /// [onAccepted] runs under the account's lease before the state says done,
  /// so what it records is in place when listeners look.
  Future<bool> run(
    DiscourseInstance instance,
    T subject,
    Future<void> Function(AccountRequestCredentials request, String apiKey)
    send, {
    void Function()? onAccepted,
  }) async {
    if (isDisposed() || instance.user == null) return false;
    final siteUrl = instance.url;
    final account = _accountFor(siteUrl);
    if (account.write != null) return false;
    final write = Object();
    account.write = write;
    bool owns() => _owns(account, siteUrl) && identical(account.write, write);
    void publish(AccountWriteState<T> state) {
      if (!owns()) return;
      account.state = state;
      notify();
    }

    publish(AccountWriteBusy(subject));
    try {
      final request = await AccountRequestSession(
        siteUrl,
        account.lease,
      ).credentials(credentials);
      if (!owns()) return false;
      final apiKey = request.apiKey;
      if (apiKey == null) {
        publish(
          AccountWriteFailed(
            subject,
            const WriteException(WriteFailure.forbidden).message,
          ),
        );
        return false;
      }
      await request.run(() => send(request, apiKey));
      if (!owns()) return false;
      if (onAccepted != null) account.lease.commit(onAccepted);
      publish(AccountWriteDone(subject));
      return owns();
    } on WriteException catch (error) {
      publish(AccountWriteFailed(subject, error.message));
      return false;
    } on AccountRequestRetiredException {
      return false;
    } catch (_) {
      publish(
        AccountWriteFailed(
          subject,
          const WriteException(WriteFailure.unreachable).message,
        ),
      );
      return false;
    } finally {
      if (identical(account.write, write)) account.write = null;
    }
  }

  /// Returns a finished write to idle once its outcome no longer applies.
  void settle(String siteUrl) {
    final account = _existing(siteUrl);
    if (account == null || account.write != null) return;
    if (account.state is AccountWriteIdle<T>) return;
    account.state = AccountWriteIdle<T>();
    notify();
  }

  void retire(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    if (account == null) return;
    account.retire();
    if (!isDisposed()) notify();
  }

  void retireAll() {
    for (final account in _accounts.values.toList()) {
      account.retire();
    }
    _accounts.clear();
  }
}
