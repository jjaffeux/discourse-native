import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/serial_operation_queue.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
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
typedef _PreferenceSave = ({_PreferencesLane lane, PreferenceSection section});

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

  final Map<String, PreferencesState> _states = {};
  final Map<String, Object> _loadRequests = {};
  final Map<String, Future<void>> _loadTasks = {};
  final Map<_PreferencesLane, int> _revisions = {};
  final Map<_PreferenceSave, int> _sectionRevisions = {};
  final Map<_PreferenceSave, Object> _latestSaves = {};

  PreferencesState? stateFor(String? siteUrl) =>
      siteUrl == null ? null : _states[siteUrl];

  Future<void> load(DiscourseInstance instance, {bool refresh = false}) {
    if (isDisposed || !instance.isConnected) return Future<void>.value();
    final user = instance.user!;
    final identity = _accountIdentity(user.id, user.username);
    final held = _states[instance.url];
    if (held != null && held.accountIdentity != identity) {
      forget(instance.url);
    }
    final current = _states[instance.url];
    if (!refresh && current?.loaded == true) return Future<void>.value();
    final active = _loadTasks[instance.url];
    if (active != null) return active;

    late final Future<void> task;
    task = _load(instance, identity).whenComplete(() {
      if (identical(_loadTasks[instance.url], task)) {
        final _ = _loadTasks.remove(instance.url);
      }
    });
    _loadTasks[instance.url] = task;
    return task;
  }

  Future<void> _load(DiscourseInstance instance, String identity) async {
    final siteUrl = instance.url;
    final lane = (siteUrl: siteUrl, accountIdentity: identity);
    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    final revision = _revisions[lane] ?? 0;
    _loadRequests[siteUrl] = request;
    _states[siteUrl] =
        (_states[siteUrl] ??
                PreferencesState(
                  accountIdentity: identity,
                  username: instance.user!.username,
                  host: instance.host,
                ))
            .copyWith(loading: true, error: null, savedSection: null);
    notifySafely();
    if (!_isCurrentLoad(lease, lane, request)) return;

    try {
      final session = await _readCredentials(lease, siteUrl);
      if (!_isCurrentLoad(lease, lane, request)) return;
      if (session == null) {
        _commitLoad(lease, lane, request, () {
          final state = _states[siteUrl]!;
          _states[siteUrl] = state.copyWith(
            loading: false,
            error: 'Reconnect to ${instance.host} to load preferences.',
          );
        });
        return;
      }

      final preferences = await _operations.read(
        owner: api,
        key: lane,
        operation: () => api.loadUserPreferences(
          siteUrl: siteUrl,
          apiKey: session.apiKey,
          clientId: session.clientId,
          username: instance.user!.username,
        ),
      );
      if (!_isCurrentLoad(lease, lane, request) ||
          (_revisions[lane] ?? 0) != revision) {
        return;
      }
      _commitLoad(lease, lane, request, () {
        final state = _states[siteUrl]!;
        _states[siteUrl] = state.copyWith(
          draft: preferences,
          confirmed: preferences,
          loading: false,
          error: preferences.canEdit
              ? null
              : 'This account is not allowed to edit these preferences.',
        );
      });
    } catch (error, stackTrace) {
      if (!_isCurrentLoad(lease, lane, request)) return;
      _report(error, stackTrace, 'preferences.load');
      _commitLoad(lease, lane, request, () {
        final state = _states[siteUrl]!;
        _states[siteUrl] = state.copyWith(
          loading: false,
          error: "Couldn't load preferences from ${instance.host}.",
        );
      });
    } finally {
      if (!isDisposed &&
          identical(_loadRequests[siteUrl], request) &&
          _states[siteUrl]?.accountIdentity == identity) {
        _loadRequests.remove(siteUrl);
        final state = _states[siteUrl];
        if (state != null && state.loading) {
          _states[siteUrl] = state.copyWith(loading: false);
          notifySafely();
        }
      }
    }
  }

  void edit(
    String siteUrl,
    PreferenceSection section,
    UserPreferences Function(UserPreferences current) change,
  ) {
    if (isDisposed) return;
    final state = _states[siteUrl];
    final draft = state?.draft;
    if (state == null || draft == null || !_canEditSection(draft, section)) {
      return;
    }
    final updated = change(draft);
    if (updated == draft) return;
    final lane = (siteUrl: siteUrl, accountIdentity: state.accountIdentity);
    _revisions[lane] = (_revisions[lane] ?? 0) + 1;
    final saveKey = (lane: lane, section: section);
    _sectionRevisions[saveKey] = (_sectionRevisions[saveKey] ?? 0) + 1;
    _states[siteUrl] = state.copyWith(
      draft: updated,
      error: null,
      savedSection: null,
    );
    notifySafely();
  }

  Future<bool> save(
    DiscourseInstance instance,
    PreferenceSection section,
  ) async {
    if (isDisposed || !instance.isConnected) return false;
    final state = _states[instance.url];
    final draft = state?.draft;
    final confirmed = state?.confirmed;
    if (state == null ||
        draft == null ||
        confirmed == null ||
        !_canEditSection(draft, section) ||
        !state.dirty(section)) {
      return false;
    }

    final lane = (
      siteUrl: instance.url,
      accountIdentity: state.accountIdentity,
    );
    final saveKey = (lane: lane, section: section);
    final request = Object();
    final lease = lifecycle.capture(instance.url);
    final sectionRevision = _sectionRevisions[saveKey] ?? 0;
    final values = _changedPayload(draft, confirmed, section);
    if (values.isEmpty) return false;

    _latestSaves[saveKey] = request;
    _states[instance.url] = state.copyWith(
      pendingWrites: state.pendingWrites + 1,
      error: null,
      savedSection: null,
    );
    notifySafely();
    try {
      final updated = await _operations.write(
        owner: api,
        key: lane,
        operation: () async {
          if (!_isCurrentSave(lease, saveKey, request)) return null;
          final session = await _readCredentials(lease, instance.url);
          if (!_isCurrentSave(lease, saveKey, request)) return null;
          if (session == null) {
            throw const WriteException(WriteFailure.forbidden);
          }
          return api.updateUserPreferences(
            siteUrl: instance.url,
            apiKey: session.apiKey,
            clientId: session.clientId,
            username: state.username,
            fallback: draft,
            values: values,
          );
        },
      );
      if (updated == null || !_isCurrentSave(lease, saveKey, request)) {
        return false;
      }

      final current = _states[instance.url]!;
      final sectionUnchanged =
          (_sectionRevisions[saveKey] ?? 0) == sectionRevision;
      final mergedConfirmed = current.confirmed!.withSectionFrom(
        section,
        updated,
      );
      _states[instance.url] = current.copyWith(
        confirmed: mergedConfirmed,
        draft: sectionUnchanged
            ? current.draft!.withSectionFrom(section, updated)
            : current.draft,
        savedSection:
            sectionUnchanged && identical(_latestSaves[saveKey], request)
            ? section
            : null,
        error: sectionUnchanged ? null : current.error,
      );
      if (sectionUnchanged) {
        onSaved?.call(instance.url, section, mergedConfirmed);
      }
      return sectionUnchanged;
    } catch (error, stackTrace) {
      if (!_isCurrentSave(lease, saveKey, request)) return false;
      _report(error, stackTrace, 'preferences.save');
      if ((_sectionRevisions[saveKey] ?? 0) == sectionRevision &&
          identical(_latestSaves[saveKey], request)) {
        final current = _states[instance.url]!;
        _states[instance.url] = current.copyWith(
          error: _saveError(error, instance.host),
          savedSection: null,
        );
      }
      return false;
    } finally {
      final current = _states[instance.url];
      if (!isDisposed &&
          current != null &&
          current.accountIdentity == lane.accountIdentity) {
        _states[instance.url] = current.copyWith(
          pendingWrites: current.pendingWrites > 0
              ? current.pendingWrites - 1
              : 0,
        );
        if (identical(_latestSaves[saveKey], request)) {
          _latestSaves.remove(saveKey);
        }
        notifySafely();
      }
    }
  }

  void forget(String siteUrl) {
    var changed = _states.remove(siteUrl) != null;
    changed = _loadRequests.remove(siteUrl) != null || changed;
    final _ = _loadTasks.remove(siteUrl);
    _revisions.removeWhere((lane, _) => lane.siteUrl == siteUrl);
    _sectionRevisions.removeWhere((save, _) => save.lane.siteUrl == siteUrl);
    _latestSaves.removeWhere((save, _) => save.lane.siteUrl == siteUrl);
    if (changed && !isDisposed) notifySafely();
  }

  Future<({String apiKey, String clientId})?> _readCredentials(
    SiteLease lease,
    String siteUrl,
  ) async {
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (isDisposed || !lease.isCurrent || apiKey == null) return null;
    final clientId = await credentials.clientId();
    if (isDisposed || !lease.isCurrent) return null;
    return (apiKey: apiKey, clientId: clientId);
  }

  bool _isCurrentLoad(SiteLease lease, _PreferencesLane lane, Object request) =>
      !isDisposed &&
      lease.isCurrent &&
      identical(_loadRequests[lane.siteUrl], request) &&
      _states[lane.siteUrl]?.accountIdentity == lane.accountIdentity;

  bool _isCurrentSave(SiteLease lease, _PreferenceSave save, Object request) =>
      !isDisposed &&
      lease.isCurrent &&
      _states[save.lane.siteUrl]?.accountIdentity ==
          save.lane.accountIdentity &&
      identical(_latestSaves[save], request);

  void _commitLoad(
    SiteLease lease,
    _PreferencesLane lane,
    Object request,
    VoidCallback mutation,
  ) {
    if (!_isCurrentLoad(lease, lane, request)) return;
    lease.commit(() {
      if (!_isCurrentLoad(lease, lane, request)) return;
      mutation();
      notifySafely();
    });
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
        WriteFailure.forbidden => 'Reconnect to $host to update preferences.',
        WriteFailure.rateLimited => write.message,
        WriteFailure.validation => write.message,
        WriteFailure.conflict =>
          'These preferences changed elsewhere. Reload and try again.',
        WriteFailure.unreachable => "Couldn't update preferences on $host.",
      };
    }
    return "Couldn't update preferences on $host.";
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'preferences',
      handled: true,
      degraded: true,
    );
  }

  @override
  void dispose() {
    _states.clear();
    _loadRequests.clear();
    _loadTasks.clear();
    _revisions.clear();
    _sectionRevisions.clear();
    _latestSaves.clear();
    super.dispose();
  }
}
