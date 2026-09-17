// Local fixture: the production composer and table use in-memory drafts/API.
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://example.test',
      topicId: 1,
      slug: 'table',
      topicTitle: 'Table editing',
    ),
  );
  const encodedSource = String.fromEnvironment('COMPOSER_TABLE_FIXTURE_BASE64');
  composer.text.value = TextEditingValue(
    text: encodedSource.isEmpty
        ? 'Plans for the team lunch:\n\n| Name | Bringing |\n| :--- | --- |\n| Sam | Bread |\n| Alex | Salad |\n| Jo | Dessert |\n\nSee you on Friday!'
        : utf8.decode(base64Decode(encodedSource)),
    selection: const TextSelection.collapsed(offset: 0),
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  var dark = false;
  var narrow = false;
  var rtl = false;
  runApp(
    StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (_, child) => DFocusHighlight(child: child!),
        home: ShellScope(
          controller: shell,
          child: Builder(
            builder: (context) => Scaffold(
              body: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          DButton(
                            label: Text(dark ? 'Light' : 'Dark'),
                            onPressed: () => setState(() => dark = !dark),
                          ),
                          DButton(
                            label: Text(narrow ? 'Wide' : 'Narrow'),
                            onPressed: () => setState(() => narrow = !narrow),
                          ),
                          DButton(
                            label: Text(rtl ? 'LTR' : 'RTL'),
                            onPressed: () => setState(() => rtl = !rtl),
                          ),
                          DButton(
                            label: const Text('Styleguide'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ComponentStyleguidePage(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: narrow ? 340 : 760,
                          child: ComposerPanel(composer: composer, height: 600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
