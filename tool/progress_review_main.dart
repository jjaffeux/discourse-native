// Offline review mounts production surfaces. No updater or network is created.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/badge.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/shell/badges_controller.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/update_sheet.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const ProgressReviewApp());
}

class ProgressReviewApp extends StatefulWidget {
  const ProgressReviewApp({super.key});
  @override
  State<ProgressReviewApp> createState() => _ProgressReviewAppState();
}

class _ProgressReviewAppState extends State<ProgressReviewApp> {
  late final ComposerController composer;
  final uploadGate = Completer<ComposerUploadResult>();
  void Function(double)? uploadProgress;
  @override
  void initState() {
    super.initState();
    composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://offline.invalid',
        topicId: 7,
        slug: 'local',
        topicTitle: 'Local draft',
      ),
      canUploadFile: (_) => true,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        uploadProgress = onProgress;
        onProgress(.25);
        return Future.any([
          uploadGate.future,
          abortTrigger.then<ComposerUploadResult>(
            (_) =>
                throw const ComposerUploadException('Local upload cancelled'),
          ),
        ]);
      },
    );
    composer.addFiles([
      ComposerUploadFile(
        name: 'local-notes.txt',
        length: () async => 3,
        openRead: () => Stream.value([1, 2, 3]),
      ),
    ], 0);
  }

  @override
  void dispose() {
    if (!uploadGate.isCompleted) {
      uploadGate.complete(
        const ComposerUploadResult(
          id: 1,
          originalFilename: 'local-notes.txt',
          shortUrl: 'upload://local',
          url: 'https://offline.invalid/local',
        ),
      );
    }
    composer.dispose();
    super.dispose();
  }

  int palette = 0;
  bool rtl = false;
  bool large = false;
  bool reduced = false;
  bool loading = true;
  double progress = .25;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: [
      AppTheme.light,
      AppTheme.dark,
      StyleguideTheme.forest.resolve(AppTheme.light),
    ][palette],
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Progress offline production review')),
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(large ? 2 : 1),
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DButton(
                      label: const Text('Styleguide'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ComponentStyleguidePage(),
                        ),
                      ),
                    ),
                    DButton(
                      label: const Text('Palette'),
                      onPressed: () =>
                          setState(() => palette = (palette + 1) % 3),
                    ),
                    DButton(
                      label: const Text('RTL'),
                      onPressed: () => setState(() => rtl = !rtl),
                    ),
                    DButton(
                      label: const Text('Text scale'),
                      onPressed: () => setState(() => large = !large),
                    ),
                    DButton(
                      label: const Text('Motion'),
                      onPressed: () => setState(() => reduced = !reduced),
                    ),
                    DButton(
                      label: const Text('Loading / ready'),
                      onPressed: () => setState(() => loading = !loading),
                    ),
                    DButton(
                      label: const Text('Sample percentage'),
                      onPressed: () => setState(
                        () => progress = progress >= 1 ? 0 : progress + .25,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Actual composer upload queue — in-memory upload'),
                ListenableBuilder(
                  listenable: composer,
                  builder: (_, _) => ComposerUploadQueue(composer: composer),
                ),
                DButton(
                  label: const Text('Advance local upload'),
                  onPressed: () => uploadProgress?.call(.75),
                ),
                const SizedBox(height: 24),
                const Text('Actual update download surface — read-only sample'),
                UpdateDownloadProgress(progress: progress),
                const SizedBox(height: 24),
                EventUnavailableCard(
                  loading: loading,
                  error: loading
                      ? 'Loading local event details…'
                      : 'Local event response failed.',
                  onRetry: () => setState(() => loading = true),
                ),
                const SizedBox(height: 24),
                const Text('Actual badge directory refresh strip'),
                SizedBox(
                  height: 350,
                  child: BadgesPage(
                    siteUrl: 'https://offline.invalid',
                    route: const BadgeRoute.directory(),
                    state: BadgesState(
                      loading: loading,
                      loaded: true,
                      catalog: BadgeCatalog.fromJson(const {
                        'badges': [
                          {
                            'id': 1,
                            'name': 'Reader',
                            'description': 'Read local discussions',
                            'badge_type_id': 3,
                          },
                        ],
                      }, 'https://offline.invalid'),
                    ),
                    onRefresh: () async => setState(() => loading = true),
                    onOpenBadge: (_) => setState(() => loading = false),
                    onLoadMore: () {},
                    onOpenUrl: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
