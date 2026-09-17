// Isolated native review of the production participants dialog using supplied rows.
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_participants.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/event_fixtures.dart';
import '../test/support/participant_fixtures.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final ports = EventTestPorts(transport: _ParticipantReviewTransport());
  ports.transport.responses['GET /discourse-post-event/events/42.json'] = {
    'event': eventJson(),
  };
  final handle = ports.controller.acquire(
    eventSite,
    PostEvent.decode(eventJson())!,
  );
  await handle.refresh();
  var dark = true;
  var narrow = false;
  var large = false;
  var rtl = false;
  runApp(
    StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (_, child) => DFocusHighlight(child: child!),
        home: Scaffold(
          body: Column(
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
                      label: Text(large ? 'Normal text' : 'Large text'),
                      onPressed: () => setState(() => large = !large),
                    ),
                    DButton(
                      label: Text(rtl ? 'LTR' : 'RTL'),
                      onPressed: () => setState(() => rtl = !rtl),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: narrow ? 360 : 1000,
                    child: LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          textScaler: TextScaler.linear(large ? 2 : 1),
                        ),
                        child: Directionality(
                          textDirection: rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Navigator(
                            onGenerateRoute: (_) => MaterialPageRoute<void>(
                              builder: (context) => Scaffold(
                                body: Center(
                                  child: DButton(
                                    label: const Text('Open participants'),
                                    onPressed: () =>
                                        showEventParticipants(context, handle),
                                  ),
                                ),
                              ),
                            ),
                          ),
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

class _ParticipantReviewTransport extends RecordingPluginTransport {
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/invitees.json')) {
      final filter = (uri.queryParameters['filter'] ?? '').toLowerCase();
      final type = uri.queryParameters['type'];
      responses['GET $path'] = {
        'invitees': participantScreenshotRows.where((row) {
          final user = row['user']! as Map<String, Object?>;
          return (type == null || type == row['status']) &&
              '${user['name']} ${user['username']}'.toLowerCase().contains(
                filter,
              );
        }).toList(),
      };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
