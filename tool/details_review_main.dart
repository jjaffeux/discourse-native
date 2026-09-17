// Local details fixture using the production post renderer and composer.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
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
      slug: 'details',
      topicTitle: 'Details editing',
    ),
  );
  composer.text.value = const TextEditingValue(
    text:
        'Before the details.\n\n[details="More information"]\nThis is **bold**, *italic* and `code` in hidden content.\n\n![An image preview|240x120](upload://details-example)\n\n[details="Nested details"]\nNested **rich content**.\n[/details]\n[/details]\n\nAfter the details.',
    selection: TextSelection.collapsed(offset: 0),
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  var dark = false;
  var narrow = false;
  var rtl = false;
  var post = true;
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
                            label: Text(post ? 'Composer' : 'Post'),
                            onPressed: () => setState(() => post = !post),
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
                          child: post
                              ? const SingleChildScrollView(
                                  child: SelectionArea(
                                    child: CookedHtml(
                                      html:
                                          '<p>Before the details.</p>'
                                          '<details><summary>More information</summary>'
                                          '<p>This is <strong>hidden content</strong> with <code>code</code>.</p>'
                                          '<details><summary>Nested details</summary><p>Nested content.</p></details>'
                                          '</details><p>After the details.</p>'
                                          '<details open><summary>Starts open</summary><p>Already visible.</p></details>',
                                      siteUrl: 'https://example.test',
                                      buildAsync: false,
                                    ),
                                  ),
                                )
                              : ComposerPanel(composer: composer, height: 600),
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
