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
const _writer = DiscourseUser(id: 1, username: 'reader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final shape in ['plain', 'escaped', 'unicode']) {
    test('offline $shape draft survives a shell and storage restart', () async {
      final file = await _draftFile();
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

  test('a long draft restores from its new account namespace', () async {
    final file = await _draftFile();
    final reply = '😀' * 150001;
    final original = await _open(file, accountNamespace: true);
    original.composer.text.text = reply;
    await original.composer.flushDraft();
    expect(original.composer.localDraftFailed, isFalse);
    final localSite = DraftStore.accountSiteKey(_siteUrl, 'id:1');
    final stored = await original.store.read(localSite, 'topic_7');
    expect(stored, isNotNull);
    expect(await original.store.read(_siteUrl, 'topic_7'), isNull);
    original.shell.dispose();

    final reopened = await _open(
      file,
      accountNamespace: true,
      olderServerDraft: true,
    );
    addTearDown(reopened.shell.dispose);
    expect(reopened.composer.raw == reply, isTrue);
    expect(await reopened.store.read(localSite, 'topic_7'), stored);
    expect(await reopened.store.read(_siteUrl, 'topic_7'), isNull);
  });

  test(
    'an excessive local save keeps the text and previous recovery copy',
    () async {
      final file = await _draftFile();
      final opened = await _open(file);
      addTearDown(opened.shell.dispose);
      opened.composer.text.text = 'Previous recovery copy';
      await opened.composer.flushDraft();
      final previous = await opened.store.read(_siteUrl, 'topic_7');
      final reply = '"' * (ComposerDraft.maximumLocalEncodedCodeUnits ~/ 2);
      expect(
        reply.length,
        lessThan(ComposerDraft.maximumLocalEncodedCodeUnits),
      );

      opened.composer.text.text = reply;
      await opened.composer.flushDraft();

      expect(opened.composer.localDraftFailed, isTrue);
      expect(opened.composer.draftStatus, DraftStatus.failing);
      expect(
        await opened.shell.prepareComposerForClose(opened.composer),
        isFalse,
      );
      expect(opened.shell.visibleComposer, same(opened.composer));
      expect(opened.composer.raw == reply, isTrue);
      expect(await opened.store.read(_siteUrl, 'topic_7'), previous);
    },
  );

  test(
    'an excessive stored copy blocks fallback and stays recoverable',
    () async {
      final file = await _draftFile();
      final store = DraftStore(
        persistence: ApplicationSupportDraftPersistence(file: file),
      );
      final encoded = ComposerDraft(
        reply: 'x' * ComposerDraft.maximumLocalEncodedCodeUnits,
      ).encode();
      await store.write(_siteUrl, 'topic_7', encoded);

      final reopened = await _open(
        file,
        olderServerDraft: true,
        restored: false,
      );
      addTearDown(reopened.shell.dispose);

      expect(reopened.composer.raw, isEmpty);
      expect(
        await reopened.shell.prepareComposerForClose(reopened.composer),
        isFalse,
      );
      expect(await reopened.store.read(_siteUrl, 'topic_7'), encoded);
    },
  );
}

Future<File> _draftFile() async {
  final directory = await Directory.systemTemp.createTemp('long-draft-');
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/drafts.json');
  await file.writeAsString(
    jsonEncode({
      'version': 1,
      'values': <String, String>{},
      'blockedLegacyKeys': <String>[],
      'blockedLegacyPrefixes': [
        'discourse_native.draft::$_siteUrl::',
        'discourse_native.account_draft::${Uri.encodeComponent(_siteUrl)}::',
      ],
    }),
  );
  return file;
}

Future<({ShellController shell, ComposerController composer, DraftStore store})>
_open(
  File file, {
  bool olderServerDraft = false,
  bool restored = true,
  bool accountNamespace = false,
}) async {
  final store = DraftStore(
    persistence: ApplicationSupportDraftPersistence(file: file),
  );
  final api = FakeDiscourseApi(
    user: _writer,
    draftFailure: const WriteException(WriteFailure.unreachable),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      accountNamespace
          ? instance('meta.discourse.org').copyWith(user: _writer)
          : instance('meta.discourse.org', user: _writer),
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
  expect(await shell.finishComposerDraftRestore(composer), restored);
  return (shell: shell, composer: composer, store: store);
}
