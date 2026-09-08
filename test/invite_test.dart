import 'package:discourse_native/src/models/invite.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/invite_fixtures.dart';

void main() {
  test(
    'reads pending details and redeemed users without merging shared invites',
    () {
      final pending = InvitePage.fromJson(
        invitePage(
          [
            {...inviteRow(1, email: 'sam@example.com'), 'emailed': true},
          ],
          pending: 3,
          expired: 1,
          redeemed: 2,
        ),
      );
      expect(pending.counts, {
        InviteFilter.pending: 3,
        InviteFilter.expired: 1,
        InviteFilter.redeemed: 2,
      });
      expect(pending.canSeeDetails, isTrue);
      final invite = pending.invites.single;
      expect(invite.label, 'sam@example.com');
      expect(invite.emailed, isTrue);
      expect(invite.canDelete, isTrue);
      expect(invite.expiresAt, DateTime.utc(2026, 12, 1, 12));

      final redeemed = InvitePage.fromJson(
        invitePage([
          {
            'id': 1,
            'user': {'id': 10, 'username': 'sam'},
            'redeemed_at': '2026-09-08T12:00:00Z',
            'invite_source': 'email',
          },
          {
            'id': 1,
            'user': {'id': 11, 'username': 'alex'},
            'invite_source': 'link',
          },
        ]),
      );
      expect(redeemed.invites.map((invite) => invite.label), ['sam', 'alex']);
      expect(redeemed.invites.first.redeemedAt, DateTime.utc(2026, 9, 8, 12));
      expect(redeemed.invites.first.inviteSource, 'email');
    },
  );

  test(
    'ignores malformed rows without losing the server pagination offset',
    () {
      final page = InvitePage.fromJson({
        'invites': [
          null,
          false,
          const {'id': 'bad'},
          inviteRow(2),
        ],
        'counts': const {'pending': '4', 'expired': -3},
      });
      expect(page.invites.map((invite) => invite.id), [2]);
      expect(page.rowCount, 4);
      expect(page.counts[InviteFilter.expired], 0);
      expect(page.canSeeDetails, isFalse);
    },
  );

  test(
    'persists invite settings and retains them when plugin settings change',
    () {
      final config = SiteConfig.fromSettings(const {
        'allow_email_invites': false,
        'invite_expiry_days': 30,
        'invite_link_max_redemptions_limit': 50,
        'invite_link_max_redemptions_limit_users': 3,
      });
      expect(config.invites.allowEmail, isFalse);
      expect(config.invites.expiryDays, 30);
      expect(config.invites.defaultRedemptions(staff: true), 50);
      expect(config.invites.defaultRedemptions(staff: false), 3);
      expect(SiteConfig.fromJson(config.toJson()), config);
      expect(config.withPlugins(config.plugins), config);
      expect(config, isNot(const SiteConfig()));
      expect(const InviteSettings().defaultRedemptions(staff: true), 100);
      expect(const InviteSettings().defaultRedemptions(staff: false), 10);
    },
  );
}
