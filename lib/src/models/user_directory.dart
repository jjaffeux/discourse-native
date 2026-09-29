import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'discourse_instance.dart';
import 'json.dart';

enum UserDirectoryPeriod {
  all('all'),
  yearly('yearly'),
  quarterly('quarterly'),
  monthly('monthly'),
  weekly('weekly'),
  daily('daily');

  const UserDirectoryPeriod(this.queryValue);

  final String queryValue;
  String get label => switch (this) {
    all => appL10n.allTime,
    yearly => appL10n.year,
    quarterly => appL10n.quarter,
    monthly => appL10n.month,
    weekly => appL10n.week,
    daily => appL10n.todayDcalendarevents,
  };
}

enum UserDirectoryColumnType {
  automatic,
  userField,
  plugin;

  static UserDirectoryColumnType fromWire(Object? value) => switch (value) {
    'user_field' || 1 => userField,
    'plugin' || 2 => plugin,
    _ => automatic,
  };
}

@immutable
final class UserDirectoryColumn {
  const UserDirectoryColumn({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
    this.icon,
    this.userFieldId,
    this.enabled = true,
  });

  factory UserDirectoryColumn.fromWire(Map<String, dynamic> json) {
    final name = jsonText(json['name']);
    if (name == null) {
      throw FormatException(appL10n.directoryColumnIsMissingItsName);
    }
    return UserDirectoryColumn(
      id: jsonInt(json['id']),
      name: name,
      type: UserDirectoryColumnType.fromWire(json['type']),
      position: jsonInt(json['position']),
      icon: jsonText(json['icon']),
      userFieldId: jsonIntOrNull(json['user_field_id']),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
  }

  final int id;
  final String name;
  final UserDirectoryColumnType type;
  final int position;
  final String? icon;
  final int? userFieldId;
  final bool enabled;

  UserDirectoryColumn copyWith({int? position, bool? enabled}) =>
      UserDirectoryColumn(
        id: id,
        name: name,
        type: type,
        position: position ?? this.position,
        icon: icon,
        userFieldId: userFieldId,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object> toConfigurationWire() => {
    'id': id,
    'enabled': enabled,
    'position': position,
  };

  String get label => switch (name) {
    'likes_received' => appL10n.likesReceived,
    'likes_given' => appL10n.likesGiven,
    'topics_entered' => appL10n.topicsViewed,
    'topic_count' => appL10n.topicsCreated,
    'post_count' => appL10n.repliesPosted,
    'posts_read' || 'posts_read_count' => appL10n.postsRead,
    'days_visited' => appL10n.daysVisited,
    'time_read' => appL10n.timeRead,
    _ => _humanize(name),
  };

  static String _humanize(String value) {
    final words = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (words.isEmpty) return value;
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }
}

@immutable
final class UserDirectoryUser {
  const UserDirectoryUser({
    required this.id,
    required this.username,
    this.name,
    this.title,
    this.avatarUrl,
    this.primaryGroupName,
    this.userFields = const {},
  });

  factory UserDirectoryUser.fromWire(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final username = jsonText(json['username']);
    if (username == null) {
      throw FormatException(appL10n.directoryUserIsMissingAUsername);
    }
    final fields = <int, List<String>>{};
    final rawFields = jsonObject(json['user_fields']);
    for (final entry in rawFields.entries) {
      final id = int.tryParse(entry.key);
      if (id == null || entry.value is! Map<String, dynamic>) continue;
      final values = <String>[
        for (final value in jsonArray(
          (entry.value as Map<String, dynamic>)['value'],
        ))
          ?jsonText(value),
      ];
      if (values.isNotEmpty) fields[id] = List.unmodifiable(values);
    }
    return UserDirectoryUser(
      id: jsonInt(json['id']),
      username: username,
      name: jsonText(json['name']),
      title: jsonText(json['title']),
      avatarUrl: resolveAvatarUrl(
        jsonText(json['avatar_template']),
        siteUrl,
        size: 90,
      ),
      primaryGroupName: jsonText(json['primary_group_name']),
      userFields: Map.unmodifiable(fields),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? title;
  final String? avatarUrl;
  final String? primaryGroupName;
  final Map<int, List<String>> userFields;

  String get displayName => name ?? username;
}

@immutable
final class UserDirectoryItem {
  const UserDirectoryItem({
    required this.id,
    required this.user,
    this.values = const {},
  });

  factory UserDirectoryItem.fromWire(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final userJson = jsonObject(json['user']);
    final user = UserDirectoryUser.fromWire(userJson, siteUrl);
    return UserDirectoryItem(
      id: jsonIntOrNull(json['id']) ?? user.id,
      user: user,
      values: Map.unmodifiable({
        for (final entry in json.entries)
          if (entry.key != 'id' && entry.key != 'user') entry.key: entry.value,
      }),
    );
  }

  final int id;
  final UserDirectoryUser user;
  final Map<String, Object?> values;

  Object? valueFor(UserDirectoryColumn column) {
    if (column.type == UserDirectoryColumnType.userField) {
      final id = column.userFieldId;
      return id == null ? null : user.userFields[id];
    }
    return values[column.name];
  }

  num? numericValueFor(UserDirectoryColumn column) {
    final numeric = switch (valueFor(column)) {
      final num value => value,
      final String value when value.length <= maximumJsonIntegerCodeUnits =>
        num.tryParse(value),
      _ => null,
    };
    return numeric != null && numeric.isFinite ? numeric : null;
  }
}

@immutable
final class UserDirectoryPage {
  const UserDirectoryPage({
    required this.items,
    required this.totalRows,
    this.lastUpdatedAt,
    this.nextPagePath,
  });

  factory UserDirectoryPage.fromWire(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final meta = jsonObject(json['meta']);
    return UserDirectoryPage(
      items: List.unmodifiable([
        for (final item in jsonObjects(json['directory_items']))
          UserDirectoryItem.fromWire(item, siteUrl),
      ]),
      totalRows: jsonInt(meta['total_rows_directory_items']),
      lastUpdatedAt: jsonDate(meta['last_updated_at']),
      nextPagePath: DiscourseInstance.pathAndQueryWithinUrl(
        siteUrl,
        jsonText(meta['load_more_directory_items']),
      ),
    );
  }

  final List<UserDirectoryItem> items;
  final int totalRows;
  final DateTime? lastUpdatedAt;
  final String? nextPagePath;
}

@immutable
final class UserDirectoryMetadata {
  const UserDirectoryMetadata({
    this.columns = const [],
    this.availableColumns = const [],
    this.groupNames = const [],
    this.canManageColumns = false,
  });

  factory UserDirectoryMetadata.fromColumns(
    Map<String, dynamic> json, {
    Iterable<String> groupNames = const [],
    bool editable = false,
  }) {
    final columns = <UserDirectoryColumn>[];
    for (final raw in jsonObjects(json['directory_columns'])) {
      try {
        columns.add(UserDirectoryColumn.fromWire(raw));
      } on FormatException {
        // A plugin can remove a column while an older response is in flight.
      }
    }
    columns.sort((a, b) => a.position.compareTo(b.position));
    final normalizedGroups = <String>{
      for (final group in groupNames)
        if (group.trim().isNotEmpty) group.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return UserDirectoryMetadata(
      columns: List.unmodifiable(
        editable ? columns.where((column) => column.enabled) : columns,
      ),
      availableColumns: List.unmodifiable(columns),
      groupNames: List.unmodifiable(normalizedGroups),
      canManageColumns: editable,
    );
  }

  final List<UserDirectoryColumn> columns;
  final List<UserDirectoryColumn> availableColumns;
  final List<String> groupNames;
  final bool canManageColumns;
}
