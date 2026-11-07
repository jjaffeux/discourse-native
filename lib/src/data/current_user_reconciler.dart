import '../models/discourse_user.dart';
import '../models/user_preferences.dart';
import '../plugin_api/discourse_model_codec.dart';
import '../plugin_api/plugin_data.dart';
import 'site_lifecycle.dart';
import 'user_status_reconciler.dart';

final class CurrentUserReconciler {
  CurrentUserReconciler({
    required this._lease,
    required this._models,
    UserStatusReconciler? statuses,
  }) : statuses = statuses ?? UserStatusReconciler(capacity: 1024);

  final UserStatusReconciler statuses;

  final SiteLease _lease;
  final DiscourseModelCodec _models;
  int _presenceRevision = 0;
  int _doNotDisturbRevision = 0;
  int _groupedUnreadRevision = 0;
  int _draftCountRevision = 0;
  int _categoryPreferencesRevision = 0;
  int _confirmationRevision = 0;
  bool _presenceWritePending = false;
  bool _retired = false;
  final Map<String, _ConfirmedUserUpdate> _pluginUpdates = {};
  final Map<PreferenceSection, _ConfirmedUserUpdate> _preferenceUpdates = {};

  bool get isCurrent => !_retired && _lease.isCurrent;

  CurrentUserSnapshot beginSnapshot() => CurrentUserSnapshot._(this);

  void presenceWriteStarted() {
    _presenceWritePending = true;
    _presenceRevision++;
  }

  void presenceWriteSettled() {
    _presenceWritePending = false;
    _presenceRevision++;
  }

  void groupedUnreadChanged() => _groupedUnreadRevision++;

  void doNotDisturbChanged() => _doNotDisturbRevision++;

  void draftCountChanged() => _draftCountRevision++;

  CurrentUserSnapshot categoryPreferencesChanged() {
    _categoryPreferencesRevision++;
    return beginSnapshot();
  }

  DiscourseUser updatePluginOption(
    String field, {
    required DiscourseUser previous,
    required PluginData Function(PluginData) update,
  }) {
    if (!isCurrent) return previous;
    DiscourseUser project(DiscourseUser user) =>
        user.withPlugins(update(user.plugins));
    _pluginUpdates[field] = (
      revision: ++_confirmationRevision,
      update: project,
    );
    return project(previous);
  }

  /// Confirms the complete current-user effect of a saved preference section.
  /// The projection preserves fields the section does not mirror.
  DiscourseUser confirmPreferences(
    PreferenceSection section, {
    required DiscourseUser previous,
    required DiscourseUser Function(DiscourseUser) update,
  }) {
    if (!isCurrent) return previous;
    _preferenceUpdates[section] = (
      revision: ++_confirmationRevision,
      update: update,
    );
    return update(previous);
  }

  bool _accepts(CurrentUserSnapshot ticket) =>
      isCurrent && identical(ticket._owner, this);

  bool categoryPreferencesAreCurrent(CurrentUserSnapshot ticket) =>
      _accepts(ticket) &&
      ticket._categoryPreferencesRevision == _categoryPreferencesRevision;

  bool doNotDisturbIsCurrent(CurrentUserSnapshot ticket) =>
      _accepts(ticket) && ticket._doNotDisturbRevision == _doNotDisturbRevision;

  bool acceptsCategoryPreferences(
    CurrentUserSnapshot ticket, {
    required DiscourseUser? previous,
    required DiscourseUser incoming,
  }) =>
      categoryPreferencesAreCurrent(ticket) &&
      previous != null &&
      _models.sameCurrentUserAccount(previous, incoming);

  CurrentUserReconciliation? reconcile(
    CurrentUserSnapshot ticket, {
    required DiscourseUser? previous,
    required DiscourseUser incoming,
  }) {
    if (!_accepts(ticket)) return null;
    final accountChanged =
        previous != null && !_models.sameCurrentUserAccount(previous, incoming);
    final groupedUnreadIsCurrent =
        ticket._groupedUnreadRevision == _groupedUnreadRevision;
    var user = _models.preserveUnknownCurrentUser(previous, incoming);
    if (!accountChanged) {
      if (_presenceWritePending ||
          ticket._presenceRevision != _presenceRevision) {
        user = user.withHidePresence(previous?.hidePresence);
      }
      if (previous != null) {
        if (!groupedUnreadIsCurrent) {
          user = user.withGroupedUnreadNotifications(
            previous.groupedUnreadNotifications,
          );
        }
        if (ticket._draftCountRevision != _draftCountRevision) {
          user = user.withDraftCount(previous.draftCount);
        }
        if (!categoryPreferencesAreCurrent(ticket)) {
          user = user.withCategoryNotificationPreferences(
            trackedCategoryIds: previous.trackedCategoryIds,
            watchedCategoryIds: previous.watchedCategoryIds,
            watchedFirstPostCategoryIds: previous.watchedFirstPostCategoryIds,
            mutedCategoryIds: previous.mutedCategoryIds,
            indirectlyMutedCategoryIds: previous.indirectlyMutedCategoryIds,
          );
        }
      }
      final confirmations =
          [..._pluginUpdates.values, ..._preferenceUpdates.values]
              .where((write) => write.revision > ticket._confirmationRevision)
              .toList()
            ..sort((left, right) => left.revision.compareTo(right.revision));
      for (final write in confirmations) {
        user = write.update(user);
      }
    } else {
      _pluginUpdates.clear();
      _preferenceUpdates.clear();
    }
    final userId = user.id;
    var statusChanged = false;
    if (userId != null) {
      final status = statuses.acceptSnapshot(
        ticket._status,
        userId,
        user.status,
      );
      final fallback = accountChanged ? incoming.status : previous?.status;
      user = user.withStatus(
        status == null
            ? (statuses.contains(userId) ? statuses.read(userId) : fallback)
            : status.status,
      );
      statusChanged = status?.changed ?? false;
    }
    return CurrentUserReconciliation._(
      statusChanged: statusChanged,
      user: user,
      accountChanged: accountChanged,
      seedGroupedUnreadCounts: accountChanged || groupedUnreadIsCurrent,
    );
  }

  void retire() {
    _retired = true;
    _pluginUpdates.clear();
    _preferenceUpdates.clear();
  }
}

final class CurrentUserSnapshot {
  CurrentUserSnapshot._(CurrentUserReconciler owner)
    : _owner = owner,
      _status = owner.statuses.beginSnapshot(),
      _presenceRevision = owner._presenceRevision,
      _doNotDisturbRevision = owner._doNotDisturbRevision,
      _groupedUnreadRevision = owner._groupedUnreadRevision,
      _draftCountRevision = owner._draftCountRevision,
      _categoryPreferencesRevision = owner._categoryPreferencesRevision,
      _confirmationRevision = owner._confirmationRevision;

  final CurrentUserReconciler _owner;
  final UserStatusSnapshot _status;
  final int _presenceRevision;
  final int _doNotDisturbRevision;
  final int _groupedUnreadRevision;
  final int _draftCountRevision;
  final int _categoryPreferencesRevision;
  final int _confirmationRevision;
}

final class CurrentUserReconciliation {
  const CurrentUserReconciliation._({
    required this.user,
    required this.statusChanged,
    required this.accountChanged,
    required this.seedGroupedUnreadCounts,
  });

  final DiscourseUser user;
  final bool statusChanged;
  final bool accountChanged;
  final bool seedGroupedUnreadCounts;
}

typedef _ConfirmedUserUpdate = ({
  int revision,
  DiscourseUser Function(DiscourseUser) update,
});
