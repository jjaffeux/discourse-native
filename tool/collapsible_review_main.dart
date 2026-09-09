// Local-data fixture mounts both migrated production editors and the styleguide.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_tables.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LocalDateEnvironment.instance.ensureDatabase();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const CollapsibleReviewApp());
}

class CollapsibleReviewApp extends StatefulWidget {
  const CollapsibleReviewApp({super.key});
  @override
  State<CollapsibleReviewApp> createState() => _ReviewState();
}

class _ReviewState extends State<CollapsibleReviewApp> {
  bool dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      appBar: AppBar(title: const Text('Collapsible review 3c15')),
      body: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              DButton(
                label: const Text('Alert groups'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Local alert groups')),
                      body: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: AlertTables(
                            siteUrl: 'https://forum.example',
                            data: AlertData.decode({
                              'alert_data': [
                                for (var i = 0; i < 32; i++)
                                  {
                                    'status': 'firing',
                                    'identifier': 'Local database alert $i',
                                    'datacenter': 'review',
                                    'description':
                                        'Self-contained alert description',
                                    'starts_at': '2026-09-09T12:00:00Z',
                                  },
                              ],
                            })!,
                            onQuote: (alert) =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Quote: ${alert.identifier}'),
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              DButton(
                label: const Text('Toggle theme'),
                onPressed: () => setState(() => dark = !dark),
              ),
              DButton(
                label: const Text('Styleguide'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const ComponentStyleguidePage(),
                  ),
                ),
              ),
              DButton(
                label: const Text('Event editor'),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => EventComposerSheet(
                    settings: const EventSettings(
                      enabled: true,
                      customFields: ['venue-code'],
                    ),
                    timezone: 'Etc/UTC',
                    isCurrent: () => true,
                    block: parseEventBlocks(
                      '[event start="2026-09-09 12:00" timezone="Etc/UTC" name="Local review" max-attendees="20"]Review draft[/event]',
                    ).single,
                  ),
                ),
              ),
              DButton(
                label: const Text('Stale event editor'),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => EventComposerSheet(
                    settings: const EventSettings(enabled: true),
                    timezone: 'Etc/UTC',
                    isCurrent: () => false,
                  ),
                ),
              ),
              DButton(
                label: const Text('Local date editor'),
                onPressed: () => showLocalDateComposerSheet(
                  context: context,
                  draft: LocalDateComposerDraft.newDate(
                    now: DateTime(2026, 9, 9, 12),
                    timezone: 'Etc/UTC',
                    environment: LocalDateEnvironment.instance,
                  ),
                  siteFormats: const ['LLL', 'YYYY-MM-DD'],
                  isCurrent: () => true,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
