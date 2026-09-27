import 'dart:async';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
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

  group('staff attachments in messages', () {
    for (final (name, staff, place, allowed) in [
      ('staff in a new message', true, _Place.newMessage, true),
      ('staff replying in a message', true, _Place.messageTopic, true),
      ('staff replying in a topic', true, _Place.topic, false),
      ('a member replying in a message', false, _Place.messageTopic, false),
    ]) {
      test('$name ${allowed ? 'may' : 'may not'} attach any file', () async {
        final fixture = await _uploadFixture(staff: staff, place: place);
        final composer = fixture.composer;

        composer.addFiles([_file('bundle.zip')], 0);
        await pumpEventQueue();

        if (!allowed) {
          expect(fixture.api.composerUploads, isEmpty);
          expect(
            composer.notice,
            'That file type is not allowed on this site.',
          );
          return;
        }
        expect(composer.notice, isNull);
        final upload = fixture.api.composerUploads.single;
        expect(upload.filename, 'bundle.zip');
        expect(upload.forPrivateMessage, isTrue);
      });
    }

    test('the site setting can withhold it from staff', () async {
      final fixture = await _uploadFixture(
        staff: true,
        place: _Place.messageTopic,
        settings: const {'allow_staff_to_upload_any_file_in_pm': false},
      );

      fixture.composer.addFiles([_file('bundle.zip')], 0);
      await pumpEventQueue();

      expect(fixture.api.composerUploads, isEmpty);
    });

    test('an allowed file is marked only when it goes to a message', () async {
      for (final (place, marked) in [
        (_Place.messageTopic, true),
        (_Place.topic, false),
      ]) {
        final fixture = await _uploadFixture(staff: false, place: place);

        fixture.composer.addFiles([_file('photo.png')], 0);
        await pumpEventQueue();

        expect(fixture.api.composerUploads.single.forPrivateMessage, marked);
      }
    });
  });

  test(
    'each upload carries the size limit the site validator applies',
    () async {
      const settings = {
        'authorized_extensions': 'png|mp4',
        'max_image_size_kb': 5120,
        'max_attachment_size_kb': 20480,
      };
      for (final (staff, place, name, limit) in [
        (
          false,
          _Place.topic,
          'clip.mp4',
          const ComposerUploadSizeLimit(20480 * 1024, enforced: true),
        ),
        (
          false,
          _Place.topic,
          'photo.png',
          const ComposerUploadSizeLimit(5120 * 1024, enforced: false),
        ),
        (
          false,
          _Place.messageTopic,
          'clip.mp4',
          const ComposerUploadSizeLimit(20480 * 1024, enforced: true),
        ),
        (
          true,
          _Place.messageTopic,
          'clip.mp4',
          const ComposerUploadSizeLimit(20480 * 1024, enforced: false),
        ),
      ]) {
        final fixture = await _uploadFixture(
          staff: staff,
          place: place,
          settings: settings,
        );

        fixture.composer.addFiles([_file(name)], 0);
        await pumpEventQueue();

        expect(
          fixture.api.composerUploads.single.sizeLimit,
          limit,
          reason: '$name (staff: $staff, ${place.name})',
        );
      }
    },
  );
}

enum _Place { newMessage, messageTopic, topic }

typedef _UploadFixture = ({FakeDiscourseApi api, ComposerController composer});

Future<_UploadFixture> _uploadFixture({
  required bool staff,
  required _Place place,
  Map<String, Object?> settings = const {},
}) async {
  final user = DiscourseUser(
    id: 1,
    username: 'reader',
    staff: staff,
    canSendPrivateMessages: true,
  );
  final api = FakeDiscourseApi(
    feeds: const {'/latest.json': <Topic>[]},
    user: user,
    siteConfigs: {_site: SiteConfig.fromSettings(settings)},
    composerUploadResult: const ComposerUploadResult(
      id: 73,
      originalFilename: 'bundle.zip',
      shortUrl: 'upload://bundle.zip',
      url: '$_site/uploads/bundle.zip',
    ),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();

  if (place == _Place.newMessage) {
    shell.pushContent(ContentRoute.group(GroupRoute.detail('tech-leads')));
    shell.openPrivateMessage(siteUrl: _site, targetRecipients: 'tech-leads');
  } else {
    shell.store.put(
      _site,
      TopicDetail(
        id: 7,
        title: 'Topic',
        stream: const [],
        canCreatePost: true,
        privateMessage: place == _Place.messageTopic,
      ),
    );
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    shell.openReply();
  }
  final composer = shell.visibleComposer!;
  await shell.finishComposerDraftRestore(composer);
  return (api: api, composer: composer);
}

ComposerUploadFile _file(String name) => ComposerUploadFile(
  name: name,
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);
