import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'src/macos_launch_screen.dart';
import 'src/models/post.dart';
import 'src/shell/topic_progress.dart';
import 'src/theme/app_theme.dart';

/// Offline review of the production topic timeline, with no account or API.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _TimelineReview(),
    ),
  );
}

class _TimelineReview extends StatelessWidget {
  const _TimelineReview();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(28),
      child: Wrap(
        spacing: 24,
        runSpacing: 24,
        children: [
          for (final dark in [false, true])
            for (final floating in [true, false])
              Theme(
                data: dark ? AppTheme.dark : AppTheme.light,
                child: _TimelineExample(floating: floating),
              ),
        ],
      ),
    ),
  );
}

class _TimelineExample extends StatefulWidget {
  const _TimelineExample({required this.floating});
  final bool floating;
  @override
  State<_TimelineExample> createState() => _TimelineExampleState();
}

class _TimelineExampleState extends State<_TimelineExample> {
  final _popover = DPopoverController();
  int _position = 58;

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 342,
    child: DCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(widget.floating ? 'Desktop timeline' : 'Footer timeline'),
            const SizedBox(height: 16),
            // Static open panel and the same trigger make side-by-side review
            // possible; clicking the trigger also exercises the real popover.
            DPopoverContent(
              variant: DPopoverVariant.timeline,
              width: 300,
              cornerRadius: 16,
              padding: const EdgeInsets.all(14),
              child: TopicProgressPanel(
                position: _position,
                total: 120,
                postAt: (at) => Post(
                  id: at,
                  postNumber: at,
                  username: 'flourpower',
                  cooked: '',
                  createdAt: DateTime(2026, 5, 17),
                ),
                firstPostedAt: DateTime(2026, 5, 17),
                lastPostedAt: DateTime(2026, 10, 14),
                onJump: (at) => setState(() => _position = at),
              ),
            ),
            const SizedBox(height: 16),
            DPopover(
              controller: _popover,
              content: DPopoverContent(
                variant: DPopoverVariant.timeline,
                side: DPopoverSide.top,
                align: DPopoverAlign.end,
                width: 300,
                sideOffset: 8,
                cornerRadius: 16,
                padding: const EdgeInsets.all(14),
                child: TopicProgressPanel(
                  position: _position,
                  total: 120,
                  onJump: (at) => setState(() => _position = at),
                ),
              ),
              child: DPopoverTrigger(
                builder: (context, trigger) => TopicProgressButton(
                  position: _position,
                  total: 120,
                  floating: widget.floating,
                  focusNode: trigger.focusNode,
                  expanded: trigger.open,
                  onPressed: trigger.toggle,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
