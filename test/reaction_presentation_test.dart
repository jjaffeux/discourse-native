import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/reaction_presentation.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('reactor list consumes only the neutral page contract', (
    tester,
  ) async {
    final source = ChangeNotifier();
    addTearDown(source.dispose);
    const page = _Page(
      reactors: [
        _User(id: 3, username: 'sam', name: 'Sam Saffron', reaction: 'clap'),
      ],
      total: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ReactionUsersList(
            siteUrl: 'https://meta.example',
            source: source,
            query: const (target: 1, reaction: 'clap'),
            select: () => (reactors: page, error: null),
            load: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Sam Saffron'), findsOneWidget);
    expect(find.text('and 2 others'), findsOneWidget);
    expect(find.bySemanticsLabel('View profile for @sam'), findsOneWidget);
  });

  testWidgets('resting on a reactor previews them inside the open panel', (
    tester,
  ) async {
    const reader = DiscourseUser(username: 'reader', name: 'Reader');
    final api = FakeDiscourseApi(
      user: reader,
      totals: const NotificationTotals(),
      cards: const {
        'sam': UserCard(username: 'sam', name: 'Sam', title: 'Co-founder'),
      },
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(user: reader),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final source = ChangeNotifier();
    addTearDown(source.dispose);
    const page = _Page(
      reactors: [
        _User(id: 3, username: 'sam', name: 'Sam Saffron', reaction: 'clap'),
      ],
      total: 3,
    );

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: ReactionPill(
                siteUrl: _siteUrl,
                reaction: 'clap',
                count: 3,
                selected: false,
                interactionOwner: Object(),
                loadReactors: () async {},
                reactorsBuilder: (_) => ReactionUsersList(
                  siteUrl: _siteUrl,
                  source: source,
                  query: const (target: 1, reaction: 'clap'),
                  select: () => (reactors: page, error: null),
                  load: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(DToggle)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('and 2 others'), findsOneWidget);

    // A reactor's profile preview opens from inside the panel's content.
    await mouse.moveTo(tester.getCenter(find.text('Sam Saffron')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(api.cardsRequested, ['sam']);
    expect(find.text('Co-founder'), findsOneWidget);
    expect(find.text('and 2 others'), findsOneWidget);
  });
}

@immutable
final class _User implements ReactionUser {
  const _User({
    required this.id,
    required this.username,
    required this.reaction,
    this.name,
  });

  @override
  final int id;

  @override
  final String username;

  @override
  final String reaction;

  @override
  final String? name;

  @override
  String? get avatarUrl => null;

  @override
  String get displayName => name ?? username;
}

final class _Page implements ReactionUsersPage {
  const _Page({required this.reactors, required this.total});

  @override
  final List<_User> reactors;

  @override
  final int total;
}
