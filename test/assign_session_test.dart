import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Assign session capabilities', () {
    test(
      'preserves present true and false values from a fresh session',
      () async {
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'current_user': {
                  'username': 'sam',
                  'can_assign': true,
                  'can_assign_globally': false,
                },
              }),
              200,
            ),
          ),
        );

        final user = await api.currentUser(
          siteUrl: 'https://example.com',
          apiKey: 'key',
        );

        expect(user.canAssign, isTrue);
        expect(user.canAssignGlobally, isFalse);
      },
    );

    test(
      'keeps absent capabilities unknown for optional plugin safety',
      () async {
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'current_user': {'username': 'sam'},
              }),
              200,
            ),
          ),
        );

        final live = await api.currentUser(
          siteUrl: 'https://example.com',
          apiKey: 'key',
        );
        final stored = DiscourseUser.fromJson(const {'username': 'sam'});

        expect(live.canAssign, isNull);
        expect(live.canAssignGlobally, isNull);
        expect(stored.canAssign, isNull);
        expect(stored.canAssignGlobally, isNull);
      },
    );

    test('round trips capabilities through persisted account JSON', () {
      const user = DiscourseUser(
        username: 'sam',
        canAssign: false,
        canAssignGlobally: true,
      );

      final restored = DiscourseUser.fromJson(
        jsonDecode(jsonEncode(user.toJson())) as Map<String, dynamic>,
      );

      expect(restored, user);
    });
  });
}
