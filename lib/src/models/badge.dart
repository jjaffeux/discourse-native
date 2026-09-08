import 'package:flutter/foundation.dart';

import 'badge_route.dart';
import 'json.dart';

enum BadgeTier {
  gold(1, 'Gold'),
  silver(2, 'Silver'),
  bronze(3, 'Bronze');

  const BadgeTier(this.id, this.label);
  final int id;
  final String label;

  static BadgeTier fromId(int id) =>
      values.firstWhere((tier) => tier.id == id, orElse: () => bronze);
}

@immutable
final class DiscourseBadge {
  const DiscourseBadge({
    required this.id,
    required this.name,
    this.description = '',
    this.longDescription = '',
    this.icon = 'certificate',
    this.imageUrl,
    this.slug,
    this.tier = BadgeTier.bronze,
    this.groupingId = 0,
    this.grantCount = 0,
    this.hasBadge,
    this.allowTitle = false,
    this.multipleGrant = false,
  });

  factory DiscourseBadge.fromJson(Map<String, dynamic> json, String siteUrl) =>
      DiscourseBadge(
        id: jsonInt(json['id']),
        name: jsonText(json['name']) ?? 'Badge',
        description: jsonString(json['description']),
        longDescription: jsonString(json['long_description']),
        icon: jsonText(json['icon']) ?? 'certificate',
        imageUrl: resolveAvatarUrl(jsonText(json['image_url']), siteUrl),
        slug: jsonText(json['slug']),
        tier: BadgeTier.fromId(
          jsonInt(
            json['badge_type_id'] ?? jsonObject(json['badge_type'])['id'],
          ),
        ),
        groupingId: jsonInt(
          json['badge_grouping_id'] ?? jsonObject(json['badge_grouping'])['id'],
        ),
        grantCount: jsonInt(json['grant_count']).clamp(0, 0x7fffffffffffffff),
        hasBadge: json['has_badge'] is bool ? json['has_badge'] as bool : null,
        allowTitle: json['allow_title'] == true,
        multipleGrant: json['multiple_grant'] == true,
      );

  final int id;
  final String name;
  final String description;
  final String longDescription;
  final String icon;
  final String? imageUrl;
  final String? slug;
  final BadgeTier tier;
  final int groupingId;
  final int grantCount;
  final bool? hasBadge;
  final bool allowTitle;
  final bool multipleGrant;

  BadgeRoute get route => BadgeRoute.detail(id, slug: slug);
}

@immutable
final class BadgeGroup {
  BadgeGroup({
    required this.id,
    required this.name,
    required Iterable<DiscourseBadge> badges,
  }) : badges = List.unmodifiable(badges);

  final int id;
  final String name;
  final List<DiscourseBadge> badges;
}

@immutable
final class BadgeCatalog {
  BadgeCatalog(Iterable<BadgeGroup> groups)
    : groups = List.unmodifiable(groups);

  factory BadgeCatalog.fromJson(Map<String, dynamic> json, String siteUrl) {
    final groupings = {
      for (final group in jsonObjects(json['badge_groupings']))
        jsonInt(group['id']): group,
    };
    final byGroup = <int, List<DiscourseBadge>>{};
    final seen = <int>{};
    for (final raw in jsonObjects(json['badges'])) {
      if (raw['enabled'] == false || raw['listable'] == false) continue;
      final badge = DiscourseBadge.fromJson(raw, siteUrl);
      if (badge.id <= 0 || !seen.add(badge.id)) continue;
      final embedded = jsonObject(raw['badge_grouping']);
      if (embedded.isNotEmpty) {
        groupings.putIfAbsent(badge.groupingId, () => embedded);
      }
      byGroup.putIfAbsent(badge.groupingId, () => []).add(badge);
    }
    final ids = byGroup.keys.toList()
      ..sort((a, b) {
        final order = (jsonIntOrNull(groupings[a]?['position']) ?? 999)
            .compareTo(jsonIntOrNull(groupings[b]?['position']) ?? 999);
        return order == 0 ? a.compareTo(b) : order;
      });
    return BadgeCatalog([
      for (final id in ids)
        BadgeGroup(
          id: id,
          name: jsonText(groupings[id]?['name']) ?? 'Other',
          badges: byGroup[id]!
            ..sort((a, b) {
              // Core presents bronze, silver, then gold within each grouping.
              final tier = b.tier.id.compareTo(a.tier.id);
              return tier == 0
                  ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
                  : tier;
            }),
        ),
    ]);
  }

  final List<BadgeGroup> groups;
  int get total =>
      groups.fold(0, (total, group) => total + group.badges.length);
  int get earned => groups.fold(
    0,
    (total, group) =>
        total + group.badges.where((badge) => badge.hasBadge == true).length,
  );
  bool get hasPersonalState => groups.any(
    (group) => group.badges.any((badge) => badge.hasBadge != null),
  );
}

@immutable
final class BadgeGrant {
  const BadgeGrant({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
    this.grantedAt,
    this.topicId,
    this.topicSlug,
    this.topicTitle,
    this.postNumber,
  });

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final DateTime? grantedAt;
  final int? topicId;
  final String? topicSlug;
  final String? topicTitle;
  final int? postNumber;

  String? get postPath => topicId == null
      ? null
      : Uri(
          pathSegments: [
            '',
            't',
            topicSlug ?? 'topic',
            '$topicId',
            if (postNumber != null) '$postNumber',
          ],
        ).toString();
}

@immutable
final class BadgeGrantPage {
  BadgeGrantPage({
    required Iterable<BadgeGrant> grants,
    required this.rawCount,
    this.total,
  }) : grants = List.unmodifiable(grants);

  factory BadgeGrantPage.fromJson(Map<String, dynamic> json, String siteUrl) {
    final info = jsonObject(json['user_badge_info']);
    final rows = jsonObjects(info['user_badges']).toList();
    final users = {
      for (final user in [
        ...jsonObjects(json['users']),
        ...jsonObjects(info['users']),
      ])
        jsonInt(user['id']): user,
    };
    final topics = {
      for (final topic in [
        ...jsonObjects(json['topics']),
        ...jsonObjects(info['topics']),
      ])
        jsonInt(topic['id']): topic,
    };
    final grants = <BadgeGrant>[];
    for (final row in rows) {
      final user = row['user'] is Map
          ? jsonObject(row['user'])
          : users[jsonInt(row['user_id'])] ?? const <String, dynamic>{};
      final topic = row['topic'] is Map
          ? jsonObject(row['topic'])
          : topics[jsonInt(row['topic_id'])] ?? const <String, dynamic>{};
      final id = jsonInt(row['id']);
      final username = jsonText(user['username']);
      if (id <= 0 || username == null) continue;
      final topicId = jsonInt(topic['id']);
      final postNumber = jsonInt(row['post_number']);
      grants.add(
        BadgeGrant(
          id: id,
          username: username,
          name: jsonText(user['name']),
          avatarUrl: resolveAvatarUrl(
            jsonText(user['avatar_template']),
            siteUrl,
          ),
          grantedAt: jsonDate(row['granted_at']),
          // Core omits the topic object for posts the viewer cannot see.
          topicId: topicId > 0 ? topicId : null,
          topicSlug: jsonText(topic['slug']),
          topicTitle: jsonText(jsonTitle(topic['title'], topic['fancy_title'])),
          postNumber: postNumber > 0 ? postNumber : null,
        ),
      );
    }
    return BadgeGrantPage(
      grants: grants,
      rawCount: rows.length,
      total: jsonIntOrNull(info['grant_count']),
    );
  }

  final List<BadgeGrant> grants;
  final int rawCount;
  final int? total;
}
