import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/serial_operation_queue.dart';
import '../data/site_lifecycle.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/user_preferences.dart';

typedef PreferencesSaved =
    void Function(
      String siteUrl,
      PreferenceSection section,
      UserPreferences preferences,
    );
typedef _PreferencesLane = ({String siteUrl, String accountIdentity});

@immutable
final class PreferencesState {
  const PreferencesState({
    required this.accountIdentity,
    required this.username,
    required this.host,
    this.draft,
    this.confirmed,
    this.loading = false,
    this.pendingWrites = 0,
    this.error,
    this.savedSection,
  });

  final String accountIdentity;
  final String username;
  final String host;
  final UserPreferences? draft;
  final UserPreferences? confirmed;
  final bool loading;
  final int pendingWrites;
  final String? error;
  final PreferenceSection? savedSection;

  bool get loaded => draft != null && confirmed != null;
  bool get saving => pendingWrites > 0;

  bool dirty(PreferenceSection section) {
    final draft = this.draft;
    final confirmed = this.confirmed;
    return draft != null &&
        confirmed != null &&
        !mapEquals(draft.payloadFor(section), confirmed.payloadFor(section));
  }

  PreferencesState copyWith({
    UserPreferences? draft,
    UserPreferences? confirmed,
    bool? loading,
    int? pendingWrites,
    Object? error = _unchanged,
    Object? savedSection = _unchanged,
  }) => PreferencesState(
    accountIdentity: accountIdentity,
    username: username,
    host: host,
    draft: draft ?? this.draft,
    confirmed: confirmed ?? this.confirmed,
    loading: loading ?? this.loading,
    pendingWrites: pendingWrites ?? this.pendingWrites,
    error: identical(error, _unchanged) ? this.error : error as String?,
    savedSection: identical(savedSection, _unchanged)
        ? this.savedSection
        : savedSection as PreferenceSection?,
  );

  static const Object _unchanged = Object();
}

final class PreferencesController extends FrameSafeNotifier {
  PreferencesController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.onSaved,
  });

  final UserPreferencesApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final PreferencesSaved? onSaved;

  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  final Map<String, _PreferenceAccountSession> _accounts = {};

  PreferencesState? stateFor(String? siteUrl) =>
      siteUrl == null ? null : _accounts[siteUrl]?.state;

  Future<void> load(DiscourseInstance instance, {bool refresh = false}) {
    if (isDisposed || !instance.isConnected) return Future<void>.value();
    final user = instance.user!;
    final identity = _accountIdentity(user.id, user.username);
    final held = _accounts[instance.url];
    if (held != null && held.state.accountIdentity != identity) {
      forget(instance.url);
    }
    final account = _accounts.putIfAbsent(
      instance.url,
      () => _PreferenceAccountSession(this, instance, identity),
    );
    return account.load(instance, refresh: refresh);
  }

  void edit(
    String siteUrl,
    PreferenceSection section,
    UserPreferences Function(UserPreferences current) change,
  ) {
    if (isDisposed) return;
    _accounts[siteUrl]?.edit(section, change);
  }

  Future<bool> save(DiscourseInstance instance, PreferenceSection section) {
    final account = _accountForSave(instance);
    return account == null
        ? Future.value(false)
        : account.section(section).save(instance);
  }

  /// Save changes in order, including a choice reversed while its write is
  /// pending. Each pass compares against the server-confirmed section.
  Future<void> saveAutomatically(
    DiscourseInstance instance,
    PreferenceSection section,
  ) {
    final account = _accountForSave(instance);
    return account == null
        ? Future.value()
        : account.section(section).saveAutomatically(instance);
  }

  _PreferenceAccountSession? _accountForSave(DiscourseInstance instance) {
    if (isDisposed || !instance.isConnected) return null;
    final account = _accounts[instance.url];
    return account?.state.accountIdentity ==
            _accountIdentity(instance.user!.id, instance.user!.username)
        ? account
        : null;
  }

  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    if (account != null && !isDisposed) notifySafely();
  }

  bool _isCurrent(_PreferenceAccountSession account) =>
      !isDisposed && identical(_accounts[account.siteUrl], account);

  void _notifySession(_PreferenceAccountSession account) {
    if (_isCurrent(account)) notifySafely();
  }

  static String _accountIdentity(int? id, String username) =>
      id == null ? 'username:${username.toLowerCase()}' : 'id:$id';

  static Map<String, Object?> _changedPayload(
    UserPreferences draft,
    UserPreferences confirmed,
    PreferenceSection section,
  ) {
    final before = confirmed.payloadFor(section);
    final after = draft.payloadFor(section);
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in after.entries)
        if (before[key] != value) key: value,
    });
  }

  static bool _canEditSection(
    UserPreferences preferences,
    PreferenceSection section,
  ) =>
      preferences.canEdit &&
      switch (section) {
        PreferenceSection.tracking => preferences.canChangeTrackingPreferences,
        _ => true,
      };

  static String _saveError(Object error, String host) {
    if (error case final WriteException write) {
      if (write.errors.isNotEmpty) return write.message;
      return switch (write.failure) {
        WriteFailure.forbidden => appL10n.reconnectToToUpdatePreferences(
          (host).toString(),
        ),
        WriteFailure.rateLimited => write.message,
        WriteFailure.validation => write.message,
        WriteFailure.conflict =>
          appL10n.thesePreferencesChangedElsewhereReloadAndTryAgain,
        WriteFailure.unreachable => appL10n.couldnTUpdatePreferencesOn(
          (host).toString(),
        ),
      };
    }
    return appL10n.couldnTUpdatePreferencesOn((host).toString());
  }

  @override
  void dispose() {
    _accounts.clear();
    super.dispose();
  }
}

final class _PreferenceAccountSession {
  _PreferenceAccountSession(
    this.owner,
    DiscourseInstance instance,
    String identity,
  ) : siteUrl = instance.url,
      state = PreferencesState(
        accountIdentity: identity,
        username: instance.user!.username,
        host: instance.host,
      );

  final PreferencesController owner;
  final String siteUrl;
  PreferencesState state;
  int editRevision = 0;
  int writeGeneration = 0;
  _PreferenceRead? _read;
  final Map<PreferenceSection, _PreferenceSectionTransaction> _sections = {};

  bool get isCurrent => owner._isCurrent(this);
  _PreferencesLane get lane =>
      (siteUrl: siteUrl, accountIdentity: state.accountIdentity);

  _PreferenceSectionTransaction section(PreferenceSection section) => _sections
      .putIfAbsent(section, () => _PreferenceSectionTransaction(this, section));

  void edit(
    PreferenceSection section,
    UserPreferences Function(UserPreferences current) change,
  ) {
    final draft = state.draft;
    if (draft == null ||
        !PreferencesController._canEditSection(draft, section)) {
      return;
    }
    final updated = change(draft);
    if (updated == draft) return;
    editRevision++;
    this.section(section).editRevision++;
    state = state.copyWith(draft: updated, error: null, savedSection: null);
    owner._notifySession(this);
  }

  Future<void> load(DiscourseInstance instance, {required bool refresh}) {
    if (!refresh && state.loaded) return Future.value();
    final active = _read;
    if (active != null) return active.completion.future;
    final read = _PreferenceRead(
      owner.lifecycle.capture(siteUrl),
      editRevision,
      writeGeneration,
    );
    _read = read;
    read.completion.complete(
      _load(instance, read).whenComplete(() {
        if (identical(_read, read)) _read = null;
      }),
    );
    return read.completion.future;
  }

  bool _ownsRead(_PreferenceRead read) =>
      isCurrent && read.lease.isCurrent && identical(_read, read);

  void _commitRead(_PreferenceRead read, PreferencesState Function() change) {
    if (!_ownsRead(read)) return;
    read.lease.commit(() {
      if (!_ownsRead(read)) return;
      state = change();
      owner._notifySession(this);
    });
  }

  Future<void> _load(DiscourseInstance instance, _PreferenceRead read) async {
    state = state.copyWith(loading: true, error: null, savedSection: null);
    owner._notifySession(this);
    if (!_ownsRead(read)) return;
    try {
      final credentials = await AccountRequestSession(
        siteUrl,
        read.lease,
      ).credentials(owner.credentials);
      if (!_ownsRead(read)) return;
      if (credentials.apiKey == null) {
        _commitRead(
          read,
          () => state.copyWith(
            loading: false,
            error: appL10n.reconnectToToLoadPreferences(
              instance.host.toString(),
            ),
          ),
        );
        return;
      }
      final preferences = await PreferencesController._operations.read(
        owner: owner.api,
        key: (lane: lane, session: read.lease.session),
        operation: () async {
          if (!_ownsRead(read)) return null;
          return credentials.run(
            () => owner.api.loadUserPreferences(
              siteUrl: siteUrl,
              apiKey: credentials.apiKey!,
              clientId: credentials.clientId,
              username: instance.user!.username,
            ),
          );
        },
      );
      if (preferences == null ||
          !_ownsRead(read) ||
          editRevision != read.editRevision ||
          writeGeneration != read.writeGeneration) {
        return;
      }
      _commitRead(
        read,
        () => state.copyWith(
          draft: preferences,
          confirmed: preferences,
          loading: false,
          error: preferences.canEdit
              ? null
              : appL10n.thisAccountIsNotAllowedToEditThesePreferences,
        ),
      );
    } catch (error) {
      if (!_ownsRead(read)) return;
      _commitRead(
        read,
        () => state.copyWith(
          loading: false,
          error: appL10n.couldnTLoadPreferencesFrom(instance.host.toString()),
        ),
      );
    } finally {
      if (isCurrent && identical(_read, read) && state.loading) {
        state = state.copyWith(loading: false);
        owner._notifySession(this);
      }
    }
  }
}

final class _PreferenceRead {
  _PreferenceRead(this.lease, this.editRevision, this.writeGeneration);

  final SiteLease lease;
  final int editRevision;
  final int writeGeneration;
  final Completer<void> completion = Completer<void>();
}

final class _PreferenceSectionTransaction {
  _PreferenceSectionTransaction(this.account, this.section);

  final _PreferenceAccountSession account;
  final PreferenceSection section;
  int editRevision = 0;
  _PreferenceWrite? _latestWrite;
  _AutomaticPreferenceSave? _automaticSave;

  bool _ownsWrite(_PreferenceWrite write) =>
      account.isCurrent &&
      write.lease.isCurrent &&
      identical(_latestWrite, write);

  Future<bool> save(DiscourseInstance instance) async {
    final state = account.state;
    final draft = state.draft;
    final confirmed = state.confirmed;
    if (!account.isCurrent ||
        draft == null ||
        confirmed == null ||
        !PreferencesController._canEditSection(draft, section) ||
        !state.dirty(section)) {
      return false;
    }
    final values = PreferencesController._changedPayload(
      draft,
      confirmed,
      section,
    );
    if (values.isEmpty) return false;
    final owner = account.owner;
    final write = _PreferenceWrite(
      owner.lifecycle.capture(account.siteUrl),
      editRevision,
    );
    _latestWrite = write;
    account.writeGeneration++;
    account.state = state.copyWith(
      pendingWrites: state.pendingWrites + 1,
      error: null,
      savedSection: null,
    );
    owner._notifySession(account);
    try {
      final updated = await PreferencesController._operations.write(
        owner: owner.api,
        key: (lane: account.lane, session: write.lease.session),
        operation: () async {
          if (!_ownsWrite(write)) return null;
          final credentials = await AccountRequestSession(
            account.siteUrl,
            write.lease,
          ).credentials(owner.credentials);
          if (!_ownsWrite(write)) return null;
          if (credentials.apiKey == null) {
            throw const WriteException(WriteFailure.forbidden);
          }
          return credentials.run(
            () => owner.api.updateUserPreferences(
              siteUrl: account.siteUrl,
              apiKey: credentials.apiKey!,
              clientId: credentials.clientId,
              username: state.username,
              fallback: draft,
              values: values,
            ),
          );
        },
      );
      if (updated == null || !_ownsWrite(write)) return false;
      final current = account.state;
      final sectionUnchanged = editRevision == write.editRevision;
      final mergedConfirmed = current.confirmed!.withSectionFrom(
        section,
        updated,
      );
      account.state = current.copyWith(
        confirmed: mergedConfirmed,
        draft: sectionUnchanged
            ? current.draft!.withSectionFrom(section, updated)
            : current.draft,
        savedSection: sectionUnchanged ? section : null,
        error: sectionUnchanged ? null : current.error,
      );
      if (sectionUnchanged) {
        owner.onSaved?.call(account.siteUrl, section, mergedConfirmed);
      }
      return sectionUnchanged;
    } catch (error) {
      if (!_ownsWrite(write)) return false;
      if (editRevision == write.editRevision) {
        account.state = account.state.copyWith(
          error: PreferencesController._saveError(error, instance.host),
          savedSection: null,
        );
      }
      return false;
    } finally {
      if (account.isCurrent && write.lease.isCurrent) {
        final current = account.state;
        account.state = current.copyWith(
          pendingWrites: current.pendingWrites > 0
              ? current.pendingWrites - 1
              : 0,
        );
        if (identical(_latestWrite, write)) _latestWrite = null;
        owner._notifySession(account);
      }
    }
  }

  Future<void> saveAutomatically(DiscourseInstance instance) {
    final lease = account.owner.lifecycle.capture(account.siteUrl);
    final pending = _automaticSave;
    if (pending != null && identical(pending.lease.session, lease.session)) {
      return pending.completion.future;
    }
    final automatic = _AutomaticPreferenceSave(lease);
    _automaticSave = automatic;
    automatic.completion.complete(() async {
      try {
        while (account.isCurrent &&
            lease.isCurrent &&
            account.state.draft != null &&
            PreferencesController._canEditSection(
              account.state.draft!,
              section,
            ) &&
            account.state.dirty(section)) {
          final saved = await save(instance);
          if (!saved &&
              (!account.isCurrent ||
                  !lease.isCurrent ||
                  account.state.error != null ||
                  account.state.draft?.canEdit != true)) {
            return;
          }
        }
      } finally {
        if (identical(_automaticSave, automatic)) _automaticSave = null;
      }
    }());
    return automatic.completion.future;
  }
}

final class _PreferenceWrite {
  _PreferenceWrite(this.lease, this.editRevision);

  final SiteLease lease;
  final int editRevision;
}

final class _AutomaticPreferenceSave {
  _AutomaticPreferenceSave(this.lease);

  final SiteLease lease;
  final Completer<void> completion = Completer<void>();
}
