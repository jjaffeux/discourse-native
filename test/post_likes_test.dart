import 'dart:async';

import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('a failed likers panel loads again when it is reopened', (
    tester,
  ) async {
    final api = _LikersApi();
    final controller = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: PostLikes(
                siteUrl: _siteUrl,
                post: Post(
                  id: 1,
                  postNumber: 1,
                  username: 'author',
                  cooked: '<p>Post body</p>',
                  likeCount: 2,
                  canLike: false,
                  canUnlike: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const failure = "Couldn't load who liked this.";

    await tester.tap(find.text('2'));
    await tester.pump();
    api.responses.single.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text(failure), findsOneWidget);

    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.text(failure), findsNothing);

    await tester.tap(find.text('2'));
    await tester.pump();
    expect(api.responses, hasLength(2));
    expect(find.text(failure), findsNothing);
    api.responses.last.complete(
      const PostLikers(
        postId: 1,
        likers: [PostLiker(id: 2, username: 'sam', name: 'Sam Saffron')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sam Saffron'), findsOneWidget);
    expect(find.text('and 1 other'), findsOneWidget);
    expect(find.text(failure), findsNothing);
  });
}

final class _LikersApi extends FakeDiscourseApi {
  final responses = <Completer<PostLikers>>[];

  @override
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<PostLikers>();
    responses.add(response);
    return response.future;
  }
}
