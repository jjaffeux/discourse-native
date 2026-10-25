import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';

void main() {
  group('Assign session capability state', () {
    test(
      'preserves present true and false values from a fresh session',
      () async {
        final api = DiscourseApi(
          models: DiscourseModelCodec(
            extensions: pluginRegistry,
            recommendationSources: pluginRegistry,
            icons: pluginRegistry,
          ),
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
          models: DiscourseModelCodec(
            extensions: pluginRegistry,
            recommendationSources: pluginRegistry,
            icons: pluginRegistry,
          ),
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
        final stored = DiscourseUser.fromJson(const {
          'username': 'sam',
        }, extensions: pluginRegistry);

        expect(live.canAssign, isNull);
        expect(live.canAssignGlobally, isNull);
        expect(stored.canAssign, isNull);
        expect(stored.canAssignGlobally, isNull);
      },
    );

    test('round trips capabilities through persisted account JSON', () {
      final user = DiscourseUser(
        username: 'sam',
        plugins: PluginData.none.withValue(
          assignCurrentUserDataKey,
          const AssignCurrentUser(canAssign: false, canAssignGlobally: true),
        ),
      );

      final restored = DiscourseUser.fromJson(
        jsonDecode(jsonEncode(user.toJson(extensions: pluginRegistry)))
            as Map<String, dynamic>,
        extensions: pluginRegistry,
      );

      expect(restored, user);
    });
  });

  group('Assign payload defaults', () {
    test('statuses stay off unless the site enables them', () {
      expect(
        AssignSettings.fromWire(const {'assign_statuses': 'New|Done'}),
        const AssignSettings(),
      );
      expect(
        AssignSettings.fromWire(const {
          'enable_assign_status': true,
          'assign_statuses': ' New || Done ',
        }).statuses,
        ['New', 'Done'],
      );
      expect(
        assignSettingsPersistenceCodec.decode(const {'statuses': <Object>[]}),
        const AssignSettings(),
      );
    });

    test('one present capability leaves the other unknown', () {
      expect(
        AssignCurrentUser.fromWire(const {'can_assign': true}),
        const AssignCurrentUser(canAssign: true),
      );
      expect(
        AssignCurrentUser.fromWire(const {'can_assign_globally': true}),
        const AssignCurrentUser(canAssignGlobally: true),
      );
    });

    test('a stored record without boolean capabilities is absent', () {
      expect(
        assignCurrentUserPersistenceCodec.decode(const {'canAssign': 'yes'}),
        isNull,
      );
      expect(
        assignCurrentUserPersistenceCodec.decodeLegacy(const {
          'canAssign': true,
        }),
        const AssignCurrentUser(canAssign: true),
      );
    });
  });
}
