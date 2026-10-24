import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/plugin_testing/plugin_test_ports.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer_draft_session.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

const _site = 'https://chat.example';
const _target = ChatChannelTarget(9);

void main() {
  for (final completedId in [3, 4]) {
    testWidgets(
      'remote attachment replacement converges with pending upload $completedId',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.chat.dispose);
        fixture.retain('before', [_upload(1)]);
        final transfer = Completer<ComposerUploadResult>();
        final first = fixture.open(transfer: transfer);
        final second = fixture.open();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        first.composer.addFiles([
          ComposerUploadFile(
            name: 'pending.png',
            length: () async => 1,
            openRead: () => Stream.value([1]),
          ),
        ], 0);
        await tester.pump();
        expect(first.composer.hasActiveUploads, isTrue);

        fixture.retain('remote replacement', [_upload(2)]);
        expect(first.composer.raw, 'remote replacement');
        expect(first.composer.completedUploads.map((u) => u.id), [1]);
        fixture.retain('newer replacement', [_upload(2), _upload(3)]);
        first.composer.text.text = 'local after remote';
        expect(second.composer.raw, 'local after remote');
        expect(second.composer.completedUploads.map((u) => u.id), [2, 3]);

        transfer.complete(_upload(completedId));
        await tester.pump();
        final expectedIds = [2, 3, if (completedId != 3) completedId];
        expect(first.composer.hasActiveUploads, isFalse);
        for (final session in [first, second]) {
          expect(session.composer.raw, 'local after remote');
          expect(
            session.composer.completedUploads.map((u) => u.id),
            expectedIds,
          );
        }
        expect(fixture.draft?.uploads.map((u) => u.id), expectedIds);
      },
    );
  }

  testWidgets('retiring one binding leaves the other synchronized', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.chat.dispose);
    final first = fixture.open();
    final second = fixture.open();
    addTearDown(second.dispose);
    first.composer.text.text = 'shared before retirement';
    expect(second.composer.raw, 'shared before retirement');
    first.dispose();
    first.dispose();
    second.composer.text.text = 'surviving document';
    fixture.retain('remote after retirement', [_upload(7)]);
    expect(second.composer.raw, 'remote after retirement');
    expect(second.composer.completedUploads.single.id, 7);
    final reopened = fixture.open();
    addTearDown(reopened.dispose);
    expect(reopened.composer.raw, 'remote after retirement');
    reopened.composer.text.text = 'both live again';
    expect(second.composer.raw, 'both live again');
  });

  testWidgets('edit document stays separate from changing retained draft', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.chat.dispose);
    fixture.retain('ordinary', [_upload(1)]);
    final session = fixture.open(editingMessage: _message);
    addTearDown(session.dispose);
    expect(session.composer.raw, 'original message');
    session.composer.text.text = 'independent edit';
    fixture.retain('new ordinary', [_upload(2)]);
    expect(session.composer.raw, 'independent edit');
    expect(fixture.draft?.raw, 'new ordinary');
    session.clearEditDocument();
    expect(fixture.draft?.raw, 'new ordinary');
    session.updateEditingMessage(null);
    expect(session.composer.raw, 'new ordinary');
    expect(session.composer.completedUploads.single.id, 2);
    session.composer.text.text = 'ordinary resumed';
    expect(fixture.draft?.raw, 'ordinary resumed');
  });

  testWidgets('same-user retirement replaces both bound refs', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.chat.dispose);
    final first = fixture.open();
    final second = fixture.open();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.composer.text.text = 'retired account document';
    final lease = fixture.chat.captureSession(_site);
    fixture.requests.forget(_site);
    fixture.chat.forget(_site);
    expect(lease.isCurrent, isFalse);
    expect(first.composer.raw, isEmpty);
    expect(second.composer.raw, isEmpty);
    first.composer.text.text = 'replacement session';
    expect(second.composer.raw, 'replacement session');
    expect(fixture.draft?.raw, 'replacement session');
  });

  testWidgets('retirement ignores late upload completion in successor draft', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.chat.dispose);
    final transfer = Completer<ComposerUploadResult>();
    final retired = fixture.open(transfer: transfer);
    retired.composer.addFiles([
      ComposerUploadFile(
        name: 'retired.png',
        length: () async => 1,
        openRead: () => Stream.value([1]),
      ),
    ], 0);
    await tester.pump();
    expect(retired.composer.hasActiveUploads, isTrue);
    retired.dispose();
    final successor = fixture.open();
    addTearDown(successor.dispose);
    successor.composer.text.text = 'successor';
    transfer.complete(_upload(8));
    await tester.pump();
    expect(successor.composer.raw, 'successor');
    expect(successor.composer.completedUploads, isEmpty);
    expect(fixture.draft?.uploads, isEmpty);
  });
}

final class _Fixture {
  _Fixture() {
    chat = ChatController(
      api: FakeDiscourseApi(),
      requests: requests,
      store: Store(),
      currentUserFor: (_) => const DiscourseUser(id: 7, username: 'sam'),
    );
  }

  final requests = PluginTestRequestHost();
  late final ChatController chat;
  ChatComposerDraft? get draft => chat.composerDraftFor(_site, _target);

  void retain(String raw, List<ComposerUploadResult> uploads) =>
      chat.retainComposerDraft(_site, _target, raw: raw, uploads: uploads);

  ChatComposerDraftSession open({
    Completer<ComposerUploadResult>? transfer,
    ChatMessage? editingMessage,
  }) => ChatComposerDraftSession(
    chat: chat,
    siteUrl: _site,
    target: _target,
    editingMessage: editingMessage,
    composer: ComposerController(
      PluginComposerTarget(
        siteUrl: _site,
        topicTitle: 'Chat',
        policy: ComposerTargetPolicy(
          kind: const ComposerTargetKind(
            owner: PluginId('chat'),
            name: 'message',
          ),
          draftKey: 'chat/channel-9',
          uploadType: ComposerUploadType.composer,
          uploadDisposition: ComposerUploadDisposition.retainAttachment,
          uploadsEnabled: true,
          supportsEditing: true,
          validate: (context) =>
              context.raw.isNotEmpty || context.completedUploadCount > 0,
          emojiUsageContext: const EmojiUsageContext(
            owner: PluginId('chat'),
            name: 'message',
          ),
        ),
      ),
      imageUploader: transfer == null
          ? null
          : (file, {required onProgress, required abortTrigger}) =>
                transfer.future,
    ),
  );
}

ComposerUploadResult _upload(int id) => ComposerUploadResult(
  id: id,
  originalFilename: '$id.png',
  shortUrl: 'upload://$id',
  url: '$_site/uploads/$id.png',
);

final _message = ChatMessage(
  id: 12,
  channelId: 9,
  raw: 'original message',
  cooked: '<p>original message</p>',
  author: const ChatMessageAuthor(id: 7, username: 'sam'),
  createdAt: DateTime.utc(2026, 10, 24),
);
