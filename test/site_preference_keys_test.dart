import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _perForum = SitePreferenceKey('test.per-forum');
const _perName = SitePreferenceKey(
  'test.per-name',
  tail: SitePreferenceTail.name,
);
const _perAccount = SitePreferenceKey(
  'test.per-account',
  tail: SitePreferenceTail.id,
);
const _perRoomAccount = SitePreferenceKey(
  'test.per-room-account',
  tail: SitePreferenceTail.idPair,
);

const _short = 'https://a.b';
const _long = 'https://a.b.c';
const _subfolder = 'https://a.b/forum';
const _longSubfolder = 'https://a.b/forum.old';

String _encoded(String siteUrl) => Uri.encodeComponent(siteUrl);

/// One value of every shape for each forum, plus a key no forum owns.
Map<String, Object> _stored(Iterable<String> sites) => {
  'test.global': true,
  for (final site in sites) ...{
    _perForum.of(site): true,
    '${_perName.of(site)}.${_encoded('sam')}': 'sam',
    '${_perAccount.of(site)}.7': true,
    '${_perRoomAccount.of(site)}.3.7': 0.5,
  },
};

Future<Set<String>> _keys() async =>
    (await SharedPreferences.getInstance()).getKeys();

Set<String> _keysOf(String siteUrl) =>
    _stored([siteUrl]).keys.toSet()..remove('test.global');

void main() {
  const shapes = [_perForum, _perName, _perAccount, _perRoomAccount];

  group('SitePreferenceKey', () {
    test('reads a key back as the forum that wrote it', () {
      expect(_perForum.sitesIn(_perForum.of(_long)), [_long]);
      expect(_perForum.sitesIn(_perForum.of(_subfolder)), [_subfolder]);
      expect(_perAccount.sitesIn('${_perAccount.of(_short)}.-1'), [_short]);
      expect(_perRoomAccount.sitesIn('${_perRoomAccount.of(_long)}.3.7'), [
        _long,
      ]);
    });

    test('an encoded forum is not followed by more of another URL', () {
      // `https://a.b.c` spells `https://a.b` and then `.c`.
      expect(_perForum.sitesIn(_perForum.of(_long)), isNot(contains(_short)));
      expect(
        _perAccount.sitesIn('${_perAccount.of(_long)}.7'),
        isNot(contains(_short)),
      );
      expect(
        _perForum.sitesIn(_perForum.of(_longSubfolder)),
        isNot(contains(_subfolder)),
      );
    });

    test('a name after the forum can make the key name several', () {
      final key = '${_perName.of(_short)}.${_encoded('c.d')}';

      expect(_perName.sitesIn(key), ['https://a', _short, _long]);
    });

    test('keys of another preference name no forum', () {
      expect(_perAccount.sitesIn(_perForum.of(_short)), isEmpty);
      expect(_perForum.sitesIn('test.per-forum-other.x'), isEmpty);
      expect(_perForum.sitesIn('test.per-forum'), isEmpty);
    });
  });

  group('forgetSitePreferences', () {
    const everyForum = [_short, _long, _subfolder, _longSubfolder];

    setUp(() => SharedPreferences.setMockInitialValues(_stored(everyForum)));

    test(
      'retirement precedes cached deletion even without stored keys',
      () async {
        final preferences = await SharedPreferences.getInstance();
        final decisions = <ForgottenSites>[];
        final key = SitePreferenceKey(
          'test.retirement',
          onForget: (sites) {
            expect(preferences.containsKey(_perForum.of(_short)), isTrue);
            decisions.add(sites);
          },
        );
        await forgetSitePreferences([
          ...shapes,
          key,
        ], () => ForgottenSites.removed(_short, keeping: const [_long]));
        expect(decisions, hasLength(1));
        expect(decisions.single.includes(_short), isTrue);
        expect(decisions.single.includes(_long), isFalse);
        expect(preferences.containsKey(_perForum.of(_short)), isFalse);
      },
    );

    test('a declined removal keeps pending preference operations', () async {
      var retired = false;
      final key = SitePreferenceKey(
        'test.retirement',
        onForget: (_) => retired = true,
      );
      await forgetSitePreferences([key], () => null);
      expect(retired, isFalse);
    });

    test('a removed forum loses only its own values', () async {
      for (final removed in [_short, _subfolder]) {
        final keeping = everyForum.where((site) => site != removed);

        await forgetSitePreferences(
          shapes,
          () => ForgottenSites.removed(removed, keeping: keeping),
        );

        final keys = await _keys();
        expect(keys.intersection(_keysOf(removed)), isEmpty, reason: removed);
        for (final kept in keeping) {
          expect(keys, containsAll(_keysOf(kept)), reason: kept);
        }
        expect(keys, contains('test.global'));
        SharedPreferences.setMockInitialValues(_stored(everyForum));
      }
    });

    test('a forum whose URL begins the others leaves theirs', () async {
      await forgetSitePreferences(
        shapes,
        () => ForgottenSites.removed('https://a', keeping: everyForum),
      );

      expect(await _keys(), _stored(everyForum).keys.toSet());
    });

    test('a key a kept forum could have written stays', () async {
      final ambiguous = '${_perName.of(_short)}.${_encoded('c.d')}';
      SharedPreferences.setMockInitialValues({ambiguous: 'c.d'});

      await forgetSitePreferences(
        shapes,
        () => ForgottenSites.removed(_short, keeping: const [_long]),
      );
      expect(await _keys(), {ambiguous});

      await forgetSitePreferences(
        shapes,
        () => ForgottenSites.removed(_short, keeping: const []),
      );
      expect(await _keys(), isEmpty);
    });

    test('forums off the rail lose their values', () async {
      await forgetSitePreferences(
        shapes,
        () => ForgottenSites.except(const [_long, _subfolder]),
      );

      expect(await _keys(), {
        'test.global',
        ..._keysOf(_long),
        ..._keysOf(_subfolder),
        // Also what `https://a.b/forum` keeps for the name `old.sam`.
        '${_perName.of(_longSubfolder)}.sam',
      });
    });

    test('nothing goes when the decision declines', () async {
      await forgetSitePreferences(shapes, () => null);

      expect(await _keys(), _stored(everyForum).keys.toSet());
    });

    test('forums are compared as the key spells them', () async {
      const lowercase = SitePreferenceKey(
        'test.lowercase',
        spelling: _lowercase,
      );
      SharedPreferences.setMockInitialValues({
        lowercase.of('https://A.B'): true,
        lowercase.of('https://Other.example'): true,
      });

      await forgetSitePreferences(const [
        lowercase,
      ], () => ForgottenSites.except(const ['https://a.B']));

      expect(await _keys(), {lowercase.of(_short)});
      expect(
        ForgottenSites.removed(
          'https://A.b',
          keeping: const [],
        ).includes(_short, lowercase),
        isTrue,
      );
    });
  });
}

String _lowercase(String siteUrl) => siteUrl.toLowerCase();
