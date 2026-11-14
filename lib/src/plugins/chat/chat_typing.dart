import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import '../../models/found_user.dart';

final class ChatTypingApi {
  const ChatTypingApi(this._transport);

  final PluginApiTransport _transport;

  Future<({int cursor, List<FoundUser> users})?> snapshot(
    String site,
    String channel,
    PluginRequestCredentials credentials,
  ) async {
    final response = await credentials.run(
      () => _transport.pluginGetJson(
        siteUrl: site,
        path: Uri(
          path: '/presence/get',
          queryParameters: {'channels[]': channel},
        ).toString(),
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      ),
    );
    final held = response[channel];
    if (held is! Map<String, dynamic>) return null;
    final cursor = jsonIntOrNull(held['last_message_id']);
    if (cursor == null) return null;
    return (cursor: cursor, users: _decodeUsers(held['users'], site));
  }

  Future<void> update(
    String site,
    String channel,
    PluginRequestCredentials credentials,
    bool present,
  ) async {
    final key = credentials.apiKey;
    if (key == null) return;
    await credentials.run(
      () => _transport.pluginWriteJson(
        siteUrl: site,
        path: '/presence/update',
        method: 'POST',
        apiKey: key,
        clientId: credentials.clientId,
        body: {
          'client_id': credentials.clientId,
          if (present)
            'present_channels': [channel]
          else
            'leave_channels': [channel],
        },
      ),
    );
  }
}

List<FoundUser> _decodeUsers(Object? data, String site) => [
  for (final user in jsonObjects(data))
    if (jsonInt(user['id']) > 0 && jsonText(user['username']) != null)
      FoundUser.fromJson(user, site),
];

/// A conversation's typing snapshot, MessageBus cursor, and local idle timer.
final class ChatTyping {
  ChatTyping({
    required this.siteUrl,
    required this.channel,
    required this.api,
    required this.requests,
    required this.currentUserId,
  });

  final String siteUrl, channel;
  final ChatTypingApi? api;
  final PluginRequestHost requests;
  final int? Function() currentUserId;
  final users = FrameSafeValueNotifier<List<FoundUser>>(const []);
  final _participants = <int, FoundUser>{};
  PluginLiveChannelHandle? _tracker;
  PluginSiteLease? _lease;
  PluginLiveChannelSubscription? _subscription;
  Timer? _retry, _idle, _send;
  Future<void> _writes = Future.value();
  bool _viewing = false;
  bool _announced = false;
  bool _wantsPresence = false;
  bool get inUse => _viewing || users.isObserved;
  int _generation = 0;

  void attach(PluginLiveChannelHandle tracker, PluginSiteLease lease) {
    if (identical(_tracker, tracker) && identical(_lease, lease)) return;
    if (!identical(_lease, lease)) {
      _send?.cancel();
      _idle?.cancel();
      _wantsPresence = _announced = false;
    }
    _reset();
    _tracker = tracker;
    _lease = lease;
    _refresh();
  }

  void setViewing(bool viewing) {
    if (_viewing == viewing) return;
    if (!viewing) reportTyping(false);
    _viewing = viewing;
    if (viewing) {
      _refresh();
    } else {
      _reset();
    }
  }

  void _reset() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    _retry?.cancel();
    _participants.clear();
    users.value = const [];
  }

  void _refresh() {
    final tracker = _tracker;
    final lease = _lease;
    final transport = api;
    if (!_viewing || tracker == null || lease == null || transport == null) {
      return;
    }
    final generation = ++_generation;
    bool current() => _generation == generation && lease.isCurrent;
    unawaited(() async {
      try {
        final credentials = await requests.credentialsFor(siteUrl);
        if (!current()) return;
        final snapshot = await transport.snapshot(
          siteUrl,
          channel,
          credentials,
        );
        if (!current() || snapshot == null) return;
        var cursor = snapshot.cursor;
        _participants
          ..clear()
          ..addEntries(snapshot.users.map((user) => MapEntry(user.id!, user)));
        _publish();
        final subscription = tracker.subscribe('/presence$channel', (data, id) {
          if (!current() || id <= cursor) return;
          if (id != cursor + 1) {
            _reset();
            _refresh();
            return;
          }
          cursor = id;
          if (data is! Map<String, dynamic>) return;
          for (final user in _decodeUsers(data['entering_users'], siteUrl)) {
            _participants[user.id!] = user;
          }
          for (final userId in jsonArray(data['leaving_user_ids'])) {
            _participants.remove(jsonIntOrNull(userId));
          }
          _publish();
        }, lastId: cursor);
        if (current()) {
          _subscription = subscription;
        } else {
          subscription.cancel();
        }
      } catch (_) {
        if (current()) {
          _retry = Timer(const Duration(seconds: 5), _refresh);
        }
      }
    }());
  }

  void _publish() {
    final me = currentUserId();
    final visible = [
      for (final user in _participants.values)
        if (user.id != me) user,
    ];
    if (!listEquals(users.value, visible)) {
      users.value = List.unmodifiable(visible);
    }
  }

  void reportTyping(bool active) {
    if (!_viewing || api == null || _lease?.isCurrent != true) return;
    _idle?.cancel();
    if (active) {
      _idle = Timer(const Duration(seconds: 5), () => reportTyping(false));
    }
    _wantsPresence = active;
    if (_wantsPresence == _announced) {
      _send?.cancel();
      _send = null;
    } else if (active) {
      _send ??= Timer(const Duration(milliseconds: 500), _flushPresence);
    } else {
      _flushPresence();
    }
  }

  void _flushPresence() {
    _send?.cancel();
    _send = null;
    final lease = _lease!;
    final active = _wantsPresence;
    _announced = active;
    _writes = _writes.then((_) async {
      try {
        if (!lease.isCurrent) return;
        final credentials = await requests.credentialsFor(siteUrl);
        if (lease.isCurrent) {
          await api!.update(siteUrl, channel, credentials, active);
        }
      } catch (_) {
        // Presence is transient and must not interrupt editing or sending.
      }
    });
  }

  void dispose() {
    setViewing(false);
    _idle?.cancel();
    _send?.cancel();
    users.dispose();
  }
}
