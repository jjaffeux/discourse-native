import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the composer target site on its image renderer', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);

    expect(composer.text.imageSiteUrl, _target.siteUrl);
  });

  test('a reply is changed only when its trimmed body differs', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);

    expect(composer.hasChanges, isFalse);
    composer.text.text = '   ';
    expect(composer.hasChanges, isFalse);
    composer.text.text = 'A reply';
    expect(composer.hasChanges, isTrue);
  });

  test('an edit compares changes with the body loaded from the site', () {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-topic',
        topicTitle: 'A topic',
        editingPostId: 11,
        editingPostNumber: 2,
      ),
    );
    addTearDown(composer.dispose);

    composer.loadedBody('Original body');
    expect(composer.hasChanges, isFalse);
    composer.text.text = 'Changed body';
    expect(composer.hasChanges, isTrue);
    composer.text.text = ' Original body ';
    expect(composer.hasChanges, isFalse);
    composer.text.clear();
    expect(composer.hasChanges, isTrue);
  });

  test('new-topic dirty state matches core title and body semantics', () {
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

    composer.setCategory(7);
    composer.setTags(const [TopicTag(name: 'mobile')]);
    expect(composer.metadataChanged, isTrue);
    expect(composer.hasChanges, isFalse);

    composer.title.text = 'A title';
    expect(composer.hasChanges, isTrue);
  });

  testWidgets('text typed after an unresolved submit is still drafted', (
    tester,
  ) async {
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        saves.add(save);
        return save.sequence + 1;
      },
    );
    addTearDown(composer.dispose);

    composer.text.text = 'Sent once.';
    await tester.pump(ComposerController.draftDebounce);
    await tester.pump();
    expect(saves, hasLength(1));

    // While the submit is out the site may be turning this draft into a post;
    // a save now would race the site clearing it.
    composer.beginSubmit();
    composer.text.text = 'Sent once. Typed while it was out.';
    await tester.pump(ComposerController.draftDebounce);
    await tester.pump();
    expect(saves, hasLength(1));

    composer.unresolved();
    composer.text.text = 'Sent once. Typed while it was out. And after.';
    await tester.pump(ComposerController.draftDebounce);
    await tester.pump();

    expect(saves, hasLength(2));
    expect(saves.last.draft.reply, endsWith('And after.'));
    expect(composer.draftPersistencePending, isFalse);
  });

  testWidgets('retargeting a reply records the new target in its draft', (
    tester,
  ) async {
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        saves.add(save);
        return save.sequence + 1;
      },
    );
    addTearDown(composer.dispose);

    composer.text.text = 'A reply.';
    await tester.pump(ComposerController.draftDebounce);
    await tester.pump();
    expect(saves.single.draft.replyToPostNumber, isNull);

    final revision = composer.draftRevision;
    composer.retarget(replyToPostNumber: 9, replyToUsername: 'nine');
    expect(composer.draftRevision, greaterThan(revision));
    await tester.pump(ComposerController.draftDebounce);
    await tester.pump();

    expect(saves, hasLength(2));
    expect(saves.last.draft.replyToPostNumber, 9);

    // The same target again is not a change worth a save.
    composer.retarget(replyToPostNumber: 9, replyToUsername: 'nine');
    await tester.pump(ComposerController.draftDebounce);
    await tester.pump();
    expect(saves, hasLength(2));
  });

  test('a reply is not retargeted while its submit is out', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);

    composer.beginSubmit();
    composer.retarget(replyToPostNumber: 9, replyingToWhisper: true);

    expect(composer.target.replyToPostNumber, isNull);
    expect(composer.whisper, isFalse);
  });

  test('an unresolved composer can still be discarded', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);

    composer.unresolved();
    expect(composer.beginDiscard(), isNotNull);
    expect(composer.discarding, isTrue);
  });

  testWidgets('whisper state is restored and saved with the reply draft', (
    tester,
  ) async {
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        saves.add(save);
        return save.sequence + 1;
      },
    );
    addTearDown(composer.dispose);

    composer.text.text = 'Visible only to the whisper groups.';
    composer.setWhisper(true);
    await tester.pump(ComposerController.draftDebounce);
    await tester.pump();

    expect(composer.whisper, isTrue);
    expect(composer.draft.whisper, isTrue);
    expect(saves.single.draft.whisper, isTrue);

    final restored = ComposerController(_target);
    addTearDown(restored.dispose);
    restored.restore(
      const ComposerDraft(reply: 'A restored whisper', whisper: true),
    );
    expect(restored.whisper, isTrue);
  });

  test('a reply to a whisper cannot be made public', () {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-topic',
        topicTitle: 'A topic',
        replyToPostNumber: 3,
        replyToUsername: 'sam',
        replyingToWhisper: true,
      ),
    );
    addTearDown(composer.dispose);

    expect(composer.whisper, isTrue);
    composer.setWhisper(false);
    expect(composer.whisper, isTrue);
  });

  test('plugin edits reject a stale selection as well as stale text', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);
    composer.text.value = _typed('draft');
    final expected = composer.text.value;
    composer.text.selection = const TextSelection.collapsed(offset: 0);

    expect(
      composer.commit(expectedValue: expected, value: _typed('replacement')),
      isFalse,
    );
    expect(composer.text.text, 'draft');
    expect(composer.text.selection.extentOffset, 0);
    expect(
      composer.insertBlock(expectedValue: expected, markdown: 'opaque block'),
      isFalse,
    );
    expect(composer.text.text, 'draft');
  });

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

  testWidgets(
    'discard waits for an active save without starting a queued one',
    (tester) async {
      final gate = Completer<void>();
      final saves = <ComposerDraftSave>[];
      final composer = ComposerController(
        _target,
        onSaveDraft: (save) async {
          saves.add(save);
          await gate.future;
          return save.sequence + 1;
        },
      );
      addTearDown(composer.dispose);

      composer.text.text = 'active save';
      await tester.pump(ComposerController.draftDebounce);
      composer.text.text = 'queued save';
      await tester.pump(ComposerController.draftDebounce);

      final finishing = composer.finishInFlightDraftSaveForDiscard();
      expect(saves.map((save) => save.draft.reply), ['active save']);

      gate.complete();
      await finishing;
      expect(saves.map((save) => save.draft.reply), ['active save']);
      expect(composer.draftPending, isFalse);
    },
  );

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

  test(
    'gallery markup survives draft restore and edit loading losslessly',
    () async {
      const source =
          'Before\n\n'
          '[grid mode=carousel]\n'
          '\n'
          '![one](upload://one)\n'
          ' \t\n'
          '![two|640x480](upload://two)\n'
          '[/grid]\n\n'
          'After';
      final saves = <ComposerDraftSave>[];
      final writer = ComposerController(
        _target,
        onSaveDraft: (save) async {
          saves.add(save);
          return save.sequence + 1;
        },
      );
      addTearDown(writer.dispose);

      writer.text.text = source;
      await writer.flushDraft();

      expect(saves.single.draft.reply, source);

      final restored = ComposerController(_target);
      addTearDown(restored.dispose);
      restored.restore(saves.single.draft);

      expect(restored.text.text, source);
      expect(
        restored.text.galleryBlocks.single.mode,
        ComposerGalleryMode.carousel,
      );
      expect(
        restored.text.galleryBlocks.single.images.map((image) => image.url),
        ['upload://one', 'upload://two'],
      );

      final editor = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 7,
          slug: 'a-topic',
          topicTitle: 'A topic',
          editingPostId: 11,
          editingPostNumber: 2,
          mode: ComposerMode.postEdit,
        ),
      );
      addTearDown(editor.dispose);
      editor.loadedBody(restored.text.text);

      expect(editor.text.text, source);
      expect(editor.originalRaw, source);
      editor.setGalleryMode(
        editor.text.galleryBlocks.single,
        ComposerGalleryMode.grid,
      );
      editor.setGalleryMode(
        editor.text.galleryBlocks.single,
        ComposerGalleryMode.carousel,
      );

      expect(editor.text.text, source);
      expect(editor.originalRaw, source);
    },
  );

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
    'plugin-owned replacements keep submission, timing, and drafts intact',
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
        syntaxPolicies: const [_TokenSyntaxPolicy()],
      );
      addTearDown(composer.dispose);
      composer.text.value = _typed('[[choice:Soup|Salad]]\n');

      expect(composer.raw, '[[choice:Soup|Salad]]');
      expect(composer.canSubmit, isTrue);
      expect(composer.draftPending, isTrue);

      now = now.add(const Duration(seconds: 1));
      final occurrence = composer.text.syntaxBlocks.single;
      final replacement = (occurrence.projection as _TokenProjection).replace(
        composer.text.value,
        '[[choice:Lunch|Soup|Salad]]',
      );
      expect(
        composer.commit(expectedValue: composer.text.value, value: replacement),
        isTrue,
      );

      expect(composer.raw, '[[choice:Lunch|Soup|Salad]]');
      expect(composer.typingDuration, const Duration(seconds: 1));

      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(saves, hasLength(1));
      expect(saves.single.draft.reply, '[[choice:Lunch|Soup|Salad]]\n');
    },
  );

  group('new topic drafts', () {
    testWidgets('track taxonomy in the new_topic draft', (tester) async {
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

    test('notify taxonomy changes before a new topic can submit', () {
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
      var notifications = 0;
      composer.addListener(() => notifications++);

      composer.setCategory(3);
      composer.setTags(const [TopicTag(name: 'mobile')]);

      expect(composer.canSubmit, isFalse);
      expect(notifications, 2);
    });

    test('late route tags become the untouched composer baseline', () {
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

      composer.applyInitialTagsIfUntouched(const [
        TopicTag(id: 7, name: 'feature'),
      ]);

      expect(composer.tags, const [TopicTag(id: 7, name: 'feature')]);
      expect(composer.metadataChanged, isFalse);
      expect(composer.draftPending, isFalse);
    });

    test('late route tags do not replace a restored draft', () {
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
          reply: '',
          action: ComposerDraft.createTopicAction,
          tags: [TopicTag(id: 8, name: 'mobile')],
        ),
      );

      composer.applyInitialTagsIfUntouched(const [
        TopicTag(id: 7, name: 'feature'),
      ]);

      expect(composer.tags, const [TopicTag(id: 8, name: 'mobile')]);
    });
  });

  group('private message drafts', () {
    testWidgets('retain their recipient in a portable draft', (tester) async {
      final composer = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 0,
          slug: '',
          topicTitle: 'New message',
          mode: ComposerMode.privateMessage,
          originFeedId: 'groups',
          targetRecipients: 'tech-leads',
        ),
      );
      addTearDown(composer.dispose);

      expect(composer.canSubmit, isFalse);
      composer.title.text = 'A private subject';
      composer.text.text = 'Hello team';

      expect(composer.canSubmit, isTrue);
      expect(composer.target.draftKey, 'new_private_message');
      expect(composer.draft.action, ComposerDraft.privateMessageAction);
      expect(composer.draft.archetypeId, ComposerDraft.privateMessageArchetype);
      expect(composer.draft.recipients, 'tech-leads');
      expect(composer.draft.categoryId, isNull);
      expect(composer.draft.tags, isEmpty);
    });

    test('cannot be restored for another recipient', () {
      final composer = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 0,
          slug: '',
          topicTitle: 'New message',
          mode: ComposerMode.privateMessage,
          targetRecipients: 'tech-leads',
        ),
      );
      addTearDown(composer.dispose);

      composer.restore(
        const ComposerDraft(
          reply: 'For another group',
          title: 'Wrong recipient',
          action: ComposerDraft.privateMessageAction,
          archetypeId: ComposerDraft.privateMessageArchetype,
          recipients: 'moderators',
        ),
      );

      expect(composer.raw, isEmpty);
      expect(composer.title.text, isEmpty);
    });
  });

  group('editing existing posts and topics', () {
    testWidgets('distinguishes metadata and body baselines', (tester) async {
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

    test('a failed edit body load keeps sending disabled until the body '
        'arrives', () {
      final composer = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 7,
          slug: 'a-topic',
          topicTitle: 'A topic',
          editingPostId: 11,
          editingPostNumber: 2,
        ),
      );
      addTearDown(composer.dispose);
      expect(composer.target.mode, ComposerMode.postEdit);

      composer.beginLoadingBody();
      composer.bodyLoadFailed();
      composer.text.text = 'typed into the empty field';
      expect(
        composer.canSubmit,
        isFalse,
        reason: 'sending now would replace the whole post with the typed text',
      );

      composer.loadedBody('Original body');
      expect(composer.raw, 'Original body');
      expect(composer.canSubmit, isFalse);

      composer.text.text = 'Original body, amended';
      expect(composer.canSubmit, isTrue);
    });

    test('a failed body load blocks a topic edit even when only metadata '
        'changed', () {
      final composer = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 7,
          slug: 'a-topic',
          topicTitle: 'Original',
          editingPostId: 11,
          editingPostNumber: 1,
          mode: ComposerMode.topicEdit,
        ),
      );
      addTearDown(composer.dispose);

      composer.beginLoadingBody();
      composer.bodyLoadFailed();
      composer.title.text = 'Changed title';
      expect(composer.metadataChanged, isTrue);
      expect(
        composer.canSubmit,
        isFalse,
        reason:
            'the submit path follows a metadata save with a body update '
            'whenever the field differs from the baseline, and with no '
            'baseline that would blank the first post',
      );

      composer.loadedBody('Original body');
      expect(composer.canSubmit, isTrue);
    });
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
    testWidgets('automatically groups three accepted images in picker order', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        canUploadImage: (filename) => filename.endsWith('.png'),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);
      composer.text.text = 'beforeAFTER';

      composer.addImages([
        _file('one.png'),
        _file('notes.txt'),
        _file('two.png'),
        _file('three.png'),
      ], 6);
      expect(calls, hasLength(3));

      calls[2].complete(_result('three'));
      calls[1].complete(_result('two'));
      await tester.pump();
      expect(composer.text.text, 'beforeAFTER');

      calls[0].complete(_result('one'));
      await tester.pump();

      expect(
        composer.text.text,
        'before\n'
        '[grid]\n'
        '![one|640x480](upload://one)\n'
        '![two|640x480](upload://two)\n'
        '![three|640x480](upload://three)\n'
        '[/grid]\n'
        'AFTER',
      );
      expect(parseComposerImageGalleries(composer.text.text), hasLength(1));
    });

    testWidgets('does not auto-group when the site setting is disabled', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: false,
      );
      addTearDown(composer.dispose);

      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], 0);
      for (var index = 0; index < calls.length; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      expect(composer.text.text, isNot(contains('[grid]')));
      expect(parseComposerImageGalleries(composer.text.text), isEmpty);
    });

    testWidgets('a live disabled setting demotes a pending automatic gallery', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);

      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], 0);
      composer.updateEnableAutoGridImages(false);
      for (var index = 0; index < calls.length; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      expect(parseComposerImageGalleries(composer.text.text), isEmpty);
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
        'upload://two',
        'upload://three',
      ]);
    });

    testWidgets('a live disabled setting does not unwrap a created gallery', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);

      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], 0);
      calls.first.complete(_result('one'));
      await tester.pump();
      expect(parseComposerImageGalleries(composer.text.text), hasLength(1));

      composer.updateEnableAutoGridImages(false);
      calls[1].complete(_result('two'));
      calls[2].complete(_result('three'));
      await tester.pump();

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://one', 'upload://two', 'upload://three'],
      );
    });

    testWidgets('never auto-groups uploads for a plugin composer target', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _markdownPluginTarget,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);

      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], 0);
      for (var index = 0; index < calls.length; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      expect(composer.text.text, isNot(contains('[grid]')));
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
        'upload://two',
        'upload://three',
      ]);
    });

    test('plugin composers keep grid source outside gallery APIs', () {
      final composer = ComposerController(_markdownPluginTarget);
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '![one](upload://one)\n'
          '[/grid]';

      expect(composer.text.galleryBlocks, isEmpty);
      expect(
        composer.galleryForImage(composer.text.imageBlocks.single),
        isNull,
      );
      expect(composer.standaloneImages, hasLength(1));
    });

    testWidgets('does not nest an auto-gallery in a mixed raw grid', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);
      composer.text.text = '[grid]\na caption\n[/grid]';

      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], composer.text.text.indexOf('caption'));
      for (var index = 0; index < calls.length; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      expect(RegExp(r'\[grid\]').allMatches(composer.text.text), hasLength(1));
      expect(parseComposerImageGalleries(composer.text.text), isEmpty);
    });

    testWidgets('rechecks a pending auto-gallery against raw grid edits', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);
      composer.text.text = 'caption';
      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], 0);

      composer.text.text = '[grid]\n${composer.text.text}';
      composer.text.text = '${composer.text.text}\n[/grid]';
      for (var index = 0; index < calls.length; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      expect(RegExp(r'\[grid\]').allMatches(composer.text.text), hasLength(1));
    });

    testWidgets(
      'grid text in code and image URLs does not suppress auto-grid',
      (tester) async {
        final calls = <_UploadCall>[];
        final composer = ComposerController(
          _target,
          imageUploader: _recordingUploader(calls),
          enableAutoGridImages: true,
        );
        addTearDown(composer.dispose);
        composer.text.text =
            '`[grid]`\n\n'
            '```text\n[grid]\n```\n\n'
            r'\[grid]'
            '\n\n'
            '![sample](https://example.com/[grid].png)\n\n';

        composer.addImages([
          _file('one.png'),
          _file('two.png'),
          _file('three.png'),
        ], composer.text.text.length);
        for (var index = 0; index < calls.length; index++) {
          calls[index].complete(_result(['one', 'two', 'three'][index]));
        }
        await tester.pump();

        expect(parseComposerImageGalleries(composer.text.text), hasLength(1));
      },
    );

    testWidgets('a failed auto-gallery member retries into its original slot', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);

      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], 0);
      calls[2].complete(_result('three'));
      calls[1].complete(_result('two'));
      calls[0].fail(const ComposerUploadException('Retry one.'));
      await tester.pump();

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://two', 'upload://three'],
      );

      composer.retryUpload(composer.uploads.single.id);
      calls.last.complete(_result('one'));
      await tester.pump();

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://one', 'upload://two', 'upload://three'],
      );
    });

    testWidgets('append to an existing gallery without nesting', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid mode=carousel]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final gallery = parseComposerImageGalleries(composer.text.text).single;

      composer.addImagesToGallery([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], gallery);
      for (var index = 0; index < calls.length; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      final galleries = parseComposerImageGalleries(composer.text.text);
      expect(galleries, hasLength(1));
      expect(galleries.single.mode, ComposerGalleryMode.carousel);
      expect(galleries.single.images.map((image) => image.url), [
        'upload://existing',
        'upload://one',
        'upload://two',
        'upload://three',
      ]);
    });

    testWidgets('a stale gallery picker resolves the surviving gallery', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final captured = parseComposerImageGalleries(composer.text.text).single;
      composer.setGalleryMode(captured, ComposerGalleryMode.carousel);

      composer.addImagesToGallery([_file('late.png')], captured);
      expect(calls, hasLength(1));
      calls.single.complete(_result('late'));
      await tester.pump();

      final gallery = parseComposerImageGalleries(composer.text.text).single;
      expect(gallery.mode, ComposerGalleryMode.carousel);
      expect(gallery.images.map((image) => image.url), [
        'upload://existing',
        'upload://late',
      ]);
    });

    testWidgets('ambiguous duplicate member URLs do not retarget a picker', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '![same](upload://same)\n'
          '[/grid]';
      final captured = parseComposerImageGalleries(composer.text.text).single;
      composer.text.text =
          '[grid mode=carousel]\n'
          '![same](upload://same)\n'
          '[/grid]\n'
          '[grid]\n'
          '![same](upload://same)\n'
          '![same](upload://same)\n'
          '[/grid]';

      composer.addImagesToGallery([_file('late.png')], captured);
      calls.single.complete(_result('late'));
      await tester.pump();

      expect(composer.notice, contains('gallery changed'));
      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).map((gallery) => gallery.images.length),
        [1, 2],
      );
      expect(composer.standaloneImages.single.url, 'upload://late');
    });

    testWidgets('an empty gallery survives a shift before the picker returns', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text = '[grid]\n[/grid]';
      final captured = parseComposerImageGalleries(composer.text.text).single;
      composer.text.text = 'before\n${composer.text.text}';

      composer.addImagesToGallery([_file('late.png')], captured);
      expect(calls, hasLength(1));
      calls.single.complete(_result('late'));
      await tester.pump();

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.single.url,
        'upload://late',
      );
    });

    testWidgets('a removed stale gallery falls back without losing files', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]\n'
          'Following prose.';
      final captured = parseComposerImageGalleries(composer.text.text).single;
      composer.unwrapGallery(captured);

      composer.addImagesToGallery([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], captured);
      expect(calls, hasLength(3));
      expect(
        composer.notice,
        'That gallery changed, so the images will be added outside it.',
      );
      for (var index = 0; index < calls.length; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      expect(parseComposerImageGalleries(composer.text.text), isEmpty);
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://existing',
        'upload://one',
        'upload://two',
        'upload://three',
      ]);
      expect(
        composer.text.text.indexOf('upload://three'),
        lessThan(composer.text.text.indexOf('Following prose.')),
      );
    });

    test('a cancelled stale gallery picker returns without a notice', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final captured = parseComposerImageGalleries(composer.text.text).single;
      composer.unwrapGallery(captured);

      composer.addImagesToGallery(const [], captured);

      expect(composer.notice, isNull);
    });

    testWidgets('gallery uploads follow membership edits while pending', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '![standalone](upload://standalone)\n'
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final gallery = parseComposerImageGalleries(composer.text.text).single;
      final standalone = composer.standaloneImages.single;

      composer.addImagesToGallery([_file('late.png')], gallery);
      composer.addExistingImagesToGallery(gallery, [standalone]);
      calls.single.complete(_result('late'));
      await tester.pump();

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://existing', 'upload://standalone', 'upload://late'],
      );
    });

    testWidgets('stale Add selected resolves a gallery changed by an upload', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '![standalone](upload://standalone)\n'
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final capturedGallery = parseComposerImageGalleries(
        composer.text.text,
      ).single;
      final capturedStandalone = composer.standaloneImages.single;

      composer.addImagesToGallery([_file('uploaded.png')], capturedGallery);
      calls.single.complete(_result('uploaded'));
      await tester.pump();
      composer.addExistingImagesToGallery(capturedGallery, [
        capturedStandalone,
      ]);

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://existing', 'upload://uploaded', 'upload://standalone'],
      );
    });

    test('Add selected rejects a partly stale image selection atomically', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.text =
          '![one](upload://one)\n'
          '![two](upload://two)\n'
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final gallery = parseComposerImageGalleries(composer.text.text).single;
      final selected = composer.standaloneImages;
      composer.setImageAlt(selected.last, 'changed');
      final changed = composer.text.text;

      composer.addExistingImagesToGallery(gallery, selected);

      expect(composer.text.text, changed);
      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.single.url,
        'upload://existing',
      );
    });

    testWidgets('unwrapping retargets an in-flight gallery upload standalone', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final gallery = parseComposerImageGalleries(composer.text.text).single;

      composer.addImagesToGallery([_file('late.png')], gallery);
      composer.unwrapGallery(gallery);
      calls.single.complete(_result('late'));
      await tester.pump();

      expect(parseComposerImageGalleries(composer.text.text), isEmpty);
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://existing',
        'upload://late',
      ]);
    });

    testWidgets(
      'dissolving the final member demotes a pending gallery upload',
      (tester) async {
        final calls = <_UploadCall>[];
        final composer = ComposerController(
          _target,
          imageUploader: _recordingUploader(calls),
        );
        addTearDown(composer.dispose);
        composer.text.text =
            '[grid]\n'
            '![existing](upload://existing)\n'
            '[/grid]';
        final gallery = parseComposerImageGalleries(composer.text.text).single;

        composer.addImagesToGallery([_file('late.png')], gallery);
        composer.removeImage(gallery.images.single);
        calls.single.complete(_result('late'));
        await tester.pump();

        expect(parseComposerImageGalleries(composer.text.text), isEmpty);
        expect(composer.text.imageBlocks.single.url, 'upload://late');
      },
    );

    testWidgets('concurrent batches at one anchor keep launch order', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);

      composer.addImages([_file('one.png')], 0);
      composer.addImages([_file('two.png')], 0);
      calls[1].complete(_result('two'));
      await tester.pump();
      expect(composer.text.imageBlocks.single.url, 'upload://two');

      calls[0].complete(_result('one'));
      await tester.pump();
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
        'upload://two',
      ]);
    });

    testWidgets('concurrent batches keep order after their anchor moves', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text = 'tail';

      composer.addImages([_file('one.png')], 0);
      composer.text.text = 'prefix tail';
      composer.addImages([_file('two.png')], 'prefix '.length);
      calls[1].complete(_result('two'));
      await tester.pump();
      calls[0].complete(_result('one'));
      await tester.pump();

      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
        'upload://two',
      ]);
    });

    testWidgets('concurrent auto-grid batches remain separate and ordered', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
        enableAutoGridImages: true,
      );
      addTearDown(composer.dispose);

      composer.addImages([
        _file('one.png'),
        _file('two.png'),
        _file('three.png'),
      ], 0);
      composer.addImages([
        _file('four.png'),
        _file('five.png'),
        _file('six.png'),
      ], 0);
      for (var index = 3; index < 6; index++) {
        calls[index].complete(_result(['four', 'five', 'six'][index - 3]));
      }
      await tester.pump();
      for (var index = 0; index < 3; index++) {
        calls[index].complete(_result(['one', 'two', 'three'][index]));
      }
      await tester.pump();

      final galleries = parseComposerImageGalleries(composer.text.text);
      expect(galleries, hasLength(2));
      expect(
        galleries.expand((gallery) => gallery.images).map((image) => image.url),
        [
          'upload://one',
          'upload://two',
          'upload://three',
          'upload://four',
          'upload://five',
          'upload://six',
        ],
      );
    });

    testWidgets('concurrent gallery batches keep launch order', (tester) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '![existing](upload://existing)\n'
          '[/grid]';
      final gallery = parseComposerImageGalleries(composer.text.text).single;

      composer.addImagesToGallery([_file('one.png')], gallery);
      composer.addImagesToGallery([_file('two.png')], gallery);
      calls[1].complete(_result('two'));
      await tester.pump();
      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://existing', 'upload://two'],
      );

      calls[0].complete(_result('one'));
      await tester.pump();
      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://existing', 'upload://one', 'upload://two'],
      );
    });

    testWidgets('an older failed batch retries before a later result', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);

      composer.addImages([_file('one.png')], 0);
      composer.addImages([_file('two.png')], 0);
      calls[0].fail(const ComposerUploadException('Retry one.'));
      calls[1].complete(_result('two'));
      await tester.pump();
      expect(composer.text.imageBlocks.single.url, 'upload://two');

      composer.retryUpload(composer.uploads.single.id);
      calls.last.complete(_result('one'));
      await tester.pump();
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
        'upload://two',
      ]);
    });

    testWidgets('removing an older failed batch leaves the later result', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);

      composer.addImages([_file('one.png')], 0);
      composer.addImages([_file('two.png')], 0);
      calls[0].fail(const ComposerUploadException('Remove one.'));
      calls[1].complete(_result('two'));
      await tester.pump();

      composer.removeUpload(composer.uploads.single.id);
      expect(composer.text.imageBlocks.single.url, 'upload://two');
      expect(composer.uploads, isEmpty);
    });

    testWidgets(
      'auto-gallery members stay before a later explicit gallery batch',
      (tester) async {
        final calls = <_UploadCall>[];
        final composer = ComposerController(
          _target,
          imageUploader: _recordingUploader(calls),
          enableAutoGridImages: true,
        );
        addTearDown(composer.dispose);

        composer.addImages([
          _file('one.png'),
          _file('two.png'),
          _file('three.png'),
        ], 0);
        calls[0].complete(_result('one'));
        await tester.pump();
        final gallery = parseComposerImageGalleries(composer.text.text).single;

        composer.addImagesToGallery([_file('later.png')], gallery);
        calls[3].complete(_result('later'));
        await tester.pump();
        calls[2].complete(_result('three'));
        calls[1].complete(_result('two'));
        await tester.pump();

        expect(
          parseComposerImageGalleries(
            composer.text.text,
          ).single.images.map((image) => image.url),
          ['upload://one', 'upload://two', 'upload://three', 'upload://later'],
        );
      },
    );

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

        composer.addImages([_file('one.png'), _file('two.png')], 4);
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

    testWidgets(
      'attachment targets retain uploads without inserting markdown',
      (tester) async {
        final calls = <_UploadCall>[];
        final composer = ComposerController(
          _attachmentTarget,
          imageUploader: _recordingUploader(calls),
        );
        addTearDown(composer.dispose);

        composer.addImages([_file('one.png'), _file('two.png')], 0);
        calls[1].complete(_result('two'));
        await tester.pump();
        expect(composer.completedUploads, isEmpty);

        calls[0].complete(_result('one'));
        await tester.pump();

        expect(composer.raw, isEmpty);
        expect(composer.canSubmit, isTrue);
        expect(composer.hasActiveUploads, isFalse);
        expect(composer.completedUploads.map((upload) => upload.id), [
          _result('one').id,
          _result('two').id,
        ]);
        expect(
          composer.uploads.map((upload) => upload.status),
          everyElement(ComposerUploadStatus.completed),
        );

        composer.removeUpload(composer.uploads.first.id);
        expect(composer.completedUploads.single.id, _result('two').id);
        composer.clearDocument();
        expect(composer.uploads, isEmpty);
        expect(composer.canSubmit, isFalse);
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
      composer.addImages([_file('photo.png')], 4);

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
      composer.addImages([_file('photo.png')], 0);

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

      composer.addImages([_file('photo.png')], 0);
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
        composer.addImages([_file('one.png'), _file('two.png')], 4);

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
      composer.addImages([_file('photo.png')], 0);

      var aborted = false;
      unawaited(calls.single.abort.then((_) => aborted = true));
      composer.cancelUpload(composer.uploads.single.id);
      await tester.pump();

      expect(aborted, isTrue);
      expect(composer.uploads, isEmpty);
      expect(composer.text.text, isEmpty);
    });

    testWidgets('cancelling an earlier slot flushes a ready later upload', (
      tester,
    ) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      addTearDown(composer.dispose);

      composer.addImages([_file('one.png'), _file('two.png')], 0);
      calls[1].complete(_result('two'));
      await tester.pump();
      expect(composer.text.text, isEmpty);

      composer.cancelUpload(composer.uploads.first.id);
      await tester.pump();

      expect(composer.text.imageBlocks.single.url, 'upload://two');
      expect(composer.uploads, isEmpty);
    });

    testWidgets('disposing aborts both active upload requests', (tester) async {
      final calls = <_UploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: _recordingUploader(calls),
      );
      composer.addImages([_file('one.png'), _file('two.png')], 0);
      expect(calls, hasLength(2));
      var aborted = 0;
      for (final call in calls) {
        unawaited(call.abort.then((_) => aborted++));
      }

      composer.dispose();
      await tester.pump();

      expect(aborted, 2);
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

      composer.addImages([_file('notes.txt')], 0);
      expect(composer.notice, contains('not allowed'));
      composer.addImages([_file('one.png'), _file('two.png')], 0);
      expect(composer.notice, 'Upload at most one image at a time.');
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

    test(
      'edits gallery membership, mode, and wrapper without deleting images',
      () {
        final composer = ComposerController(_target);
        addTearDown(composer.dispose);
        composer.text.text =
            '![standalone](upload://standalone)\n'
            '[grid]\n'
            '![one](upload://one)\n'
            '![two](upload://two)\n'
            '[/grid]';

        var gallery = parseComposerImageGalleries(composer.text.text).single;
        composer.addExistingImagesToGallery(gallery, [
          composer.standaloneImages.single,
        ]);
        gallery = parseComposerImageGalleries(composer.text.text).single;
        expect(gallery.images.map((image) => image.url), [
          'upload://one',
          'upload://two',
          'upload://standalone',
        ]);

        composer.setGalleryMode(gallery, ComposerGalleryMode.carousel);
        gallery = parseComposerImageGalleries(composer.text.text).single;
        expect(gallery.mode, ComposerGalleryMode.carousel);
        expect(composer.text.text, contains('[grid mode=carousel]'));

        composer.moveImageOutOfGallery(gallery, gallery.images[1]);
        gallery = parseComposerImageGalleries(composer.text.text).single;
        expect(gallery.images.map((image) => image.url), [
          'upload://one',
          'upload://standalone',
        ]);
        expect(composer.standaloneImages.single.url, 'upload://two');

        composer.unwrapGallery(gallery);
        expect(parseComposerImageGalleries(composer.text.text), isEmpty);
        expect(composer.text.imageBlocks.map((image) => image.url), [
          'upload://one',
          'upload://standalone',
          'upload://two',
        ]);
      },
    );

    test('changes only the gallery opening tag when switching mode', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid]\n'
          '\n'
          '![one](upload://one)\n'
          ' \t\n'
          '[/grid]';
      final before = composer.text.text;
      final gallery = parseComposerImageGalleries(before).single;

      composer.setGalleryMode(gallery, ComposerGalleryMode.carousel);

      expect(
        composer.text.text,
        '[grid mode=carousel]${before.substring('[grid]'.length)}',
      );
    });

    test('reorders gallery members without changing their image source', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.text =
          '[grid mode=carousel]\n'
          '![one|640x480](upload://one)\n'
          '![two](upload://two)\n'
          '![three](upload://three)\n'
          '[/grid]';
      final gallery = parseComposerImageGalleries(composer.text.text).single;

      composer.reorderGalleryImage(gallery, gallery.images.first, 2);

      final reordered = parseComposerImageGalleries(composer.text.text).single;
      expect(reordered.mode, ComposerGalleryMode.carousel);
      expect(reordered.images.map((image) => image.url), [
        'upload://two',
        'upload://three',
        'upload://one',
      ]);
      expect(reordered.images.last.source, '![one|640x480](upload://one)');
    });
  });
}

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

const _tokenSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('fake-syntax'),
  name: 'token',
);

final class _TokenSyntaxPolicy implements ComposerSyntaxPolicy {
  const _TokenSyntaxPolicy();

  @override
  ComposerSyntaxKind get kind => _tokenSyntaxKind;

  @override
  Object? get projectionState => null;

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final match in RegExp(r'\[\[[^\]\n]+\]\]').allMatches(source))
      _TokenProjection(match.start, match.end, match.group(0)!),
  ];
}

final class _TokenProjection implements ComposerSyntaxProjection {
  const _TokenProjection(this.start, this.end, this.source);

  @override
  final int start;
  @override
  final int end;
  @override
  final String source;

  TextEditingValue replace(TextEditingValue document, String replacement) {
    if (start < 0 ||
        end > document.text.length ||
        document.text.substring(start, end) != source) {
      return document;
    }
    return document.copyWith(
      text: document.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
  }

  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      !suppressCollapsedCaret &&
      document.selection.extentOffset > start &&
      document.selection.extentOffset < end;

  @override
  int caretAfter(String document) => end;

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: end),
        composing: TextRange.empty,
      );

  @override
  bool get supportsHover => false;

  @override
  bool get protectsAdjacentDelete => false;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) => [
    TextSpan(text: source, style: context.baseStyle),
  ];

  @override
  FutureOr<void> edit(BuildContext context, ComposerEditorHost editor) {}

  @override
  FutureOr<void> remove(BuildContext context, ComposerEditorHost editor) {}
}

const _attachmentTargetKind = ComposerTargetKind(
  owner: PluginId('attachments'),
  name: 'message',
);

final _attachmentTarget = ComposerTarget.plugin(
  siteUrl: 'https://meta.discourse.org',
  topicTitle: 'Attachment message',
  policy: ComposerTargetPolicy(
    kind: _attachmentTargetKind,
    draftKey: 'attachments/message',
    uploadType: const ComposerUploadType('attachment'),
    uploadDisposition: ComposerUploadDisposition.retainAttachment,
    uploadsEnabled: true,
    supportsEditing: true,
    validate: (context) =>
        context.raw.trim().isNotEmpty || context.completedUploadCount > 0,
    emojiUsageContext: const EmojiUsageContext(
      owner: PluginId('attachments'),
      name: 'message',
    ),
  ),
);

final _markdownPluginTarget = ComposerTarget.plugin(
  siteUrl: 'https://meta.discourse.org',
  topicTitle: 'Markdown plugin message',
  policy: ComposerTargetPolicy(
    kind: const ComposerTargetKind(
      owner: PluginId('markdown-plugin'),
      name: 'message',
    ),
    draftKey: 'markdown-plugin/message',
    uploadType: const ComposerUploadType('composer'),
    uploadDisposition: ComposerUploadDisposition.insertMarkdown,
    uploadsEnabled: true,
    supportsEditing: true,
    validate: (context) => context.raw.trim().isNotEmpty,
    emojiUsageContext: const EmojiUsageContext(
      owner: PluginId('markdown-plugin'),
      name: 'message',
    ),
  ),
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
  id: name.hashCode.abs() + 1,
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
