import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart' show listEquals;

const cakedayPluginId = PluginId('discourse-cakeday');
const cakedaySettingsKey = PluginDataKey<CakedaySettings>(
  owner: 'discourse-cakeday',
  name: 'settings',
);
const cakedayDatesKey = PluginDataKey<CakedayDates>(
  owner: 'discourse-cakeday',
  name: 'dates',
);
const cakedayPreferenceSection = PreferenceSection.plugin(
  owner: 'discourse-cakeday',
  name: 'birthday',
);

final class CakedaySettings {
  const CakedaySettings({
    this.enabled = false,
    this.birthdays = false,
    this.anniversaryEmoji = const ['cake'],
    this.birthdayEmoji = const ['birthday'],
  });
  final bool enabled, birthdays;
  final List<String> anniversaryEmoji, birthdayEmoji;
  @override
  bool operator ==(Object other) =>
      other is CakedaySettings &&
      enabled == other.enabled &&
      birthdays == other.birthdays &&
      listEquals(anniversaryEmoji, other.anniversaryEmoji) &&
      listEquals(birthdayEmoji, other.birthdayEmoji);

  @override
  int get hashCode => Object.hash(
    enabled,
    birthdays,
    Object.hashAll(anniversaryEmoji),
    Object.hashAll(birthdayEmoji),
  );

  factory CakedaySettings.read(Map<String, dynamic> json) => CakedaySettings(
    enabled: json['cakeday_enabled'] == true,
    birthdays: json['cakeday_birthday_enabled'] == true,
    anniversaryEmoji: _emoji(json['cakeday_emoji'], 'cake'),
    birthdayEmoji: _emoji(json['cakeday_birthday_emoji'], 'birthday'),
  );
  static List<String> _emoji(Object? value, String fallback) =>
      List.unmodifiable(
        (value is String ? value : fallback)
            .split('|')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty),
      );
}

final class CakedaySettingsCodec
    extends PluginDataPersistenceCodec<CakedaySettings> {
  const CakedaySettingsCodec();
  @override
  PluginDataKey<CakedaySettings> get key => cakedaySettingsKey;
  @override
  CakedaySettings? decode(Object? value) => value is Map
      ? CakedaySettings.read(Map<String, dynamic>.from(value))
      : null;
  @override
  Object encode(CakedaySettings value) => {
    'cakeday_enabled': value.enabled,
    'cakeday_birthday_enabled': value.birthdays,
    'cakeday_emoji': value.anniversaryEmoji.join('|'),
    'cakeday_birthday_emoji': value.birthdayEmoji.join('|'),
  };
}

final class CakedayDate {
  const CakedayDate._(this.year, this.month, this.day);
  final int year, month, day;
  static CakedayDate? parse(Object? value, {bool timestamp = false}) {
    if (value is! String) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(.*)$',
    ).firstMatch(value);
    if (match == null || (!timestamp && match[4]!.isNotEmpty)) return null;
    if (match[4]!.isNotEmpty &&
        (!match[4]!.startsWith('T') || DateTime.tryParse(value) == null)) {
      return null;
    }
    final y = int.parse(match[1]!),
        m = int.parse(match[2]!),
        d = int.parse(match[3]!);
    final date = DateTime.utc(y, m, d);
    return y > 0 && date.year == y && date.month == m && date.day == d
        ? CakedayDate._(y, m, d)
        : null;
  }

  DateTime get date => DateTime.utc(year, month, day);
  @override
  bool operator ==(Object other) =>
      other is CakedayDate &&
      (year, month, day) == (other.year, other.month, other.day);
  @override
  int get hashCode => Object.hash(year, month, day);
}

final class CakedayBirthday {
  const CakedayBirthday._(this.month, this.day);
  final int month, day;
  static CakedayBirthday? create(int month, int day) {
    final date = DateTime.utc(1904, month, day);
    return date.month == month && date.day == day
        ? CakedayBirthday._(month, day)
        : null;
  }

  static CakedayBirthday? parse(Object? value, {bool timestamp = false}) {
    final date = CakedayDate.parse(value, timestamp: timestamp);
    return date == null ? null : create(date.month, date.day);
  }

  String get wire => '1904-$month-$day';
  DateTime get date => DateTime.utc(1904, month, day);
  @override
  bool operator ==(Object other) =>
      other is CakedayBirthday && (month, day) == (other.month, other.day);
  @override
  int get hashCode => Object.hash(month, day);
}

final class CakedayDates {
  const CakedayDates({this.joined, this.birthday});
  final CakedayDate? joined;
  final CakedayBirthday? birthday;

  @override
  bool operator ==(Object other) =>
      other is CakedayDates &&
      joined == other.joined &&
      birthday == other.birthday;

  @override
  int get hashCode => Object.hash(joined, birthday);

  static CakedayDates? read(Map<String, dynamic> json, {bool post = false}) {
    final joinKey = post ? 'user_cakedate' : 'cakedate';
    final birthKey = post ? 'user_birthdate' : 'birthdate';
    if (!json.containsKey(joinKey) && !json.containsKey(birthKey)) return null;
    return CakedayDates(
      joined: CakedayDate.parse(json[joinKey]),
      birthday: CakedayBirthday.parse(json[birthKey]),
    );
  }

  bool celebratesBirthday(DateTime today) =>
      birthday?.month == today.month && birthday?.day == today.day;
  bool celebratesAnniversary(DateTime today) =>
      joined != null &&
      joined!.year < today.year &&
      joined!.month == today.month &&
      joined!.day == today.day;
}

enum CakedayKind { birthdays, anniversaries }

enum CakedayPeriod { today, tomorrow, upcoming, month }

final class CakedayQuery {
  const CakedayQuery(this.kind, this.period, {this.month = 1})
    : assert(month >= 1 && month <= 12);
  final CakedayKind kind;
  final CakedayPeriod period;
  final int month;
  String get id =>
      'cakeday/${kind.name}/${period == CakedayPeriod.month ? 'all/$month' : period.name}';
  String path(int page) => Uri(
    path: '/cakeday/${kind.name}.json',
    queryParameters: {
      'page': '$page',
      if (period == CakedayPeriod.month)
        'month': '$month'
      else
        'filter': period.name,
    },
  ).toString();
  static CakedayQuery? parse(String id, {DateTime? today}) {
    final parts = id.split('/');
    if (parts.length < 2 || parts[0] != 'cakeday') return null;
    final kind = CakedayKind.values
        .where((v) => v.name == parts[1])
        .firstOrNull;
    if (kind == null) return null;
    if (parts.length == 2) return CakedayQuery(kind, CakedayPeriod.today);
    if (parts[2] == 'all' && parts.length <= 4) {
      final month = parts.length == 4
          ? int.tryParse(parts[3])
          : (today ?? DateTime.now()).month;
      return month != null && month >= 1 && month <= 12
          ? CakedayQuery(kind, CakedayPeriod.month, month: month)
          : null;
    }
    final period = CakedayPeriod.values
        .where((v) => v != CakedayPeriod.month && v.name == parts[2])
        .firstOrNull;
    return parts.length == 3 && period != null
        ? CakedayQuery(kind, period)
        : null;
  }

  @override
  bool operator ==(Object other) =>
      other is CakedayQuery &&
      kind == other.kind &&
      period == other.period &&
      (period != CakedayPeriod.month || month == other.month);
  @override
  int get hashCode =>
      Object.hash(kind, period, period == CakedayPeriod.month ? month : null);
}

final class CakedayMember {
  const CakedayMember({
    required this.id,
    required this.username,
    this.name,
    this.title,
    this.avatarTemplate,
    this.birthday,
    this.joined,
  });
  final int id;
  final String username;
  final String? name, title, avatarTemplate;
  final CakedayBirthday? birthday;
  final CakedayDate? joined;
  static CakedayMember read(Object? value, CakedayKind kind) {
    if (value is! Map) {
      throw const FormatException('Invalid celebration member');
    }
    final id = value['id'], username = value['username'];
    if (id is! int || id <= 0 || username is! String || username.isEmpty) {
      throw const FormatException('Invalid celebration identity');
    }
    final birthday = kind == CakedayKind.birthdays
        ? CakedayBirthday.parse(value['cakedate'], timestamp: true)
        : null;
    final joined = kind == CakedayKind.anniversaries
        ? CakedayDate.parse(value['cakedate'], timestamp: true)
        : null;
    if (birthday == null && joined == null) {
      throw const FormatException('Invalid celebration date');
    }
    return CakedayMember(
      id: id,
      username: username,
      name: value['name'] is String ? value['name'] as String : null,
      title: value['title'] is String ? value['title'] as String : null,
      avatarTemplate: value['avatar_template'] is String
          ? value['avatar_template'] as String
          : null,
      birthday: birthday,
      joined: joined,
    );
  }
}

final class CakedayPage {
  const CakedayPage(this.members, this.total, this.nextPage);
  final List<CakedayMember> members;
  final int total;
  final int? nextPage;
}

final class CakedayPreferences implements UserPreferenceValues {
  const CakedayPreferences(this.birthday) : available = true, valid = true;
  const CakedayPreferences.invalid(this.birthday)
    : available = true,
      valid = false;
  const CakedayPreferences.unavailable()
    : available = false,
      valid = false,
      birthday = null;
  final bool available, valid;
  final CakedayBirthday? birthday;
  @override
  Map<String, Object?> get payload =>
      available && valid ? {'date_of_birth': birthday?.wire ?? ''} : const {};
  @override
  bool operator ==(Object other) =>
      other is CakedayPreferences &&
      available == other.available &&
      valid == other.valid &&
      birthday == other.birthday;
  @override
  int get hashCode => Object.hash(available, valid, birthday);
}

final class CakedayPreferenceCodec implements UserPreferenceCodec {
  const CakedayPreferenceCodec();
  @override
  PreferenceSection get section => cakedayPreferenceSection;
  @override
  Set<String> get fields => const {'date_of_birth'};
  @override
  CakedayPreferences decode(
    Map<String, dynamic> json,
    UserPreferenceValues? fallback,
  ) {
    final key = json.containsKey('birthdate')
        ? 'birthdate'
        : json.containsKey('date_of_birth')
        ? 'date_of_birth'
        : null;
    if (key == null) {
      return fallback is CakedayPreferences
          ? fallback
          : const CakedayPreferences.unavailable();
    }
    final wire = json[key];
    if (wire == null || wire == '') return const CakedayPreferences(null);
    final value = CakedayBirthday.parse(wire);
    return value == null
        ? const CakedayPreferences.unavailable()
        : CakedayPreferences(value);
  }
}
