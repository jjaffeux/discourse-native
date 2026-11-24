import 'dart:convert';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _body = 'Pick preview then publish.';
final _post = find.text(_body, findRichText: true).hitTestable();
final _dock = find.byKey(const ValueKey('mobile-bottom-bar'));
final _tray = find.byKey(const ValueKey('mobile-post-selection-tray'));

Finder _action(String name) => find.byKey(ValueKey('$name-selection'));

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets(
    'keeps the tray mounted while dragging a handle and copies the adjusted range',
    (tester) async {
      final clipboard = watchClipboard(tester);
      final shell = await _openTopic(tester);
      expect(_dock.hitTestable(), findsOneWidget);

      await _selectPreview(tester);
      expect(_tray.hitTestable(), findsOneWidget);
      expect(_dock, findsNothing);
      expect(
        tester.getCenter(_action('edit')).dy,
        tester.getCenter(_action('copy')).dy,
      );
      final trayElement = tester.element(_tray);
      final handles = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SelectionHandleOverlay',
        description: 'text selection handles',
      );
      expect(handles, findsNWidgets(2));
      final endHandle = find
          .descendant(
            of: handles.last,
            matching: find.byType(RawGestureDetector),
          )
          .first;
      expect(endHandle.hitTestable(), findsOneWidget);
      final end = _textPoint(tester, 12, leading: true);
      final collapse = _textPoint(tester, 5, leading: true) - end;
      final extension = _textPoint(tester, 17, leading: true) - end;
      final region = tester
          .state<SelectionAreaState>(
            find
                .ancestor(of: _post, matching: find.byType(SelectionArea))
                .first,
          )
          .selectableRegion;
      final gesture = await tester.startGesture(tester.getCenter(endHandle));
      const startDrag = Offset(44, 0);
      await gesture.moveBy(startDrag);
      await tester.pump();
      expect(region.selectionOverlay?.isDraggingEndHandle, isTrue);
      await gesture.moveBy(collapse - startDrag);
      await tester.pump();
      expect(
        region.selectionEndpoints.first.point,
        region.selectionEndpoints.last.point,
      );
      expect(tester.element(_tray), same(trayElement));

      await gesture.moveBy(extension - collapse);
      await tester.pump();
      expect(tester.element(_tray), same(trayElement));
      expect(_dock, findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);
      expect(tester.element(_tray), same(trayElement));

      await tester.tap(_action('copy'));
      await tester.pumpAndSettle();
      expect(clipboard, ['preview then']);
      expect(_tray, findsNothing);
      expect(_dock, findsOneWidget);
      expect(
        find.descendant(of: _dock, matching: find.text('Copied')),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'uses two rows with large text and restores navigation when selection clears',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final shell = await _openTopic(tester, size: const Size(320, 740));
      await _selectPreview(tester);

      for (final name in ['copy', 'quote', 'copy-quote', 'edit']) {
        expect(_action(name).hitTestable(), findsOneWidget);
      }
      expect(
        tester.getCenter(_action('copy')).dy,
        closeTo(tester.getCenter(_action('quote')).dy, .5),
      );
      expect(
        tester.getCenter(_action('edit')).dy,
        greaterThan(tester.getCenter(_action('copy')).dy),
      );

      await tester.tapAt(_textPoint(tester, 1));
      await tester.pumpAndSettle();
      expect(_tray, findsNothing);
      expect(_dock.hitTestable(), findsOneWidget);

      await _selectPreview(tester);
      expect(_tray, findsOneWidget);
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(_tray, findsNothing);
      expect(_dock.hitTestable(), findsOneWidget);
      expect(shell.handleForward(), isTrue);
      await tester.pumpAndSettle();
      expect(_tray, findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}

Future<ShellController> _openTopic(
  WidgetTester tester, {
  Size size = phone,
}) async {
  const user = DiscourseUser(id: 9, username: 'reader');
  const title = 'Selection example';
  await pumpShell(
    tester,
    size,
    instances: [instance('meta.discourse.org').copyWith(user: user)],
    api: FakeDiscourseApi(
      user: user,
      feeds: const {
        '/latest.json': [Topic(id: 7, title: title, slug: 'selection')],
      },
      topics: {
        7: topicPayload(
          id: 7,
          title: title,
          canCreatePost: true,
          posts: const [
            Post(
              id: 71,
              postNumber: 1,
              username: 'reader',
              canEdit: true,
              raw: _body,
              cooked: '<p>$_body</p>',
            ),
          ],
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
  );
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewPadding = tester.view.padding;
  final shell = ShellScope.read(
    tester.element(find.byKey(const ValueKey('topic-card-7'))),
  );
  await shell.forumSettings.setShared(
    shell.forumSettings.shared.copyWith(
      font: ForumFont.lato,
      interfaceFont: ForumFont.lato,
    ),
  );
  shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _selectPreview(WidgetTester tester) async {
  await tester.longPressAt(_textPoint(tester, 8));
  await tester.pumpAndSettle();
}

Offset _textPoint(WidgetTester tester, int index, {bool leading = false}) {
  final paragraph = tester.renderObject<RenderParagraph>(_post);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
      )
      .single;
  return paragraph.localToGlobal(
    leading ? box.toRect().centerLeft : box.toRect().center,
  );
}
