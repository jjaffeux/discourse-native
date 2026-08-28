import 'package:discourse_native/src/plugin_api/reaction_presentation.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
