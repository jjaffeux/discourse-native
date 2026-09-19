import 'dart:io';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/application_cooking.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/cooking/cooking_module.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'installed Chat and dates preserve native capabilities and cook without HTTP',
    () async {
      var clients = 0;
      await HttpOverrides.runZoned(
        () async {
          final installed = PluginInstaller.install(
            PluginManifest([cookingModule, chatModule, localDatesModule]),
          );
          final app = ApplicationCooking(plugins: installed);
          addTearDown(app.dispose);
          addTearDown(installed.close);
          final config = SiteConfig(
            plugins: PluginData.none
                .withValue(chatSettingsDataKey, const ChatSettings())
                .withValue(
                  localDatesSettingsDataKey,
                  const LocalDatesSettings(enabled: true),
                ),
          );
          Future<String> cook(
            String raw, {
            CookingContext context = const CookingContext(),
            String site = 'https://a.test',
            CookingProfile profile = CookingProfile.chat,
            SiteConfig? settings,
          }) async {
            final request = app.request(
              siteUrl: site,
              accountId: '7',
              raw: raw,
              config: settings ?? config,
              profile: profile,
              context: context,
            );
            final result = await app.cook(request);
            expect(result.failure, isNull);
            expect(result.requestFingerprint, request.fingerprint);
            return result.html;
          }

          expect(
            await cook(
              '/me **waves**',
              context: const CookingContext(authorUsername: '<Alice>'),
            ),
            contains(
              '<em class="chat-message-action">&lt;Alice&gt; <strong>waves</strong></em>',
            ),
          );
          expect(await cook('/shrug'), '<p>¯\\_(ツ)_/¯</p>');
          expect(await cook('# Title'), '<p># Title</p>');
          expect(
            await cook('# Title', context: const CookingContext(authorId: -1)),
            contains('<h1>'),
          );
          expect(
            await cook('<kbd onclick="bad()">K</kbd>'),
            '<p><kbd>K</kbd></p>',
          );
          expect(
            await cook(
              '[date=2026-3-29 time=02:30:00 timezone="Europe/Paris"]',
            ),
            contains('2026-03-29T01:30:00Z'),
          );
          expect(
            await cook(
              '[date=2026-3-29 format="LL"]',
              context: const CookingContext(locale: 'fr'),
            ),
            contains('29 mars 2026'),
          );
          expect(
            await cook('[date=2026-3-29 format="LL"]', site: 'https://b.test'),
            contains('March 29, 2026'),
          );
          const transcript =
              '[chat quote="Alice;1;2026-01-01T12:00:00Z" channel="General" channelId="2"]\n# Heading\n[/chat]';
          expect(
            await cook(transcript, profile: CookingProfile.post),
            contains('<p># Heading</p>'),
          );
          expect(
            await cook(transcript, site: 'https://b.test'),
            contains('https://b.test/chat/c/-/2/1'),
          );
          final lease = app.captureUploads('https://a.test', '7');
          expect(
            app.ingestMetadata(
              lease,
              CookingCachedMetadata(
                mentions: {
                  'Alice': const CookingMention(
                    username: 'Alice',
                    href: '/u/alice',
                    kind: CookingMentionKind.user,
                  ),
                },
              ),
            ),
            isTrue,
          );
          expect(
            await cook('@ALICE'),
            contains('<a class="mention" href="/u/alice">@Alice</a>'),
          );
          expect(await cook('`x\u202ey`'), contains('bidi-warning'));
          expect(await cook('x\u202ey'), isNot(contains('bidi-warning')));
          expect(
            await cook('[link](https://external.test)'),
            contains('rel="noopener nofollow ugc"'),
          );
          expect(
            await cook('[link](https://a.test)'),
            isNot(contains('nofollow')),
          );
          final disabled = config.withPlugins(
            config.plugins
                .withValue(
                  chatSettingsDataKey,
                  const ChatSettings(chatEnabled: false),
                )
                .withValue(
                  localDatesSettingsDataKey,
                  const LocalDatesSettings(enabled: false),
                ),
          );
          expect(await cook('/shrug', settings: disabled), '<p>/shrug</p>');
          expect(
            await cook('[date=2026-3-29]', settings: disabled),
            isNot(contains('discourse-local-date')),
          );
          app.forget('https://a.test');
          expect(app.ingestMetadata(lease, CookingCachedMetadata()), isFalse);
        },
        createHttpClient: (_) {
          clients++;
          throw StateError('Compiler attempted HTTP');
        },
      );
      expect(clients, 0);
    },
  );
  test(
    'shell cached collection merges leased enrichment and preserves subfolder paths',
    () async {
      final installed = PluginInstaller.install(
        const PluginManifest([cookingModule, chatModule]),
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        plugins: installed,
      );
      addTearDown(() async {
        shell.dispose();
        await shell.cooking.dispose();
        await installed.close();
      });
      const site = 'https://a.test/forum';
      shell.store.put<UserCard>(
        site,
        const UserCard(username: 'Alice', avatarUrl: 'https://a.test/a.png'),
      );
      final lease = shell.cooking.captureUploads(site, 'anonymous');
      expect(
        shell.cooking.ingestMetadata(
          lease,
          CookingCachedMetadata(
            oneboxes: {
              'https://external.test/box':
                  '<aside class="onebox">Cached card</aside>',
            },
            primaryGroups: {'Alice': 'team'},
            inlineOneboxes: {
              'https://external.test/inline': const CookingInlineOnebox(
                title: 'Inline cached title',
              ),
            },
          ),
        ),
        isTrue,
      );
      final request = shell.cookingRequest(
        siteUrl: site,
        raw:
            '@Alice\n\nhttps://external.test/box\n\nLook https://external.test/inline',
        profile: CookingProfile.chat,
      );
      expect(request.snapshot.oneboxes, isNotEmpty);
      expect(request.snapshot.primaryGroups['Alice'], 'team');
      final result = await shell.cooking.cook(request);
      expect(result.failure, isNull);
      expect(result.html, contains('href="/forum/u/Alice"'));
      expect(result.html, contains('Cached card'));
      expect(result.html, contains('Inline cached title'));
    },
  );
}
