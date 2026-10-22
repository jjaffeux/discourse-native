part of 'chat_controller.dart';

final class _ChatChannelDirectory {
  _ChatChannelDirectory({
    required this.siteUrl,
    required this.lease,
    required this.api,
    required this.requests,
    required this.store,
    required this.liveSync,
    required this.currentUserFor,
    required this.onChanged,

    required this.onChatNotificationsDelta,
    required this.hasThreads,
    required this.replaceHasThreads,
    required this.advanceLastViewedAt,
  });

  final String siteUrl;
  final PluginSiteLease lease;
  final ChatApi api;
  final PluginRequestHost requests;
  final Store store;
  final ChatLiveSyncCoordinator liveSync;
  final DiscourseUser? Function(String) currentUserFor;
  final void Function() onChanged;

  final ChatNotificationsDelta? onChatNotificationsDelta;
  final bool Function() hasThreads;
  final void Function(bool, bool) replaceHasThreads;
  final void Function(int) advanceLastViewedAt;
  final Map<int, _ChatChannelDirectoryEntry> _channels = {};

  _ChatChannelDirectoryEntry _entry(int id) =>
      _channels.putIfAbsent(id, _ChatChannelDirectoryEntry.new);

  void _releaseIdleEntry(int channelId) {
    if (_channels[channelId]?.idle == true) _channels.remove(channelId);
  }

  bool _retired = false;
  bool get isCurrent => !_retired && lease.isCurrent;
  bool get isDisposed => !isCurrent;
  bool get hasSnapshot => _publicIds != null;

  List<int>? _publicIds;
  List<int>? _directIds;
  final Set<int> _partialChannelIds = {};
  ChatChannelRefresh? _refresh;
  Future<void>? _loadRequest;
  Object? _loadRun;
  bool _loading = false;
  bool _revalidating = false;
  int _attempts = 0;
  String? _error;

  bool _requestIsCurrent(PluginSiteLease lease, bool Function() ownsRequest) =>
      isCurrent && lease.isCurrent && ownsRequest();

  bool isListed(int channelId) =>
      (_publicIds?.contains(channelId) ?? false) ||
      (_directIds?.contains(channelId) ?? false);

  bool hasWrite(int channelId) =>
      (_channels[channelId]?.starWrite != null) ||
      (_channels[channelId]?.notificationWrite != null) ||
      (_channels[channelId]?.followWrite != null) ||
      (_channels[channelId]?.settingsWrite != null);

  void recordTrackingState(ChatChannel channel) =>
      _refresh?.recordTrackingState(channel);
  void recordMetadataEdit(int channelId) {
    _channels[channelId]?.settingsWrite?.receivedMetadata = true;
  }

  void recordStatusEdit(int channelId) {
    _channels[channelId]?.settingsWrite?.receivedStatus = true;
  }

  void resolvePartial(int channelId) => _partialChannelIds.remove(channelId);
  void hydratePartialIfMissing(ChatChannel incoming) {
    if (channel(incoming.id) != null) return;
    store.put(siteUrl, incoming);
    _partialChannelIds.add(incoming.id);
  }

  void revokeChannel(int channelId) {
    _refresh?.removeChannel(channelId);
    _publishListedNotificationChange(() {
      _publicIds?.remove(channelId);
      _directIds?.remove(channelId);
    });
    _partialChannelIds.remove(channelId);
    _channels[channelId]?.detailRun = null;
    _channels[channelId]?.detailRequest = null;
    _channels[channelId]?.messageResume = null;
    _releaseIdleEntry(channelId);
  }

  void retire() {
    _retired = true;
    _channels.clear();
    _refresh = null;
    _loadRequest = null;
    _loadRun = null;
  }

  List<ChatChannel> publicChannels() => _resolve(_publicIds);

  List<ChatChannel> directChannels() => _resolve(_directIds);

  List<ChatChannel> activitySortedPublicChannels() {
    final channels = [...publicChannels()];
    final originalPositions = <int, int>{};
    for (final channel in channels) {
      originalPositions[channel.id] = originalPositions.length;
    }
    final unreadCounts = Map<ChatChannel, int>.identity();
    int unread(ChatChannel channel) => unreadCounts.putIfAbsent(
      channel,
      () =>
          channel.tracking.unreadCount +
          channel.unreadThreadsCountSinceLastViewed,
    );
    channels.sort((a, b) {
      int urgent(ChatChannel channel) =>
          channel.tracking.mentionCount +
          channel.tracking.watchedThreadsUnreadCount;
      int bySlug(ChatChannel first, ChatChannel second) {
        final compared = (first.slug ?? first.title).toLowerCase().compareTo(
          (second.slug ?? second.title).toLowerCase(),
        );
        return compared != 0
            ? compared
            : originalPositions[first.id]!.compareTo(
                originalPositions[second.id]!,
              );
      }

      final aUrgent = urgent(a);
      final bUrgent = urgent(b);
      if (aUrgent > 0 && bUrgent > 0) return bySlug(a, b);
      if ((aUrgent > 0) != (bUrgent > 0)) return aUrgent > 0 ? -1 : 1;

      final aUnread = unread(a);
      final bUnread = unread(b);
      if (aUnread > 0 && bUnread > 0) return bySlug(a, b);
      if ((aUnread > 0) != (bUnread > 0)) return aUnread > 0 ? -1 : 1;
      return bySlug(a, b);
    });
    return List.unmodifiable(channels);
  }

  bool channelsLoaded() => _publicIds != null && _directIds != null;

  bool channelsLoading() {
    return _loading && !_revalidating;
  }

  bool channelStarWriteInFlight(int channelId) =>
      (_channels[channelId]?.starWrite != null);

  bool channelNotificationWriteInFlight(int channelId) =>
      (_channels[channelId]?.notificationWrite != null);

  Future<String?> updateChannelStarred(int channelId, bool starred) async {
    if (isDisposed || channelId <= 0) {
      return appL10n.thisChannelCanNoLongerBeChanged;
    }
    final held = channel(channelId);
    if (held == null || !held.membership.following) {
      return appL10n.onlyFollowedChannelsCanBeStarred;
    }
    if (held.membership.starred == starred) return null;

    final key = channelId;
    if (_channels[key]?.starWrite != null) {
      return appL10n.anotherChannelChangeIsStillFinishing;
    }
    final token = Object();
    final lease = this.lease;
    _entry(key).starWrite = token;

    bool isCurrentRequest() =>
        identical(_channels[key]?.starWrite, token) &&
        lease.isCurrent &&
        isCurrent;

    void projectStarred(bool starred) {
      lease.commit(() {
        final current = channel(channelId) ?? held;
        _putChannel(current.withStarred(starred));
        onChanged();
      });
    }

    projectStarred(starred);
    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrentRequest()) return null;
      if (apiKey == null) {
        projectStarred(held.membership.starred);
        return appL10n.reconnectThisSiteToChangeTheChannel;
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrentRequest()) return null;
      await requestCredentials.run(
        () => api.updateChatChannelStarred(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          starred: starred,
          clientId: clientId,
        ),
      );
      return null;
    } on WriteException catch (error) {
      if (isCurrentRequest()) projectStarred(held.membership.starred);
      return error.message;
    } catch (error) {
      if (isCurrentRequest()) {
        projectStarred(held.membership.starred);
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channels[key]?.starWrite, token)) {
        _channels[key]?.starWrite = null;
        _releaseIdleEntry(key);
      }
      if (isCurrent) onChanged();
    }
  }

  Future<String?> updateChannelNotifications(
    int channelId, {
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
  }) async {
    if (isDisposed || channelId <= 0) {
      return appL10n.thisChannelCanNoLongerBeChanged;
    }
    if (muted == null && notificationLevel == null) {
      return appL10n.chooseAChannelNotificationSettingToChange;
    }
    final held = channel(channelId);
    if (held == null || !held.membership.following) {
      return appL10n.onlyFollowedChannelsHaveNotificationSettings;
    }
    final projectedMembership = held.membership.withNotifications(
      muted: muted,
      notificationLevel: notificationLevel,
    );
    if (projectedMembership == held.membership) return null;

    final key = channelId;
    if (_channels[key]?.notificationWrite != null) {
      return appL10n.anotherNotificationChangeIsStillFinishing;
    }
    final token = Object();
    final lease = this.lease;
    _entry(key).notificationWrite = token;

    bool isCurrentRequest() =>
        identical(_channels[key]?.notificationWrite, token) &&
        lease.isCurrent &&
        isCurrent;

    // This write owns only muting and the push level. A read, star, or pin
    // view that lands while the request is in flight stays on the live
    // membership: the server's answer carries cursors older than a read that
    // happened locally meanwhile, and the rollback must not undo a
    // concurrent optimistic star. Muting changes how the channel counts, so
    // the projection, the server's answer and a rollback each publish their
    // own counter change. Each also moves the channel's new-messages stream
    // with its muting; restarting it needs fresh cursors, so that waits for a
    // [settled] membership, the server's answer or a rollback to its state.
    final changesMuting = held.membership.muted || projectedMembership.muted;
    void project(ChatMembership source, {bool settled = true}) {
      lease.commit(() {
        final current = channel(channelId) ?? held;
        final next = current.withMembership(
          current.membership.withNotifications(
            muted: source.muted,
            notificationLevel: source.notificationLevel,
          ),
        );
        _publishListedNotificationChange(() => _putChannel(next));
        if (next.membership.muted) {
          _channels[key]?.messageResume = null;
          _releaseIdleEntry(key);
          liveSync.muteChannel(siteUrl, channelId);
        } else if (settled && changesMuting) {
          _resumeChannelMessages(channelId);
        }
        onChanged();
      });
    }

    project(projectedMembership, settled: false);
    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrentRequest()) return null;
      if (apiKey == null) {
        project(held.membership);
        return appL10n.reconnectThisSiteToChangeChannelNotifications;
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrentRequest()) return null;
      final membership = await requestCredentials.run(
        () => api.updateChatChannelNotifications(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          muted: muted,
          notificationLevel: notificationLevel,
          clientId: clientId,
        ),
      );
      if (isCurrentRequest()) project(membership);
      return null;
    } on WriteException catch (error) {
      if (isCurrentRequest()) project(held.membership);
      return error.message;
    } catch (error) {
      if (isCurrentRequest()) {
        project(held.membership);
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channels[key]?.notificationWrite, token)) {
        _channels[key]?.notificationWrite = null;
        _releaseIdleEntry(key);
      }
      if (isCurrent) onChanged();
    }
  }

  // Channel detail supplies fresh bus cursors after muting stops the stream.
  // It omits tracking, which is reconciled by the next channel-list snapshot.
  void _resumeChannelMessages(int channelId) {
    if (liveSync.ownsChannelMessages(siteUrl, channelId)) return;
    final key = channelId;
    final run = Object();
    _entry(key).messageResume = run;
    final lease = this.lease;
    bool isCurrentRequest() => _requestIsCurrent(
      lease,
      () => identical(_channels[key]?.messageResume, run),
    );

    Future<void> resume() async {
      try {
        final requestCredentials = await requests.credentialsFor(siteUrl);
        final apiKey = requestCredentials.apiKey;
        if (!isCurrentRequest() || apiKey == null) return;
        final clientId = requestCredentials.clientId;
        if (!isCurrentRequest()) return;
        final fresh = await requestCredentials.run(
          () => api.chatChannel(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            channelId: channelId,
          ),
        );
        if (!isCurrentRequest() || fresh.id != channelId) return;
        lease.commit(() {
          final membership = channel(channelId)?.membership;
          if (membership == null || !membership.following || membership.muted) {
            return;
          }
          liveSync.unmuteChannel(siteUrl, fresh);
        });
      } catch (error) {
      } finally {
        if (identical(_channels[key]?.messageResume, run)) {
          _channels[key]?.messageResume = null;
          _releaseIdleEntry(key);
        }
      }
    }

    unawaited(resume());
  }

  Future<ChatChannelMembersResult> fetchChannelMembers(
    int channelId, {
    String username = '',
    int offset = 0,
    int limit = 20,
  }) async {
    if (isDisposed || channelId <= 0) {
      return (page: null, error: appL10n.thisMemberListIsNoLongerAvailable);
    }
    final held = channel(channelId);
    if (held == null || !held.membership.following) {
      return (page: null, error: appL10n.onlyFollowedChannelsShowTheirMembers);
    }
    final lease = this.lease;
    bool isCurrentRequest() => isCurrent && lease.isCurrent;
    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrentRequest()) return (page: null, error: null);
      if (apiKey == null) {
        return (
          page: null,
          error: appL10n.reconnectThisSiteToSeeChannelMembers,
        );
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrentRequest()) return (page: null, error: null);
      final page = await requestCredentials.run(
        () => api.chatChannelMembers(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          username: username,
          offset: offset,
          limit: limit,
          clientId: clientId,
        ),
      );
      return isCurrentRequest()
          ? (page: page, error: null)
          : (page: null, error: null);
    } on SiteLookupException catch (error) {
      return (page: null, error: error.message);
    } catch (error) {
      return (page: null, error: appL10n.couldnTLoadThisChannelSMembers);
    }
  }

  Future<ChatChannelBrowseResult> fetchBrowseChannels({
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
  }) async {
    if (isDisposed) {
      return (
        page: null,
        error: appL10n.theChannelDirectoryIsNoLongerAvailable,
      );
    }
    final lease = this.lease;
    bool isCurrentRequest() => isCurrent && lease.isCurrent;
    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrentRequest()) return (page: null, error: null);
      if (apiKey == null) {
        return (
          page: null,
          error: appL10n.reconnectThisSiteToBrowseChatChannels,
        );
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrentRequest()) return (page: null, error: null);
      final page = await requestCredentials.run(
        () => api.browseChatChannels(
          siteUrl: siteUrl,
          apiKey: apiKey,
          filter: filter,
          status: status,
          offset: offset,
          limit: limit,
          clientId: clientId,
        ),
      );
      return isCurrentRequest()
          ? (page: page, error: null)
          : (page: null, error: null);
    } on SiteLookupException catch (error) {
      return (page: null, error: error.message);
    } catch (error) {
      return (page: null, error: appL10n.couldnTLoadChatChannels);
    }
  }

  bool channelFollowWriteInFlight(int channelId) =>
      (_channels[channelId]?.followWrite != null);

  bool channelSettingsWriteInFlight(int channelId) =>
      (_channels[channelId]?.settingsWrite != null);

  bool canEditChannelMetadata(int channelId) {
    final held = channel(channelId);
    return currentUserFor(siteUrl)?.staff == true &&
        held?.isCategoryChannel == true &&
        held!.membership.following;
  }

  Future<String?> updateChannelMetadata(
    int channelId, {
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
  }) async {
    final held = channel(channelId);
    if (held == null || !canEditChannelMetadata(channelId)) {
      return appL10n.thisChannelCannotBeEdited;
    }
    if (name == null &&
        slug == null &&
        description == null &&
        threadingEnabled == null) {
      return null;
    }
    if (slug != null && (slug.trim().isEmpty || slug.trim().length > 100)) {
      return appL10n.theChannelSlugMustBeBetween1And100Characters;
    }
    if (description != null &&
        description.runes.length > ChatChannel.maxDescriptionLength) {
      return appL10n.theChannelDescriptionCannotExceed500Characters;
    }
    final nextName = name?.trim();
    final nextSlug = slug?.trim();
    final nameChanged = name != null && nextName != held.title;
    final slugChanged = slug != null && nextSlug != held.slug;
    final descriptionChanged =
        description != null && description != held.description;
    final threadingChanged =
        threadingEnabled != null && threadingEnabled != held.threadingEnabled;
    if (!nameChanged &&
        !slugChanged &&
        !descriptionChanged &&
        !threadingChanged) {
      return null;
    }

    final key = channelId;
    if (_channels[key]?.settingsWrite != null) {
      return appL10n.anotherChannelChangeIsStillFinishing;
    }
    final token = _ChannelSettingsWrite();
    final lease = this.lease;
    _entry(key).settingsWrite = token;
    bool isCurrentRequest() =>
        identical(_channels[key]?.settingsWrite, token) &&
        lease.isCurrent &&
        isCurrent;
    if (threadingChanged) {
      _putChannel(held.withThreadingEnabled(threadingEnabled));
    }
    onChanged();

    void restoreThreading() {
      if (!threadingChanged || !isCurrentRequest()) return;
      lease.commit(() {
        final current = channel(channelId);
        if (current != null) {
          _putChannel(current.withThreadingEnabled(held.threadingEnabled));
        }
        onChanged();
      });
    }

    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrentRequest()) return null;
      if (apiKey == null) {
        restoreThreading();
        return appL10n.reconnectThisSiteToEditTheChannel;
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrentRequest()) return null;
      token.receivedMetadata = false;
      final fresh = await requestCredentials.run(
        () => api.updateChatChannel(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          name: name == null ? null : nextName,
          slug: nextSlug,
          description: description,
          threadingEnabled: threadingEnabled,
          clientId: clientId,
        ),
      );
      if (!isCurrentRequest()) return null;
      lease.commit(() {
        final current = channel(channelId);
        if (current != null && fresh.id == current.id) {
          // PUT returns a full serializer, but only submitted settings belong
          // to this write. Preserve conflicting live edits; our own event echo
          // still accepts normalization such as unicode_title from the response.
          bool acceptsText(String? submitted, String? currentValue) =>
              submitted != null &&
              (!token.receivedMetadata || submitted == currentValue);

          var next = current.withRemoteMetadata(
            title: acceptsText(nextName, current.title)
                ? fresh.title
                : current.title,
            slug: acceptsText(nextSlug, current.slug)
                ? fresh.slug
                : current.slug,
            description: acceptsText(description, current.description)
                ? fresh.description
                : current.description,
          );
          // /chat/channel-edits does not carry threading_enabled.
          if (threadingEnabled != null) {
            next = next.withThreadingEnabled(fresh.threadingEnabled);
          }
          _putChannel(next);
        }
        onChanged();
      });
      return null;
    } on WriteException catch (error) {
      restoreThreading();
      return error.message;
    } catch (error) {
      restoreThreading();

      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channels[key]?.settingsWrite, token)) {
        _channels[key]?.settingsWrite = null;
        _releaseIdleEntry(key);
        if (isCurrent) onChanged();
      }
    }
  }

  Future<String?> updateChannelThreading(int channelId, bool enabled) {
    final held = channel(channelId);
    if (held == null ||
        !canEditChannelMetadata(channelId) ||
        held.status != ChatChannelStatus.open) {
      return Future.value(appL10n.searchThreadingCannotBeChanged);
    }
    return updateChannelMetadata(channelId, threadingEnabled: enabled);
  }

  bool canChangeChannelStatus(int channelId) {
    final held = channel(channelId);
    return currentUserFor(siteUrl)?.staff == true &&
        held?.isCategoryChannel == true &&
        held!.membership.following &&
        (held.status == ChatChannelStatus.open ||
            held.status == ChatChannelStatus.closed);
  }

  Future<String?> setChannelClosed(
    int channelId, {
    required bool closed,
  }) async {
    final held = channel(channelId);
    final target = closed ? ChatChannelStatus.closed : ChatChannelStatus.open;
    if (held == null || !canChangeChannelStatus(channelId)) {
      return appL10n.thisChannelSStatusCannotBeChanged;
    }
    if (held.status == target) return null;
    if ((closed && held.status != ChatChannelStatus.open) ||
        (!closed && held.status != ChatChannelStatus.closed)) {
      return appL10n.thisChannelSStatusCannotBeChanged;
    }

    final key = channelId;
    if (_channels[key]?.settingsWrite != null) {
      return appL10n.anotherChannelChangeIsStillFinishing;
    }
    final token = _ChannelSettingsWrite();
    final lease = this.lease;
    _entry(key).settingsWrite = token;
    bool isCurrentRequest() =>
        identical(_channels[key]?.settingsWrite, token) &&
        lease.isCurrent &&
        isCurrent;
    onChanged();

    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrentRequest()) return null;
      if (apiKey == null) return appL10n.reconnectThisSiteToChangeTheChannel;
      final clientId = requestCredentials.clientId;
      if (!isCurrentRequest()) return null;
      token.receivedStatus = false;
      final fresh = await requestCredentials.run(
        () => api.updateChatChannelStatus(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          status: target,
          clientId: clientId,
        ),
      );
      if (!isCurrentRequest()) return null;
      lease.commit(() {
        final current = channel(channelId);
        if (current != null &&
            fresh.id == current.id &&
            !token.receivedStatus) {
          _publishListedNotificationChange(
            () => _putChannel(current.withRemoteStatus(fresh.status)),
          );
        }
        onChanged();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channels[key]?.settingsWrite, token)) {
        _channels[key]?.settingsWrite = null;
        _releaseIdleEntry(key);
        if (isCurrent) onChanged();
      }
    }
  }

  Future<String?> updateChannelFollowing(
    ChatChannel candidate,
    bool following,
  ) async {
    if (isDisposed || candidate.id <= 0) {
      return appL10n.thisChannelCanNoLongerBeChanged;
    }
    final held = channel(candidate.id) ?? candidate;
    if (held.isDirectMessage && following) {
      return appL10n.directMessagesCannotBeJoinedFromBrowseChannels;
    }
    if (held.membership.following == following) return null;
    if (following && (!held.canJoin || held.status != ChatChannelStatus.open)) {
      return appL10n.thisChannelCannotBeJoined;
    }

    final key = held.id;
    if (_channels[key]?.followWrite != null) {
      return appL10n.anotherChannelChangeIsStillFinishing;
    }
    final token = Object();
    final lease = this.lease;
    _entry(key).followWrite = token;

    bool isCurrentRequest() =>
        identical(_channels[key]?.followWrite, token) &&
        lease.isCurrent &&
        isCurrent;

    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrentRequest()) return null;
      if (apiKey == null) {
        return appL10n.reconnectThisSiteToChangeTheChannel;
      }
      final clientId = requestCredentials.clientId;
      if (!isCurrentRequest()) return null;
      final membership = following
          ? await requestCredentials.run(
              () => api.followChatChannel(
                siteUrl: siteUrl,
                apiKey: apiKey,
                channelId: held.id,
                clientId: clientId,
              ),
            )
          : await requestCredentials.run(
              () => api.unfollowChatChannel(
                siteUrl: siteUrl,
                apiKey: apiKey,
                channelId: held.id,
                clientId: clientId,
              ),
            );
      if (!isCurrentRequest()) return null;

      lease.commit(() {
        final current = channel(held.id) ?? held;
        final changed = membership.following != current.membership.following;
        final memberDelta = current.isDirectMessage || !changed
            ? 0
            : membership.following
            ? 1
            : -1;
        final next = current.withMembership(
          membership,
          membershipsCount: current.membershipsCount + memberDelta,
        );
        _publishListedNotificationChange(() {
          _putChannel(next);
          final ids = next.isDirectMessage
              ? (_directIds ??= [])
              : (_publicIds ??= []);
          if (!membership.following) {
            ids.remove(next.id);
            return;
          }
          if (!ids.contains(next.id)) ids.add(next.id);
          if (!next.isDirectMessage) {
            ids.sort((left, right) {
              final a = channel(left);
              final b = channel(right);
              return (a?.slug ?? a?.title ?? '').toLowerCase().compareTo(
                (b?.slug ?? b?.title ?? '').toLowerCase(),
              );
            });
          }
        });
        if (membership.following) {
          liveSync.adoptChannel(siteUrl, next, includeActivity: true);
        } else {
          liveSync.stopFollowingChannel(siteUrl, next.id);
        }
        onChanged();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_channels[key]?.followWrite, token)) {
        _channels[key]?.followWrite = null;
        _releaseIdleEntry(key);
      }
      if (isCurrent) onChanged();
    }
  }

  Future<ChatChannel?> createDirectMessageChannel({
    required Iterable<String> usernames,
    Iterable<String> groups = const [],
    String? name,
    bool upsert = false,
  }) async {
    final targets = <String>{
      for (final username in usernames)
        if (username.trim().isNotEmpty) username.trim(),
    }.toList(growable: false);
    final targetGroups = <String>{
      for (final group in groups)
        if (group.trim().isNotEmpty) group.trim(),
    }.toList(growable: false);
    final channelName = switch (name?.trim()) {
      final value? when value.isNotEmpty => value,
      _ => null,
    };
    if (isDisposed || targets.isEmpty && targetGroups.isEmpty) return null;
    final lease = this.lease;

    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (isDisposed || !lease.isCurrent) return null;
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final clientId = requestCredentials.clientId;
      if (isDisposed || !lease.isCurrent) return null;
      var channel = await requestCredentials.run(
        () => api.createChatDirectMessageChannel(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          usernames: targets,
          groups: targetGroups,
          name: channelName,
          upsert: upsert,
        ),
      );
      if (isDisposed || !lease.isCurrent || channel.id <= 0) return null;

      // Creation omits current_user_membership, including when upserting an
      // existing DM. Following returns the membership required for reactions.
      if (!channel.membership.following) {
        final membership = await requestCredentials.run(
          () => api.followChatChannel(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            channelId: channel.id,
          ),
        );
        if (isDisposed || !lease.isCurrent) return null;
        channel = channel.withMembership(membership);
      }

      lease.commit(() {
        channel =
            this.channel(channel.id)?.withServerSettings(channel) ?? channel;
        _publishListedNotificationChange(() {
          _putChannel(channel);
          final direct = _directIds ?? const <int>[];
          _directIds = [
            channel.id,
            for (final id in direct)
              if (id != channel.id) id,
          ];
        });
        liveSync.adoptChannel(siteUrl, channel, includeActivity: true);
        onChanged();
      });
      return channel;
    } catch (error) {
      rethrow;
    }
  }

  Future<ChatDirectMessageSearchResults> searchDirectMessages(
    String term, {
    bool includeGroups = false,
    bool includeDirectMessageChannels = true,
    bool includeCategoryChannels = false,
  }) async {
    final query = term.trim();
    if (isDisposed || query.isEmpty) {
      return ChatDirectMessageSearchResults(const []);
    }
    final lease = this.lease;
    final requestCredentials = await requests.credentialsFor(siteUrl);
    final apiKey = requestCredentials.apiKey;
    if (isDisposed || !lease.isCurrent) {
      return ChatDirectMessageSearchResults(const []);
    }
    if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
    final result = await requestCredentials.run(
      () => api.searchChatDirectMessages(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: requestCredentials.clientId,
        term: query,
        includeGroups: includeGroups,
        includeDirectMessageChannels: includeDirectMessageChannels,
        includeCategoryChannels: includeCategoryChannels,
      ),
    );
    if (isDisposed || !lease.isCurrent) {
      return ChatDirectMessageSearchResults(const []);
    }

    lease.commit(() {
      final listed = _directIds;
      var sidebarChanged = false;
      _publishListedNotificationChange(() {
        for (final item in result.items) {
          if (item case ChatDirectMessageChannel(:final channel)) {
            final held = store.read<ChatChannel>(siteUrl, channel.id);
            store.put(siteUrl, held?.withServerSettings(channel) ?? channel);
            if (listed != null &&
                channel.isDirectMessage &&
                channel.membership.following &&
                !listed.contains(channel.id)) {
              listed.insert(0, channel.id);
              liveSync.adoptChannel(siteUrl, channel, includeActivity: true);
              sidebarChanged = true;
            }
          }
        }
      });
      if (sidebarChanged) {
        onChanged();
      }
    });
    return result;
  }

  // Mirrors Chat::ChannelFetcher.unreads_total. Followed open public channels
  // contribute mentions; followed unmuted DMs contribute unread messages.
  static int _notificationContribution(ChatChannel channel) {
    final membership = channel.membership;
    if (!membership.following) return 0;
    if (channel.isDirectMessage) {
      return membership.muted ? 0 : channel.tracking.unreadCount;
    }
    return channel.status == ChatChannelStatus.open
        ? channel.tracking.mentionCount
        : 0;
  }

  int _chatNotifications() => [
    ...publicChannels(),
    ...directChannels(),
  ].fold(0, (count, channel) => count + _notificationContribution(channel));

  void _publishListedNotificationChange(void Function() change) {
    if (_publicIds == null) {
      change();
      return;
    }
    final before = _chatNotifications();
    change();
    final delta = _chatNotifications() - before;
    if (delta != 0) onChatNotificationsDelta?.call(siteUrl, delta);
  }

  void _publishNotificationChange(ChatChannel before, ChatChannel after) {
    final delta =
        _notificationContribution(after) - _notificationContribution(before);
    if (delta != 0) onChatNotificationsDelta?.call(siteUrl, delta);
  }

  void _insertLiveChannel(ChatChannel incoming) =>
      _publishListedNotificationChange(() {
        if (incoming.isDirectMessage && incoming.membership.following) {
          final ids = (_directIds ??= []);
          if (!ids.contains(incoming.id)) ids.add(incoming.id);
          return;
        }
        if (!incoming.isCategoryChannel) return;
        final ids = (_publicIds ??= []);
        if (!ids.contains(incoming.id)) ids.add(incoming.id);
        ids.sort((a, b) {
          final left = channel(a);
          final right = channel(b);
          return (left?.slug ?? left?.title ?? '').toLowerCase().compareTo(
            (right?.slug ?? right?.title ?? '').toLowerCase(),
          );
        });
      });

  Object? _beginLiveChannelFollow(int channelId) {
    final key = channelId;
    if (_channels[key]?.followWrite != null) return null;
    final token = Object();
    _entry(key).followWrite = token;
    return token;
  }

  bool _ownsLiveChannelFollow(int channelId, Object token) =>
      identical(_channels[channelId]?.followWrite, token);

  void _endLiveChannelFollow(int channelId, Object token) {
    final key = channelId;
    if (identical(_channels[key]?.followWrite, token)) {
      _channels[key]?.followWrite = null;
      _releaseIdleEntry(key);
    }
  }

  List<ChatChannel> starredChannels() {
    final direct = directChannels()
        .where((channel) => channel.membership.starred)
        .toList();
    direct.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return [
      for (final channel in publicChannels())
        if (channel.membership.starred) channel,
      ...direct,
    ];
  }

  List<ChatChannel> unstarredPublicChannels() => [
    for (final channel in publicChannels())
      if (!channel.membership.starred) channel,
  ];

  List<ChatChannel> unstarredDirectChannels() {
    final channels = [
      for (final channel in directChannels())
        if (!channel.membership.starred) channel,
    ];
    return List.unmodifiable(_sortDirectMessageActivity(channels));
  }

  List<ChatChannel> activitySortedDirectChannels() =>
      List.unmodifiable(_sortDirectMessageActivity([...directChannels()]));

  List<ChatChannel> activitySortedStarredChannels() {
    final channels = [...starredChannels()];
    final originalPositions = <int, int>{};
    for (final channel in channels) {
      originalPositions[channel.id] = originalPositions.length;
    }

    int urgent(ChatChannel channel) => channel.isDirectMessage
        ? channel.tracking.unreadCount +
              channel.tracking.mentionCount +
              channel.tracking.watchedThreadsUnreadCount
        : channel.tracking.mentionCount +
              channel.tracking.watchedThreadsUnreadCount;
    final unreadCounts = Map<ChatChannel, int>.identity();
    int unread(ChatChannel channel) => unreadCounts.putIfAbsent(
      channel,
      () =>
          channel.tracking.unreadCount +
          channel.unreadThreadsCountSinceLastViewed,
    );
    int byActivity(ChatChannel a, ChatChannel b) {
      final compared = _newestActivityFirst(a, b);
      return compared != 0
          ? compared
          : originalPositions[a.id]!.compareTo(originalPositions[b.id]!);
    }

    channels.sort((a, b) {
      final aUrgent = urgent(a);
      final bUrgent = urgent(b);
      final aUnread = unread(a);
      final bUnread = unread(b);
      final aHasActivity = aUrgent > 0 || aUnread > 0;
      final bHasActivity = bUrgent > 0 || bUnread > 0;
      if (aHasActivity != bHasActivity) return aHasActivity ? -1 : 1;
      if (a.isDirectMessage != b.isDirectMessage) {
        return a.isDirectMessage ? 1 : -1;
      }
      if (aHasActivity) {
        if (aUrgent > 0 && bUrgent > 0) return byActivity(a, b);
        if ((aUrgent > 0) != (bUrgent > 0)) return aUrgent > 0 ? -1 : 1;
        if (aUnread > 0 && bUnread > 0) return byActivity(a, b);
        if ((aUnread > 0) != (bUnread > 0)) return aUnread > 0 ? -1 : 1;
      }
      return byActivity(a, b);
    });
    return List.unmodifiable(channels);
  }

  List<ChatChannel> _sortDirectMessageActivity(List<ChatChannel> channels) {
    final unreadCounts = Map<ChatChannel, int>.identity();
    int unreadThreads(ChatChannel channel) => unreadCounts.putIfAbsent(
      channel,
      () => channel.unreadThreadsCountSinceLastViewed,
    );
    final oldestThreads = Map<ChatChannel, DateTime?>.identity();
    DateTime? oldestThread(ChatChannel channel) =>
        oldestThreads.putIfAbsent(channel, () => channel.lastUnreadThreadAt);
    // Mirrors core's activity ordering for unstarred direct messages.
    int compare(ChatChannel a, ChatChannel b) {
      final aHasMessage = a.lastMessageId != null && a.lastMessageAt != null;
      final bHasMessage = b.lastMessageId != null && b.lastMessageAt != null;
      if (aHasMessage != bHasMessage) return aHasMessage ? -1 : 1;

      final aUrgent =
          a.tracking.unreadCount +
          a.tracking.mentionCount +
          a.tracking.watchedThreadsUnreadCount;
      final bUrgent =
          b.tracking.unreadCount +
          b.tracking.mentionCount +
          b.tracking.watchedThreadsUnreadCount;
      if (aUrgent > 0 && bUrgent > 0) {
        return _newestActivityFirst(a, b);
      }
      if ((aUrgent > 0) != (bUrgent > 0)) return aUrgent > 0 ? -1 : 1;

      final aThreads = unreadThreads(a);
      final bThreads = unreadThreads(b);
      if (aThreads > 0 && bThreads > 0) {
        final aAt = oldestThread(a);
        final bAt = oldestThread(b);
        if (aAt != null && bAt != null) {
          final byThreadDate = bAt.compareTo(aAt);
          if (byThreadDate != 0) return byThreadDate;
        }
        return _newestActivityFirst(a, b);
      }
      if ((aThreads > 0) != (bThreads > 0)) return aThreads > 0 ? -1 : 1;

      return _newestActivityFirst(a, b);
    }

    final originalPositions = {
      for (var index = 0; index < channels.length; index++)
        channels[index].id: index,
    };
    channels.sort((a, b) {
      final compared = compare(a, b);
      return compared != 0
          ? compared
          : originalPositions[a.id]!.compareTo(originalPositions[b.id]!);
    });
    return channels;
  }

  static int _newestActivityFirst(ChatChannel a, ChatChannel b) {
    final aAt = a.lastMessageAt;
    final bAt = b.lastMessageAt;
    if (aAt == null || bAt == null) {
      if (aAt == bAt) return 0;
      return aAt == null ? 1 : -1;
    }
    final byDate = bAt.compareTo(aAt);
    if (byDate != 0) return byDate;
    return (b.lastMessageId ?? 0).compareTo(a.lastMessageId ?? 0);
  }

  List<ChatChannel> _resolve(List<int>? ids) => [
    for (final id in ids ?? const <int>[])
      ?store.read<ChatChannel>(siteUrl, id),
  ];

  ChatChannel? channel(int channelId) =>
      store.read<ChatChannel>(siteUrl, channelId);

  void _putChannel(ChatChannel next) {
    _refresh?.recordChange(channel(next.id), next);
    store.put(siteUrl, next);
  }

  void _updateChannel(int channelId, ChatChannel Function(ChatChannel) change) {
    final held = channel(channelId);
    if (held != null) _putChannel(change(held));
  }

  Future<ChatChannel?> ensureChannel(int channelId) {
    if (isDisposed || channelId <= 0) return Future.value();
    final held = channel(channelId);
    if (held != null && !_partialChannelIds.contains(channelId)) {
      return Future.value(held);
    }
    final key = channelId;
    final active = _channels[key]?.detailRequest;
    if (active != null) return active;

    final run = Object();
    _entry(key).detailRun = run;
    late final Future<ChatChannel?> request;
    request = _ensureChannel(channelId, key, run).whenComplete(() {
      if (identical(_channels[key]?.detailRequest, request)) {
        _channels[key]?.detailRequest = null;
      }
      if (identical(_channels[key]?.detailRun, run)) {
        _channels[key]?.detailRun = null;
        _releaseIdleEntry(key);
      }
    });
    _entry(key).detailRequest = request;
    return request;
  }

  Future<ChatChannel?> _ensureChannel(
    int channelId,
    int key,
    Object run,
  ) async {
    final lease = this.lease;
    bool ownsRequest() => identical(_channels[key]?.detailRun, run);
    try {
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest) || apiKey == null) return null;
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return null;
      final fetched = await requestCredentials.run(
        () => api.chatChannel(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: channelId,
        ),
      );
      if (!_requestIsCurrent(lease, ownsRequest) || fetched.id != channelId) {
        return null;
      }
      return lease.commit(() {
            _partialChannelIds.remove(channelId);
            store.put(siteUrl, fetched);
            liveSync.adoptChannel(siteUrl, fetched, includeActivity: false);
          })
          ? channel(channelId)
          : null;
    } catch (error) {
      rethrow;
    }
  }

  String? channelsError() => _error;

  Future<void> loadChannels({bool force = false, bool revalidate = false}) {
    if (isDisposed) return Future.value();
    if (revalidate) {
      if (_publicIds == null) return Future.value();
    } else if (!force && _publicIds != null) {
      return Future.value();
    }

    final active = _loadRequest;
    if (active != null) {
      if (!revalidate && _revalidating) {
        _revalidating = false;
        onChanged();
      }
      return active;
    }

    if (force || revalidate) _attempts = 0;
    if (_attempts >= ChatController.maxChannelAttempts) return Future.value();

    final run = Object();
    _loadRun = run;
    if (revalidate) _revalidating = true;
    late final Future<void> request;
    request = _loadChannels(run).whenComplete(() {
      if (identical(_loadRequest, request)) {
        _loadRequest = null;
      }
      if (identical(_loadRun, run)) {
        _loadRun = null;
        _revalidating = false;
      }
    });
    _loadRequest = request;
    onChanged();
    return request;
  }

  Future<void> _loadChannels(Object run) async {
    if (_loading) return;
    _loading = true;

    final lease = this.lease;
    ChatChannelRefresh? refresh;
    bool ownsRequest() => identical(_loadRun, run);
    _attempts++;

    try {
      // Unsigned macOS keychain reads may throw; keep them inside cleanup guards.
      final requestCredentials = await requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      refresh = ChatChannelRefresh(
        publicIds: _publicIds ?? const [],
        directIds: _directIds ?? const [],
      );
      _refresh = refresh;
      final hadThreads = hasThreads();
      final snapshot = await requestCredentials.run(
        () => api.chatChannels(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
        ),
      );
      if (!_requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        final channels = refresh!.reconcile(
          snapshot,
          public: publicChannels(),
          direct: directChannels(),
        );
        _refresh = null;
        _publishListedNotificationChange(() {
          store.putAll(siteUrl, channels.public);
          store.putAll(siteUrl, channels.direct);
          _partialChannelIds.removeAll([
            for (final channel in [...channels.public, ...channels.direct])
              channel.id,
          ]);
          for (final channel in [...channels.public, ...channels.direct]) {
            if (liveSync.isViewingChannel(siteUrl, channel.id)) {
              advanceLastViewedAt(channel.id);
            }
          }
          _publicIds = [for (final c in channels.public) c.id];
          _directIds = [for (final c in channels.direct) c.id];
        });
        replaceHasThreads(hadThreads, channels.hasThreads);
        liveSync.replace(
          siteUrl,
          channels,
          preservedActivityChannelIds: refresh.preservedActivityChannelIds,
        );
        _error = null;
        _attempts = 0;
      });
    } catch (error) {
      if (!_requestIsCurrent(lease, ownsRequest)) return;

      if (_revalidating) return;
      lease.commit(() {
        _error = appL10n.couldNotLoadThisSiteSChatChannels;
      });
    } finally {
      if (identical(_refresh, refresh)) {
        _refresh = null;
      }
      if (_requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          _loading = false;
          onChanged();
        });
      }
    }
  }
}

final class _ChannelSettingsWrite {
  bool receivedMetadata = false;
  bool receivedStatus = false;
}

final class _ChatChannelDirectoryEntry {
  bool get idle =>
      detailRequest == null &&
      detailRun == null &&
      starWrite == null &&
      notificationWrite == null &&
      messageResume == null &&
      followWrite == null &&
      settingsWrite == null;

  Future<ChatChannel?>? detailRequest;
  Object? detailRun;
  Object? starWrite;
  Object? notificationWrite;
  Object? messageResume;
  Object? followWrite;
  _ChannelSettingsWrite? settingsWrite;
}
