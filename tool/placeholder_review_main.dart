import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/discourse_placeholder/discourse_placeholder_module.dart';
import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_store.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp(
    'placeholder-native-review-',
  );
  final installed = PluginInstaller.install(
    PluginManifest([
      DiscoursePlaceholderModule(
        persistence: PlaceholderStore(
          file: File('${directory.path}/values.json'),
        ),
      ),
    ]),
  );
  final session = installed.openSession(
    PluginHostBindings([
      PluginHostPort<PluginUserIdReader>(corePluginUserPort, (_) => 1),
    ]),
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    PluginScope(
      session: session,
      registry: installed.registry,
      child: const _Review(),
    ),
  );
}

const _post = Post(
  id: 22,
  postNumber: 1,
  username: 'author',
  cooked: '''
<h2>Connect to your community</h2>
<div class="d-wrap" data-wrap="placeholder" data-key="HOSTED_SITE_NAME" data-default="community.example" data-description="Your server">
<p>From the above <strong>options</strong></p></div>
<p><span class="d-wrap" data-wrap="placeholder" data-key="COUNTRY" data-default="FR" data-defaults="FR,DE,US,CA" data-description="Choose a country"></span></p>
<p>Your server is <strong>=HOSTED_SITE_NAME=</strong>, in =COUNTRY=.</p>
<pre><code class="lang-bash">ssh admin@=HOSTED_SITE_NAME=
curl https://=HOSTED_SITE_NAME=/status</code></pre>
<p><a href="https://=HOSTED_SITE_NAME=/docs">Read documentation for =HOSTED_SITE_NAME=</a></p>
''',
);
const _topic = PluginContainingTopic(id: 7, slug: 'example', archived: false);

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  bool _rtl = false;
  bool _narrow = false;
  bool _large = false;
  int _mount = 0;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    label: const Text('Light'),
                    onPressed: () => setState(() => _dark = false),
                  ),
                  DButton(
                    label: const Text('Dark'),
                    onPressed: () => setState(() => _dark = true),
                  ),
                  DButton(
                    label: Text(_narrow ? 'Wide layout' : '320px layout'),
                    onPressed: () => setState(() => _narrow = !_narrow),
                  ),
                  DButton(
                    label: Text(_large ? '100% text' : '200% text'),
                    onPressed: () => setState(() => _large = !_large),
                  ),
                  DButton(
                    label: const Text('RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: const Text('Revisit post'),
                    onPressed: () => setState(() => _mount++),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Directionality(
                textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
                  child: SizedBox(
                    width: _narrow ? 320 : 720,
                    child: Builder(
                      key: ValueKey(_mount),
                      builder: (context) => PluginScope.maybeOf(context)!
                          .registry
                          .transformPostBody(
                            context,
                            'https://community.example',
                            _post,
                            topic: _topic,
                            builder: (context, cooked) => CookedHtml(
                              html: cooked,
                              siteUrl: 'https://community.example',
                              post: _post,
                              containingTopic: _topic,
                              buildAsync: false,
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
