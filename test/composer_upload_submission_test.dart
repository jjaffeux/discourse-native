import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/composer_media_editing_coordinator.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final editing in [false, true]) {
    final operation = editing ? 'updatePost' : 'createPost';

    testWidgets('$operation blocks new uploads and retries until failure', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _UploadApi(gate);
      final shell = await _openComposer(api, editing: editing);
      final composer = shell.visibleComposer!;
      composer.text.text = _galleryRaw;
      final gallery = composer.text.galleryBlocks.single;
      composer.addImages([_file('failed.png')], composer.text.text.length);
      await tester.pump();
      expect(api.uploads, hasLength(1));
      api.uploads.single.result.completeError(_uploadFailure);
      await tester.pump();
      final failed = composer.uploads.single;
      expect(composer.canSubmit, isTrue);

      final submitting = shell.submitComposer();
      await tester.pump();
      final writes = editing ? api.updated : api.created;
      expect(writes.single['raw'], _galleryRaw);
      expect(composer.submitting, isTrue);

      composer.addImages([_file('new.png')], 0);
      composer.addFiles([_file('notes.txt')], 0);
      composer.addImagesToGallery([_file('gallery.png')], gallery);
      composer.retryUpload(failed.id);
      await tester.pump();

      expect(api.uploads, hasLength(1));
      expect(composer.uploads.single, same(failed));
      expect(composer.raw, writes.single['raw']);

      gate.completeError(_writeFailure);
      await submitting;
      expect(shell.visibleComposer, same(composer));
      expect(composer.submitting, isFalse);
      expect(composer.error, same(_writeFailure));

      composer.retryUpload(failed.id);
      composer.addFiles([_file('notes.txt')], 0);
      await tester.pump();
      expect(api.uploads.map((call) => call.file.name), [
        'failed.png',
        'failed.png',
        'notes.txt',
      ]);
      expect(composer.hasActiveUploads, isTrue);
      expect(composer.canSubmit, isFalse);
      for (final call in api.uploads.skip(1)) {
        call.complete();
      }
      await tester.pump();
      expect(composer.raw, contains('![failed](upload://failed.png)'));
      expect(composer.raw, contains('[notes.txt](upload://notes.txt)'));
      expect(composer.uploads, isEmpty);
      expect(composer.canSubmit, isTrue);
      await composer.flushDraft();
      if (!editing) {
        expect(api.draftsSaved.last['data'], contains('upload://failed.png'));
        expect(api.draftsSaved.last['data'], contains('upload://notes.txt'));
      }
    });

    testWidgets('$operation disables upload and retry controls until failure', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _UploadApi(gate);
      final shell = await _openComposer(api, editing: editing);
      final composer = shell.visibleComposer!;
      composer.addImages([_file('failed.png')], 0);
      await tester.pump();
      api.uploads.single.result.completeError(_uploadFailure);
      await tester.pump();
      var pickerCalls = 0;
      await _pumpPanel(tester, shell, () async {
        pickerCalls++;
        return [_file('new.png')];
      });
      final uploadButton = find.byKey(const ValueKey('composer-upload'));
      final retryButton = _iconButton('Retry upload');
      expect(tester.widget<IconButton>(uploadButton).onPressed, isNotNull);
      expect(
        tester.widget<DAttachmentAction>(retryButton).onPressed,
        isNotNull,
      );

      await tester.tap(
        find.widgetWithText(FilledButton, editing ? 'Save' : 'Reply'),
      );
      await tester.pump();
      expect((editing ? api.updated : api.created).single['raw'], _body);
      expect(composer.submitting, isTrue);
      expect(tester.widget<IconButton>(uploadButton).onPressed, isNull);
      expect(tester.widget<DAttachmentAction>(retryButton).onPressed, isNull);
      expect(
        tester
            .widget<DAttachmentAction>(_attachmentAction('Remove upload'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(uploadButton);
      await tester.tap(retryButton);
      await tester.pump();
      expect(pickerCalls, 0);
      expect(api.uploads, hasLength(1));

      gate.completeError(_writeFailure);
      await tester.pump();
      expect(composer.submitting, isFalse);
      expect(tester.widget<IconButton>(uploadButton).onPressed, isNotNull);
      expect(
        tester.widget<DAttachmentAction>(retryButton).onPressed,
        isNotNull,
      );
      await tester.tap(retryButton);
      await tester.tap(uploadButton);
      await tester.pump();
      expect(pickerCalls, 1);
      expect(api.uploads, hasLength(3));
      await tester.tap(find.byTooltip('Cancel upload').first);
      await tester.pump();
      expect(api.uploads[1].aborted, isTrue);
      expect(composer.uploads, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('an open toolbar picker cannot add uploads during createPost', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = _UploadApi(gate);
    final shell = await _openComposer(api);
    final composer = shell.visibleComposer!;
    final picker = Completer<List<ComposerUploadFile>>();
    var pickerCalls = 0;
    await _pumpPanel(tester, shell, () {
      pickerCalls++;
      return picker.future;
    });
    await tester.tap(find.byKey(const ValueKey('composer-upload')));
    await tester.pump();
    expect(pickerCalls, 1);

    final submitting = shell.submitComposer();
    await tester.pump();
    expect(api.created.single['raw'], _body);
    picker.complete([_file('late.png')]);
    await tester.pump();
    expect(api.uploads, isEmpty);
    expect(composer.uploads, isEmpty);
    expect(composer.raw, _body);

    gate.complete();
    await submitting;
    await tester.pump();
    expect(composer.isDisposed, isTrue);
    expect(shell.visibleComposer, isNull);
    expect(api.uploads, isEmpty);
  });

  testWidgets('an open gallery picker cannot add uploads during createPost', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = _UploadApi(gate);
    final shell = await _openComposer(api);
    final composer = shell.visibleComposer!;
    composer.text.text = _galleryRaw;
    final media = ComposerMediaEditingCoordinator(composer);
    addTearDown(media.dispose);
    media.selectGallery(composer.text.galleryBlocks.single);
    final picker = Completer<List<ComposerUploadFile>>();
    final picking = media.pickImagesForSelectedGallery(() => picker.future);
    expect(media.value.pickingGalleryImages, isTrue);

    final submitting = shell.submitComposer();
    await tester.pump();
    expect(api.created.single['raw'], _galleryRaw);
    picker.complete([_file('late.png')]);
    await picking;
    await tester.pump();
    expect(api.uploads, isEmpty);
    expect(composer.raw, _galleryRaw);
    expect(media.value.pickingGalleryImages, isFalse);

    gate.completeError(_writeFailure);
    await submitting;
    await media.pickImagesForSelectedGallery(() async => [_file('retry.png')]);
    await tester.pump();
    expect(api.uploads.single.file.name, 'retry.png');
  });

  for (final result in ['image', 'empty', 'error']) {
    testWidgets('a late clipboard $result is consumed during createPost', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _UploadApi(gate);
      final shell = await _openComposer(api);
      final composer = shell.visibleComposer!;
      final media = ComposerMediaEditingCoordinator(composer);
      addTearDown(media.dispose);
      final clipboard = Completer<List<ComposerUploadFile>>();
      final pasting = media.pasteClipboardImages(() => clipboard.future);

      final submitting = shell.submitComposer();
      await tester.pump();
      expect(api.created.single['raw'], _body);
      if (result == 'error') {
        clipboard.completeError(StateError('Clipboard unavailable'));
      } else {
        clipboard.complete(result == 'image' ? [_file('late.png')] : []);
      }
      expect(await pasting, isTrue, reason: 'do not fall back to pasting text');
      await tester.pump();
      expect(api.uploads, isEmpty);
      expect(composer.raw, _body);

      gate.completeError(_writeFailure);
      await submitting;
      expect(
        await media.pasteClipboardImages(() async => [_file('retry.png')]),
        isTrue,
      );
      await tester.pump();
      expect(api.uploads.single.file.name, 'retry.png');
    });
  }
}

Future<ShellController> _openComposer(
  _UploadApi api, {
  bool editing = false,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.resolveSiteConfig(_site);
  shell.store.put(
    _site,
    const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  if (editing) {
    final post = const Post(
      id: 22,
      postNumber: 2,
      username: 'author',
      cooked: '<p>Original body</p>',
      canEdit: true,
    ).withRaw('Original body');
    shell.store.put(_site, post);
    shell.openEdit(post);
  } else {
    shell.openReply();
    await shell.finishComposerDraftRestore(shell.visibleComposer!);
  }
  shell.visibleComposer!.text.text = _body;
  return shell;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerImagePicker pickImages,
) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: ShellScope(
      controller: shell,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: shell,
          builder: (context, _) {
            if (shell.visibleComposer case final composer?) {
              return ComposerPanel(composer: composer, pickImages: pickImages);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  ),
);

final class _UploadApi extends FakeDiscourseApi {
  _UploadApi(Completer<void> gate)
    : super(
        createPostGate: gate,
        updatePostGate: gate,
        siteConfigs: const {
          _site: SiteConfig(authorizedExtensions: ['png', 'txt']),
        },
      );

  final List<_UploadCall> uploads = [];

  @override
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    String? clientId,
  }) {
    final call = _UploadCall(file);
    uploads.add(call);
    unawaited(abortTrigger.then((_) => call.aborted = true));
    return call.result.future;
  }
}

final class _UploadCall {
  _UploadCall(this.file);

  final ComposerUploadFile file;
  final result = Completer<ComposerUploadResult>();
  bool aborted = false;

  void complete() => result.complete(
    ComposerUploadResult(
      id: 42,
      originalFilename: file.name,
      shortUrl: 'upload://${file.name}',
      url: '$_site/uploads/${file.name}',
    ),
  );
}

ComposerUploadFile _file(String name) => ComposerUploadFile(
  name: name,
  length: () => Future.value(3),
  openRead: () => Stream.value([1, 2, 3]),
);

Finder _iconButton(String tooltip) => _attachmentAction(tooltip);

Finder _attachmentAction(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is DAttachmentAction && widget.tooltip == tooltip,
);

const _site = 'https://meta.discourse.org';
const _body = 'A post ready to submit';
const _galleryRaw = '$_body\n[grid]\n![inside](upload://inside)\n[/grid]';
const _uploadFailure = ComposerUploadException('Try uploading again.');
const _writeFailure = WriteException(WriteFailure.conflict);
