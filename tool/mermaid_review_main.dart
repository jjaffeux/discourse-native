import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/discourse_mermaid/discourse_mermaid_module.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/styleguide/examples/mermaid_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final installed = PluginInstaller.install(
    const PluginManifest([discourseMermaidModule]),
  );
  runApp(
    PluginRegistryScope(registry: installed.registry, child: const _Review()),
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false, _narrow = false, _large = false, _rtl = false;
  String _sample = mermaidSamples.keys.first;
  @override
  Widget build(BuildContext context) => DFocusHighlight(
    child: MaterialApp(
      title: 'Mermaid review',
      debugShowCheckedModeBanner: false,
      theme: _dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Builder(
            builder: (context) => DScrollArea(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DButton(
                        label: const Text('Styleguide'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (context) => ComponentStyleguidePage(
                              onClose: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DSelect<String>.controlled(
                          value: _sample,
                          entries: [
                            for (final name in mermaidSamples.keys)
                              DSelectOption(
                                value: name,
                                label: name,
                                child: Text(name),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _sample = value);
                          },
                        ),
                      ),
                      DToggle(
                        pressed: _dark,
                        onPressedChanged: (v) => setState(() => _dark = v),
                        child: const Text('Dark'),
                      ),
                      DToggle(
                        pressed: _narrow,
                        onPressedChanged: (v) => setState(() => _narrow = v),
                        child: const Text('320px'),
                      ),
                      DToggle(
                        pressed: _large,
                        onPressedChanged: (v) => setState(() => _large = v),
                        child: const Text('200% text'),
                      ),
                      DToggle(
                        pressed: _rtl,
                        onPressedChanged: (v) => setState(() => _rtl = v),
                        child: const Text('RTL'),
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
                        child: CookedHtml(
                          buildAsync: false,
                          html:
                              '<p>Before the diagram — $_sample</p><pre data-code-wrap="mermaid"><code class="lang-mermaid">${const HtmlEscape().convert(mermaidSamples[_sample]!)}</code></pre><p>After the diagram</p>',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 500),
                  const Text('End of scroll fixture'),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
