import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_parser.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('serializes draft saves and keeps only the newest queued text', (
    tester,
  ) async {
    final gates = [Completer<void>(), Completer<void>()];
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        final index = saves.length;
        saves.add(save);
        await gates[index].future;
        return save.sequence + 1;
      },
    )..draftSequence = 4;

    composer.text.text = 'first';
    await tester.pump(ComposerController.draftDebounce);
    expect(saves.map((save) => save.draft.reply), ['first']);

    composer.text.text = 'second';
    await tester.pump(ComposerController.draftDebounce);
    composer.text.text = 'latest';
    await tester.pump(ComposerController.draftDebounce);

    expect(saves, hasLength(1));
    expect(saves.single.isCurrent(), isFalse);

    gates.first.complete();
    await tester.pump();

    expect(saves.map((save) => save.draft.reply), ['first', 'latest']);
    expect(saves.last.sequence, 5);
    expect(saves.last.isCurrent(), isTrue);

    gates.last.complete();
    await tester.pump();
    expect(composer.draftSequence, 6);

    composer.dispose();
  });

  testWidgets('flushes debounced text before submission continues', (
    tester,
  ) async {
    final gate = Completer<void>();
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        saves.add(save);
        await gate.future;
        return 1;
      },
    );
    addTearDown(composer.dispose);

    composer.text.text = 'not debounced yet';
    final finishing = composer.finishDraftSaves();
    await tester.pump();

    expect(saves.map((save) => save.draft.reply), ['not debounced yet']);

    gate.complete();
    await finishing;
    expect(composer.draftPending, isFalse);
  });

  testWidgets('a failed autocomplete search closes stale suggestions', (
    tester,
  ) async {
    final composer = ComposerController(
      _target,
      search: (
        users: (query) async {
          if (query == 'sa') {
            return const [
              ComposerSuggestion(
                kind: ComposerTriggerKind.mention,
                value: 'sam',
                label: 'Sam',
              ),
            ];
          }
          throw StateError('search failed');
        },
        hashtags: (_) async => const [],
        emojis: (_) async => const [],
      ),
    );
    addTearDown(composer.dispose);

    composer.text.value = _typed('hello @sa');
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();
    expect(composer.autocomplete.suggestions.single.label, 'Sam');

    composer.text.value = _typed('hello @sam');
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();

    expect(composer.autocomplete.suggestions, isEmpty);
    expect(composer.autocomplete.isOpen, isFalse);
  });

  test('restoring a draft does not count idle time as typing', () {
    var now = DateTime.utc(2026, 8, 8, 12);
    final composer = ComposerController(_target, now: () => now);
    addTearDown(composer.dispose);

    composer.restore(const ComposerDraft(reply: 'restored'));
    now = now.add(const Duration(seconds: 4));
    composer.text.text = 'restored once';

    expect(composer.typingDuration, Duration.zero);

    now = now.add(const Duration(seconds: 1));
    composer.text.text = 'restored twice';
    expect(composer.typingDuration, const Duration(seconds: 1));
  });

  testWidgets('clearing an enqueued reply does not save an empty draft', (
    tester,
  ) async {
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        saves.add(save);
        return 1;
      },
    );
    addTearDown(composer.dispose);

    composer.text.text = 'accepted for review';
    composer.enqueued(null);

    expect(composer.text.text, isEmpty);
    expect(composer.draftPending, isFalse);
    await tester.pump(ComposerController.draftDebounce);
    expect(saves, isEmpty);
  });

  test('an enqueued reply starts fresh timing for the new document', () {
    var now = DateTime.utc(2026, 8, 8, 12);
    final composer = ComposerController(_target, now: () => now);
    addTearDown(composer.dispose);

    composer.text.text = 'first';
    now = now.add(const Duration(seconds: 2));
    composer.text.text = 'first reply';
    expect(composer.typingDuration, const Duration(seconds: 2));
    expect(composer.openDuration, const Duration(seconds: 2));

    now = now.add(const Duration(seconds: 3));
    composer.enqueued(null);

    expect(composer.typingDuration, Duration.zero);
    expect(composer.openDuration, Duration.zero);
  });

  testWidgets('an enqueued reply retries draft sync as a new document', (
    tester,
  ) async {
    var saveAttempts = 0;
    final composer = ComposerController(
      _target,
      onSaveDraft: (_) async {
        saveAttempts++;
        throw const WriteException(WriteFailure.unreachable);
      },
    );
    addTearDown(composer.dispose);

    for (
      var attempt = 0;
      attempt < ComposerController.maxDraftFailures;
      attempt++
    ) {
      composer.text.text = 'reply $attempt';
      await composer.flushDraft();
    }
    expect(composer.draftsGaveUp, isTrue);

    composer.enqueued(null);
    expect(composer.draftsGaveUp, isFalse);

    composer.text.text = 'new reply';
    await composer.flushDraft();
    expect(saveAttempts, ComposerController.maxDraftFailures + 1);
  });

  testWidgets(
    'verified poll replacements keep composer submission, timing, and drafts intact',
    (tester) async {
      var now = DateTime.utc(2026, 8, 8, 12);
      final saves = <ComposerDraftSave>[];
      final composer = ComposerController(
        _target,
        now: () => now,
        onSaveDraft: (save) async {
          saves.add(save);
          return 1;
        },
      );
      addTearDown(composer.dispose);
      composer.text.selection = const TextSelection.collapsed(offset: 0);

      final markup = PollComposerDraft.newPoll(
        name: 'poll',
        defaultPublic: true,
      ).copyWith(options: ['Soup', 'Salad']).serialize();
      final inserted = insertVerifiedPoll(
        current: composer.text.value,
        expectedDocument: '',
        expectedSelection: composer.text.selection,
        markup: markup,
      );
      composer.text.value = inserted.value;

      expect(composer.text.text, '$markup\n');
      expect(composer.raw, markup);
      expect(composer.canSubmit, isTrue);
      expect(composer.draftPending, isTrue);

      now = now.add(const Duration(seconds: 1));
      final block = parsePollComposerBlocks(composer.raw).single;
      final replacement = PollComposerDraft.fromBlock(
        block,
      ).copyWith(title: 'Lunch').serialize();
      final edited = replaceVerifiedPoll(
        current: composer.text.value,
        expectedDocument: composer.text.text,
        expectedBlock: block,
        replacement: replacement,
      );
      composer.text.value = edited.value;

      expect(composer.text.text, '$replacement\n');
      expect(composer.raw, replacement);
      expect(composer.typingDuration, const Duration(seconds: 1));

      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(saves, hasLength(1));
      expect(saves.single.draft.reply, '$replacement\n');
    },
  );

  testWidgets('new topics track taxonomy in the new_topic draft', (
    tester,
  ) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 0,
        slug: '',
        topicTitle: 'New topic',
        mode: ComposerMode.newTopic,
        originFeedId: 'latest',
        initialCategoryId: 4,
      ),
    );
    addTearDown(composer.dispose);

    composer.title.text = 'A useful title';
    composer.text.text = 'The body';
    composer.setTags(const [TopicTag(id: 7, name: 'feature')]);

    expect(composer.canSubmit, isTrue);
    expect(composer.target.draftKey, 'new_topic');
    expect(composer.draft.action, ComposerDraft.createTopicAction);
    expect(composer.draft.title, 'A useful title');
    expect(composer.draft.categoryId, 4);
    expect(composer.draft.tags.single.toJson(), {'id': 7, 'name': 'feature'});
  });

  testWidgets('restores all new topic draft fields', (tester) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 0,
        slug: '',
        topicTitle: 'New topic',
        mode: ComposerMode.newTopic,
      ),
    );
    addTearDown(composer.dispose);

    composer.restore(
      const ComposerDraft(
        action: ComposerDraft.createTopicAction,
        title: 'Restored',
        reply: 'Restored body',
        categoryId: 3,
        tags: [TopicTag(name: 'mobile')],
      ),
    );

    expect(composer.title.text, 'Restored');
    expect(composer.raw, 'Restored body');
    expect(composer.categoryId, 3);
    expect(composer.tags.single.name, 'mobile');
  });

  testWidgets('topic edits distinguish metadata and body baselines', (
    tester,
  ) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-topic',
        topicTitle: 'Original',
        editingPostId: 11,
        editingPostNumber: 1,
        mode: ComposerMode.topicEdit,
        initialCategoryId: 2,
        initialTags: [TopicTag(id: 4, name: 'old')],
      ),
    );
    addTearDown(composer.dispose);
    composer.loadedBody('Original body');

    expect(composer.canSubmit, isFalse);
    composer.title.text = 'Changed title';
    expect(composer.metadataChanged, isTrue);
    expect(composer.canSubmit, isTrue);

    composer.metadataSettled();
    expect(composer.metadataChanged, isFalse);
    expect(composer.canSubmit, isFalse);
    composer.text.text = 'Changed body';
    expect(composer.canSubmit, isTrue);
  });

  group('emoji insertion', () {
    test('replaces an incomplete shortcode at the caret', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.value = _typed('hello :smi');

      composer.insertEmoji('smile');

      expect(composer.text.text, 'hello :smile:');
      expect(composer.text.selection.baseOffset, 13);
    });

    test('replaces a selection and separates it from preceding prose', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.value = const TextEditingValue(
        text: 'helloworld',
        selection: TextSelection(baseOffset: 5, extentOffset: 10),
      );

      composer.insertEmoji(':wave:t3:');

      expect(composer.text.text, 'hello :wave:t3:');
      expect(composer.text.value.composing, TextRange.empty);
    });

    test('does not mistake a colon inside a word for a partial shortcode', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.value = _typed('time:smi');

      composer.insertEmoji('smile');

      expect(composer.text.text, 'time:smi :smile:');
    });

    test('rejects noncanonical and t1 codes', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.value = _typed('draft');

      composer.insertEmoji('wave:t1');
      composer.insertEmoji('not valid');

      expect(composer.text.text, 'draft');
    });

    testWidgets('closes an open emoji trigger when the feature is disabled', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        search: (
          users: (_) async => const [],
          hashtags: (_) async => const [],
          emojis: (_) async => const [
            ComposerSuggestion(
              kind: ComposerTriggerKind.emoji,
              value: 'wave',
              label: 'wave',
            ),
          ],
        ),
      );
      addTearDown(composer.dispose);
      composer.text.value = _typed(':wa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(composer.autocomplete.isOpen, isTrue);

      composer.closeEmojiAutocomplete();
      expect(composer.autocomplete.isOpen, isFalse);
    });
  });

  group('image uploads', () {
    testWidgets(
      'keeps the drop anchor through typing and inserts a batch in drop order',
      (tester) async {
        final calls = <_UploadCall>[];
        final composer = ComposerController(
          _target,
          imageUploader: _recordingUploader(calls),
          canUploadImage: (filename) => filename.endsWith('.png'),
        );
        addTearDown(composer.dispose);
        composer.text.text = 'leftRIGHT';

        composer.addDroppedImages([_file('one.png'), _file('two.png')], 4);
        expect(calls, hasLength(2));
        expect(composer.uploads.map((upload) => upload.file.name), [
          'one.png',
          'two.png',
        ]);
        expect(composer.canSubmit, isFalse);

        composer.text.value = const TextEditingValue(
          text: 'lefttypedRIGHT',
          selection: TextSelection.collapsed(offset: 9),
        );
        calls[1].complete(_result('two'));
        await tester.pump();
        expect(composer.raw, 'lefttypedRIGHT');

        calls[0].complete(_result('one'));
        await tester.pump();

        expect(
          composer.text.text,
          'lefttyped\n'
          '![one|640x480](upload://one)\n'
          '![two|640x480](upload://two)\n'
          'RIGHT',
        );
        expect(composer.uploads, isEmpty);
        expect(composer.canSubmit, isTrue);
      },
    );

    testWidgets('reports progress, retains failures, and retries them', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text = 'body';
      composer.addDroppedImages([_file('photo.png')], 4);

      calls.single.onProgress(0.42);
      expect(composer.uploads.single.progress, 0.42);
      calls.single.fail(
        const ComposerUploadException(
          'The image is too large.',
          statusCode: 422,
        ),
      );
      await tester.pump();

      expect(composer.uploads.single.status, ComposerUploadStatus.failed);
      expect(composer.uploads.single.error, 'The image is too large.');
      expect(
        composer.canSubmit,
        isTrue,
        reason: 'failed rows do not gate send',
      );

      composer.retryUpload(composer.uploads.single.id);
      expect(calls, hasLength(2));
      expect(composer.uploads.single.status, ComposerUploadStatus.retrying);
      expect(composer.canSubmit, isFalse);
      calls.last.complete(_result('photo'));
      await tester.pump();

      expect(composer.uploads, isEmpty);
      expect(composer.text.text, 'body\n![photo|640x480](upload://photo)');
    });

    testWidgets('only failed uploads can be retried', (tester) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.addDroppedImages([_file('photo.png')], 0);

      final upload = composer.uploads.single;
      composer.retryUpload(upload.id);

      expect(calls, hasLength(1));
      expect(composer.uploads.single.status, ComposerUploadStatus.uploading);
    });

    testWidgets('turns synchronous uploader errors into retryable rows', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) {
          throw const ComposerUploadException(
            'The upload could not be started.',
          );
        },
      );
      addTearDown(composer.dispose);

      composer.addDroppedImages([_file('photo.png')], 0);
      await tester.pump();

      expect(composer.uploads.single.status, ComposerUploadStatus.failed);
      expect(composer.uploads.single.error, 'The upload could not be started.');
      expect(composer.canSubmit, isFalse);
    });

    testWidgets(
      'a failure does not block later success or lose retry ordering',
      (tester) async {
        final calls = <_UploadCall>[];
        final composer = ComposerController(
          _target,
          imageUploader: _recordingUploader(calls),
        );
        addTearDown(composer.dispose);
        composer.text.text = 'body';
        composer.addDroppedImages([_file('one.png'), _file('two.png')], 4);

        calls[1].complete(_result('two'));
        calls[0].fail(const ComposerUploadException('Try one again.'));
        await tester.pump();

        expect(composer.uploads, hasLength(1));
        expect(composer.uploads.single.status, ComposerUploadStatus.failed);
        expect(composer.canSubmit, isTrue);
        expect(composer.text.text, 'body\n![two|640x480](upload://two)');

        composer.retryUpload(composer.uploads.single.id);
        calls.last.complete(_result('one'));
        await tester.pump();

        expect(
          composer.text.text,
          'body\n'
          '![one|640x480](upload://one)\n'
          '![two|640x480](upload://two)',
        );
      },
    );

    testWidgets('cancel removes a row and aborts its request', (tester) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.addDroppedImages([_file('photo.png')], 0);

      var aborted = false;
      unawaited(calls.single.abort.then((_) => aborted = true));
      composer.cancelUpload(composer.uploads.single.id);
      await tester.pump();

      expect(aborted, isTrue);
      expect(composer.uploads, isEmpty);
      expect(composer.text.text, isEmpty);
    });

    testWidgets('disposing aborts every active request', (tester) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      composer.addDroppedImages([_file('one.png'), _file('two.png')], 0);

      composer.dispose();

      await Future.wait(calls.map((call) => call.abort));
    });

    test('rejects unsupported images and batches above the site limit', () {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        canUploadImage: (filename) => filename.endsWith('.png'),
        simultaneousUploads: 1,
      );
      addTearDown(composer.dispose);

      composer.addDroppedImages([_file('notes.txt')], 0);
      expect(composer.notice, contains('not allowed'));
      composer.addDroppedImages([_file('one.png'), _file('two.png')], 0);
      expect(composer.notice, 'Drop at most 1 images at a time.');
      expect(calls, isEmpty);
    });

    test('edits alt, scale, and removal in raw markdown', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.text = '![old|640x480](upload://photo)';

      composer.setImageAlt(composer.text.imageBlocks.single, 'new [alt]');
      expect(composer.text.text, r'![new \[alt\]|640x480](upload://photo)');
      composer.setImageScale(composer.text.imageBlocks.single, 50);
      expect(
        composer.text.text,
        r'![new \[alt\]|640x480, 50%](upload://photo)',
      );
      composer.removeImage(composer.text.imageBlocks.single);
      expect(composer.text.text, isEmpty);
    });
  });
}

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

TextEditingValue _typed(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

ComposerUploadFile _file(String name) => ComposerUploadFile(
  name: name,
  length: () => Future.value(3),
  openRead: () => Stream.value([1, 2, 3]),
);

ComposerUploadResult _result(String name) => ComposerUploadResult(
  originalFilename: '$name.png',
  shortUrl: 'upload://$name',
  url: 'https://meta.discourse.org/uploads/$name.png',
  thumbnailWidth: 640,
  thumbnailHeight: 480,
);

ComposerImageUploader _recordingUploader(List<_UploadCall> calls) =>
    (file, {required onProgress, required abortTrigger}) {
      final call = _UploadCall(file, onProgress, abortTrigger);
      calls.add(call);
      return call.result.future;
    };

class _UploadCall {
  _UploadCall(this.file, this.onProgress, this.abort);

  final ComposerUploadFile file;
  final void Function(double) onProgress;
  final Future<void> abort;
  final Completer<ComposerUploadResult> result = Completer();

  void complete(ComposerUploadResult value) => result.complete(value);
  void fail(Object error) => result.completeError(error);
}
