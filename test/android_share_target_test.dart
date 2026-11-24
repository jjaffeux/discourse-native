import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _channel = MethodChannel('org.discourse.native/android_shares');
const _photoUri = 'content://sender/photo';
const _pickerTitle = 'Choose forum for new topic';
const _android = TargetPlatformVariant({TargetPlatform.android});

void main() {
  testWidgets('a launch share opens a draft only after choosing its forum', (
    tester,
  ) async {
    const shared = 'A link from another app\nhttps://example.test/clip';
    final api = FakeDiscourseApi();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'listen');
      unawaited(_receive(messenger, text: shared));
      return null;
    });

    final shell = await _pumpApp(tester, api);
    expect(find.text(_pickerTitle), findsOneWidget);
    expect(find.text('Browse only'), findsNothing);
    expect(shell.visibleComposer, isNull);

    await tester.tap(find.text('Second forum'));
    await tester.pumpAndSettle();

    expect(shell.currentInstance?.url, 'https://second.example');
    expect(shell.visibleComposer?.raw, shared);
    expect(shell.visibleComposer?.title.text, isEmpty);
    expect(api.topicsCreated, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _android);

  testWidgets('sharing media into a warm app preserves open writing', (
    tester,
  ) async {
    final media = Directory.systemTemp.createTempSync('android-share-test-');
    addTearDown(() {
      if (media.existsSync()) media.deleteSync(recursive: true);
    });
    final image = File('${media.path}/0')..writeAsBytesSync([71, 73, 70]);
    final api = FakeDiscourseApi(
      composerUploadResult: const ComposerUploadResult(
        id: 8,
        originalFilename: 'photo.gif',
        shortUrl: 'upload://shared.gif',
        url: 'https://first.example/uploads/shared.gif',
      ),
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    var imports = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'listen') return null;
      expect(call.method, 'importMedia');
      expect(call.arguments, {
        'uris': [_photoUri],
        'mimeType': 'image/gif',
      });
      imports++;
      return {
        'directory': media.path,
        'files': [
          {'path': image.path, 'name': 'photo.gif'},
        ],
      };
    });
    final shell = await _pumpApp(tester, api);
    await shell.openNewTopicFromSidebar();
    await tester.pumpAndSettle();
    final existing = shell.visibleComposer!;
    existing.insertText('My unfinished draft');
    await tester.pumpAndSettle();

    await _receive(messenger, text: 'Photo caption', uris: [_photoUri]);
    await tester.pumpAndSettle();
    expect(find.text(_pickerTitle), findsOneWidget);
    expect(api.composerUploads, isEmpty);
    expect(imports, 0);

    await tester.tap(find.text('First forum'));
    await tester.pumpAndSettle();

    expect(imports, 1);
    final shared = shell.visibleComposer!;
    expect(shared.target.draftKey, isNot(existing.target.draftKey));
    expect(existing.raw, 'My unfinished draft');
    expect(
      shared.raw,
      allOf(contains('Photo caption'), contains('upload://shared.gif')),
    );
    expect(api.composerUploads.single.siteUrl, 'https://first.example');
    expect(api.topicsCreated, isEmpty);

    await tester.runAsync(() async {
      shell.closeComposer(composer: shared);
      await shared.disposed;
      for (var attempt = 0; attempt < 20 && await media.exists(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    expect(media.existsSync(), isFalse);
    await tester.pumpAndSettle();
    expect(shell.visibleComposer, same(existing));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _android);
}

Future<ShellController> _pumpApp(
  WidgetTester tester,
  FakeDiscourseApi api,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  const author = DiscourseUser(id: 1, username: 'author', canCreateTopic: true);
  final sites = [
    instance('first.example', title: 'First forum', user: author),
    instance('second.example', title: 'Second forum', user: author),
    instance('readonly.example', title: 'Browse only'),
  ];
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore(sites),
      authenticator: FakeAuthenticator.signedIn(sites, site: api),
      api: api,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      notificationOpenUrls: const Stream.empty(),
      linkOpenRequests: const Stream.empty(),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;
}

Future<void> _receive(
  TestDefaultBinaryMessenger messenger, {
  required String text,
  List<String> uris = const [],
}) => messenger.handlePlatformMessage(
  _channel.name,
  _channel.codec.encodeMethodCall(
    MethodCall('receive', {
      'text': text,
      'uris': uris,
      'mimeType': uris.isEmpty ? 'text/plain' : 'image/gif',
    }),
  ),
  (_) {},
);
