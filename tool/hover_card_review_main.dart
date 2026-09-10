// Source-exact native review fixture. User data and responses are local fakes.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/styleguide/examples/hover_card_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

const _siteUrl = 'https://hover-card-review.invalid';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const reader = DiscourseUser(username: 'reviewer', name: 'Reviewer');
  final api = _HoverCardReviewApi();
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('hover-card-review.invalid').copyWith(user: reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'local-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Fixture(controller: controller, api: api));
}

class _HoverCardReviewApi extends FakeDiscourseApi {
  _HoverCardReviewApi()
    : super(
        user: const DiscourseUser(username: 'reviewer', name: 'Reviewer'),
        totals: const NotificationTotals(),
      );

  final loadingProfile = Completer<UserCard>();

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    if (username == 'loading') return loadingProfile.future;
    if (username == 'missing') {
      throw StateError('Fixture profile failure');
    }
    return const UserCard(
      username: 'alex',
      name: 'alex',
      title: 'Design engineer and open-source maintainer',
      location: 'San Francisco',
    );
  }
}

class _Fixture extends StatefulWidget {
  const _Fixture({required this.controller, required this.api});

  final ShellController controller;
  final _HoverCardReviewApi api;

  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  bool dark = false;
  bool custom = false;
  bool rtl = false;
  bool reducedMotion = false;
  double scale = 1;

  ThemeData get theme {
    final base = dark ? AppTheme.dark : AppTheme.light;
    return custom ? StyleguideTheme.forest.resolve(base) : base;
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.controller,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Hover Card native review')),
          body: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
            ),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 24,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DButton(
                          label: Text(dark ? 'Light' : 'Dark'),
                          onPressed: () => setState(() => dark = !dark),
                        ),
                        DButton(
                          label: Text(custom ? 'Site palette' : 'Forest'),
                          onPressed: () => setState(() => custom = !custom),
                        ),
                        DButton(
                          label: const Text('RTL'),
                          onPressed: () => setState(() => rtl = !rtl),
                        ),
                        DButton(
                          label: const Text('200%'),
                          onPressed: () =>
                              setState(() => scale = scale == 1 ? 2 : 1),
                        ),
                        DButton(
                          label: const Text('Reduced motion'),
                          onPressed: () =>
                              setState(() => reducedMotion = !reducedMotion),
                        ),
                        DButton(
                          label: const Text('Open full styleguide'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ComponentStyleguidePage(),
                            ),
                          ),
                        ),
                        DButton(
                          label: const Text('Complete loading profile'),
                          onPressed: widget.api.loadingProfile.isCompleted
                              ? null
                              : () => widget.api.loadingProfile.complete(
                                  const UserCard(
                                    username: 'loading',
                                    name: 'Loaded later',
                                    title: 'Completed local fixture response',
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const Text('Frozen Basic example'),
                    Builder(builder: hoverCardExamples.examples.first.builder),
                    const Text('All physical sides'),
                    Builder(
                      builder: hoverCardExamples.examples
                          .firstWhere((example) => example.title == 'Sides')
                          .builder,
                    ),
                    const Text('Arabic physical and logical sides'),
                    Builder(
                      builder: hoverCardExamples.examples
                          .firstWhere((example) => example.title == 'RTL')
                          .builder,
                    ),
                    const Text('Multiple triggers and payloads'),
                    Builder(
                      builder: hoverCardExamples.examples
                          .firstWhere(
                            (example) =>
                                example.title ==
                                'Multiple triggers and payloads',
                          )
                          .builder,
                    ),
                    const Text('Controlled state and callbacks'),
                    Builder(
                      builder: hoverCardExamples.examples
                          .firstWhere(
                            (example) =>
                                example.title == 'Controlled and controller',
                          )
                          .builder,
                    ),
                    const Text('Production UserCardTarget'),
                    const Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        UserCardTarget(
                          username: 'alex',
                          siteUrl: _siteUrl,
                          child: Text('@alex ready'),
                        ),
                        UserCardTarget(
                          username: 'loading',
                          siteUrl: _siteUrl,
                          child: Text('@loading pending'),
                        ),
                        UserCardTarget(
                          username: 'missing',
                          siteUrl: _siteUrl,
                          child: Text('@missing error'),
                        ),
                      ],
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

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }
}
