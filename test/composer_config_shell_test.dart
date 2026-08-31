import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('passes site authoring settings to the composer', () async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      ]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: {
          _site: SiteConfig.fromSettings(const {
            'enable_auto_grid_images': false,
            'enable_markdown_linkify': false,
            'markdown_linkify_tlds': 'fr|dev',
          }),
        },
      ),
      authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpEventQueue();

    shell.store.put(
      _site,
      const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
    );
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    shell.openReply();

    expect(shell.visibleComposer?.enableAutoGridImages, isFalse);
    expect(shell.visibleComposer?.text.enableMarkdownLinkify, isFalse);
    expect(shell.visibleComposer?.text.markdownLinkifyTlds, ['fr', 'dev']);
  });

  test('an open composer adopts authoring settings after cold load', () async {
    final configGate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': <Topic>[]},
      siteConfigs: const {
        _site: SiteConfig(
          enableAutoGridImages: false,
          enableMarkdownLinkify: false,
          markdownLinkifyTlds: ['fr'],
        ),
      },
      siteConfigGate: configGate,
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpEventQueue();
    expect(api.siteConfigsRequested, [_site]);

    shell.store.put(
      _site,
      const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
    );
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    shell.openReply();
    final composer = shell.visibleComposer;

    expect(composer?.enableAutoGridImages, isTrue);
    expect(composer?.text.enableMarkdownLinkify, isTrue);

    configGate.complete();
    await pumpEventQueue();

    expect(shell.visibleComposer, same(composer));
    expect(composer?.enableAutoGridImages, isFalse);
    expect(composer?.text.enableMarkdownLinkify, isFalse);
    expect(composer?.text.markdownLinkifyTlds, ['fr']);
  });
}
