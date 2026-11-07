import '../models/badge.dart';
import '../models/badge_route.dart';

abstract interface class BadgesApi {
  static const int pageSize = 96;

  Future<BadgeCatalog> catalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<DiscourseBadge> badge({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  });

  Future<BadgeGrantPage> grants({
    required String siteUrl,
    required BadgeRoute route,
    int offset = 0,
    String? apiKey,
    String? clientId,
  });
}
