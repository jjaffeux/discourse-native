import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four settings default closed and preserve configured emoji order', () {
    final empty = CakedaySettings.read({});
    expect(empty.enabled, isFalse);
    expect(empty.birthdays, isFalse);
    expect(empty.anniversaryEmoji, ['cake']);
    expect(empty.birthdayEmoji, ['birthday']);
    final configured = CakedaySettings.read({
      'cakeday_enabled': true,
      'cakeday_birthday_enabled': true,
      'cakeday_emoji': 'cake|custom_party',
    });
    expect(configured.anniversaryEmoji, ['cake', 'custom_party']);
    expect(
      const CakedaySettingsCodec()
          .decode(const CakedaySettingsCodec().encode(configured))!
          .anniversaryEmoji,
      ['cake', 'custom_party'],
    );
  });
  test(
    'birthdays discard real years and validate civil dates including leap day',
    () {
      expect(CakedayBirthday.parse('1992-02-29')!.wire, '1904-2-29');
      expect(CakedayBirthday.create(2, 29), isNotNull);
      for (final wire in [
        '2000-04-31',
        '2000-13-01',
        '2000-02-30',
        'garbage',
      ]) {
        expect(CakedayBirthday.parse(wire), isNull);
      }
      expect(
        CakedayDate.parse('2020-11-01T23:50:00Z', timestamp: true)!.day,
        1,
      );
      expect(CakedayDate.parse('2020-11-01T23:50:00Z'), isNull);
    },
  );
  test(
    'inline parity excludes join day and does not fold February29 to March1',
    () {
      final dates = CakedayDates.read({
        'cakedate': '2026-11-01',
        'birthdate': '1992-02-29',
      })!;
      expect(dates.celebratesAnniversary(DateTime(2026, 11, 1)), isFalse);
      expect(dates.celebratesAnniversary(DateTime(2027, 11, 1)), isTrue);
      expect(dates.celebratesBirthday(DateTime(2027, 3, 1)), isFalse);
      expect(dates.celebratesBirthday(DateTime(2028, 2, 29)), isTrue);
      expect(CakedayDates.read({}), isNull);
      expect(CakedayDates.read({'birthdate': null})!.birthday, isNull);
    },
  );
  test(
    'preferences distinguish unavailable, invalid and explicit empty with partial fallback',
    () {
      const codec = CakedayPreferenceCodec();
      final known = codec.decode({'birthdate': '1992-02-29'}, null);
      expect(known.payload, {'date_of_birth': '1904-2-29'});
      expect(codec.decode({}, null).available, isFalse);
      expect(codec.decode({}, null).payload, isEmpty);
      expect(codec.decode({}, known), same(known));
      for (final invalid in [
        '2026-04-31',
        false,
        <String, Object?>{},
        'not-a-date',
      ]) {
        expect(codec.decode({'birthdate': invalid}, known).available, isFalse);
        expect(codec.decode({'birthdate': invalid}, known).payload, isEmpty);
      }
      expect(codec.decode({'birthdate': null}, known).payload, {
        'date_of_birth': '',
      });
      expect(codec.decode({'date_of_birth': ''}, known).payload, {
        'date_of_birth': '',
      });
    },
  );
  test(
    'installed record codecs own schemas and drop dates after redacted edit',
    () {
      final installed = PluginInstaller.install(
        const PluginManifest([cakedayModule]),
      );
      addTearDown(installed.close);
      final post = installed.models.post({
        'id': 1,
        'user_id': 4,
        'user_cakedate': '2020-11-01',
        'user_birthdate': '1990-11-01',
      }, 'https://forum.example');
      expect(post.plugins.get(cakedayDatesKey)!.birthday!.wire, '1904-11-1');
      expect(
        const DiscourseModelCodec.core()
            .post({
              'id': 1,
              'user_birthdate': '1990-11-01',
            }, 'https://forum.example')
            .plugins
            .get(cakedayDatesKey),
        isNull,
      );
      final card = installed.models.userCard({
        'id': 4,
        'username': 'maya',
        'birthdate': '1990-11-01',
      }, 'https://forum.example');
      expect(card.plugins.get(cakedayDatesKey)!.birthday!.month, 11);
      final redacted = installed.models.post({
        'id': 1,
        'user_id': 4,
      }, 'https://forum.example');
      final merged = installed.registry.mergeAfterPostEdit(
        held: post.plugins,
        incoming: redacted.plugins,
      );
      expect(merged.get(cakedayDatesKey), isNull);
      final nullDates = installed.models.post({
        'id': 1,
        'user_id': 4,
        'user_birthdate': null,
        'user_cakedate': null,
      }, 'https://forum.example');
      final explicit = installed.registry
          .mergeAfterPostEdit(held: post.plugins, incoming: nullDates.plugins)
          .get(cakedayDatesKey)!;
      expect(explicit.birthday, isNull);
      expect(explicit.joined, isNull);
    },
  );
  test('query IDs retain month and reject invalid/foreign destinations', () {
    final query = CakedayQuery.parse('cakeday/birthdays/all/11')!;
    expect(query.period, CakedayPeriod.month);
    expect(query.month, 11);
    expect(query.path(2), '/cakeday/birthdays.json?page=2&month=11');
    for (final route in [
      'cakeday/birthdays/all/13',
      'cakeday/birthdays/all/0',
      'other/birthdays/today',
      'cakeday/invalid/today',
      'cakeday/birthdays/today/extra',
    ]) {
      expect(CakedayQuery.parse(route), isNull);
    }
  });
}
