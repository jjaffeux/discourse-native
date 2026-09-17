// Local fixture for reviewing the production Compact event card.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/event_fixtures.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final ports = EventTestPorts();
  var dark = true;
  var narrow = false;
  var largeText = false;
  String? response;
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
                      label: Text(largeText ? 'Normal text' : 'Large text'),
                      onPressed: () => setState(() => largeText = !largeText),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: narrow ? 320 : 680,
                      child: Builder(
                        builder: (context) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(largeText ? 2 : 1),
                          ),
                          child: EventCard(
                            siteUrl: eventSite,
                            zones: ports.zones,
                            accountTimezone: 'Europe/Madrid',
                            onRespond: (status, _) =>
                                setState(() => response = status),
                            event: PostEvent.decode({
                              'id': 42,
                              'name': 'Dinner @Petra',
                              'starts_at': '2026-09-29T20:15:00+02:00',
                              'ends_at': '2026-09-29T22:15:00+02:00',
                              'timezone': 'Europe/Madrid',
                              'status': 'public',
                              'is_public': true,
                              'can_update_attendance': true,
                              'should_display_invitees': true,
                              'creator': {'id': 1, 'username': 'Aimee'},
                              'stats': {'going': 2, 'interested': 0},
                              'location':
                                  'Meet in the hotel community room to travel together- Google link',
                              'description':
                                  'Distance from Only YOU Hotel Sevilla\n'
                                  'Please check the bus route on the day to see if it is more convenient.\n'
                                  'Arrival by Tram + Walk:\n'
                                  'Please check the bus route on the day to see if it is more convenient.\n'
                                  'Walk approximately 6–8 minutes to the Luis de Morales tram stop\n'
                                  'Take the T1 MetroCentro tram → Archivo de Indias (current end of line)\n'
                                  'Walk approximately 12–15 minutes to the restaurant\n'
                                  'Reference Topic:',
                              if (response != null)
                                'watching_invitee': {
                                  'status': response,
                                  'user': {'username': 'preview'},
                                },
                            })!,
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
