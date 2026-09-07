import 'package:flutter/foundation.dart';

import '../../plugin_api/preserved_json.dart';
import '../../plugin_api/site_plugin_api.dart';

const eventsPluginId = PluginId('discourse-events');
const eventPostKey = PluginDataKey<EventPostData>(
  owner: 'discourse-events',
  name: 'post',
);
const eventTopicKey = PluginDataKey<EventTopicData>(
  owner: 'discourse-events',
  name: 'topic',
);
const eventSettingsKey = PluginDataKey<EventSettings>(
  owner: 'discourse-events',
  name: 'settings',
);
const eventUserKey = PluginDataKey<EventUserPermissions>(
  owner: 'discourse-events',
  name: 'current-user',
);

Map<String, Object?>? eventObject(Object? value) => value is Map
    ? Map.unmodifiable({
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: _freeze(entry.value),
      })
    : null;

Object? _freeze(Object? value) => value is Map
    ? eventObject(value)
    : value is List
    ? List<Object?>.unmodifiable(value.map(_freeze))
    : value;

String? eventText(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
int? eventInt(Object? value) => value is int ? value : null;
int? _positive(Object? value) => switch (eventInt(value)) {
  final id? when id > 0 => id,
  _ => null,
};

/// The frozen wire snapshot preserves optional fields and distinguishes
/// withheld private data from empty data. Unknown fields survive decoding.
@immutable
final class PostEvent {
  const PostEvent._(this.id, this.topicId, this.fields);

  static PostEvent? decode(Object? value, {int? topicId}) {
    final fields = eventObject(value);
    final id = _positive(fields?['id']);
    if (fields == null || id == null) return null;
    final post = eventObject(fields['post']);
    if (post?['id'] != null && post!['id'] != id) return null;
    final topic = eventObject(post?['topic']);
    return PostEvent._(id, _positive(topic?['id']) ?? topicId, fields);
  }

  /// Event IDs are post IDs; the topic is a separate identifier.
  final int id;
  final int? topicId;
  final Map<String, Object?> fields;

  String? text(String key) => eventText(fields[key]);
  bool flag(String key) => fields[key] == true;
  String get title =>
      text('name') ??
      eventText(eventObject(eventObject(fields['post'])?['topic'])?['title']) ??
      'Event';
  String? get startsAt => text('starts_at');
  String? get endsAt => text('ends_at');
  String? get timezone => text('timezone');
  String? get recurrence => text('recurrence');
  bool get recurring => recurrence != null && recurrence != 'none';
  bool get allDay => flag('all_day');
  bool get showLocalTime => flag('show_local_time');
  bool get canManage => flag('can_act_on_discourse_post_event');
  bool get canRespond =>
      flag('can_update_attendance') &&
      !flag('is_closed') &&
      !flag('is_expired') &&
      !flag('is_standalone');
  bool get public => flag('is_public') || text('status') == 'public';
  bool get private => flag('is_private') || text('status') == 'private';
  bool get displayInvitees => flag('should_display_invitees');
  EventInvitee? get watching => EventInvitee.decode(fields['watching_invitee']);
  Map<String, Object?>? get stats => eventObject(fields['stats']);
  EventPerson? get creator => EventPerson.decode(fields['creator']);
  List<EventInvitee> get sampleInvitees => _invitees(fields['sample_invitees']);
  String get topicPath =>
      eventText(eventObject(fields['post'])?['url']) ??
      (topicId == null ? '/p/$id' : '/t/$topicId/1');
  bool canChoose(String status) =>
      canRespond &&
      (status != 'going' ||
          !flag('at_capacity') ||
          watching?.status == 'going');

  @override
  bool operator ==(Object other) =>
      other is PostEvent &&
      id == other.id &&
      topicId == other.topicId &&
      deepJsonEquals(fields, other.fields);
  @override
  int get hashCode => Object.hash(id, topicId, deepJsonHash(fields));
}

@immutable
final class EventPerson {
  const EventPerson({
    required this.username,
    this.id,
    this.name,
    this.avatarTemplate,
  });
  static EventPerson? decode(Object? value) {
    final fields = eventObject(value);
    final username = eventText(fields?['username']);
    return username == null
        ? null
        : EventPerson(
            username: username,
            id: _positive(fields?['id']),
            name: eventText(fields?['name']),
            avatarTemplate: eventText(fields?['avatar_template']),
          );
  }

  final int? id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  String? avatarUrl(String siteUrl) {
    final path = avatarTemplate?.replaceAll('{size}', '80');
    return path == null
        ? null
        : Uri.parse('$siteUrl/').resolve(path).toString();
  }
}

@immutable
final class EventInvitee {
  const EventInvitee({
    this.id,
    this.status,
    required this.recurring,
    required this.user,
  });
  static EventInvitee? decode(Object? value) {
    final fields = eventObject(value);
    final user = EventPerson.decode(fields?['user']);
    return user == null
        ? null
        : EventInvitee(
            id: _positive(fields?['id']),
            status: eventText(fields?['status']),
            recurring: fields?['recurring'] == true,
            user: user,
          );
  }

  final int? id;
  final String? status;
  final bool recurring;
  final EventPerson user;
}

List<EventInvitee> _invitees(Object? value) => List.unmodifiable([
  if (value is List)
    for (final item in value) ?EventInvitee.decode(item),
]);

@immutable
final class EventPostData {
  EventPostData({this.event, Map<int, PostEvent> oneboxes = const {}})
    : oneboxes = Map.unmodifiable(oneboxes);

  static EventPostData? decode(Map<String, dynamic> json) {
    final event = PostEvent.decode(
      json['event'],
      topicId: eventInt(json['topic_id']),
    );
    final oneboxes = <int, PostEvent>{};
    final entries = eventObject(json['event_oneboxes']);
    if (entries != null) {
      for (final entry in entries.entries) {
        final topicId = int.tryParse(entry.key);
        final event = PostEvent.decode(entry.value, topicId: topicId);
        if (topicId != null &&
            topicId > 0 &&
            event != null &&
            event.topicId == topicId) {
          oneboxes[topicId] = event;
        }
      }
    }
    return event == null && oneboxes.isEmpty
        ? null
        : EventPostData(event: event, oneboxes: oneboxes);
  }

  final PostEvent? event;
  final Map<int, PostEvent> oneboxes;
  @override
  bool operator ==(Object other) =>
      other is EventPostData &&
      event == other.event &&
      mapEquals(oneboxes, other.oneboxes);
  @override
  int get hashCode => Object.hash(
    event,
    Object.hashAllUnordered(
      oneboxes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

@immutable
final class EventTopicData {
  const EventTopicData({
    required this.startsAt,
    this.endsAt,
    this.timezone,
    this.allDay = false,
    this.showLocalTime = false,
  });
  static EventTopicData? decode(Map<String, dynamic> json) {
    final start = eventText(json['event_starts_at']);
    return start == null
        ? null
        : EventTopicData(
            startsAt: start,
            endsAt: eventText(json['event_ends_at']),
            timezone: eventText(json['event_timezone']),
            allDay: json['event_all_day'] == true,
            showLocalTime: json['event_show_local_time'] == true,
          );
  }

  final String startsAt;
  final String? endsAt;
  final String? timezone;
  final bool allDay;
  final bool showLocalTime;
  @override
  bool operator ==(Object other) =>
      other is EventTopicData &&
      startsAt == other.startsAt &&
      endsAt == other.endsAt &&
      timezone == other.timezone &&
      allDay == other.allDay &&
      showLocalTime == other.showLocalTime;
  @override
  int get hashCode =>
      Object.hash(startsAt, endsAt, timezone, allDay, showLocalTime);
}

@immutable
final class EventSettings {
  const EventSettings({
    this.enabled = false,
    this.buttons = const ['going', 'interested', 'not_going'],
    this.displayTopicDate = true,
    this.customFields = const [],
  });
  factory EventSettings.decode(Map<String, Object?> json) => EventSettings(
    enabled:
        json['discourse_events_enabled'] == true &&
        json['discourse_post_event_enabled'] == true,
    buttons: List.unmodifiable(
      _settingList(
            json['event_participation_buttons'] ?? 'going|interested|not going',
          )
          .map((s) => s.replaceAll(' ', '_'))
          .where(eventResponseStatuses.contains),
    ),
    displayTopicDate: json['display_post_event_date_on_topic_title'] != false,
    customFields: _settingList(
      json['discourse_post_event_allowed_custom_fields'],
    ),
  );
  final bool enabled;
  final List<String> buttons;
  final bool displayTopicDate;
  final List<String> customFields;
  @override
  bool operator ==(Object other) =>
      other is EventSettings &&
      enabled == other.enabled &&
      displayTopicDate == other.displayTopicDate &&
      listEquals(buttons, other.buttons) &&
      listEquals(customFields, other.customFields);
  @override
  int get hashCode => Object.hash(
    enabled,
    displayTopicDate,
    Object.hashAll(buttons),
    Object.hashAll(customFields),
  );
}

const eventResponseStatuses = ['going', 'interested', 'not_going'];

String eventLinkUrl(String value) =>
    RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(value)
    ? value
    : value.startsWith('//')
    ? 'https:$value'
    : 'https://$value';
List<String> _settingList(Object? value) => List.unmodifiable(
  (value is String
          ? value.split('|')
          : value is List
          ? value.whereType<String>()
          : <String>[])
      .where((s) => s.isNotEmpty),
);

@immutable
final class EventUserPermissions {
  const EventUserPermissions(this.canCreate);
  final bool canCreate;
  static EventUserPermissions? decode(Map<String, Object?> json) =>
      json['can_create_discourse_post_event'] is bool
      ? EventUserPermissions(json['can_create_discourse_post_event'] == true)
      : null;
  @override
  bool operator ==(Object other) =>
      other is EventUserPermissions && canCreate == other.canCreate;
  @override
  int get hashCode => canCreate.hashCode;
}

final class EventSettingsCodec
    extends PluginDataPersistenceCodec<EventSettings> {
  const EventSettingsCodec();
  @override
  PluginDataKey<EventSettings> get key => eventSettingsKey;
  @override
  EventSettings? decode(Object? value) => switch (eventObject(value)) {
    final fields? => EventSettings.decode(fields),
    _ => null,
  };
  @override
  Object encode(EventSettings value) => {
    'discourse_events_enabled': value.enabled,
    'discourse_post_event_enabled': value.enabled,
    'event_participation_buttons': value.buttons,
    'display_post_event_date_on_topic_title': value.displayTopicDate,
    'discourse_post_event_allowed_custom_fields': value.customFields,
  };
}

final class EventUserCodec
    extends PluginDataPersistenceCodec<EventUserPermissions> {
  const EventUserCodec();
  @override
  PluginDataKey<EventUserPermissions> get key => eventUserKey;
  @override
  EventUserPermissions? decode(Object? value) => switch (eventObject(value)) {
    final fields? => EventUserPermissions.decode(fields),
    _ => null,
  };
  @override
  Object encode(EventUserPermissions value) => {
    'can_create_discourse_post_event': value.canCreate,
  };
}
