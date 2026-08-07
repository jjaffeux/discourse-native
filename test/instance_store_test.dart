import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = InstanceStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('load', () {
    test('answers an empty rail when nothing was stored', () async {
      expect(await store.load(), isEmpty);
    });

    test('answers an empty rail when the stored blob is blank', () async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': '',
      });
      expect(await store.load(), isEmpty);
    });

    test('answers an empty rail when the stored blob cannot be read',
        () async {
      // A shape change should cost the user their list, not crash the app.
      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': 'not json',
      });
      expect(await store.load(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': '[1, 2, 3]',
      });
      expect(await store.load(), isEmpty);
    });
  });

  group('round trip', () {
    test('brings back everything save() was given', () async {
      const instance = DiscourseInstance(
        url: 'https://meta.discourse.org',
        title: 'Meta',
        description: 'About Discourse',
        iconUrl: 'https://meta.discourse.org/uploads/default/icon.png',
        apiVersion: 20250101,
        loginRequired: true,
        user: DiscourseUser(
          username: 'sam',
          id: 3,
          name: 'Sam Saffron',
          avatarUrl: 'https://meta.discourse.org/avatar.png',
        ),
        config: SiteConfig(
          emojiSet: 'apple_classic',
          externalEmojiUrl: 'https://cdn.example.com/emoji',
          mainReaction: 'heart',
          offeredReactions: ['heart', '+1'],
          allowAnyEmoji: true,
          desaturatedReactionPanel: true,
        ),
      );

      await store.save([instance]);
      final loaded = await store.load();

      expect(loaded, hasLength(1));
      final back = loaded.single;
      expect(back.url, instance.url);
      expect(back.title, instance.title);
      expect(back.description, instance.description);
      expect(back.iconUrl, instance.iconUrl);
      expect(back.apiVersion, instance.apiVersion);
      expect(back.loginRequired, instance.loginRequired);
      expect(back.user, instance.user);
      expect(back.config, instance.config);
    });

    test('keeps the rail in order, and keeps a signed-out site', () async {
      const first = DiscourseInstance(url: 'https://one.example.com',
          title: 'One');
      const second = DiscourseInstance(url: 'https://two.example.com',
          title: 'Two');

      await store.save([first, second]);
      final loaded = await store.load();

      expect(loaded.map((i) => i.url), [first.url, second.url]);
      expect(loaded.every((i) => !i.isConnected), isTrue);
    });

    test('saving an empty rail wipes the stored one', () async {
      await store.save([
        const DiscourseInstance(url: 'https://one.example.com', title: 'One'),
      ]);
      await store.save(const []);

      expect(await store.load(), isEmpty);
    });
  });
}
