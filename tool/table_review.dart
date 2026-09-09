import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_tables.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Local-only review of the actual styleguide and migrated production owner.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDateEnvironment.instance.initialize();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  final _registry = PluginRegistry([
    LocalDatesPlugin(environment: LocalDateEnvironment.instance),
  ]);
  bool _dark = false;
  bool _rtl = false;
  bool _large = false;
  bool _canQuote = true;
  bool _empty = false;
  bool _refreshed = false;
  String _quote = '';

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Table Review 7328 — local data')),
        body: Column(
          children: [
            Wrap(
              spacing: 8,
              children: [
                DButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ComponentStyleguidePage(),
                    ),
                  ),
                  label: const Text('Open styleguide'),
                ),
                DButton(
                  onPressed: () => setState(() => _dark = !_dark),
                  label: Text(_dark ? 'Light' : 'Dark'),
                ),
                DButton(
                  onPressed: () => setState(() => _rtl = !_rtl),
                  label: const Text('Toggle RTL'),
                ),
                DButton(
                  onPressed: () => setState(() => _large = !_large),
                  label: Text(_large ? '100% text' : '200% text'),
                ),
                DButton(
                  onPressed: () => setState(() => _canQuote = !_canQuote),
                  label: Text(
                    _canQuote ? 'Remove quote permission' : 'Allow quote',
                  ),
                ),
                DButton(
                  onPressed: () => setState(() => _empty = !_empty),
                  label: Text(_empty ? 'Ready data' : 'Empty data'),
                ),
                DButton(
                  onPressed: () => setState(() => _refreshed = !_refreshed),
                  label: const Text('Refresh data'),
                ),
              ],
            ),
            if (_quote.isNotEmpty) Text('Local quote callback: $_quote'),
            Expanded(
              child: Directionality(
                textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
                  child: PluginRegistryScope(
                    registry: _registry,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: AlertTables(
                        siteUrl: 'https://example.com',
                        onQuote: _canQuote
                            ? (alert) =>
                                  setState(() => _quote = alert.identifier)
                            : null,
                        data: AlertData.decode({
                          'alert_data': _empty
                              ? <Object>[]
                              : [
                                  _alert(
                                    'DatabaseLatency',
                                    description: _refreshed
                                        ? 'Recovered latency after refresh'
                                        : 'High database latency; investigate the primary replica.',
                                  ),
                                  _alert('QueueDepth'),
                                  _alert(
                                    'SuppressedWorker',
                                    status: 'suppressed',
                                  ),
                                  _alert(
                                    'PreviousIncident',
                                    status: 'resolved',
                                  ),
                                ],
                        })!,
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
  );
}

Map<String, Object?> _alert(
  String name, {
  String status = 'firing',
  String? description,
}) => {
  'status': status,
  'identifier': name,
  'datacenter': 'sjc1',
  'description': description,
  'starts_at': '2026-09-09T09:15:00Z',
  'ends_at': status == 'resolved' ? '2026-09-09T10:00:00Z' : null,
  'external_url': 'https://example.com/alerts',
  'generator_url': 'https://example.com/graph',
  'link_url': 'https://example.com/logs',
};
