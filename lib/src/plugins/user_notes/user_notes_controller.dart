import 'dart:async';
import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';
import 'user_notes_api.dart';
import 'user_notes_data.dart';

const userNotesControllerService = PluginServiceKey<UserNotesController>(
  owner: userNotesPluginId,
  name: 'controller',
);

enum UserNotesReadStatus { loading, ready, failed, closed }

enum UserNotesFailure {
  network,
  malformed,
  forbidden,
  uncertain,
  blank,
  tooLong,
}

final class UserNotesController extends FrameSafeNotifier
    implements PluginCurrentUserObserver {
  UserNotesController({
    required this.api,
    required this.requests,
    required this.account,
    required this.site,
    required this.cooking,
    this.emoji,
  });
  final UserNotesApi api;
  final PluginRequestHost requests;
  final PluginFreshAccountHost account;
  final PluginSiteStateHost site;
  final PluginCookingHost cooking;
  final PluginEmojiHost? emoji;
  final _accounts = <String, _NotesAccount>{};
  final _settings = <String, (Listenable, VoidCallback)>{};
  final _denied = <String>{};
  bool _foreground = true;

  UserNotesSettings settings(String siteUrl) =>
      site.siteConfigFor(siteUrl).plugins.get(userNotesSettingsKey) ??
      const UserNotesSettings();
  bool canOpen(String siteUrl) =>
      !isDisposed &&
      !_denied.contains(siteUrl) &&
      settings(siteUrl).enabled &&
      account.profileFor(siteUrl)?.staff == true;

  void observe(String siteUrl) {
    if (isDisposed) return;
    if (!_settings.containsKey(siteUrl)) {
      final changes = site.siteConfigListenableFor?.call(siteUrl);
      if (changes != null) {
        void changed() {
          _denied.remove(siteUrl);
          if (!canOpen(siteUrl)) _clear(siteUrl);
          notifySafely();
        }

        changes.addListener(changed);
        _settings[siteUrl] = (changes, changed);
      }
    }
    if (!canOpen(siteUrl)) {
      _clear(siteUrl);
      return;
    }
    _currentAccount(siteUrl);
  }

  _NotesAccount _currentAccount(String siteUrl) {
    final held = _accounts[siteUrl];
    if (held != null && held.lease.isCurrent) return held;
    _clear(siteUrl);
    final current = _NotesAccount(requests.capture(siteUrl));
    _accounts[siteUrl] = current;
    current.detach = current.lease.onRetire(() {
      if (identical(_accounts[siteUrl], current)) {
        _clear(siteUrl);
        notifySafely();
      }
    });
    return current;
  }

  int? count(String siteUrl, int userId, {int? fallback}) {
    if (!canOpen(siteUrl)) return null;
    final state = _accounts[siteUrl];
    return state?.lease.isCurrent == true
        ? state!.counts[userId] ?? fallback
        : fallback;
  }

  UserNotesSession open({
    required String siteUrl,
    required int userId,
    String? username,
    int? postId,
  }) {
    observe(siteUrl);
    if (!canOpen(siteUrl) || userId == 0) {
      throw const WriteException(WriteFailure.forbidden);
    }
    final current = _currentAccount(siteUrl);
    final held = current.sessions[userId];
    if (held != null && held.isCurrent && held.postId == postId) {
      unawaited(held.refresh());
      return held;
    }
    held?.close();
    final session = UserNotesSession._(
      this,
      current,
      siteUrl,
      userId,
      username,
      postId,
    );
    current.sessions[userId] = session;
    unawaited(session.refresh());
    return session;
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    _denied.remove(siteUrl);
    if (!canOpen(siteUrl)) _clear(siteUrl);
    notifySafely();
  }

  void setForeground(bool foreground) {
    final returned = foreground && !_foreground;
    _foreground = foreground;
    if (returned) {
      for (final current in _accounts.values.toList()) {
        for (final session in current.sessions.values.toList()) {
          unawaited(session.refresh());
        }
      }
    }
  }

  void _deny(String siteUrl) {
    _denied.add(siteUrl);
    _clear(siteUrl);
    notifySafely();
  }

  void _clear(String siteUrl) {
    final current = _accounts.remove(siteUrl);
    if (current == null) return;
    current.detach?.call();
    current.counts.clear();
    for (final session in current.sessions.values.toList()) {
      session.close();
    }
    current.sessions.clear();
  }

  void forget(String siteUrl) {
    _clear(siteUrl);
    _denied.remove(siteUrl);
    final listener = _settings.remove(siteUrl);
    if (listener != null) listener.$1.removeListener(listener.$2);
    notifySafely();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    for (final siteUrl in {..._settings.keys, ..._accounts.keys}.toList()) {
      forget(siteUrl);
    }
    super.dispose();
  }
}

final class _NotesAccount {
  _NotesAccount(this.lease);
  final PluginSiteLease lease;
  VoidCallback? detach;
  final counts = <int, int>{};
  final sessions = <int, UserNotesSession>{};
}

final class UserNotesSession extends FrameSafeNotifier {
  UserNotesSession._(
    this.controller,
    this._account,
    this.siteUrl,
    this.userId,
    this.username,
    this.postId,
  );
  final UserNotesController controller;
  final _NotesAccount _account;
  final String siteUrl;
  final int userId;
  final int? postId;
  String? username;
  UserNotesReadStatus status = UserNotesReadStatus.loading;
  List<UserNote> notes = const [];
  UserNotesFailure? failure;
  String? serverError;
  bool writing = false;
  bool uncertain = false;
  int _revision = 0;
  Future<void>? _reading;
  final _abort = Completer<void>();
  Future<void> get aborted => _abort.future;
  bool get isCurrent =>
      status != UserNotesReadStatus.closed &&
      !controller.isDisposed &&
      _account.lease.isCurrent &&
      controller.canOpen(siteUrl) &&
      identical(controller._accounts[siteUrl], _account);
  int? get maximumLength => controller.settings(siteUrl).maximumLength;

  Future<void> refresh() {
    if (!isCurrent || writing) return Future.value();
    if (_reading case final pending?) return pending;
    final reading = Completer<void>();
    _reading = reading.future;
    reading.complete(_read().whenComplete(() => _reading = null));
    return reading.future;
  }

  Future<void> _read() async {
    final revision = ++_revision;
    status = UserNotesReadStatus.loading;
    failure = null;
    serverError = null;
    notifySafely();
    try {
      final credential = await controller.requests.credentialsFor(siteUrl);
      if (!isCurrent || revision != _revision) return;
      if (credential.apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final result = await credential.run(
        () => controller.api.list(
          siteUrl: siteUrl,
          userId: userId,
          credentials: credential,
        ),
      );
      if (!isCurrent || revision != _revision) return;
      _account.lease.commit(() {
        notes = result.notes;
        username = result.username;
        status = UserNotesReadStatus.ready;
        uncertain = false;
        _account.counts[userId] = notes.length;
        controller.notifySafely();
      });
    } catch (error) {
      if (!isCurrent || revision != _revision) return;
      if (_forbidden(error)) {
        controller._deny(siteUrl);
        return;
      }
      status = UserNotesReadStatus.failed;
      failure = error is FormatException
          ? UserNotesFailure.malformed
          : UserNotesFailure.network;
    } finally {
      if (isCurrent && revision == _revision) notifySafely();
    }
  }

  Future<bool> add(String raw) async {
    if (!isCurrent ||
        writing ||
        status != UserNotesReadStatus.ready ||
        uncertain) {
      return false;
    }
    if (raw.trim().isEmpty) {
      failure = UserNotesFailure.blank;
      notifySafely();
      return false;
    }
    if (maximumLength case final limit? when raw.runes.length > limit) {
      failure = UserNotesFailure.tooLong;
      notifySafely();
      return false;
    }
    return _write(() async {
      final credential = await _writeCredentials();
      if (credential == null) return;
      final result = await credential.run(
        () => controller.api.create(
          siteUrl: siteUrl,
          userId: userId,
          raw: raw,
          postId: postId,
          credentials: credential,
        ),
      );
      if (isCurrent) {
        notes = List.unmodifiable([
          result,
          ...notes.where((note) => note.id != result.id),
        ]);
      }
    }, creating: true);
  }

  Future<bool> remove(String noteId) async {
    if (!isCurrent ||
        writing ||
        status != UserNotesReadStatus.ready ||
        uncertain ||
        !notes.any((note) => note.id == noteId && note.canDelete)) {
      return false;
    }
    return _write(() async {
      final credential = await _writeCredentials();
      if (credential == null) return;
      await credential.run(
        () => controller.api.remove(
          siteUrl: siteUrl,
          userId: userId,
          noteId: noteId,
          credentials: credential,
        ),
      );
      if (isCurrent) {
        notes = List.unmodifiable(notes.where((note) => note.id != noteId));
      }
    });
  }

  Future<PluginRequestCredentials?> _writeCredentials() async {
    final result = await controller.requests.writeCredentialFor(siteUrl);
    if (!isCurrent) return null;
    if (result.failure != null) throw result.failure!;
    if (result.credentials?.apiKey == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    return result.credentials;
  }

  Future<bool> _write(
    Future<void> Function() operation, {
    bool creating = false,
  }) async {
    writing = true;
    failure = null;
    serverError = null;
    ++_revision;
    notifySafely();
    try {
      await operation();
      if (!isCurrent) return false;
      _account.lease.commit(() {
        _account.counts[userId] = notes.length;
        controller.notifySafely();
      });
      return true;
    } catch (error) {
      if (!isCurrent) return false;
      if (_forbidden(error)) {
        controller._deny(siteUrl);
        return false;
      }
      uncertain =
          creating &&
          !(error is WriteException &&
              (error.notSent ||
                  error.failure == WriteFailure.validation ||
                  error.failure == WriteFailure.rateLimited));
      failure = uncertain
          ? UserNotesFailure.uncertain
          : error is FormatException
          ? UserNotesFailure.malformed
          : UserNotesFailure.network;
      if (error is WriteException && error.errors.isNotEmpty) {
        serverError = error.errors.join('\n');
      }
      return false;
    } finally {
      writing = false;
      if (isCurrent) notifySafely();
    }
  }

  static bool _forbidden(Object error) => switch (error) {
    SiteLookupException(statusCode: 401 || 403 || 404) => true,
    WriteException(failure: WriteFailure.forbidden) => true,
    WriteException(statusCode: 401 || 403 || 404) => true,
    _ => false,
  };
  void close() {
    if (status == UserNotesReadStatus.closed) return;
    status = UserNotesReadStatus.closed;
    ++_revision;
    notes = const [];
    username = null;
    failure = null;
    serverError = null;
    if (!_abort.isCompleted) _abort.complete();
    if (identical(_account.sessions[userId], this)) {
      _account.sessions.remove(userId);
    }
    notifySafely();
  }
}
