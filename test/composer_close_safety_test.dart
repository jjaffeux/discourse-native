import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _firstSite = 'https://one.example';
const _secondSite = 'https://two.example';
const _user = DiscourseUser(id: 1, username: 'reader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;
  late _SessionApi api;
  late _DraftStore drafts;
  var shellDisposed = false;

  void disposeShell() {
    if (shellDisposed) return;
    shellDisposed = true;
    shell.dispose();
  }

  Future<void> createShell({
    WriteException? draftFailure,
    Completer<void>? postGate,
    Completer<void>? draftGate,
  }) async {
    shellDisposed = false;
    api = _SessionApi(
      draftFailure: draftFailure,
      postGate: postGate,
      draftGate: draftGate,
    );
    drafts = _DraftStore();
    shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('one.example', title: 'One', user: _user),
        instance('two.example', title: 'Two', user: _user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()
        ..keys[_firstSite] = 'first-key'
        ..keys[_secondSite] = 'second-key',
      drafts: drafts,
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await shell.load();
    await shell.loadFeed('latest');
  }

  void showTopic(int topicId) {
    shell.store.put(
      shell.currentInstance!.url,
      TopicDetail(
        id: topicId,
        title: 'Topic $topicId',
        stream: const [],
        canCreatePost: true,
      ),
    );
    shell.pushContent(
      ContentRoute.topic(
        topicId: topicId,
        slug: 'topic-$topicId',
        title: 'Topic $topicId',
      ),
    );
  }

  Future<ComposerController> openReply(int topicId) async {
    showTopic(topicId);
    shell.openReply();
    final composer = shell.visibleComposer!;
    await shell.finishComposerDraftRestore(composer);
    return composer;
  }

  setUp(createShell);
  tearDown(disposeShell);

  test(
    'save and close waits for presentation before persisting its draft',
    () async {
      final composer = await openReply(7);
      composer.text.text = 'Preserve this exact editor';
      final frame = Completer<void>();
      final closing = shell.saveComposerAndClose(
        composer,
        afterHide: () => frame.future,
      );
      expect(composer.closing, isTrue);
      expect(composer.isDisposed, isFalse);
      expect(api.draftsSaved, isEmpty);
      frame.complete();
      expect(await closing, isA<ComposerClosed>());
      expect(composer.isDisposed, isTrue);
      expect(
        api.draftsSaved.last['data'],
        contains('Preserve this exact editor'),
      );
    },
  );

  test(
    'failed save and close restores the retained editor for retry',
    () async {
      disposeShell();
      await createShell(
        draftFailure: const WriteException(WriteFailure.unreachable),
      );
      final composer = await openReply(7);
      composer.text.text = 'Keep until storage succeeds';
      drafts.failWrites = true;
      expect(
        await shell.saveComposerAndClose(composer, afterHide: () async {}),
        isA<ComposerCloseFailed>(),
      );
      expect(composer.closing, isFalse);
      expect(composer.isDisposed, isFalse);
      expect(shell.visibleComposer, same(composer));
      drafts.failWrites = false;
      expect(
        await shell.saveComposerAndClose(composer, afterHide: () async {}),
        isA<ComposerClosed>(),
      );
      expect(composer.isDisposed, isTrue);
      expect(
        ComposerDraft.decode(await drafts.read(_firstSite, 'topic_7'))?.reply,
        'Keep until storage succeeds',
      );
    },
  );

  test('close publication cannot run work against a retired editor', () async {
    final composer = await openReply(7);
    composer.text.text = 'An abandoned close';
    ComposerController? successor;
    shell.addListener(() {
      if (!composer.closing || composer.isDisposed) return;
      shell.closeComposer(composer: composer);
      shell.openReply();
      successor = shell.visibleComposer;
    });
    var frameRequested = false;
    expect(
      await shell.saveComposerAndClose(
        composer,
        afterHide: () async {
          frameRequested = true;
        },
      ),
      isA<ComposerClosed>(),
    );
    expect(frameRequested, isFalse);
    expect(composer.isDisposed, isTrue);
    expect(successor, isNotNull);
    expect(successor!.isDisposed, isFalse);
    expect(shell.visibleComposer, same(successor));
  });

  test(
    'close resumes only its original editor after the presentation boundary',
    () async {
      final composer = await openReply(7);
      composer.text.text = 'First draft';
      final frame = Completer<void>();
      final closing = shell.saveComposerAndClose(
        composer,
        afterHide: () => frame.future,
      );
      shell.closeComposer(composer: composer);
      final successor = await openReply(8);
      successor.text.text = 'Second draft';
      frame.complete();
      expect(await closing, isA<ComposerClosed>());
      expect(successor.isDisposed, isFalse);
      expect(successor.closing, isFalse);
      expect(shell.visibleComposer, same(successor));
      expect(successor.raw, 'Second draft');
    },
  );

  test(
    'a failed presentation boundary restores the editor before propagating',
    () async {
      final composer = await openReply(7);
      composer.text.text = 'Still here';
      final failure = StateError('frame failed');
      await expectLater(
        shell.saveComposerAndClose(
          composer,
          afterHide: () => Future.error(failure),
        ),
        throwsA(same(failure)),
      );
      expect(composer.isDisposed, isFalse);
      expect(composer.closing, isFalse);
      expect(shell.visibleComposer, same(composer));
    },
  );

  test('close preparation refuses unsafe storage and supports retry', () async {
    disposeShell();
    await createShell(
      draftFailure: const WriteException(WriteFailure.unreachable),
    );
    final composer = await openReply(7);
    composer.text.text = 'Keep the editor until the draft is safe';
    drafts.failWrites = true;

    expect(await shell.prepareComposerForClose(composer), isFalse);
    expect(composer.isDisposed, isFalse);

    drafts.failWrites = false;
    expect(await shell.prepareComposerForClose(composer), isTrue);
    expect(
      ComposerDraft.decode(await drafts.read(_firstSite, 'topic_7'))?.reply,
      'Keep the editor until the draft is safe',
    );
  });

  test('close preparation refuses an in-flight submission', () async {
    disposeShell();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await createShell(postGate: gate);
    final composer = await openReply(7);
    composer.text.text = 'Await the posting result';
    final submission = shell.submitComposer(composer: composer);

    expect(await shell.prepareComposerForClose(composer), isFalse);
    gate.complete();
    await submission;
    expect(composer.isDisposed, isTrue);
  });

  test('a reply landing after its editor closed settles its draft', () async {
    disposeShell();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await createShell(
      postGate: gate,
      draftFailure: const WriteException(WriteFailure.unreachable),
    );
    final composer = await openReply(7);
    composer.text.text = 'Posted after closing';
    await composer.flushDraft();
    expect(await drafts.read(_firstSite, 'topic_7'), isNotNull);
    final submission = shell.submitComposer(composer: composer);
    await pumpEventQueue();
    shell.closeComposer(composer: composer);
    expect(composer.isDisposed, isTrue);

    gate.complete();
    await submission;
    await pumpEventQueue();

    expect(api.created, hasLength(1));
    expect(await drafts.read(_firstSite, 'topic_7'), isNull);
  });

  test('active uploads prevent unsafe close and remain available', () async {
    final composer = await openReply(7);
    final editor = composer.text;
    api.pendingUpload = Completer<ComposerUploadResult>();
    composer.addImages([
      ComposerUploadFile(
        name: 'photo.png',
        length: () async => 3,
        openRead: () => Stream.value([1, 2, 3]),
      ),
    ], 0);
    await api.uploadStarted.future;
    final upload = composer.uploads.single;

    var frameRequested = false;
    expect(
      await shell.saveComposerAndClose(
        composer,
        afterHide: () async {
          frameRequested = true;
        },
      ),
      isA<ComposerCloseBlocked>(),
    );
    expect(frameRequested, isFalse);
    expect(composer.closing, isFalse);
    expect(await shell.prepareComposerForClose(composer), isFalse);
    expect(composer.uploads.single, same(upload));
    expect(composer.text, same(editor));

    api.pendingUpload!.complete(
      const ComposerUploadResult(
        id: 1,
        originalFilename: 'photo.png',
        shortUrl: 'upload://photo.png',
        url: 'https://one.example/photo.png',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(composer.hasActiveUploads, isFalse);
    expect(composer.raw, contains('upload://photo.png'));
    expect(await shell.prepareComposerForClose(composer), isTrue);
  });

  test('an upload arriving during close preparation vetoes disposal', () async {
    disposeShell();
    final saveGate = Completer<void>();
    await createShell(draftGate: saveGate);
    final composer = await openReply(7);
    composer.text.text = 'Save while a file picker is open';
    api.pendingUpload = Completer<ComposerUploadResult>();
    final preparation = shell.prepareComposerForClose(composer);
    await Future<void>.delayed(Duration.zero);
    expect(api.draftsSaved, isNotEmpty);

    composer.addImages([
      ComposerUploadFile(
        name: 'photo.png',
        length: () async => 3,
        openRead: () => Stream.value([1, 2, 3]),
      ),
    ], composer.raw.length);
    await api.uploadStarted.future;
    saveGate.complete();

    expect(await preparation, isFalse);
    expect(composer.hasActiveUploads, isTrue);
    expect(composer.isDisposed, isFalse);
    api.pendingUpload!.complete(
      const ComposerUploadResult(
        id: 1,
        originalFilename: 'photo.png',
        shortUrl: 'upload://photo.png',
        url: 'https://one.example/photo.png',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(composer.raw, contains('upload://photo.png'));
  });
}

final class _DraftStore extends FakeDraftStore {
  bool failWrites = false;

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (failWrites) throw StateError('Draft storage unavailable');
    return super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}

final class _SessionApi extends FakeDiscourseApi {
  _SessionApi({super.draftFailure, super.draftGate, Completer<void>? postGate})
    : super(
        user: _user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
        createPostGate: postGate,
        topics: {},
        postsById: {},
      );

  Completer<ComposerUploadResult>? pendingUpload;
  final uploadStarted = Completer<void>();

  @override
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    bool forPrivateMessage = false,
    ComposerUploadSizeLimit? sizeLimit,
    String? clientId,
  }) {
    uploadStarted.complete();
    return pendingUpload!.future;
  }
}
