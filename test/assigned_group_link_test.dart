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

    test('does not claim other Assign group filters or nearby pages', () {
      for (final url in const [
        '/g/support/assigned/everyone',
        '/g/support/assigned/sam',
        '/g/support/assigned',
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
