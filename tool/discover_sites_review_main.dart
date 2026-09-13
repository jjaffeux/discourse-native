// Isolated, local-data fixture for the production Add a site surface.
import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discover_sites.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(ShellScope(controller: controller, child: const _Review()));
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  final _sources = <DiscoverSites>[];

  DiscoverSites _source(String state) {
    final source = DiscoverSites(
      client: MockClient((_) async {
        if (state == 'Loading') return Completer<http.Response>().future;
        if (state == 'Error') return http.Response('{}', 200);
        const communities = {
          'Discourse Meta': 'meta.discourse.org',
          'Home Assistant': 'community.home-assistant.io',
          'OpenAI Developer Community': 'community.openai.com',
          'Obsidian': 'forum.obsidian.md',
          'Figma Community Forum': 'forum.figma.com',
          'Standard Ebooks': 'standardebooks.discourse.group',
          'Blender Artists': 'blenderartists.org',
          'Julia Programming Language': 'discourse.julialang.org',
          'Hugging Face': 'discuss.huggingface.co',
          'Framework Community': 'community.frame.work',
          'Rust Programming Language': 'users.rust-lang.org',
        };
        return http.Response(
          jsonEncode({
            'topics': [
              for (final entry in communities.entries)
                {'title': entry.key, 'featured_link': 'https://${entry.value}'},
            ],
          }),
          200,
        );
      }),
    );
    _sources.add(source);
    return source;
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: (_dark ? AppTheme.dark : AppTheme.light).copyWith(
      platform: TargetPlatform.macOS,
    ),
    home: Builder(
      builder: (context) => ColoredBox(
        color: DTokens.of(context).background,
        child: Padding(
          padding: const EdgeInsets.all(DSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a site · isolated review',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: DSpacing.lg),
              Wrap(
                spacing: DSpacing.sm,
                children: [
                  for (final state in ['Ready', 'Loading', 'Error'])
                    DButton(
                      label: Text(state),
                      onPressed: () => showAddInstanceSheet(
                        context,
                        discoverSites: _source(state),
                      ),
                    ),
                  DButton(
                    label: const Text('Toggle dark'),
                    onPressed: () => setState(() {
                      _dark = !_dark;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
