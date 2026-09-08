import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final state in [
    'loading',
    'submitting',
    'checking',
    'closing',
    'discarding',
    'retired',
    'disposed',
  ]) {
    test(
      '$state rejects authoring without changing selection or composition',
      () {
        var current = true;
        final composer = ComposerController(
          _target,
          isCurrentComposer: () => current,
        );
        addTearDown(() {
          if (!composer.isDisposed) composer.dispose();
        });
        composer.text.value = const TextEditingValue(
          text: _document,
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
          composing: TextRange(start: 0, end: 4),
        );
        final image = composer.standaloneImages.single;
        final gallery = composer.text.galleryBlocks.single;
        final quote = composer.text.quoteBlocks.single;
        switch (state) {
          case 'loading':
            composer.beginLoadingBody();
          case 'submitting':
            composer.beginSubmit();
          case 'checking':
            composer.checking();
          case 'closing':
            composer.beginClose();
          case 'discarding':
            composer.beginDiscard();
          case 'retired':
            current = false;
          case 'disposed':
            composer.dispose();
        }
        expect(composer.isEditing, isFalse);
        final before = composer.value;
        final revision = composer.draftRevision;
        final commands = <String, void Function()>{
          'bold': () => composer.toggleMark(ComposerMark.bold),
          'italic': () => composer.toggleMark(ComposerMark.italic),
          'inline code': composer.toggleSelectedInlineCode,
          'text': () => composer.insertText('late text'),
          'emoji': () => composer.insertEmoji('smile'),
          'whisper': composer.toggleWhisper,
          'block': () => expect(
            composer.insertBlock(expectedValue: before, markdown: 'late block'),
            isFalse,
          ),
          'prepend': () => composer.prependBlock('late block'),
          'quote removal': () => composer.removeQuote(quote),
          'image alt': () => composer.setImageAlt(image, 'late alt'),
          'image scale': () => composer.setImageScale(image, 50),
          'image removal': () => composer.removeImage(image),
          'gallery mode': () =>
              composer.setGalleryMode(gallery, ComposerGalleryMode.carousel),
          'gallery unwrap': () => composer.unwrapGallery(gallery),
          'gallery removal': () => composer.removeGallery(gallery),
          'gallery membership': () =>
              composer.addExistingImagesToGallery(gallery, [image]),
          'gallery reorder': () =>
              composer.reorderGalleryImage(gallery, gallery.images.first, 1),
          'gallery image removal': () =>
              composer.removeImage(gallery.images.first),
          'move image out': () =>
              composer.moveImageOutOfGallery(gallery, gallery.images.first),
        };
        for (final command in commands.entries) {
          command.value();
          expect(composer.value, before, reason: command.key);
          expect(composer.draftRevision, revision, reason: command.key);
        }
      },
    );
  }

  test('autocomplete cannot accept a suggestion during submission', () {
    var accepted = 0;
    final composer = ComposerController(
      _target,
      onEmojiAccepted: (_) => accepted++,
    );
    addTearDown(composer.dispose);
    composer.text.value = const TextEditingValue(
      text: 'body :smi',
      selection: TextSelection.collapsed(offset: 9),
    );
    expect(composer.autocomplete.trigger?.kind, ComposerTriggerKind.emoji);
    const suggestion = ComposerSuggestion(
      kind: ComposerTriggerKind.emoji,
      value: 'smile',
      label: 'Smile',
    );
    composer.beginSubmit();
    final before = composer.value;
    composer.acceptSuggestion(suggestion);
    expect(composer.value, before);
    expect(accepted, 0);
    composer.unresolved();
    composer.acceptSuggestion(suggestion);
    expect(composer.raw, 'body :smile:');
    expect(accepted, 1);
  });

  for (final resume in [
    'loaded',
    'failed',
    'unresolved',
    'cancel close',
    'cancel discard',
  ]) {
    test('$resume restores user authoring', () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.value = const TextEditingValue(
        text: 'body',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
      );
      switch (resume) {
        case 'loaded':
          composer.beginLoadingBody();
          composer.loadedBody('body');
          composer.text.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 4,
          );
        case 'failed':
          composer.beginSubmit();
          composer.failed(const WriteException(WriteFailure.conflict));
        case 'unresolved':
          composer.checking();
          composer.unresolved();
        case 'cancel close':
          composer.beginClose();
          composer.cancelClose();
        case 'cancel discard':
          composer.beginDiscard();
          composer.finishDiscard();
      }
      expect(composer.isEditing, isTrue);
      composer.toggleMark(ComposerMark.bold);
      expect(composer.raw, '**body**');
      composer.insertText('replacement');
      expect(composer.raw, '**replacement**');
      composer.insertEmoji('smile');
      expect(composer.raw, '**replacement :smile:**');
      expect(
        composer.insertBlock(expectedValue: composer.value, markdown: 'block'),
        isTrue,
      );
      expect(composer.raw, contains('\n\nblock\n\n'));
    });
  }

  test('submit preparers can commit while user authoring is suspended', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);
    composer.text.text = 'original';
    composer.beginSubmit();
    expect(composer.isEditing, isFalse);
    expect(
      composer.commit(
        expectedValue: composer.value,
        value: const TextEditingValue(text: 'prepared'),
      ),
      isTrue,
    );
    expect(
      composer.commitText(
        expectedText: 'prepared',
        value: const TextEditingValue(text: 'final preparation'),
      ),
      isTrue,
    );
    expect(composer.raw, 'final preparation');
    expect(composer.submitting, isTrue);
  });
}

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'topic',
  topicTitle: 'Topic',
);
const _document =
    'body\n\n[quote="sam"]\nquoted\n[/quote]\n\n![outside|640x480](upload://outside)\n[grid]\n![one](upload://one)\n![two](upload://two)\n[/grid]';
