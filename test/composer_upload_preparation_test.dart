import 'dart:async';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('prepares before upload and reuses the file on retry', (
    tester,
  ) async {
    final preparation = Completer<PreparedComposerUpload>();
    var preparations = 0;
    var releases = 0;
    final sent = <ComposerUploadFile>[];
    final replies = <Completer<ComposerUploadResult>>[];
    final composer = ComposerController(
      _target,
      prepareUpload: (file, {required abortTrigger}) {
        preparations++;
        return preparation.future;
      },
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        sent.add(file);
        final reply = Completer<ComposerUploadResult>();
        replies.add(reply);
        return reply.future;
      },
    );
    addTearDown(composer.dispose);
    composer.addFiles([_file('source.png')], 0);
    expect(composer.hasActiveUploads, isTrue);
    expect(composer.uploads.single.status, ComposerUploadStatus.processing);
    expect(sent, isEmpty);
    final processed = _file('source.webp');
    preparation.complete(
      PreparedComposerUpload(
        processed,
        release: () async {
          releases++;
        },
      ),
    );
    await tester.pump();
    expect(sent, [same(processed)]);
    expect(composer.uploads.single.file, same(processed));
    expect(composer.uploads.single.status, ComposerUploadStatus.uploading);
    replies.first.completeError(const ComposerUploadException('Retry me'));
    await tester.pump();
    expect(composer.uploads.single.status, ComposerUploadStatus.failed);
    expect(releases, 0);
    composer.retryUpload(composer.uploads.single.id);
    await tester.pump();
    expect(preparations, 1);
    expect(sent, [same(processed), same(processed)]);
    replies.last.complete(_result);
    await tester.pump();
    expect(releases, 1);
    expect(composer.hasActiveUploads, isFalse);
    expect(composer.raw, contains('upload://optimized'));
  });

  for (final dispose in [false, true]) {
    testWidgets(
      '${dispose ? 'disposing' : 'cancelling'} while preparing prevents upload and releases late output',
      (tester) async {
        final preparation = Completer<PreparedComposerUpload>();
        var aborted = false;
        var sent = false;
        var releases = 0;
        final composer = ComposerController(
          _target,
          prepareUpload: (file, {required abortTrigger}) {
            unawaited(abortTrigger.then((_) => aborted = true));
            return preparation.future;
          },
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async {
                sent = true;
                return _result;
              },
        );
        composer.addImages([_file('source.png')], 0);
        if (dispose) {
          composer.dispose();
        } else {
          composer.cancelUpload(composer.uploads.single.id);
          addTearDown(composer.dispose);
        }
        await tester.pump();
        expect(aborted, isTrue);
        preparation.complete(
          PreparedComposerUpload(
            _file('source.jpg'),
            release: () async {
              releases++;
            },
          ),
        );
        await tester.pump();
        expect(sent, isFalse);
        expect(releases, 1);
      },
    );

    testWidgets(
      '${dispose ? 'disposing' : 'removing'} a failed upload releases the cached image',
      (tester) async {
        var releases = 0;
        final composer = ComposerController(
          _target,
          prepareUpload: (file, {required abortTrigger}) async =>
              PreparedComposerUpload(
                _file('source.jpg'),
                release: () async {
                  releases++;
                },
              ),
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async =>
                  throw const ComposerUploadException('Failure'),
        );
        composer.addImages([_file('source.png')], 0);
        await tester.pump();
        expect(releases, 0);
        if (dispose) {
          composer.dispose();
        } else {
          composer.removeUpload(composer.uploads.single.id);
          addTearDown(composer.dispose);
        }
        await tester.pump();
        expect(releases, 1);
      },
    );
  }
}

const _target = ComposerTarget(
  siteUrl: 'https://example.com',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);
const _result = ComposerUploadResult(
  id: 1,
  originalFilename: 'source.webp',
  shortUrl: 'upload://optimized',
  url: '/optimized.webp',
  width: 60,
  height: 40,
);
ComposerUploadFile _file(String name) => ComposerUploadFile(
  name: name,
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);
