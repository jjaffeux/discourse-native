import 'package:flutter/material.dart';

import '../data/app_release.dart';
import '../data/updater.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'update_controller.dart';

Future<void> showUpdateSheet(BuildContext context) {
  return showShellSheet<void>(
    context: context,
    title: 'App updates',
    builder: (context) => const _UpdatePanel(),
  );
}

/// What the running build is, which channel it follows, and whatever is on
/// offer.
///
/// Deliberately not a StatefulWidget holding its own async state, which is what
/// [_AddInstanceForm] does. A site lookup can die with the sheet that started
/// it; a download must not. Closing this sheet mid-download and opening it
/// again has to show the same download still running, so the state lives on the
/// controller and this only reads it.
class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel();

  @override
  Widget build(BuildContext context) => ShellSelector<UpdateController>(
    select: (controller) => controller.updates,
    builder: (context, updates, _) => ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final theme = Theme.of(context);
        final busy =
            updates.status == UpdateStatus.downloading ||
            updates.status == UpdateStatus.installing;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              updates.runningVersion.isEmpty
                  ? 'Discourse Native'
                  : 'Discourse Native ${updates.runningVersion}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Following the ${updates.channel.label.toLowerCase()} channel.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            SegmentedButton<UpdateChannel>(
              segments: [
                for (final channel in UpdateChannel.values)
                  ButtonSegment(value: channel, label: Text(channel.label)),
              ],
              selected: {updates.channel},
              // Locked while something is in flight: switching would discard a
              // download that is still being written to.
              onSelectionChanged: busy
                  ? null
                  : (selection) => updates.setChannel(selection.first),
            ),
            const SizedBox(height: 20),

            _Status(updates: updates),
          ],
        );
      },
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.updates});

  final UpdateController updates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final release = updates.available;

    return switch (updates.status) {
      UpdateStatus.checking => const _CheckButton(checking: true),

      UpdateStatus.upToDate => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateStatusAnnouncement(
            label: "You're up to date.",
            child: Row(
              children: [
                DIcon(
                  DIcons.farCircleCheck,
                  size: 18,
                  color: theme.discourse.success,
                ),
                const SizedBox(width: 8),
                Text("You're up to date.", style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _CheckButton(),
        ],
      ),

      UpdateStatus.available => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateStatusAnnouncement(
            label: _releaseMessage(release!),
            announce: updates.error == null,
            child: Text(
              _releaseMessage(release),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (release.sizeBytes case final bytes?) ...[
            const SizedBox(height: 4),
            Text(
              _humanSize(bytes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (release.notes case final notes? when notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(notes, style: theme.textTheme.bodySmall),
          ],
          if (updates.error case final error?) ...[
            const SizedBox(height: 12),
            _UpdateError(message: error),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: updates.download,
            // "Switch to" rather than "Update to" when the offer is older than
            // what is running, which is what moving canary -> stable means.
            child: Text(
              release.isDowngrade
                  ? 'Switch to ${release.version}'
                  : 'Download ${release.version}',
            ),
          ),
        ],
      ),

      UpdateStatus.downloading => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            key: const ValueKey('update-download-progress'),
            value: updates.progress,
            semanticsLabel: 'Downloading update',
            // Progress indicators carry numeric min/max semantics. Keeping the
            // override numeric lets assistive technology announce it as a
            // percentage without invalidating that native range.
            semanticsValue: '${(updates.progress * 100).round()}',
          ),
          const SizedBox(height: 8),
          _UpdateStatusAnnouncement(
            label: 'Download in progress.',
            child: Text(
              'Downloading — ${(updates.progress * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),

      UpdateStatus.readyToInstall => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateStatusAnnouncement(
            label: 'Ready to install.',
            announce: updates.error == null,
            child: Text('Ready to install.', style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 4),
          Text(
            'The app will close and reopen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (updates.error case final error?) ...[
            const SizedBox(height: 12),
            _UpdateError(message: error),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: updates.installAndRestart,
            child: const Text('Restart and install'),
          ),
        ],
      ),

      UpdateStatus.installing => const _UpdateStatusAnnouncement(
        label: 'Installing update',
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Installing…'),
          ],
        ),
      ),

      UpdateStatus.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateError(
            message: updates.error ?? 'The update could not be checked.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const _CheckButton(label: 'Try again'),
              const SizedBox(width: 8),
              // Not decoration. The Linux update path is preview-grade, and
              // someone whose in-app update is broken must not be left with no
              // way to get the build at all.
              TextButton(
                onPressed: () => openExternalLink(AppRelease.releasesUrl),
                child: const Text('Open the releases page'),
              ),
            ],
          ),
        ],
      ),

      UpdateStatus.idle => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // relativeTime is the compact form the topic list uses -- "2h",
            // "3d", "now" -- so "now" needs its own phrasing rather than
            // reading as "now ago".
            switch (updates.lastChecked) {
              null => 'Never checked for updates.',
              final at => switch (relativeTime(at)) {
                'now' => 'Checked just now.',
                final ago => 'Last checked $ago ago.',
              },
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const _CheckButton(),
        ],
      ),
    };
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({this.checking = false, this.label = 'Check for updates'});

  final bool checking;
  final String label;

  @override
  Widget build(BuildContext context) {
    final updates = ShellScope.read(context).updates;

    return MergeSemantics(
      child: Semantics(
        liveRegion: checking,
        label: checking ? 'Checking for updates' : null,
        child: FilledButton(
          onPressed: checking ? null : updates.check,
          child: checking
              // Same shape as the connecting state in _AddInstanceForm.
              ? const ExcludeSemantics(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

class _UpdateStatusAnnouncement extends StatelessWidget {
  const _UpdateStatusAnnouncement({
    required this.label,
    required this.child,
    this.announce = true,
  });

  final String label;
  final Widget child;
  final bool announce;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: announce,
    label: label,
    child: ExcludeSemantics(child: child),
  );
}

class _UpdateError extends StatelessWidget {
  const _UpdateError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _UpdateStatusAnnouncement(
      label: message,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DIcon(
            DIcons.triangleExclamation,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

String _releaseMessage(UpdateRelease release) => release.isDowngrade
    ? 'Version ${release.version} is on this channel.'
    : 'Version ${release.version} is available.';

String _humanSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}
