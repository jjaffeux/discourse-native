import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/styleguide/examples/message_examples.dart';
import 'src/styleguide/styleguide_theme.dart';
import 'src/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _MessageReviewApp());
}

class _MessageReviewApp extends StatefulWidget {
  const _MessageReviewApp();

  @override
  State<_MessageReviewApp> createState() => _MessageReviewAppState();
}

class _MessageReviewAppState extends State<_MessageReviewApp> {
  var dark = false;
  var plum = false;
  var narrow = false;
  var largeText = false;
  var rtl = false;
  var reducedMotion = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: plum
        ? StyleguideTheme.plum.resolve(AppTheme.light)
        : dark
        ? AppTheme.dark
        : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Message Review dee9')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DButton(
                  label: const Text('Light / dark'),
                  onPressed: () => setState(() => dark = !dark),
                ),
                DButton(
                  label: const Text('Plum palette'),
                  onPressed: () => setState(() => plum = !plum),
                ),
                DButton(
                  label: const Text('360px'),
                  onPressed: () => setState(() => narrow = !narrow),
                ),
                DButton(
                  label: const Text('200% text'),
                  onPressed: () => setState(() => largeText = !largeText),
                ),
                DButton(
                  label: const Text('RTL'),
                  onPressed: () => setState(() => rtl = !rtl),
                ),
                DButton(
                  label: const Text('Reduced motion'),
                  onPressed: () =>
                      setState(() => reducedMotion = !reducedMotion),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: narrow ? 360 : 640,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(largeText ? 2 : 1),
                    disableAnimations: reducedMotion,
                  ),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Frozen documented examples',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final example in messageExamples.examples) ...[
                          Text(
                            example.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(example.description),
                          const SizedBox(height: 12),
                          Builder(builder: example.builder),
                          const SizedBox(height: 32),
                        ],
                        const Text(
                          'Discourse Chat adapter geometry',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _ChatAdapterGeometry(),
                      ],
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

/// Offline geometry fixture for the compatibility options used by
/// ChatMessageTile. The reviewer must still inspect the actual production tile.
class _ChatAdapterGeometry extends StatelessWidget {
  const _ChatAdapterGeometry();

  @override
  Widget build(BuildContext context) => const DMessage(
    avatarAlignment: DMessageAvatarAlignment.top,
    spacing: 0,
    children: [
      DMessageAvatar(
        minimumExtent: 0,
        shiftForFooter: false,
        child: SizedBox(
          width: 42,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: DAvatar(
              dimension: 28,
              semanticLabel: 'Sam',
              fallback: DAvatarFallback(child: Text('S')),
            ),
          ),
        ),
      ),
      DMessageContent(
        spacing: 0,
        alignChildren: false,
        flushMetadata: true,
        children: [
          Text('Sam', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(
            'This fixture preserves the existing top-anchored Discourse Chat row.',
          ),
          Text('(edited)', style: TextStyle(fontSize: 12)),
        ],
      ),
    ],
  );
}
