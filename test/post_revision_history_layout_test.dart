import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_revision.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _post = Post(
  id: 42,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Post body</p>',
  version: 4,
  canViewEditHistory: true,
);

Finder get _footer => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_PostRevisionHistoryFooter',
);

Finder _button(String label) => find.descendant(
  of: _footer,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DButton &&
        (widget.tooltip == label ||
            (widget.label is Text && (widget.label as Text).data == label)),
  ),
);

void main() {
  for (final width in [390.0, 500.0, 600.0, 1000.0]) {
    testWidgets(
      'post edit history navigation fits ${width}px at 200% text',
      (tester) async {
        final api = _RevisionApi();
        final shell = ShellController(
          instanceStore: FakeInstanceStore([instance('meta.example')]),
          api: api,
          authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
        );
        await shell.load();
        addTearDown(shell.dispose);
        shell.pushContent(
          ContentRoute.topic(topicId: 7, slug: 'edited', title: 'Edited'),
        );
        shell.store.put(
          _site,
          const TopicDetail(id: 7, title: 'Edited', stream: [42]),
        );
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
              home: const Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    height: 100,
                    child: PostActions(
                      siteUrl: _site,
                      post: _post,
                      child: Center(child: Text('Post body')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('Post body')));
        await tester.pump();
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DDropdownMenuItem, 'View edit history'),
        );
        await tester.pumpAndSettle();
        expect(api.postRevisionsRequested, [(postId: 42, revision: null)]);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final bounds = tester.getRect(_footer);
        for (final action in ['First', 'Previous', 'Next', 'Latest']) {
          final button = _button(action);
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(bounds.left));
          expect(rect.right, lessThanOrEqualTo(bounds.right));
          expect(button.hitTestable(), findsOneWidget);
          if (width == 1000) {
            expect(tester.widget<DButton>(button).label, isA<Text>());
            if (defaultTargetPlatform == TargetPlatform.macOS) {
              expect(
                rect.center.dy,
                closeTo(tester.getCenter(_button('First')).dy, 1),
              );
            }
          }
        }
        for (final (direction, number) in [('Previous', 3), ('Next', 4)]) {
          final pending = api.gateNext();
          await tester.tap(_button(direction));
          await tester.pump();
          expect(api.postRevisionsRequested.last.revision, number);
          expect(find.byType(DProgress), findsOneWidget);
          for (final action in ['First', 'Previous', 'Next', 'Latest']) {
            expect(tester.widget<DButton>(_button(action)).onPressed, isNull);
          }
          pending.complete(_revision(number));
          await tester.pumpAndSettle();
          expect(
            find.text('Comparing version ${number - 1} to $number of 4'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

class _RevisionApi extends FakeDiscourseApi {
  Completer<PostRevision>? pending;

  Completer<PostRevision> gateNext() => pending = Completer<PostRevision>();

  @override
  Future<PostRevision> postRevision({
    required String siteUrl,
    required int postId,
    int? revision,
    String? apiKey,
    String? clientId,
  }) async {
    postRevisionsRequested.add((postId: postId, revision: revision));
    final gate = pending;
    pending = null;
    return gate != null ? gate.future : _revision(revision ?? 4);
  }
}

PostRevision _revision(int number) => PostRevision(
  postId: 42,
  currentRevision: number,
  currentVersion: number,
  versionCount: 4,
  firstRevision: 2,
  previousRevision: number > 2 ? number - 1 : null,
  nextRevision: number < 4 ? number + 1 : null,
  lastRevision: 4,
  username: 'editor',
  bodyChanges: PostRevisionDiff(inline: '<p>Revision $number</p>'),
);
