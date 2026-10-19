import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic_tag.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://one.example';
const _saved = ComposerDraft(
  reply: 'We can meet on Friday.\n\nBring the original notes.',
  title: 'A saved meeting',
  action: ComposerDraft.createTopicAction,
  categoryId: 1,
  tags: [TopicTag(name: 'original')],
);
const _edited = 'We can meet on Saturday.\n\nBring the revised notes.';
const _capture = ValueKey('rollback-capture');

void main() {
  setUpAll(() async {
    if (Platform.environment['DRAFT_ROLLBACK_RENDER_DIR'] == null) return;
    await (FontLoader(
      'Lato',
    )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load();
  });

  test(
    'autosave leaves the opened savepoint stable and rollback restores metadata',
    () async {
      final h = await _Harness.create();
      addTearDown(h.shell.dispose);
      final composer = h.composer;
      final saved = composer.savedDraft!;
      composer.text.text = _edited;
      composer.title.text = 'An edited meeting';
      composer.setCategory(2);
      composer.setTags(const [TopicTag(name: 'changed')]);
      await composer.flushDraft();
      expect(composer.savedDraft, same(saved));
      expect(h.api.writes.last.reply, _edited);
      final gate = h.api.writeGate = Completer<void>();
      final pending = h.shell.rollbackSavedComposerDraft(
        composer,
        confirmedRevision: composer.draftRevision,
      );
      await _until(() => h.api.writes.length == 2);
      expect(composer.text.text, _edited);
      expect(composer.title.text, 'An edited meeting');
      expect(composer.discarding, isTrue);
      gate.complete();
      final result = await pending;
      expect(result.error, isNull);
      expect(result.revision, composer.draftRevision);
      expect(composer.text.text, saved.reply);
      expect(composer.title.text, saved.title);
      expect(composer.categoryId, saved.categoryId);
      expect(composer.tags, saved.tags);
      expect(h.api.writes.last.reply, saved.reply);
      expect(composer.history.undo(), isTrue);
      expect(composer.text.text, _edited);
    },
  );

  test(
    'failed rollback retains live changes and their local copy, then retries',
    () async {
      final h = await _Harness.create();
      addTearDown(h.shell.dispose);
      h.composer.text.text = _edited;
      h.composer.title.text = 'An edited meeting';
      h.api.fail = true;
      final revision = h.composer.draftRevision;
      var result = await h.shell.rollbackSavedComposerDraft(
        h.composer,
        confirmedRevision: revision,
      );
      expect(result.error, isNotNull);
      expect(h.composer.text.text, _edited);
      expect(h.composer.title.text, 'An edited meeting');
      expect(
        ComposerDraft.decode(await h.drafts.read(_site, 'new_topic'))!.reply,
        _edited,
      );
      expect(h.composer.isEditing, isTrue);
      h.api.fail = false;
      result = await h.shell.rollbackSavedComposerDraft(
        h.composer,
        confirmedRevision: revision,
      );
      expect(result.error, isNull);
      expect(h.composer.text.text, _saved.reply);
    },
  );

  test(
    'failed local and remote rollback keeps the editor open for retry',
    () async {
      final store = _FailingStore();
      final h = await _Harness.create(store: store);
      addTearDown(h.shell.dispose);
      h.composer.text.text = _edited;
      store.fail = h.api.fail = true;
      final revision = h.composer.draftRevision;
      final failed = await h.shell.rollbackSavedComposerDraft(
        h.composer,
        confirmedRevision: revision,
      );
      expect(failed.error, isNotNull);
      expect(h.composer.isDisposed, isFalse);
      expect(h.composer.text.text, _edited);
      expect(h.composer.localDraftFailed, isTrue);
      store.fail = h.api.fail = false;
      expect(
        (await h.shell.rollbackSavedComposerDraft(
          h.composer,
          confirmedRevision: revision,
        )).error,
        isNull,
      );
      expect(h.composer.text.text, _saved.reply);
    },
  );

  test('a changed revision outranks a rollback already writing', () async {
    final h = await _Harness.create();
    addTearDown(h.shell.dispose);
    h.composer.text.text = _edited;
    final gate = h.api.writeGate = Completer<void>();
    final pending = h.shell.rollbackSavedComposerDraft(
      h.composer,
      confirmedRevision: h.composer.draftRevision,
    );
    await _until(() => h.api.writes.isNotEmpty);
    h.composer.text.text = 'A newer external edit';
    gate.complete();
    final result = await pending;
    expect(result.error, isNotNull);
    expect(h.composer.text.text, 'A newer external edit');
    expect(h.api.writes.last.reply, 'A newer external edit');
    expect(h.composer.isDisposed, isFalse);
  });

  test(
    'disconnect during rollback cannot restore an expired account editor',
    () async {
      final h = await _Harness.create();
      addTearDown(h.shell.dispose);
      h.composer.text.text = _edited;
      final gate = h.api.writeGate = Completer<void>();
      final pending = h.shell.rollbackSavedComposerDraft(
        h.composer,
        confirmedRevision: h.composer.draftRevision,
      );
      await _until(() => h.api.writes.isNotEmpty);
      final disconnected = h.shell.disconnectInstance(_site);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await disconnected;
      final result = await pending;
      expect(result.revision, isNull);
      expect(h.composer.isDisposed, isTrue);
      expect(h.shell.visibleComposer, isNull);
    },
  );

  test('pending work and stale confirmation cannot start rollback', () async {
    final h = await _Harness.create();
    addTearDown(h.shell.dispose);
    final old = h.composer.draftRevision;
    h.composer.text.text = _edited;
    expect(
      (await h.shell.rollbackSavedComposerDraft(
        h.composer,
        confirmedRevision: old,
      )).error,
      isNotNull,
    );
    h.composer.beginLoadingBody();
    expect(
      (await h.shell.rollbackSavedComposerDraft(
        h.composer,
        confirmedRevision: h.composer.draftRevision,
      )).error,
      isNotNull,
    );
    expect(h.api.writes, isEmpty);
    expect(h.composer.text.text, _edited);
  });

  test(
    'rollback waits for an older autosave before writing the savepoint',
    () async {
      final h = await _Harness.create();
      addTearDown(h.shell.dispose);
      h.composer.text.text = _edited;
      final gate = h.api.writeGate = Completer<void>();
      final autosave = h.composer.flushDraft();
      await _until(() => h.api.writes.isNotEmpty);
      final rollback = h.shell.rollbackSavedComposerDraft(
        h.composer,
        confirmedRevision: h.composer.draftRevision,
      );
      await Future<void>.delayed(Duration.zero);
      expect(h.api.writes, hasLength(1));
      gate.complete();
      await autosave;
      expect((await rollback).error, isNull);
      expect(h.api.writes.map((d) => d.reply), [_edited, _saved.reply]);
      expect(h.composer.text.text, _saved.reply);
    },
  );

  test(
    'active upload vetoes rollback and its completion still inserts normally',
    () async {
      final h = await _Harness.create();
      addTearDown(h.shell.dispose);
      h.api.pendingUpload = Completer<ComposerUploadResult>();
      h.composer.addImages([
        ComposerUploadFile(
          name: 'photo.png',
          length: () async => 3,
          openRead: () => Stream.value([1, 2, 3]),
        ),
      ], 0);
      await h.api.uploadStarted.future;
      final upload = h.composer.uploads.single;
      expect(
        (await h.shell.rollbackSavedComposerDraft(
          h.composer,
          confirmedRevision: h.composer.draftRevision,
        )).error,
        isNotNull,
      );
      expect(h.api.writes, isEmpty);
      expect(h.composer.uploads.single, same(upload));
      h.api.pendingUpload!.complete(
        const ComposerUploadResult(
          id: 1,
          originalFilename: 'photo.png',
          shortUrl: 'upload://photo.png',
          url: 'https://one.example/photo.png',
        ),
      );
      await _until(() => !h.composer.hasActiveUploads);
      expect(h.composer.raw, contains('upload://photo.png'));
    },
  );

  test(
    'rollback preserves reply visibility, reply target and message recipients',
    () {
      for (final mode in [ComposerMode.reply, ComposerMode.privateMessage]) {
        final c = ComposerController(
          mode == ComposerMode.privateMessage
              ? const PrivateMessageComposerTarget(
                  siteUrl: _site,
                  topicTitle: 'Message',
                  targetRecipients: '',
                )
              : const ReplyComposerTarget(
                  siteUrl: _site,
                  topicId: 7,
                  slug: 'topic',
                  topicTitle: 'Topic',
                  privateMessageTopic: false,
                  replyToPostNumber: 2,
                  replyToUsername: 'original',
                ),
        );
        addTearDown(c.dispose);
        c.restore(
          ComposerDraft(
            reply: 'Saved text',
            title: 'Saved title',
            archetypeId: mode == ComposerMode.privateMessage
                ? ComposerDraft.privateMessageArchetype
                : ComposerDraft.regularArchetype,
            recipients: mode == ComposerMode.privateMessage ? 'original' : null,
            whisper: mode == ComposerMode.reply,
          ),
        );
        final saved = c.draft;
        c.text.text = 'Edited text';
        if (mode == ComposerMode.privateMessage) {
          c.setRecipients(['changed']);
        } else {
          c.setWhisper(false);
          c.retarget(replyToPostNumber: 3, replyToUsername: 'changed');
        }
        expect(c.hasSavedDraftChanges, isTrue);
        final revision = c.beginDiscard()!;
        expect(c.applySavedDraftRollback(revision), isNotNull);
        expect(c.draft.recipients, saved.recipients);
        expect(c.draft.replyToPostNumber, saved.replyToPostNumber);
        expect(c.draft.replyToUsername, saved.replyToUsername);
        expect(c.draft.whisper, saved.whisper);
        expect(c.hasSavedDraftChanges, isFalse);
      }
    },
  );

  testWidgets(
    'unchanged saved draft offers Keep and Delete, deletion previews everything',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(h.shell.dispose);
      await h.pump(tester);
      await tester.tap(find.byKey(const ValueKey('composer-close')));
      await tester.pumpAndSettle();
      expect(find.text('Keep draft'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-revert-saved-draft')),
        findsNothing,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('composer-confirm-discard')),
        ),
      );
      await tester.pump();
      expect(h.composer.discardPreviewTarget!.reply, isEmpty);
      expect(h.composer.discardPreviewTarget!.title, isEmpty);
      expect(h.composer.text.text, _saved.reply);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await mouse.removePointer();
    },
  );

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('phone preview remains readable dark=$dark scale=$scale', (
        tester,
      ) async {
        final h = await _Harness.create();
        addTearDown(h.shell.dispose);
        h.composer.text.text = _edited;
        h.composer.title.text = 'An edited meeting';
        await h.pump(tester, mobile: true, dark: dark, scale: scale);
        await tester.tap(find.byKey(const ValueKey('composer-close')));
        await tester.pumpAndSettle();
        expect(find.text('Save changes'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('composer-cancel')));
        await tester.pumpAndSettle();
        final revert = find.byKey(
          const ValueKey('composer-revert-saved-draft'),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(revert));
        await tester.pumpAndSettle();
        expect(h.composer.discardPreviewTarget!.reply, _saved.reply);
        await _render(tester, 'phone-${dark ? 'dark' : 'light'}-$scale');
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(h.composer.text.text, _edited);
        await tester.runAsync(h.composer.finishDraftSaves);
        await tester.pump();
        await mouse.removePointer();
      });
    }
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'saved choices preview without mutation and close after successful rollback (reduced=$reduced)',
      (tester) async {
        final h = await _Harness.create();
        addTearDown(h.shell.dispose);
        h.composer.text.text = _edited;
        h.composer.title.text = 'An edited meeting';
        await h.pump(tester, reduced: reduced);
        final field = tester.element(find.byType(ComposerEditor));
        await tester.tap(find.byKey(const ValueKey('composer-close')));
        await tester.pumpAndSettle();
        expect(find.text('Save changes'), findsOneWidget);
        expect(find.text('Delete draft'), findsOneWidget);
        final revert = find.byKey(
          const ValueKey('composer-revert-saved-draft'),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(revert));
        await tester.pumpAndSettle();
        expect(h.composer.discardPreviewTarget!.reply, _saved.reply);
        expect(h.composer.text.text, _edited);
        expect(tester.element(find.byType(ComposerEditor)), same(field));
        await _render(tester, 'preview-${reduced ? 'reduced' : 'normal'}');
        final gate = h.api.writeGate = Completer<void>();
        await tester.tap(revert);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(h.composer.text.text, _edited);
        expect(h.composer.rollbackAnimation, isNull);
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (!reduced) {
          expect(h.composer.isDisposed, isFalse);
          expect(h.composer.text.text, _saved.reply);
          await _render(tester, 'restoring');
        }
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        expect(h.composer.isDisposed, isTrue);
        expect(h.api.writes.last.reply, _saved.reply);
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
      },
    );
  }

  testWidgets(
    'Escape cancels the preview and a later external edit invalidates confirmation',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(h.shell.dispose);
      h.composer.text.text = _edited;
      await h.pump(tester);
      await tester.tap(find.byKey(const ValueKey('composer-close')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(h.composer.discardPreviewTarget, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.composer.discardPreviewTarget, isNull);
      expect(h.composer.text.text, _edited);
      await tester.tap(find.byKey(const ValueKey('composer-close')));
      await tester.pumpAndSettle();
      h.composer.text.text = 'Newer while confirming';
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('composer-revert-saved-draft')),
      );
      await tester.pump();
      expect(h.composer.text.text, 'Newer while confirming');
      expect(find.textContaining('This draft changed'), findsOneWidget);
      expect(h.composer.isDisposed, isFalse);
    },
  );
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue);
}

Future<void> _render(WidgetTester tester, String name) async {
  final output = Platform.environment['DRAFT_ROLLBACK_RENDER_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _Harness {
  _Harness(this.shell, this.api, this.drafts, this.composer);
  final ShellController shell;
  final _Api api;
  final FakeDraftStore drafts;
  final ComposerController composer;
  static Future<_Harness> create({FakeDraftStore? store}) async {
    final api = _Api();
    final drafts = store ?? FakeDraftStore();
    await drafts.write(_site, 'new_topic', _saved.encode());
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('one.example').copyWith(
          user: const DiscourseUser(
            id: 1,
            username: 'reader',
            canCreateTopic: true,
          ),
        ),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      drafts: drafts,
      trackers: FakeSiteTracker.reset(),
    );
    await shell.load();
    await shell.loadFeed('latest');
    await shell.resumeDraft(
      _site,
      const UserDraft(key: 'new_topic', sequence: 0, data: _saved),
    );
    final composer = shell.visibleComposer!;
    await shell.finishComposerDraftRestore(composer);
    expect(composer.savedDraft, isNotNull);
    return _Harness(shell, api, drafts, composer);
  }

  Future<void> pump(
    WidgetTester tester, {
    bool reduced = false,
    bool mobile = false,
    bool dark = false,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(
      mobile ? const Size(390, 844) : const Size(1000, 760),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final base = dark ? AppTheme.dark : AppTheme.light;
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: ShellScope(
          controller: shell,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base.copyWith(
              platform: mobile ? TargetPlatform.iOS : TargetPlatform.linux,
              textTheme: base.textTheme.apply(fontFamily: 'Lato'),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduced,
                textScaler: TextScaler.linear(scale),
              ),
              child: DToaster(child: child!),
            ),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: shell,
                builder: (context, _) => composer.isDisposed
                    ? const SizedBox()
                    : ComposerPanel(
                        composer: composer,
                        height: mobile ? 844 : 700,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        user: const DiscourseUser(
          id: 1,
          username: 'reader',
          canCreateTopic: true,
        ),
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
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

  Completer<void>? writeGate;
  bool fail = false;
  final List<ComposerDraft> writes = [];
  @override
  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  }) async {
    writes.add(ComposerDraft.decode(data)!);
    final held = writeGate;
    writeGate = null;
    if (held != null) await held.future;
    if (fail) throw const WriteException(WriteFailure.unreachable);
    return sequence + 1;
  }
}

class _FailingStore extends FakeDraftStore {
  bool fail = false;
  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (fail) throw StateError('Draft storage unavailable');
    return super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}
