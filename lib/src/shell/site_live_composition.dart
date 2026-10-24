part of 'shell_controller.dart';

final class _ShellSiteLiveCurrentUsers implements SiteLiveCurrentUsers {
  _ShellSiteLiveCurrentUsers(this._shell);
  final ShellController _shell;

  @override
  DiscourseInstance? instanceAt(String siteUrl) => _shell._instanceAt(siteUrl);

  @override
  CurrentUserReconciler reconcilerFor(String siteUrl) =>
      _shell._currentUsers.reconcilerFor(siteUrl);

  @override
  DiscourseUser? acceptSnapshot(
    String siteUrl,
    DiscourseUser user,
    SiteLease lease,
    CurrentUserSnapshot ticket,
  ) => _shell._currentUsers.acceptSnapshot(siteUrl, user, lease, ticket);

  @override
  Future<int?> accountId(
    String siteUrl, {
    required String apiKey,
    required SiteLease lease,
  }) => _shell._accountId(siteUrl, apiKey: apiKey, lease: lease);
}

final class _ShellSiteLiveComposition implements SiteLiveComposition {
  _ShellSiteLiveComposition(this._shell);
  final ShellController _shell;

  @override
  void bootstrapReceived(String siteUrl, SiteMessageBusBootstrap bootstrap) {
    _shell._serverPluginNames[siteUrl] = bootstrap.serverPluginNames;
    _shell._notify();
  }

  @override
  void changed(String siteUrl, SiteLiveChange change) {
    if (_shell.currentInstance?.url != siteUrl) return;
    switch (change) {
      case SiteLiveChange.tracking:
        _shell._notify();
      case SiteLiveChange.incomingTopics:
        _shell._notifyLiveChange();
    }
  }

  @override
  void acceptMessage(
    String siteUrl,
    SiteLease lease,
    SiteLiveMessage kind,
    Object? data,
  ) {
    switch (kind) {
      case SiteLiveMessage.notifications:
        _shell._acceptLiveNotificationState(siteUrl, data, lease);
      case SiteLiveMessage.reviewableCounts:
        _shell.accountActivity.applyReviewableCounts(siteUrl, data);
      case SiteLiveMessage.userStatus:
        _shell._applyUserStatusMessage(siteUrl, data);
      case SiteLiveMessage.userDrafts:
        _shell._applyUserDraftsMessage(siteUrl, data);
      case SiteLiveMessage.doNotDisturb:
        _shell.doNotDisturb.applyMessage(siteUrl, data);
      case SiteLiveMessage.refreshSidebar:
        _shell._customSidebar.invalidate(siteUrl, account: lease);
    }
  }

  @override
  void trackIncomingLists(String siteUrl) =>
      _shell._trackIncomingLists(siteUrl);

  @override
  void synchronizeVisibleTopics(String siteUrl, SiteTracker tracker) =>
      _shell._syncTopicWatch(siteUrl, tracker);

  @override
  Iterable<SiteLivePluginAttachment> get pluginAttachments sync* {
    for (final owned
        in _shell._pluginSession.ownedCapabilities<PluginTrackerAttachment>()) {
      yield (
        attach: owned.capability.attachPluginTracker,
        scopes: _shell.plugins.liveChannelScopesFor(owned.owner),
      );
    }
  }
}
