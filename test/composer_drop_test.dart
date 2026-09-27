import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_drop.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/native_drop.dart';
import 'support/shell_test_harness.dart';

const _meta = 'https://meta.discourse.org';
const _team = 'https://team.discourse.org';

void main() {
  testWidgets('a drop target answers only where the pointer is over it', (
    tester,
  ) async {
    final visible = <String>[];
    final hidden = <String>[];
    Widget target(List<String> events) => NativeDropTarget(
      onDragEntered: (_) => events.add('entered'),
      onDragUpdated: (_) => events.add('updated'),
      onDragExited: (_) => events.add('exited'),
      onDragDone: (details) => events.add('done ${details.files.single.name}'),
      // Nothing inside would pass a hit test on its own.
      child: const SizedBox.expand(),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 400,
              height: 400,
              child: target(visible),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: 400,
              height: 400,
              child: Offstage(child: target(hidden)),
            ),
            // A surface drawn over the target's right half.
            const Positioned(
              left: 200,
              top: 0,
              width: 200,
              height: 400,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                child: SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );

    final drag = NativeFileDrag(tester);
    await drag.moveTo(const Offset(100, 200));
    await drag.moveTo(const Offset(120, 200));
    await drag.moveTo(const Offset(300, 200));
    await drag.drop([nativeDropFile('covered.png')]);
    expect(visible, ['entered', 'updated', 'exited']);

    visible.clear();
    await drag.moveTo(const Offset(300, 200));
    await drag.moveTo(const Offset(100, 200));
    await drag.drop([nativeDropFile('shot.png')]);
    expect(visible, ['entered', 'exited', 'done shot.png']);
    expect(hidden, isEmpty);
  });

  testWidgets(
    'a composer kept for another forum takes no drop aimed at this one',
    (tester) async {
      final api = FakeDiscourseApi(composerUploadResult: _uploaded);
      final shell = await _pumpApp(tester, api: api);
      final hidden = await _openReply(shell);
      await tester.pumpAndSettle();
      shell.selectInstance(1);
      await tester.pumpAndSettle();
      expect(shell.currentInstance!.url, _team);
      expect(find.byType(ComposerEditor), findsNothing);

      // Meta's editor is still laid out, Offstage, under Team's sidebar and
      // reader: exactly where the screenshot is released.
      final behind = tester.getCenter(
        find.byType(ComposerEditor, skipOffstage: false),
      );
      await dropNativeFiles(tester, behind, [nativeDropFile('shot.png')]);
      await tester.pumpAndSettle();

      expect(hidden.raw, isEmpty);
      expect(api.composerUploads, isEmpty);

      shell.selectInstance(0);
      await tester.pumpAndSettle();
      await dropNativeFiles(
        tester,
        tester.getCenter(find.byType(ComposerEditor)),
        [nativeDropFile('shot.png')],
      );
      await tester.pumpAndSettle();

      expect(hidden.raw, contains('(upload://shot.png)'));
      expect(api.composerUploads.map((upload) => upload.siteUrl), [_meta]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'a minimized composer takes no drop aimed at the reader it sits over',
    (tester) async {
      final api = FakeDiscourseApi(composerUploadResult: _uploaded);
      final shell = await _pumpApp(tester, api: api);
      final composer = await _openReply(shell);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Full screen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-minimize')));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerEditor), findsNothing);

      final behind = tester.getCenter(
        find.byType(ComposerEditor, skipOffstage: false),
      );
      await dropNativeFiles(tester, behind, [nativeDropFile('shot.png')]);
      await tester.pumpAndSettle();

      expect(composer.raw, isEmpty);
      expect(api.composerUploads, isEmpty);

      await tester.tap(find.byKey(const ValueKey('composer-restore')));
      await tester.pumpAndSettle();
      await dropNativeFiles(
        tester,
        tester.getCenter(find.byType(ComposerEditor)),
        [nativeDropFile('shot.png')],
      );
      await tester.pumpAndSettle();

      expect(composer.raw, contains('(upload://shot.png)'));
      expect(api.composerUploads.map((upload) => upload.siteUrl), [_meta]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

const _uploaded = ComposerUploadResult(
  id: 41,
  originalFilename: 'shot.png',
  shortUrl: 'upload://shot.png',
  url: '$_meta/uploads/shot.png',
  width: 640,
  height: 480,
);

Future<ShellController> _pumpApp(
  WidgetTester tester, {
  required FakeDiscourseApi api,
}) async {
  const reader = DiscourseUser(id: 1, username: 'reader');
  await pumpShell(
    tester,
    desktop,
    api: api,
    instances: [
      instance('meta.discourse.org').copyWith(user: reader),
      instance('team.discourse.org').copyWith(user: reader),
    ],
    authenticator: FakeAuthenticator()
      ..keys[_meta] = 'meta-key'
      ..keys[_team] = 'team-key',
  );
  return tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;
}

Future<ComposerController> _openReply(ShellController shell) async {
  shell.store.put(
    shell.currentInstance!.url,
    const TopicDetail(id: 7, title: 'Topic 7', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic-7', title: 'Topic 7'),
  );
  shell.openReply();
  final composer = shell.visibleComposer!;
  await shell.finishComposerDraftRestore(composer);
  return composer;
}
