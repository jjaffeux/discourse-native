import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/badge_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'badge_fixtures.dart';

/// Isolated review entrypoint; fixture routes never use real accounts or stores.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await createBadgeFixtureController();
  final largeProfile = ValueNotifier(false);
  componentExamples['badge'] = ComponentExamples(
    status: badgeExamples.status,
    description: badgeExamples.description,
    notes: badgeExamples.notes,
    examples: [
      ...badgeExamples.examples,
      StyleguideExample(
        title: 'Ring fixtures',
        description:
            'Focus ghost, outline and destructive states. Idle invalid has a border only.',
        code:
            'DBadge.action(variant: variant, invalid: invalid, onPressed: () {}, child: Text(label))',
        builder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final invalid in [false, true])
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final variant in [
                      DBadgeVariant.ghost,
                      DBadgeVariant.outline,
                      DBadgeVariant.destructive,
                    ])
                      DBadge.action(
                        variant: variant,
                        invalid: invalid,
                        onPressed: () {},
                        child: Text(
                          '${variant.name}${invalid ? ' invalid' : ''}',
                        ),
                      ),
                  ],
                ),
              ),
            TextButton(
              onPressed: () => largeProfile.value = true,
              child: const Text('Open 200% profile review'),
            ),
          ],
        ),
      ),
      StyleguideExample(
        title: 'Migration fixtures',
        description:
            'Actual Groups, TopicUnreadBadge, UserCardTarget and Chat drawer widgets with local data. Open the staff profile to inspect its status and badge count. No real account data is used.',
        code: 'BadgeMigrationFixtures(controller: inMemoryController)',
        builder: (_) => BadgeMigrationFixtures(controller: controller),
      ),
    ],
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    ShellScope(
      controller: controller,
      child: ValueListenableBuilder<bool>(
        valueListenable: largeProfile,
        builder: (context, large, _) => BadgeReviewApp(
          controller: controller,
          largeProfile: large,
          onReturn: () => largeProfile.value = false,
        ),
      ),
    ),
  );
}

/// Keeps review scaling above the root Navigator used by the real profile popup.
class BadgeReviewApp extends StatelessWidget {
  const BadgeReviewApp({
    super.key,
    required this.controller,
    required this.largeProfile,
    required this.onReturn,
  });
  final ShellController controller;
  final bool largeProfile;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: largeProfile
        ? StyleguideTheme.plum.resolve(AppTheme.light)
        : AppTheme.light,
    darkTheme: largeProfile
        ? StyleguideTheme.plum.resolve(AppTheme.light)
        : AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(largeProfile ? 2 : 1)),
      child: child!,
    ),
    home: largeProfile
        ? Scaffold(
            appBar: AppBar(
              leading: BackButton(onPressed: onReturn),
              title: const Text('Profile at 200%'),
            ),
            body: const Center(
              child: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: UserCardTarget(
                    username: 'reviewer',
                    siteUrl: badgeFixtureSite,
                    child: Text('Open staff profile'),
                  ),
                ),
              ),
            ),
          )
        : const ComponentStyleguidePage(),
  );
}
