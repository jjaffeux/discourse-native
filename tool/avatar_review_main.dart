// Self-contained native review fixture. All HTTP responses are local bytes.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/forum_icon.dart';
import 'package:discourse_native/src/styleguide/examples/avatar_examples.dart';
import 'package:discourse_native/src/styleguide/examples/direction_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaPipeline.replace(
    MediaPipeline(
      client: MockClient((request) async {
        if (request.url.path.contains('loading')) {
          await Completer<void>().future;
        }
        if (request.url.path.contains('error')) return http.Response('', 404);
        return http.Response.bytes(
          avatarExampleImage.bytes,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    ),
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _Review(),
    ),
  );
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _narrow = false;
  bool _reducedMotion = false;
  double _scale = 1;
  String _state = 'loading';
  int _actions = 0;
  @override
  Widget build(BuildContext context) => Theme(
    data: _theme.resolve(AppTheme.light),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Avatar review — local production fixtures'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DButton(
                label: const Text('Open styleguide'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ComponentStyleguidePage(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    label: Text('Theme: ${_theme.name}'),
                    onPressed: () => setState(() {
                      const themes = [
                        StyleguideTheme.light,
                        StyleguideTheme.dark,
                        StyleguideTheme.forest,
                        StyleguideTheme.plum,
                      ];
                      _theme =
                          themes[(themes.indexOf(_theme) + 1) % themes.length];
                    }),
                  ),
                  DButton(
                    label: const Text('RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: const Text('200%'),
                    onPressed: () =>
                        setState(() => _scale = _scale == 1 ? 2 : 1),
                  ),
                  DButton(
                    label: const Text('360px'),
                    onPressed: () => setState(() => _narrow = !_narrow),
                  ),
                  DButton(
                    label: const Text('Reduced motion'),
                    onPressed: () =>
                        setState(() => _reducedMotion = !_reducedMotion),
                  ),
                  for (final state in ['loading', 'error', 'ready'])
                    DButton(
                      label: Text(state),
                      onPressed: () => setState(() => _state = state),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Preview: ${_theme.name}, ${_rtl ? 'RTL' : 'LTR'}, '
                '${(_scale * 100).round()}%, ${_narrow ? '360px' : 'wide'}, '
                '${_reducedMotion ? 'reduced' : 'standard'} motion',
              ),
              const SizedBox(height: 24),
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(_scale),
                  disableAnimations: _reducedMotion,
                ),
                child: SizedBox(
                  width: _narrow ? 360 : null,
                  child: Directionality(
                    textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Final Avatar dropdown composition'),
                        const SizedBox(height: 8),
                        Builder(
                          builder: avatarExamples.examples
                              .firstWhere(
                                (example) => example.title == 'Dropdown',
                              )
                              .builder,
                        ),
                        const SizedBox(height: 24),
                        const Text('Final Avatar group actions'),
                        const SizedBox(height: 8),
                        Builder(
                          builder: avatarExamples.examples
                              .firstWhere(
                                (example) => example.title == 'Group actions',
                              )
                              .builder,
                        ),
                        const SizedBox(height: 24),
                        const Text('Final Direction dropdown composition'),
                        const SizedBox(height: 8),
                        Builder(
                          builder: directionExamples.examples
                              .firstWhere(
                                (example) =>
                                    example.title ==
                                    'Inherited direction in a dropdown menu',
                              )
                              .builder,
                        ),
                        const SizedBox(height: 24),
                        Text('Production AvatarImage: $_state'),
                        DAvatar.frame(
                          child: AvatarImage(
                            url: 'https://avatar-review.invalid/$_state',
                            size: 40,
                            fallback: const DAvatarFallback(child: Text('CN')),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Production ForumIcon and action owner'),
                        DButton(
                          semanticLabel: 'Open local forum',
                          label: ForumIcon(
                            forum: DiscourseInstance(
                              url: 'https://avatar-review.invalid',
                              title: 'Local community',
                              iconUrl: 'https://avatar-review.invalid/$_state',
                            ),
                            size: 40,
                          ),
                          onPressed: () => setState(() => _actions++),
                        ),
                        Text('Forum actions: $_actions'),
                      ],
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
