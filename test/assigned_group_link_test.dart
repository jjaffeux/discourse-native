import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AssignedGroupLink.parse', () {
    test('reads a direct group assignment route and its JSON endpoint', () {
      final link = AssignedGroupLink.parse('/g/support/assigned/support')!;

      expect(link.groupName, 'support');
      expect(
        link.feedPath,
        '/topics/group-topics-assigned/support.json?direct=true',
      );
    });

    test('reads absolute, encoded, and trailing-slash routes', () {
      final link = AssignedGroupLink.parse(
        'https://meta.discourse.org/g/team%2Bops/assigned/team%2Bops/',
      )!;

      expect(link.groupName, 'team+ops');
      expect(
        link.feedPath,
        '/topics/group-topics-assigned/team%2Bops.json?direct=true',
      );
      expect(link.uri.host, 'meta.discourse.org');
    });

    test('reads everyone, direct-group, and member filters', () {
      expect(
        AssignedGroupLink.parse('/g/support/assigned')!.filter,
        const AssignedGroupFilter.everyone(),
      );
      expect(
        AssignedGroupLink.parse('/g/support/assigned/everyone')!.filter,
        const AssignedGroupFilter.everyone(),
      );
      expect(
        AssignedGroupLink.parse('/g/support/assigned/support')!.filter,
        const AssignedGroupFilter.directGroup(),
      );
      expect(
        AssignedGroupLink.parse('/g/support/assigned/Sam')!.filter,
        AssignedGroupFilter.member('sam'),
      );
    });

    test('reads a route under the forum\'s subfolder, and no other', () {
      final link = AssignedGroupLink.parse(
        'https://example.com/forum/g/staff/assigned/everyone',
        siteUrl: 'https://example.com/forum',
      );

      expect(link?.groupName, 'staff');
      expect(
        AssignedGroupLink.parse(
          'https://example.com/g/staff/assigned',
          siteUrl: 'https://example.com/forum',
        ),
        isNull,
      );
    });

    test('does not claim nearby pages', () {
      for (final url in const [
        '/g/support/members',
        '/g/support/assigned/support/preferences',
        '/topics/group-topics-assigned/support',
      ]) {
        expect(AssignedGroupLink.parse(url), isNull, reason: url);
      }
    });

    test('rejects unsafe or oversized aliases', () {
      expect(
        AssignedGroupLink.parse(
          'https://reader:secret@meta.discourse.org/g/a/assigned/a',
        ),
        isNull,
      );
      expect(
        AssignedGroupLink.parse(
          '/g/${'a' * AssignedGroupLink.maximumUrlLength}/assigned/a',
        ),
        isNull,
      );
      expect(AssignedGroupLink.parse('/g/a%2Fb/assigned/a%2Fb'), isNull);
    });
  });
}
