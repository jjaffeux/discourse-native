import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';

const gamificationPluginId = PluginId('discourse-gamification');
const gamificationSettingsKey = PluginDataKey<GamificationSettings>(
  owner: 'discourse-gamification',
  name: 'site-settings',
);
const gamificationUserScoreKey = PluginDataKey<GamificationUserScore>(
  owner: 'discourse-gamification',
  name: 'user-score',
);

Map<String, dynamic> gameObject(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  return Map<String, dynamic>.from(value);
}

int gameInt(Object? value, {int? minimum}) {
  if (value is! int || (minimum != null && value < minimum)) {
    throw const FormatException('Expected integer');
  }
  return value;
}

String gameString(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

List<T> gameList<T>(Object? value, T Function(Object?) decode) {
  if (value is! List) throw const FormatException('Expected list');
  return List.unmodifiable(value.map(decode));
}

Set<int> gameIds(Object? value) => Set.unmodifiable(
  gameList(value ?? const [], (v) => gameInt(v, minimum: 0)),
);
DCalendarDate? gameDate(Object? value) {
  if (value == null || value == '') return null;
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Expected calendar date');
  }
  final parts = value.split('-').map(int.parse).toList();
  try {
    return DCalendarDate(parts[0], parts[1], parts[2]);
  } on ArgumentError {
    throw const FormatException('Invalid calendar date');
  }
}

DateTime gameInstant(Object? value) => DateTime.parse(gameString(value));

final class GamificationSettings {
  const GamificationSettings({required this.enabled});
  final bool enabled;
  @override
  bool operator ==(Object other) =>
      other is GamificationSettings && enabled == other.enabled;
  @override
  int get hashCode => enabled.hashCode;
}

final class GamificationSettingsCodec
    extends PluginDataPersistenceCodec<GamificationSettings> {
  const GamificationSettingsCodec();
  @override
  PluginDataKey<GamificationSettings> get key => gamificationSettingsKey;
  @override
  GamificationSettings? decode(Object? value) =>
      value is Map && value['enabled'] is bool
      ? GamificationSettings(enabled: value['enabled'] as bool)
      : null;
  @override
  Object encode(GamificationSettings value) => {'enabled': value.enabled};
}

final class GamificationUserScore {
  const GamificationUserScore(this.totalScore);
  final int totalScore;
}

enum GamificationPeriod {
  allTime('all_time'),
  yearly('yearly'),
  quarterly('quarterly'),
  monthly('monthly'),
  weekly('weekly'),
  daily('daily');

  const GamificationPeriod(this.wire);
  final String wire;
  static GamificationPeriod decode(Object? value) {
    if (value == 'all') return allTime;
    for (final period in values) {
      if (value == period.wire || value == period.index) return period;
    }
    throw const GamificationUnsupportedResponse();
  }
}

final class GamificationAmbiguousWrite implements Exception {
  const GamificationAmbiguousWrite();
}

final class GamificationUnsupportedResponse implements Exception {
  const GamificationUnsupportedResponse();
}

enum GamificationRule {
  likeGiven('like_given'),
  likeReceived('like_received'),
  solution('solution'),
  userInvited('user_invited'),
  timeRead('time_read'),
  postRead('post_read'),
  topicCreated('topic_created'),
  postCreated('post_created'),
  flagCreated('flag_created'),
  dayVisited('day_visited'),
  reactionReceived('reaction_received'),
  reactionGiven('reaction_given'),
  chatReactionReceived('chat_reaction_received'),
  chatReactionGiven('chat_reaction_given'),
  chatMessageCreated('chat_message_created');

  const GamificationRule(this.wire);
  final String wire;
  String get setting => '${wire}_score_value';
}

enum GamificationRankingStrategy {
  denseRank('dense_rank'),
  rank('rank'),
  rowNumber('row_number');

  const GamificationRankingStrategy(this.wire);
  final String wire;
  static GamificationRankingStrategy decode(Object? value) => values.firstWhere(
    (v) => v.wire == value,
    orElse: () => throw const GamificationUnsupportedResponse(),
  );
}

sealed class LeaderboardTarget {
  const LeaderboardTarget();
  int? get id;
}

final class DefaultLeaderboard extends LeaderboardTarget {
  const DefaultLeaderboard();
  @override
  int? get id => null;
}

final class LeaderboardById extends LeaderboardTarget {
  const LeaderboardById(this.id) : assert(id > 0);
  @override
  final int id;
}

final class GamificationQuery {
  const GamificationQuery({
    this.target = const DefaultLeaderboard(),
    this.period,
  });
  final LeaderboardTarget target;
  final GamificationPeriod? period;
  GamificationQuery withPeriod(GamificationPeriod value) =>
      GamificationQuery(target: target, period: value);
  @override
  bool operator ==(Object other) =>
      other is GamificationQuery &&
      target.id == other.target.id &&
      period == other.period;
  @override
  int get hashCode => Object.hash(target.id, period);
}

final class GamificationLeaderboard {
  GamificationLeaderboard.decode(Object? value) {
    final j = gameObject(value);
    id = gameInt(j['id'], minimum: 1);
    name = gameString(j['name']);
    createdById = gameInt(j['created_by_id']);
    fromDate = gameDate(j['from_date']);
    toDate = gameDate(j['to_date']);
    defaultPeriod = GamificationPeriod.decode(j['default_period']);
    periodFilterDisabled = j['period_filter_disabled'] == true;
    visibleToGroupIds = gameIds(j['visible_to_groups_ids']);
    includedGroupIds = gameIds(j['included_groups_ids']);
    excludedGroupIds = gameIds(j['excluded_groups_ids']);
    updatedAt = gameInstant(j['updated_at']);
  }
  late final int id, createdById;
  late final String name;
  late final DCalendarDate? fromDate, toDate;
  late final GamificationPeriod defaultPeriod;
  late final bool periodFilterDisabled;
  late final Set<int> visibleToGroupIds, includedGroupIds, excludedGroupIds;
  late final DateTime updatedAt;
}

final class GamificationRankedUser {
  GamificationRankedUser.decode(Object? value) {
    final j = gameObject(value);
    id = gameInt(j['id'], minimum: 1);
    username = gameString(j['username']);
    name = j['name'] as String?;
    avatarTemplate = j['avatar_template'] as String?;
    totalScore = gameInt(j['total_score']);
    position = gameInt(j['position'], minimum: 1);
  }
  late final int id, totalScore, position;
  late final String username;
  late final String? name, avatarTemplate;
}

sealed class GamificationPersonalRank {
  const GamificationPersonalRank();
}

final class AnonymousRank extends GamificationPersonalRank {
  const AnonymousRank();
}

final class UnrankedMember extends GamificationPersonalRank {
  const UnrankedMember();
}

final class RankedMember extends GamificationPersonalRank {
  const RankedMember(this.user);
  final GamificationRankedUser user;
}

sealed class LeaderboardRead {
  const LeaderboardRead();
}

final class LeaderboardReady extends LeaderboardRead {
  const LeaderboardReady(this.board, this.users, this.personal);
  final GamificationLeaderboard board;
  final List<GamificationRankedUser> users;
  final GamificationPersonalRank personal;
}

final class LeaderboardPreparing extends LeaderboardRead {
  const LeaderboardPreparing({required this.reason, this.board});
  final String reason;
  final GamificationLeaderboard? board;
}

final class GamificationBoardDraft {
  GamificationBoardDraft({
    required this.name,
    this.fromDate,
    this.toDate,
    this.defaultPeriod = GamificationPeriod.allTime,
    this.periodFilterDisabled = false,
    Set<int> visibleToGroupIds = const {},
    Set<int> includedGroupIds = const {},
    Set<int> excludedGroupIds = const {},
    Set<int> categoryIds = const {},
    Map<GamificationRule, int> scoreOverrides = const {},
  }) : visibleToGroupIds = Set.unmodifiable(visibleToGroupIds),
       includedGroupIds = Set.unmodifiable(includedGroupIds),
       excludedGroupIds = Set.unmodifiable(excludedGroupIds),
       categoryIds = Set.unmodifiable(categoryIds),
       scoreOverrides = Map.unmodifiable(scoreOverrides);
  final String name;
  final DCalendarDate? fromDate, toDate;
  final GamificationPeriod defaultPeriod;
  final bool periodFilterDisabled;
  final Set<int> visibleToGroupIds,
      includedGroupIds,
      excludedGroupIds,
      categoryIds;
  final Map<GamificationRule, int> scoreOverrides;
  bool get valid =>
      name.trim().isNotEmpty &&
      (fromDate == null || toDate == null || !fromDate!.isAfter(toDate!)) &&
      scoreOverrides.values.every((v) => v >= 0) &&
      [
        ...visibleToGroupIds,
        ...includedGroupIds,
        ...excludedGroupIds,
        ...categoryIds,
      ].every((id) => id >= 0);
  Map<String, Object?> toBody() {
    if (!valid) throw ArgumentError('Invalid leaderboard draft');
    return {
      'name': name,
      'from_date': fromDate?.toString() ?? '',
      'to_date': toDate?.toString() ?? '',
      'default_period': defaultPeriod.index,
      'period_filter_disabled': periodFilterDisabled,
      'visible_to_groups_ids': visibleToGroupIds.toList(),
      'included_groups_ids': includedGroupIds.toList(),
      'excluded_groups_ids': excludedGroupIds.toList(),
      'scorable_category_ids': categoryIds.toList(),
      'score_overrides': {
        for (final e in scoreOverrides.entries) e.key.wire: e.value,
      },
    };
  }
}

final class GamificationCreator {
  GamificationCreator.decode(Object? value) {
    final j = gameObject(value);
    id = gameInt(j['id']);
    username = gameString(j['username']);
    name = j['name'] as String?;
    avatarTemplate = j['avatar_template'] as String?;
  }
  late final int id;
  late final String username;
  late final String? name, avatarTemplate;
}

final class GamificationAdminBoard {
  GamificationAdminBoard.decode(Object? value) {
    final j = gameObject(value);
    board = GamificationLeaderboard.decode(j);
    final overrides = gameObject(j['score_overrides'] ?? {});
    final decoded = <GamificationRule, int>{};
    for (final e in overrides.entries) {
      final matches = GamificationRule.values.where((r) => r.wire == e.key);
      if (matches.isEmpty) throw const GamificationUnsupportedResponse();
      decoded[matches.single] = gameInt(e.value, minimum: 0);
    }
    draft = GamificationBoardDraft(
      name: board.name,
      fromDate: board.fromDate,
      toDate: board.toDate,
      defaultPeriod: board.defaultPeriod,
      periodFilterDisabled: board.periodFilterDisabled,
      visibleToGroupIds: board.visibleToGroupIds,
      includedGroupIds: board.includedGroupIds,
      excludedGroupIds: board.excludedGroupIds,
      categoryIds: gameIds(j['scorable_category_ids']),
      scoreOverrides: decoded,
    );
    creator = j['created_by'] == null
        ? null
        : GamificationCreator.decode(j['created_by']);
  }
  late final GamificationLeaderboard board;
  late final GamificationBoardDraft draft;
  late final GamificationCreator? creator;
}

final class GamificationGroup {
  GamificationGroup.decode(Object? value) {
    final j = gameObject(value);
    id = gameInt(j['id'], minimum: 0);
    name = gameString(j['name']);
    displayName = j['display_name'] as String?;
  }
  late final int id;
  late final String name;
  late final String? displayName;
}

final class GamificationAdminIndex {
  const GamificationAdminIndex(
    this.boards,
    this.groups,
    this.recalculationsRemaining,
  );
  final List<GamificationAdminBoard> boards;
  final List<GamificationGroup> groups;
  final int recalculationsRemaining;
}

final class GamificationGlobalSettings {
  GamificationGlobalSettings({
    required this.enabled,
    required Set<int> categoryIds,
    required Map<GamificationRule, int> weights,
    required this.ranking,
  }) : categoryIds = Set.unmodifiable(categoryIds),
       weights = Map.unmodifiable(weights);
  final bool enabled;
  final Set<int> categoryIds;
  final Map<GamificationRule, int> weights;
  final GamificationRankingStrategy ranking;
  bool get valid =>
      weights.length == GamificationRule.values.length &&
      categoryIds.every((v) => v >= 0);
}

final class ScoreEventQuery {
  const ScoreEventQuery({this.id, this.userId, this.date});
  final int? id, userId;
  final DCalendarDate? date;
}

final class GamificationScoreEvent {
  GamificationScoreEvent.decode(Object? value) {
    final j = gameObject(value);
    id = gameInt(j['id'], minimum: 1);
    userId = gameInt(j['user_id']);
    points = gameInt(j['points']);
    date = gameDate(j['date']) ?? (throw const FormatException('Missing date'));
    categoryId = j['category_id'] == null
        ? null
        : gameInt(j['category_id'], minimum: 0);
    description = j['description'] as String?;
    createdAt = gameInstant(j['created_at']);
    updatedAt = gameInstant(j['updated_at']);
  }
  late final int id, userId, points;
  late final int? categoryId;
  late final DCalendarDate date;
  late final String? description;
  late final DateTime createdAt, updatedAt;
}

final class CreateScoreEvent {
  const CreateScoreEvent({
    required this.userId,
    required this.date,
    required this.points,
    this.description,
    this.categoryId,
  });
  final int userId, points;
  final DCalendarDate date;
  final String? description;
  final int? categoryId;
}

final class EditScoreEvent {
  const EditScoreEvent({
    required this.id,
    required this.points,
    required this.description,
    required this.categoryId,
  });
  final int id, points;
  final String? description;
  final int? categoryId;
}

enum RecalculationPreset {
  tenDays,
  thirtyDays,
  ninetyDays,
  lastYear,
  allTime,
  custom,
}

DCalendarDate recalculationDate(
  RecalculationPreset preset,
  DateTime now, {
  DCalendarDate? custom,
}) {
  final today = DCalendarDate.fromDateTime(now.toUtc());
  return switch (preset) {
    RecalculationPreset.tenDays => today.addDays(-10),
    RecalculationPreset.thirtyDays => today.addDays(-30),
    RecalculationPreset.ninetyDays => today.addDays(-90),
    RecalculationPreset.lastYear => today.addMonths(-12),
    RecalculationPreset.allTime => DCalendarDate(2014, 8, 26),
    RecalculationPreset.custom => custom ?? today,
  };
}
