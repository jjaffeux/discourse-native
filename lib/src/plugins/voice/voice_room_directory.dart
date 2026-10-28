part of 'voice_controller.dart';

final class _VoiceRoomDirectory {
  _VoiceRoomDirectory(this.controller, this.siteUrl, this.siteSession);

  final VoiceController controller;
  final String siteUrl;
  final Object siteSession;
  VoiceDirectory? _snapshot;
  VoiceDirectory? get snapshot => _snapshot;
  String? _error;
  String? get error => _error;
  bool loading = false;
  bool _unavailable = false;
  bool _retired = false;
  Future<void>? _closeOperation;
  Object? _directoryRequest;
  int _roomRequestVersion = 0;
  final Map<int, VoiceRoom> _linkedRooms = {};
  final Map<int, int> _roomResponseVersions = {};
  final Map<int, int> _roomLiveVersions = {};
  final Map<int, int> _destroyedRoomVersions = {};
  final _VoiceLiveCursors _liveCursors = _VoiceLiveCursors();
  PluginLiveChannelSubscription? _directorySubscription;
  final Map<int, PluginLiveChannelSubscription> _roomSubscriptions = {};
  final Set<Future<void>> _subscriptionTeardowns = {};
  Object _subscriptionRun = Object();

  bool get isCurrent =>
      !_retired && controller._isCurrentSiteSession(siteUrl, siteSession);

  void _notifyChanged() => controller._notifyDirectoryChanged(this);

  VoiceRoom? get retainedRoom => controller._retainedRoom(siteUrl);

  Map<int, VoiceRoom> get heldRooms {
    final rooms = {
      for (final room in snapshot?.rooms ?? const <VoiceRoom>[]) room.id: room,
      for (final room in _linkedRooms.values) room.id: room,
    };
    final retained = retainedRoom;
    if (retained != null) rooms[retained.id] = retained;
    return rooms;
  }

  VoiceRoom? room(int id) {
    for (final room in snapshot?.rooms ?? const <VoiceRoom>[]) {
      if (room.id == id) return room;
    }
    final retained = retainedRoom;
    return retained?.id == id ? retained : _linkedRooms[id];
  }

  bool setError(String? error) {
    final changed = _error != error;
    _error = error;
    return changed;
  }

  Future<VoiceRoom?> saveRoom({
    required VoiceRoomDraft draft,
    int? roomId,
  }) async {
    final credentials = await controller._keyRequestCredentials(
      siteUrl,
      ifCurrent: () => isCurrent,
    );
    if (credentials == null) return null;
    try {
      var room = roomId == null
          ? await credentials.run(
              () => controller.api.createRoom(
                siteUrl: siteUrl,
                apiKey: credentials.apiKey!,
                draft: draft,
              ),
            )
          : await credentials.run(
              () => controller.api.updateRoom(
                siteUrl: siteUrl,
                roomId: roomId,
                apiKey: credentials.apiKey!,
                draft: draft,
              ),
            );
      if (!isCurrent) return null;
      room = acceptWrite(room);
      await controller.ensureLoaded(siteUrl, force: true);
      return isCurrent ? room : null;
    } catch (failure) {
      if (!isCurrent) return null;
      _error = failure is WriteException
          ? failure.message
          : appL10n.couldnTSaveTheVoiceRoom;

      _notifyChanged();
      return null;
    }
  }

  Future<bool> deleteRoom(int roomId) async {
    final target = room(roomId);
    if (!isCurrent || target == null || !target.canDelete || target.ephemeral) {
      return false;
    }
    final credentials = await controller._keyRequestCredentials(
      siteUrl,
      ifCurrent: () => isCurrent,
    );
    if (credentials == null) return false;
    try {
      await credentials.run(
        () => controller.api.deleteRoom(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: credentials.apiKey!,
        ),
      );
      if (!isCurrent) return false;
      _error = null;
      removeDestroyedRoom(roomId);
      return true;
    } catch (failure) {
      if (!isCurrent) return false;
      _error = failure is WriteException
          ? failure.message
          : appL10n.voiceRoomDeleteFailed;
      _notifyChanged();
      return false;
    }
  }

  void removeDestroyedRoom(int roomId) {
    _roomResponseVersions.remove(roomId);
    _roomLiveVersions.remove(roomId);
    _destroyedRoomVersions[roomId] = ++_roomRequestVersion;
    while (_destroyedRoomVersions.length > _maxDestroyedRoomsPerSite) {
      _destroyedRoomVersions.remove(_destroyedRoomVersions.keys.first);
    }
    final held = snapshot;
    if (held != null) {
      _snapshot = VoiceDirectory(
        rooms: List.unmodifiable(held.rooms.where((room) => room.id != roomId)),
        canCreateRoom: held.canCreateRoom,
        messageBusLastId: held.messageBusLastId,
      );
    }
    _linkedRooms.remove(roomId);
    controller._directoryRoomDestroyed(siteUrl, roomId);
    syncSubscriptions();
    _notifyChanged();
  }

  VoiceRoom acceptWrite(VoiceRoom incoming) {
    final room = acceptResponse(incoming, ++_roomRequestVersion);
    refreshRoom(room);
    return room;
  }

  Future<VoiceRoom?> resolveRoom(
    String slug, {
    bool Function()? ifCurrent,
  }) async {
    bool ownsRequest() => isCurrent && (ifCurrent?.call() ?? true);
    if (!ownsRequest() || _unavailable) return null;
    try {
      final capabilityEnabled = await controller._capabilityEnabledFor(siteUrl);
      if (!ownsRequest() || capabilityEnabled == false) return null;
      final directory = snapshot;
      for (final room in directory?.rooms ?? const <VoiceRoom>[]) {
        if (room.slug == slug) return room;
      }
      final credentials = await controller._requestCredentials(
        siteUrl,
        ifCurrent: ownsRequest,
      );
      if (credentials == null) return null;
      final requestVersion = ++_roomRequestVersion;
      var room = await credentials.run(
        () => controller.api.room(
          siteUrl: siteUrl,
          slug: slug,
          apiKey: credentials.apiKey!,
          clientId: credentials.clientId,
        ),
      );
      if (!ownsRequest() || _destroyedSince(room.id, requestVersion)) {
        return null;
      }
      room = acceptResponse(room, requestVersion);
      rememberLinkedRoom(room);
      if (!ownsRequest()) return null;
      _notifyChanged();
      return ownsRequest() ? room : null;
    } catch (failure) {
      return null;
    }
  }

  void rememberLinkedRoom(VoiceRoom room) {
    final previous = this.room(room.id);
    refreshRoom(room);
    final linked = _linkedRooms;
    linked.remove(room.id);
    linked[room.id] = VoiceController._mergeRoom(previous, room);
    final protectedId = retainedRoom?.id;
    for (final id in linked.keys.toList()) {
      if (linked.length <= _maxLinkedRoomsPerSite) break;
      if (id == room.id || id == protectedId) continue;
      linked.remove(id);
    }
    syncSubscriptions();
  }

  Future<void> ensureLoaded({bool force = false}) async {
    if (!controller.supportedPlatform) return;
    if (!isCurrent || loading || _unavailable) {
      return;
    }
    if (!force && (snapshot != null)) {
      controller.attachTracker(siteUrl);
      return;
    }

    final request = Object();
    _directoryRequest = request;
    bool ownsRequest() => isCurrent && identical(_directoryRequest, request);
    final capabilityEnabled = await controller._capabilityEnabledFor(siteUrl);
    if (!ownsRequest()) return;
    if (capabilityEnabled == false) {
      _snapshot = null;
      controller._pruneChatAssociations(siteUrl, const {});
      _directoryRequest = null;

      _notifyChanged();
      return;
    }
    final credentials = await controller._requestCredentials(
      siteUrl,
      ifCurrent: ownsRequest,
    );
    if (credentials == null) {
      if (!ownsRequest()) return;
      controller.forget(siteUrl);
      return;
    }
    loading = true;
    _error = null;
    _notifyChanged();
    if (!ownsRequest()) return;
    try {
      final requestVersion = ++_roomRequestVersion;
      final directory = await credentials.run(
        () => controller.api.rooms(
          siteUrl: siteUrl,
          apiKey: credentials.apiKey!,
          clientId: credentials.clientId,
        ),
      );
      if (!ownsRequest()) return;
      final incomingRooms = [
        for (final room in directory.rooms)
          if (!_destroyedSince(room.id, requestVersion))
            acceptResponse(room, requestVersion),
      ];
      final previousRooms = heldRooms;
      final listedIds = {for (final room in incomingRooms) room.id};
      final liveVersions = _roomLiveVersions;
      _snapshot = VoiceDirectory(
        rooms: List.unmodifiable([
          for (final room in incomingRooms)
            VoiceController._mergeRoom(previousRooms[room.id], room),
          for (final room in snapshot?.rooms ?? const <VoiceRoom>[])
            if (!listedIds.contains(room.id) &&
                (liveVersions[room.id] ?? 0) > requestVersion)
              room,
        ]),
        canCreateRoom: directory.canCreateRoom,
        messageBusLastId: directory.messageBusLastId,
      );
      for (final room in incomingRooms) {
        final linked = _linkedRooms;
        if (linked[room.id] case final previous?) {
          linked[room.id] = VoiceController._mergeRoom(previous, room);
        }
        controller._refreshRetainedRoom(siteUrl, room);
        if (!ownsRequest()) return;
      }
      final retainedIds = heldRooms.keys.toSet();
      _roomResponseVersions.removeWhere((id, _) => !retainedIds.contains(id));
      _roomLiveVersions.removeWhere((id, _) => !retainedIds.contains(id));
      controller._pruneChatAssociations(siteUrl, retainedIds);

      syncSubscriptions();
    } on SiteLookupException catch (failure) {
      if (!ownsRequest()) return;
      if (_isUnavailableDirectoryFailure(failure)) {
        _snapshot = null;
        controller._pruneChatAssociations(siteUrl, const {});
        _unavailable = true;
      } else {
        _error = appL10n.couldnTLoadVoiceRooms;
      }
    } catch (failure) {
      if (!ownsRequest()) return;
      _error = appL10n.couldnTLoadVoiceRooms;
    } finally {
      if (ownsRequest()) {
        _directoryRequest = null;
        loading = false;
        _notifyChanged();
      }
    }
  }

  static bool _isUnavailableDirectoryFailure(SiteLookupException error) =>
      error.failure == SiteLookupFailure.notDiscourse ||
      error.statusCode == HttpStatus.notFound;

  void _onDirectoryEvent(Object? data, int messageId) {
    if (!isCurrent) return;
    _liveCursors.directoryDelivered(messageId);
    if (data is! Map<String, dynamic>) return;
    final rawRoom = data['room'];
    if (rawRoom is! Map<String, dynamic>) return;
    final incoming = VoiceRoom.fromJson(rawRoom);

    final held = snapshot;
    if (held == null) return;
    final rooms = [...held.rooms];
    final index = rooms.indexWhere((room) => room.id == incoming.id);
    switch (data['type']) {
      case 'created':
      case 'updated':
        if (index < 0) {
          rooms.add(
            VoiceController._mergeRoom(
              room(incoming.id),
              incoming,
              preserveRecording: true,
            ),
          );
        } else {
          rooms[index] = VoiceController._mergeRoom(
            rooms[index],
            incoming,
            preserveRecording: true,
          );
        }
        final linked = _linkedRooms;
        if (linked[incoming.id] case final previous?) {
          linked[incoming.id] = VoiceController._mergeRoom(previous, incoming);
        }
        controller._refreshRetainedRoom(siteUrl, incoming);
        liveRoomChanged(incoming.id);
      case 'destroyed':
        removeDestroyedRoom(incoming.id);
        return;
      default:
        return;
    }
    _snapshot = VoiceDirectory(
      rooms: List.unmodifiable(rooms),
      canCreateRoom: held.canCreateRoom,
      messageBusLastId: held.messageBusLastId,
    );
    syncSubscriptions();
    _notifyChanged();
  }

  // Broadcasts omit the authenticated user fields supplied by HTTP reads.
  VoiceRoom acceptResponse(VoiceRoom incoming, int requestVersion) {
    final versions = _roomResponseVersions;
    if ((versions[incoming.id] ?? 0) > requestVersion) {
      return heldRooms[incoming.id] ?? incoming;
    }
    versions[incoming.id] = requestVersion;
    if ((_roomLiveVersions[incoming.id] ?? 0) <= requestVersion) {
      return incoming;
    }
    return heldRooms[incoming.id]?.withUserFieldsFrom(incoming) ?? incoming;
  }

  void liveRoomChanged(int roomId) {
    _roomLiveVersions[roomId] = ++_roomRequestVersion;
  }

  bool _destroyedSince(int roomId, int requestVersion) =>
      (_destroyedRoomVersions[roomId] ?? 0) > requestVersion;

  void refreshRoom(VoiceRoom incoming) {
    updateRoom(
      incoming.id,
      (held) => VoiceController._mergeRoom(held, incoming),
    );
    controller._refreshRetainedRoom(siteUrl, incoming);
  }

  void updateRoom(int roomId, VoiceRoom Function(VoiceRoom room) update) {
    updateListedRoom(roomId, update);
    final linkedRoom = _linkedRooms[roomId];
    if (linkedRoom != null) _linkedRooms[roomId] = update(linkedRoom);
  }

  void updateListedRoom(int roomId, VoiceRoom Function(VoiceRoom room) update) {
    final held = snapshot;
    if (held != null && held.rooms.any((room) => room.id == roomId)) {
      _snapshot = VoiceDirectory(
        rooms: List.unmodifiable([
          for (final room in held.rooms)
            room.id == roomId ? update(room) : room,
        ]),
        canCreateRoom: held.canCreateRoom,
        messageBusLastId: held.messageBusLastId,
      );
    }
  }

  void syncSubscriptions() {
    if (!isCurrent) return;
    final directory = snapshot;
    final directoryCursor = _liveCursors.directoryCursor(
      directory?.messageBusLastId,
    );
    final wanted = heldRooms;
    for (final room in wanted.values) {
      _liveCursors.roomCursor(room.id, room.messageBusLastId);
    }
    final tracker = controller._trackerFor(siteUrl);
    if (tracker == null) return;
    final root = controller.api.namespaceFor(siteUrl).root;
    final run = _subscriptionRun;
    bool ownsSubscription() => isCurrent && identical(run, _subscriptionRun);
    var changed = false;
    if (directory != null && _directorySubscription == null) {
      _directorySubscription = tracker.subscribe('$root/rooms/index', (
        data,
        messageId,
      ) {
        if (ownsSubscription()) _onDirectoryEvent(data, messageId);
      }, lastId: directoryCursor);
      changed = true;
    }
    for (final id
        in _roomSubscriptions.keys
            .where((id) => !wanted.containsKey(id))
            .toList()) {
      final subscription = _roomSubscriptions.remove(id);
      if (subscription != null) _cancelSubscription(subscription);
      _liveCursors.dropRoom(id);
      changed = true;
    }
    for (final room in wanted.values) {
      final roomCursor = _liveCursors.roomCursor(
        room.id,
        room.messageBusLastId,
      );
      if (_roomSubscriptions.containsKey(room.id)) continue;
      late final PluginLiveChannelSubscription subscription;
      subscription = tracker.subscribe('$root/rooms/${room.id}', (
        data,
        messageId,
      ) {
        if (!ownsSubscription() ||
            !identical(_roomSubscriptions[room.id], subscription)) {
          return;
        }
        _liveCursors.roomDelivered(room.id, messageId);
        if (!controller._disposed) {
          controller._roomEvents.deliver(siteUrl, room.id, data);
        }
      }, lastId: roomCursor);
      _roomSubscriptions[room.id] = subscription;
      changed = true;
    }
    changed =
        controller._syncAuxiliarySubscriptions(siteUrl, tracker) || changed;
  }

  List<PluginLiveChannelSubscription> _takeSubscriptions() {
    _subscriptionRun = Object();
    final subscriptions = [
      ?_directorySubscription,
      ..._roomSubscriptions.values,
    ];
    _directorySubscription = null;
    _roomSubscriptions.clear();
    return subscriptions;
  }

  void detachTracker() {
    for (final subscription in _takeSubscriptions()) {
      _cancelSubscription(subscription);
    }
  }

  void _cancelSubscription(PluginLiveChannelSubscription subscription) {
    late final Future<void> cancellation;
    cancellation = controller
        ._cancelSubscription(subscription)
        .whenComplete(() => _subscriptionTeardowns.remove(cancellation));
    _subscriptionTeardowns.add(cancellation);
  }

  Future<void> close() => _closeOperation ??= _finishClose();

  Future<void> _finishClose() {
    _retired = true;
    _directoryRequest = null;
    detachTracker();
    return Future.wait(_subscriptionTeardowns.toList());
  }
}

final class _VoiceLiveCursors {
  int? _directory;
  final Map<int, int> _rooms = {};

  int? directoryCursor(int? snapshot) =>
      _directory = _newerCursor(_directory, snapshot);

  int? roomCursor(int roomId, int? snapshot) {
    final cursor = _newerCursor(_rooms[roomId], snapshot);
    if (cursor != null) _rooms[roomId] = cursor;
    return cursor;
  }

  void directoryDelivered(int messageId) {
    final current = _directory;
    if (current == null || messageId > current) _directory = messageId;
  }

  void roomDelivered(int roomId, int messageId) {
    final current = _rooms[roomId];
    if (current == null || messageId > current) _rooms[roomId] = messageId;
  }

  void dropRoom(int roomId) => _rooms.remove(roomId);
}

const _maxLinkedRoomsPerSite = 8;

const _maxDestroyedRoomsPerSite = 16;
