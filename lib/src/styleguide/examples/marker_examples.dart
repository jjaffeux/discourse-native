import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final markerExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Conversation notes, live status, actions and labeled boundaries.',
  notes:
      'Source, rendered reference and native macOS review complete. '
      '14/20 text, 16px decorative icons, 8px gap, 1px borders and 12px separator gaps. '
      'Status is opt-in with liveRegion; actions use explicit button/link semantics and caller callbacks. '
      'Native touch actions have 48px bounds; large labels wrap. No Form value is owned. '
      'MarkerIcon suppresses focus, pointer input and semantics. Reduced motion renders plain text. '
      'Navigation and asynchronous work stay outside Marker.',
  examples: [
    StyleguideExample(
      title: 'Overview and variants',
      description:
          'The reference conversation markers: notes, thinking, compaction and file exploration.',
      code: '''const DMarker(
  icon: DMarkerIcon(child: DSpinner(semanticLabel: null)),
  liveRegion: true,
  child: DMarkerContent(shimmer: true, child: Text('Thinking...')),
)
const DMarker(
  variant: DMarkerVariant.separator,
  child: DMarkerContent(child: Text('Conversation compacted')),
)''',
      builder: (_) => const _MarkerOverview(),
    ),
    StyleguideExample(
      title: 'Status and shimmer',
      description:
          'Complete or restart local work. Updates are a live region; the spinner stays decorative. Try reduced motion and RTL.',
      code: '''DMarker(
  liveRegion: true,
  icon: running ? const DMarkerIcon(child: DSpinner(semanticLabel: null)) : null,
  child: DMarkerContent(shimmer: running,
    child: Text(running ? 'Compacting conversation' : 'Conversation compacted')),
)''',
      builder: (_) => const _MarkerStatus(),
    ),
    StyleguideExample(
      title: 'Separators, borders and stacked icons',
      description:
          'Reference dates, elapsed work, bordered notes and a vertically stacked icon.',
      code: '''const DMarker(variant: DMarkerVariant.separator,
  child: DMarkerContent(child: Text('Today')))
const DMarker(variant: DMarkerVariant.border,
  child: DMarkerContent(child: Text('Opened implementation notes')))
const DMarker(axis: Axis.vertical,
  icon: DMarkerIcon(child: Icon(Icons.check)),
  child: DMarkerContent(child: Text('Syncing completed')))''',
      builder: (_) => const Column(
        spacing: 24,
        children: [
          DMarker(
            variant: DMarkerVariant.separator,
            child: DMarkerContent(child: Text('Today')),
          ),
          DMarker(
            variant: DMarkerVariant.separator,
            child: DMarkerContent(child: Text('Worked for 42s')),
          ),
          DMarker(
            variant: DMarkerVariant.border,
            icon: DMarkerIcon(child: _Artwork.branch()),
            child: DMarkerContent(child: Text('Switched to release-candidate')),
          ),
          DMarker(
            variant: DMarkerVariant.border,
            icon: DMarkerIcon(child: _Artwork.search()),
            child: DMarkerContent(child: Text('Reviewed 8 related files')),
          ),
          DMarker(
            variant: DMarkerVariant.border,
            child: DMarkerContent(child: Text('Opened implementation notes')),
          ),
          DMarker(
            axis: Axis.vertical,
            icon: DMarkerIcon(child: _Artwork.check()),
            child: DMarkerContent(child: Text('Syncing completed')),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Links and buttons',
      description:
          'Tab then Return or Space activates each enabled marker. The link opens a local detail panel; Revert updates local state.',
      code: '''DMarker(action: DMarkerAction.link, onPressed: openDetails,
  child: const DMarkerContent(child: Text('View the pull request')))
DMarker(action: DMarkerAction.button, onPressed: revert,
  child: const DMarkerContent(child: Text('Revert this change')))
const DMarker(action: DMarkerAction.button,
  child: DMarkerContent(child: Text('Revert unavailable')))''',
      builder: (_) => const _MarkerActions(),
    ),
  ],
);

class _MarkerOverview extends StatelessWidget {
  const _MarkerOverview();
  @override
  Widget build(BuildContext context) => const Column(
    spacing: 32,
    children: [
      DMarker(
        icon: DMarkerIcon(child: _Artwork.branch()),
        child: DMarkerContent(child: Text('Switched to a new branch')),
      ),
      DMarker(
        liveRegion: true,
        icon: DMarkerIcon(child: DSpinner(semanticLabel: null)),
        child: DMarkerContent(shimmer: true, child: Text('Thinking...')),
      ),
      DMarker(
        variant: DMarkerVariant.separator,
        child: DMarkerContent(child: Text('Conversation compacted')),
      ),
      DMarker(
        icon: DMarkerIcon(child: _Artwork.search()),
        child: DMarkerContent(child: Text('Explored 4 files')),
      ),
    ],
  );
}

class _MarkerStatus extends StatefulWidget {
  const _MarkerStatus();
  @override
  State<_MarkerStatus> createState() => _MarkerStatusState();
}

class _MarkerStatusState extends State<_MarkerStatus> {
  bool running = true;
  @override
  Widget build(BuildContext context) => Column(
    spacing: 24,
    children: [
      for (final variant in [DMarkerVariant.inline, DMarkerVariant.separator])
        DMarker(
          variant: variant,
          liveRegion: true,
          icon: running
              ? const DMarkerIcon(child: DSpinner(semanticLabel: null))
              : const DMarkerIcon(child: _Artwork.check()),
          child: DMarkerContent(
            shimmer: running,
            child: Text(
              running ? 'Compacting conversation' : 'Conversation compacted',
            ),
          ),
        ),
      DButton(
        onPressed: () => setState(() => running = !running),
        label: Text(running ? 'Complete work' : 'Restart work'),
      ),
    ],
  );
}

class _MarkerActions extends StatefulWidget {
  const _MarkerActions();
  @override
  State<_MarkerActions> createState() => _MarkerActionsState();
}

class _MarkerActionsState extends State<_MarkerActions> {
  bool details = false;
  bool reverted = false;
  @override
  Widget build(BuildContext context) => Column(
    spacing: 24,
    children: [
      DMarker(
        action: DMarkerAction.link,
        onPressed: () => setState(() => details = !details),
        icon: const DMarkerIcon(child: _Artwork.branch()),
        child: const DMarkerContent(child: Text('View the pull request')),
      ),
      if (details)
        const Text(
          'Pull request #42: Update the conversation notes. All checks passed.',
        ),
      DMarker(
        action: DMarkerAction.button,
        onPressed: () => setState(() => reverted = !reverted),
        child: DMarkerContent(
          child: Text(reverted ? 'Restore this change' : 'Revert this change'),
        ),
      ),
      const DMarker(
        action: DMarkerAction.button,
        child: DMarkerContent(child: Text('Revert unavailable')),
      ),
      Text(reverted ? 'Change reverted' : 'Change applied'),
    ],
  );
}

// Lucide reference artwork, under licenses/lucide.txt.
class _Artwork extends StatelessWidget {
  const _Artwork.branch()
    : paths =
          '<path d="M6 3v12"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/>';
  const _Artwork.search()
    : paths = '<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>';
  const _Artwork.check()
    : paths =
          '<path d="M12 5v16" /><path d="m16 12 2 2 4-4" /><path d="M22 6V5a2 2 0 00-1.999-2L16 3.002A5 5 0 0012 5a5 5 0 00-4-2H4a2 2 0 00-2 2v12a2 2 0 001.999 2H8a5 5 0 014 2 5 5 0 014-2h4.001A2 2 0 0022 17v-1.344" />';
  final String paths;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">$paths</svg>',
    width: 16,
    height: 16,
    theme: SvgTheme(currentColor: IconTheme.of(context).color!),
  );
}
