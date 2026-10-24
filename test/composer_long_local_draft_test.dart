import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final shape in ['plain', 'escaped', 'unicode']) {
    test('offline $shape draft survives a shell and storage restart', () async {
      final directory = await Directory.systemTemp.createTemp('long-draft-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/drafts.json');
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'values': <String, String>{},
          'blockedLegacyKeys': <String>[],
          'blockedLegacyPrefixes': ['discourse_native.draft::$_siteUrl::'],
        }),
      );
      final reply = switch (shape) {
        'escaped' => List.filled(25000, r'"\text').join(),
        'unicode' => List.filled(150001, '😀').join(),
        _ => 'x' * 150001,
      };
      final original = await _open(file);
      original.composer.text.text = reply;
      await original.composer.flushDraft();
      expect(original.composer.localDraftFailed, isFalse);
      expect(original.composer.draftStatus, DraftStatus.failing);
      final stored = await original.store.read(_siteUrl, 'topic_7');
      expect(stored, isNotNull);
      expect(stored!.runes.length, greaterThan(150000));
      expect(ComposerDraft.decode(stored), isNull);
      original.shell.dispose();

      final reopened = await _open(file, olderServerDraft: true);
      addTearDown(reopened.shell.dispose);
      expect(
        reopened.composer.raw == reply,
        isTrue,
        reason: 'The complete local draft must outrank the old server copy.',
      );
      expect(await reopened.store.read(_siteUrl, 'topic_7'), stored);
    });
  }
}

Future<({ShellController shell, ComposerController composer, DraftStore store})>
_open(File file, {bool olderServerDraft = false}) async {
  final store = DraftStore(persistence: AppleFileDraftPersistence(file: file));
  final api = FakeDiscourseApi(
    draftFailure: const WriteException(WriteFailure.unreachable),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org')
          .copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: store,
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  shell.store.put(
    _siteUrl,
    TopicDetail(
      id: 7,
      title: 'A topic',
      stream: const [],
      canCreatePost: true,
      draft: olderServerDraft
          ? const ComposerDraft(reply: 'Older server copy')
          : null,
    ),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  shell.openReply();
  final composer = shell.visibleComposer!;
  expect(await shell.finishComposerDraftRestore(composer), isTrue);
  return (shell: shell, composer: composer, store: store);
}
