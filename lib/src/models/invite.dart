import 'package:flutter/foundation.dart';

import 'json.dart';

enum InviteFilter {
  pending('Pending', 'No pending invites.'),
  expired('Expired', 'No expired invites.'),
  redeemed('Redeemed', 'No redeemed invites yet.');

  const InviteFilter(this.label, this.emptyMessage);

  final String label;
  final String emptyMessage;
}

@immutable
final class InviteSettings {
  const InviteSettings({
    this.allowEmail = true,
    this.expiryDays = 90,
    this.staffRedemptionLimit = 5000,
    this.userRedemptionLimit = 10,
  });

  factory InviteSettings.fromJson(Map<String, dynamic> json) => InviteSettings(
    allowEmail: json['allow_email_invites'] != false,
    expiryDays:
        jsonIntOrNull(json['invite_expiry_days'])?.clamp(0, 36500) ?? 90,
    staffRedemptionLimit:
        jsonIntOrNull(
          json['invite_link_max_redemptions_limit'],
        )?.clamp(1, 1000000) ??
        5000,
    userRedemptionLimit:
        jsonIntOrNull(
          json['invite_link_max_redemptions_limit_users'],
        )?.clamp(1, 1000000) ??
        10,
  );

  final bool allowEmail;
  final int expiryDays;
  final int staffRedemptionLimit;
  final int userRedemptionLimit;

  int redemptionLimit({required bool staff}) =>
      staff ? staffRedemptionLimit : userRedemptionLimit;

  int defaultRedemptions({required bool staff}) =>
      (staff ? 100 : 10).clamp(1, redemptionLimit(staff: staff));

  Map<String, dynamic> toJson() => {
    'allow_email_invites': allowEmail,
    'invite_expiry_days': expiryDays,
    'invite_link_max_redemptions_limit': staffRedemptionLimit,
    'invite_link_max_redemptions_limit_users': userRedemptionLimit,
  };

  @override
  bool operator ==(Object other) =>
      other is InviteSettings &&
      other.allowEmail == allowEmail &&
      other.expiryDays == expiryDays &&
      other.staffRedemptionLimit == staffRedemptionLimit &&
      other.userRedemptionLimit == userRedemptionLimit;

  @override
  int get hashCode => Object.hash(
    allowEmail,
    expiryDays,
    staffRedemptionLimit,
    userRedemptionLimit,
  );
}

@immutable
final class DiscourseInvite {
  const DiscourseInvite({
    required this.id,
    this.email,
    this.link,
    this.description,
    this.domain,
    this.emailed = false,
    this.canDelete = false,
    this.redemptionCount = 0,
    this.maxRedemptions = 1,
    this.expiresAt,
    this.expired = false,
    this.redeemedAt,
    this.username,
    this.userId,
    this.inviteSource,
  });

  factory DiscourseInvite.fromJson(Map<String, dynamic> json) {
    final user = jsonObject(json['user']);
    return DiscourseInvite(
      id: jsonInt(json['id']),
      email: jsonText(json['email']),
      link: jsonText(json['link']),
      description: jsonText(json['description']),
      domain: jsonText(json['domain']),
      emailed: json['emailed'] == true,
      canDelete: json['can_delete_invite'] == true,
      redemptionCount: jsonInt(json['redemption_count']).clamp(0, 1000000),
      maxRedemptions:
          jsonIntOrNull(json['max_redemptions_allowed'])?.clamp(1, 1000000) ??
          1,
      expiresAt: jsonDate(json['expires_at']),
      expired: json['expired'] == true,
      redeemedAt: jsonDate(json['redeemed_at']),
      username: jsonText(user['username']),
      userId: jsonIntOrNull(user['id']),
      inviteSource: jsonText(json['invite_source']),
    );
  }

  final int id;
  final String? email;
  final String? link;
  final String? description;
  final String? domain;
  final bool emailed;
  final bool canDelete;
  final int redemptionCount;
  final int maxRedemptions;
  final DateTime? expiresAt;
  final bool expired;
  final DateTime? redeemedAt;
  final String? username;
  final int? userId;
  final String? inviteSource;

  String get label => username ?? email ?? description ?? 'Invite link';
}

@immutable
final class InvitePage {
  const InvitePage({
    this.invites = const [],
    this.counts = const {},
    this.canSeeDetails = false,
    this.error,
    this.rowCount = 0,
  });

  factory InvitePage.fromJson(Map<String, dynamic> json) {
    final counts = jsonObject(json['counts']);
    return InvitePage(
      invites: List.unmodifiable([
        for (final row in jsonObjects(json['invites']))
          if (DiscourseInvite.fromJson(row) case final invite
              when invite.id > 0)
            invite,
      ]),
      counts: Map.unmodifiable({
        for (final filter in InviteFilter.values)
          filter: jsonInt(counts[filter.name]).clamp(0, 1 << 31),
      }),
      canSeeDetails: json['can_see_invite_details'] == true,
      error: jsonText(json['error']),
      rowCount: jsonArray(json['invites']).length,
    );
  }

  final List<DiscourseInvite> invites;
  final Map<InviteFilter, int> counts;
  final bool canSeeDetails;
  final String? error;
  final int rowCount;
}

@immutable
final class InviteDraft {
  const InviteDraft({
    this.email = '',
    this.description = '',
    this.customMessage = '',
    required this.maxRedemptions,
    required this.expiresAt,
    this.sendEmail = false,
  });

  final String email;
  final String description;
  final String customMessage;
  final int maxRedemptions;
  final DateTime expiresAt;
  final bool sendEmail;

  Map<String, Object?> toWire() => {
    if (email.trim().isNotEmpty) 'email': email.trim(),
    'description': description.trim(),
    if (email.trim().isNotEmpty) 'custom_message': customMessage.trim(),
    'max_redemptions_allowed': email.trim().isEmpty ? maxRedemptions : 1,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    if (email.trim().isNotEmpty && sendEmail) 'send_email': true,
    if (!sendEmail) 'skip_email': true,
  };
}
