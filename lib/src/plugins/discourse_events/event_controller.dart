import 'dart:async';

import '../../data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import '../../foundation/frame_safe_notifier.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/shell_extensions.dart';
import 'event_api.dart';
import 'event_data.dart';

const eventControllerKey = PluginServiceKey<EventController>(
  owner: eventsPluginId,
  name: 'controller',
);

/// One hydrated record and one subscription per site/event, shared by all
/// cards (including oneboxes). Cooked/post snapshots are seeds, not authority.
final class EventController extends FrameSafeNotifier
    implements PluginCurrentUserObserver, PluginTrackerAttachment {
  EventController({
    required this.api,
    required this.requests,
    required this.posts,
    required this.siteState,
    required this.accounts,
    required this.topics,
    required this.trackers,
    required this.zones,
  }) {
    zones.changes.addListener(notifySafely);
  }

  final EventApi api;
  final PluginRequestHost requests;
  final PluginPostHost posts;
  final PluginSiteStateHost siteState;
  final PluginAccountConnectionHost accounts;
  final PluginTopicRefreshHost topics;
  final PluginTrackerReader trackers;
  final PluginTimezoneHost zones;
  final _entries = <(String, int), _EventEntry>{};
  final _trackers = <String, PluginLiveChannelHandle>{};
  bool _foreground = true;
  int _foregroundRevision = 0;
  int get foregroundRevision => _foregroundRevision;
  final _accountRevisions = <String, int>{};
  int accountRevision(String site) => _accountRevisions[site] ?? 0;

  EventSettings settings(String site) =>
      siteState.siteConfigFor(site).plugins.get(eventSettingsKey) ??
      const EventSettings();
  String? accountTimezone(String site) =>
      siteState.currentUserFor(site)?.timezone;

  EventHandle acquire(String site, PostEvent seed) {
    final key = (site, seed.id);
    final entry = _entries.putIfAbsent(key, () => _EventEntry(site, seed));
    entry.references++;
    _subscribe(entry);
    if (!entry.authoritative && !entry.reading) unawaited(_refresh(entry));
    return EventHandle._(this, entry);
  }

  bool _current(_EventEntry entry) =>
      !isDisposed && identical(_entries[(entry.site, entry.id)], entry);

  void _release(_EventEntry entry) {
    if (--entry.references != 0) return;
    entry.subscription?.cancel();
    entry.subscription = null;
    entry.generation++;
    if (_current(entry)) _entries.remove((entry.site, entry.id));
  }

  void _subscribe(_EventEntry entry) {
    if (!_foreground || entry.subscription != null || entry.topicId == null) {
      return;
    }
    final tracker = _trackers[entry.site] ?? trackers(entry.site);
    entry.subscription = tracker?.subscribe(
      '/discourse-post-event/${entry.topicId}',
      (data, _) {
        if (eventObject(data)?['id'] == entry.id) unawaited(_refresh(entry));
      },
    );
  }

  void _sourceChanged(_EventEntry entry, PostEvent seed) {
    if (!_current(entry) || entry.source == seed) return;
    entry.source = seed;
    // In particular, an old topic GET must never roll a successful RSVP back.
    // Re-read the event endpoint when a post edit or core live reload changes it.
    unawaited(_refresh(entry));
  }

  Future<void> _refresh(_EventEntry entry) {
    if (!_current(entry)) return Future.value();
    if (entry.pending) {
      entry.dirty = true;
      return Future.value();
    }
    if (entry.reading) {
      entry.dirty = true;
      entry.generation++;
      return entry.readFuture!;
    }
    entry.reading = true;
    entry.readFuture = _readLoop(entry);
    notifySafely();
    return entry.readFuture!;
  }

  Future<void> _readLoop(_EventEntry entry) async {
    do {
      entry.dirty = false;
      final generation = ++entry.generation;
      final lease = requests.capture(entry.site);
      bool current() =>
          _current(entry) && lease.isCurrent && generation == entry.generation;
      try {
        final credentials = await requests.credentialsFor(entry.site);
        if (!current()) continue;
        final value = await api.get(entry.site, entry.id, credentials);
        if (!current()) continue;
        lease.commit(() {
          if (entry.topicId != value.topicId) {
            entry.subscription?.cancel();
            entry.subscription = null;
          }
          entry.value = value;
          entry.authoritative = true;
          entry.error = null;
          entry.topicId = value.topicId;
          _subscribe(entry);
        });
      } catch (error) {
        if (current()) {
          entry.authoritative = false;
          // A denied/missing event must not retain a private roster or actions.
          entry.value = null;
          entry.error = eventError(error, reading: true);
        }
      }
    } while (_current(entry) && entry.dirty && !entry.pending);
    entry.reading = false;
    if (_current(entry)) notifySafely();
  }

  Future<bool> _write(
    _EventEntry entry, {
    String? status,
    bool recurring = false,
    List<String>? invites,
  }) async {
    final event = entry.value;
    if (!_current(entry) ||
        entry.pending ||
        !entry.authoritative ||
        event == null) {
      return false;
    }
    if (invites != null
        ? !event.canManage
        : status == null
        ? !(event.public && event.canRespond && event.watching?.id != null)
        : !event.canChoose(status)) {
      return false;
    }
    if (!accounts.isConnected(entry.site) ||
        (entry.topicId != null &&
            posts.topicArchived(entry.site, entry.topicId!)) ||
        !posts.beginWrite(entry.site, entry.id)) {
      return false;
    }

    entry.pending = true;
    entry.generation++;
    entry.error = null;
    notifySafely();
    final lease = requests.capture(entry.site);
    String? failure;
    var mayHaveChanged = false;
    try {
      final credential = await requests.writeCredentialFor(entry.site);
      if (!_current(entry) || !lease.isCurrent) return false;
      if (credential.failure case final error?) throw error;
      final key = credential.apiKey;
      if (key == null) throw const WriteException(WriteFailure.forbidden);
      final credentials = await requests.credentialsFor(entry.site);
      if (!_current(entry) || !lease.isCurrent) return false;
      mayHaveChanged = true;
      if (invites != null) {
        await api.invite(
          entry.site,
          entry.id,
          invites,
          apiKey: key,
          clientId: credentials.clientId,
        );
      } else if (status == null) {
        await api.withdraw(
          entry.site,
          entry.id,
          event.watching!.id!,
          apiKey: key,
          clientId: credentials.clientId,
        );
      } else {
        await api.respond(
          entry.site,
          entry.id,
          apiKey: key,
          clientId: credentials.clientId,
          status: status,
          recurring: status == 'going' && event.recurring && recurring,
          inviteeId: event.watching?.id,
        );
      }
    } catch (error) {
      failure = eventError(error);
    } finally {
      // The host owns this lane; an obsolete account lease must never release
      // a newer account's lane with the same numeric post ID.
      lease.commit(() => posts.endWrite(entry.site, entry.id));
      entry.pending = false;
      if (_current(entry) && lease.isCurrent) {
        await _refresh(entry);
        if (_current(entry) && lease.isCurrent) {
          if (failure != null) entry.error = failure;
          notifySafely();
          // Attendance also affects Watching/Tracking and server Chat membership.
          if (mayHaveChanged && entry.topicId != null) {
            unawaited(
              topics
                  .reloadTopic(entry.site, entry.topicId!)
                  .catchError((Object _) {}),
            );
          }
        }
      }
    }
    return failure == null &&
        _current(entry) &&
        lease.isCurrent &&
        entry.authoritative;
  }

  Future<List<EventInvitee>> participants(
    EventHandle handle, {
    String? filter,
    String? type,
  }) async {
    final entry = handle._entry;
    if (!_current(entry) ||
        entry.value?.displayInvitees != true ||
        !entry.authoritative) {
      throw const WriteException(WriteFailure.forbidden);
    }
    final lease = requests.capture(entry.site);
    final credentials = await requests.credentialsFor(entry.site);
    if (!lease.isCurrent) throw const WriteException(WriteFailure.forbidden);
    final rows = await api.invitees(
      entry.site,
      entry.id,
      credentials,
      filter: filter,
      type: type,
    );
    if (!_current(entry) ||
        !lease.isCurrent ||
        entry.value?.displayInvitees != true) {
      throw const WriteException(WriteFailure.forbidden);
    }
    return rows;
  }

  Future<List<PostEvent>> list(
    String site, {
    bool mine = false,
    String? search,
  }) async {
    final lease = requests.capture(site);
    final username = mine ? siteState.currentUserFor(site)?.username : null;
    if (mine && username == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    final credentials = await requests.credentialsFor(site);
    if (!lease.isCurrent) throw const WriteException(WriteFailure.forbidden);
    final rows = await api.list(
      site,
      credentials,
      attendingUser: username,
      search: search,
    );
    if (!lease.isCurrent || isDisposed) {
      throw const WriteException(WriteFailure.forbidden);
    }
    return rows;
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    _accountRevisions[siteUrl] = accountRevision(siteUrl) + 1;
    for (final entry
        in _entries.values.where((e) => e.site == siteUrl).toList()) {
      entry.authoritative = false;
      entry.value = null;
      entry.generation++;
      unawaited(_refresh(entry));
    }
    notifySafely();
  }

  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) {
    _trackers[siteUrl] = channels;
    for (final entry in _entries.values.where((e) => e.site == siteUrl)) {
      entry.subscription?.cancel();
      entry.subscription = null;
      _subscribe(entry);
      unawaited(_refresh(entry));
    }
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) _foregroundRevision++;
    for (final entry in _entries.values) {
      if (foreground) {
        _subscribe(entry);
        unawaited(_refresh(entry));
      } else {
        entry.subscription?.cancel();
        entry.subscription = null;
      }
    }
    notifySafely();
  }

  void forget(String site) {
    _accountRevisions[site] = accountRevision(site) + 1;
    _trackers.remove(site);
    for (final entry in _entries.values.where((e) => e.site == site).toList()) {
      entry.subscription?.cancel();
      entry.value = null;
      entry.authoritative = false;
      entry.generation++;
      _entries.remove((site, entry.id));
    }
    notifySafely();
  }

  @override
  void dispose() {
    zones.changes.removeListener(notifySafely);
    for (final entry in _entries.values) {
      entry.subscription?.cancel();
    }
    _entries.clear();
    _trackers.clear();
    super.dispose();
  }
}

final class _EventEntry {
  _EventEntry(this.site, PostEvent seed)
    : id = seed.id,
      topicId = seed.topicId,
      value = seed,
      source = seed;
  final String site;
  final int id;
  int? topicId;
  PostEvent? value;
  PostEvent source;
  int references = 0;
  int generation = 0;
  bool authoritative = false;
  bool pending = false;
  bool reading = false;
  bool dirty = false;
  String? error;
  Future<void>? readFuture;
  PluginLiveChannelSubscription? subscription;
}

final class EventHandle {
  EventHandle._(this.controller, this._entry);
  final EventController controller;
  final _EventEntry _entry;
  bool _released = false;
  String get site => _entry.site;
  PostEvent? get event => _entry.value;
  bool get pending => _entry.pending;
  bool get loading => _entry.reading;
  bool get authoritative => _entry.authoritative && controller._current(_entry);
  String? get error => _entry.error;
  void updateSource(PostEvent seed) => controller._sourceChanged(_entry, seed);
  Future<void> refresh() => controller._refresh(_entry);
  Future<void> respond(String status, {bool recurring = false}) =>
      controller._write(_entry, status: status, recurring: recurring);
  Future<void> withdraw() => controller._write(_entry);
  Future<bool> invite(List<String> usernames) =>
      controller._write(_entry, invites: usernames);
  void dispose() {
    if (_released) return;
    _released = true;
    controller._release(_entry);
  }
}

String eventError(Object error, {bool reading = false}) =>
    error is WriteException
    ? error.message
    : reading
    ? 'Unable to load this event. Try again.'
    : 'Unable to confirm the change. The event has been refreshed; check your response before trying again.';
