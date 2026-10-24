import '../models/discourse_user.dart';
import '../plugin_api/discourse_model_codec.dart';
import '../plugin_api/plugin_data.dart';
import 'site_lifecycle.dart';

final class CurrentUserReconciler {
  CurrentUserReconciler({required this._lease, required this._models});

  final SiteLease _lease;
  final DiscourseModelCodec _models;
  int _presenceRevision = 0;
  int _doNotDisturbRevision = 0;
  int _groupedUnreadRevision = 0;
  int _draftCountRevision = 0;
  int _categoryPreferencesRevision = 0;
  int _pluginOptionsRevision = 0;
  bool _presenceWritePending = false;
  bool _retired = false;
  final Map<String, _PluginOptionUpdate> _pluginUpdates = {};

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
    _pluginUpdates[field] = (
      revision: ++_pluginOptionsRevision,
      update: update,
    );
    return previous.withPlugins(update(previous.plugins));
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
      var data = user.plugins;
      for (final write in _pluginUpdates.values) {
        if (write.revision > ticket._pluginOptionsRevision) {
          data = write.update(data);
        }
      }
      user = user.withPlugins(data);
    } else {
      _pluginUpdates.clear();
    }
    return CurrentUserReconciliation._(
      user: user,
      accountChanged: accountChanged,
      seedGroupedUnreadCounts: accountChanged || groupedUnreadIsCurrent,
    );
  }

  void retire() {
    _retired = true;
    _pluginUpdates.clear();
  }
}

final class CurrentUserSnapshot {
  CurrentUserSnapshot._(CurrentUserReconciler owner)
    : _owner = owner,
      _presenceRevision = owner._presenceRevision,
      _doNotDisturbRevision = owner._doNotDisturbRevision,
      _groupedUnreadRevision = owner._groupedUnreadRevision,
      _draftCountRevision = owner._draftCountRevision,
      _categoryPreferencesRevision = owner._categoryPreferencesRevision,
      _pluginOptionsRevision = owner._pluginOptionsRevision;

  final CurrentUserReconciler _owner;
  final int _presenceRevision;
  final int _doNotDisturbRevision;
  final int _groupedUnreadRevision;
  final int _draftCountRevision;
  final int _categoryPreferencesRevision;
  final int _pluginOptionsRevision;
}

final class CurrentUserReconciliation {
  const CurrentUserReconciliation._({
    required this.user,
    required this.accountChanged,
    required this.seedGroupedUnreadCounts,
  });

  final DiscourseUser user;
  final bool accountChanged;
  final bool seedGroupedUnreadCounts;
}

typedef _PluginOptionUpdate = ({
  int revision,
  PluginData Function(PluginData) update,
});
