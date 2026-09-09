// Local-only native fixture: mounts actual production editors and styleguide.
import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/shell/invite_editor.dart';
import 'package:discourse_native/src/shell/invites_controller.dart';
import 'package:discourse_native/src/styleguide/examples/textarea_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_chrome.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/invite_fixtures.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const TextareaReviewApp());
}

class TextareaReviewApp extends StatefulWidget {
  const TextareaReviewApp({super.key});
  @override
  State<TextareaReviewApp> createState() => _TextareaReviewAppState();
}

class _TextareaReviewAppState extends State<TextareaReviewApp> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _large = false;
  bool _narrow = false;
  String _outcome = 'success';
  Completer<Map<String, dynamic>>? _pending;
  late final _transport = InviteTransport()
    ..onWrite = (request) async {
      if (_outcome == 'error') {
        throw const WriteException(WriteFailure.forbidden);
      }
      if (_outcome == 'pending') {
        _pending = Completer<Map<String, dynamic>>();
        return _pending!.future;
      }
      return inviteRow(99);
    };
  late final _invites = InvitesController(
    api: InvitesApi(_transport),
    credentials: InviteCredentials(),
    instance: inviteSite,
    lifecycle: SiteLifecycle(),
  );
  @override
  void dispose() {
    _invites.dispose();
    _pending?.complete(inviteRow(99));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme.resolve(AppTheme.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_large ? 2 : 1),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Textarea review — local data')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final theme in [
                    StyleguideTheme.light,
                    StyleguideTheme.dark,
                    StyleguideTheme.forest,
                    StyleguideTheme.plum,
                  ])
                    StyleguideAction(
                      label: theme.label,
                      onPressed: () => setState(() => _theme = theme),
                    ),
                  StyleguideAction(
                    label: 'RTL',
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  StyleguideAction(
                    label: '200%',
                    onPressed: () => setState(() => _large = !_large),
                  ),
                  StyleguideAction(
                    label: '320px',
                    onPressed: () => setState(() => _narrow = !_narrow),
                  ),
                  StyleguideAction(
                    label: 'Styleguide',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const ComponentStyleguidePage(),
                      ),
                    ),
                  ),
                  StyleguideAction(
                    label: 'Production Events editor',
                    onPressed: () => showDialog<String>(
                      context: context,
                      builder: (_) => Dialog(
                        child: SizedBox(
                          width: 560,
                          height: 650,
                          child: EventComposerSheet(
                            settings: const EventSettings(enabled: true),
                            timezone: 'Europe/Paris',
                            isCurrent: () => true,
                            block: parseEventBlocks(
                              '[event start="2026-09-10 12:00" name="Local review"]\nAgenda\n[/event]',
                            ).single,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: [
                  for (final outcome in ['success', 'error', 'pending'])
                    StyleguideAction(
                      label: 'Invite $outcome',
                      selected: _outcome == outcome,
                      onPressed: () => setState(() => _outcome = outcome),
                    ),
                  StyleguideAction(
                    label: 'Finish pending invite',
                    onPressed: () {
                      _pending?.complete(inviteRow(99));
                      _pending = null;
                    },
                  ),
                ],
              ),
              const Text(
                'Production InviteEditor: enter an email to reveal custom message. All writes stay in memory.',
              ),
              SizedBox(
                width: _narrow ? 320 : 560,
                child: InviteEditor(controller: _invites, onClose: () {}),
              ),
              for (final example in textareaExamples.examples) ...[
                const SizedBox(height: 24),
                Text(example.title),
                const SizedBox(height: 12),
                SizedBox(
                  width: _narrow ? 320 : 560,
                  child: Builder(builder: example.builder),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
