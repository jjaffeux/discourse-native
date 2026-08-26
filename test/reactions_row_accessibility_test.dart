import 'dart:async';

import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _errorMessage = 'Could not find out who reacted.';
const _post = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Post body</p>',
);

void main() {
  testWidgets('reaction stays disabled until its write finishes', (
    tester,
  ) async {
    final write = Completer<String?>();
    var toggles = 0;
    final owner = Object();
    final controller = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: ReactionPill(
                siteUrl: _siteUrl,
                reaction: 'clap',
                count: 2,
                selected: false,
                onTapHint: 'add this reaction',
                interactionOwner: owner,
                onToggle: () {
                  toggles++;
                  return write.future;
                },
                loadReactors: () async {},
                reactorsBuilder: (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );

      final reaction = find.bySemanticsLabel('2 clap reactions');
      expect(
        tester.getSemantics(reaction),
        isSemantics(
          label: '2 clap reactions',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(reaction);
      await tester.pump();

      expect(toggles, 1);
      expect(
        tester.getSemantics(reaction),
        isSemantics(
          label: '2 clap reactions',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );

      await tester.tap(reaction);
      await tester.pump();
      expect(toggles, 1);

      write.complete(null);
      await tester.pump();
      expect(
        tester.getSemantics(reaction),
        isSemantics(isEnabled: true, hasTapAction: true),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reactor failure is announced and keyboard retryable', (
    tester,
  ) async {
    final responses = <String, PostReactors>{};
    final api = FakeDiscourseApi(reactorsById: responses);
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final controller = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(
              body: Center(
                child: ReactorList(
                  siteUrl: _siteUrl,
                  post: _post,
                  filter: 'clap',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await controller.reactions.load(
        siteUrl: _siteUrl,
        postId: _post.id,
        filter: 'clap',
      );
      await tester.pumpAndSettle();

      final error = find.byKey(const ValueKey('reactor-list-error'));
      expect(
        tester.getSemantics(error),
        isSemantics(label: _errorMessage, isLiveRegion: true),
      );

      final retry = find.byKey(const ValueKey('reactor-list-retry'));
      expect(tester.getSize(retry).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(retry),
        isSemantics(
          label: 'Retry',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.getSemantics(retry),
        isSemantics(isFocusable: true, isFocused: true),
      );

      responses[PostReactors.key(_post.id, 'clap')] = const PostReactors(
        postId: 1,
        filter: 'clap',
        total: 1,
        reactors: [
          PostReactor(
            id: 2,
            username: 'sam',
            name: 'Sam Example',
            reaction: 'clap',
          ),
        ],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(api.reactorsRequested, [
        (postId: 1, filter: 'clap'),
        (postId: 1, filter: 'clap'),
      ]);
      expect(error, findsNothing);
      expect(find.text('Sam Example'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
