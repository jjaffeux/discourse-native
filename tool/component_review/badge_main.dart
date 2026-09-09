import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/badge_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'badge_fixtures.dart';

/// Isolated review entrypoint; fixture routes never use real accounts or stores.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await createBadgeFixtureController();
  componentExamples['badge'] = ComponentExamples(
    status: badgeExamples.status,
    description: badgeExamples.description,
    notes: badgeExamples.notes,
    examples: [
      ...badgeExamples.examples,
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
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const ComponentStyleguidePage(),
      ),
    ),
  );
}
