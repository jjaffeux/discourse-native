import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../data/app_release.dart';
import '../data/updater.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'update_controller.dart';

Future<void> showUpdateSheet(BuildContext context) {
  return showShellSheet<void>(
    context: context,
    title: appL10n.appUpdates,
    builder: (context) => const _UpdatePanel(),
  );
}

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
                  ? context.l10n.discourseNative
                  : context.l10n.discourseNativeUpdatesheet(
                      (updates.runningVersion).toString(),
                    ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.followingTheChannel(
                (updates.channel.label.toLowerCase()).toString(),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            DToggleGroup<UpdateChannel>(
              items: [
                for (final channel in UpdateChannel.values)
                  DToggleGroupItem(value: channel, child: Text(channel.label)),
              ],
              values: [updates.channel],
              allowEmptySelection: false,
              variant: DToggleVariant.outline,
              spacing: 0,
              onChanged: busy
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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return switch (updates.status) {
      UpdateStatus.checking => const _CheckButton(checking: true),

      UpdateStatus.upToDate => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateStatusAnnouncement(
            label: context.l10n.youReUpToDate,
            child: Row(
              children: [
                DIcon(
                  DIcons.farCircleCheck,
                  size: 18,
                  color: theme.discourse.success,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.youReUpToDate,
                  style: theme.textTheme.bodyMedium,
                ),
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
          DButton(
            // "Switch to" rather than "Update to" when the offer is older than
            // what is running, which is what moving canary -> stable means.
            label: Text(
              release.isDowngrade
                  ? context.l10n.switchTo((release.version).toString())
                  : context.l10n.downloadUpdatesheet(
                      (release.version).toString(),
                    ),
            ),
            onPressed: updates.download,
            variant: DButtonVariant.primary,
          ),
        ],
      ),

      UpdateStatus.downloading => UpdateDownloadProgress(
        progress: updates.progress,
      ),

      UpdateStatus.readyToInstall => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateStatusAnnouncement(
            label: context.l10n.readyToInstall,
            announce: updates.error == null,
            child: Text(
              context.l10n.readyToInstall,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.theAppWillCloseAndReopen,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (updates.error case final error?) ...[
            const SizedBox(height: 12),
            _UpdateError(message: error),
          ],
          const SizedBox(height: 16),
          DButton(
            label: Text(context.l10n.restartAndInstall),
            onPressed: updates.installAndRestart,
            variant: DButtonVariant.primary,
          ),
        ],
      ),

      UpdateStatus.installing => _UpdateStatusAnnouncement(
        label: context.l10n.installingUpdate,
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: DSpinner()),
            const SizedBox(width: 12),
            Text(context.l10n.installing),
          ],
        ),
      ),

      UpdateStatus.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateError(
            message: updates.error ?? context.l10n.theUpdateCouldNotBeChecked,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _CheckButton(label: context.l10n.tryAgain),
              const SizedBox(width: 8),
              // Not decoration. The Linux update path is preview-grade, and
              // someone whose in-app update is broken must not be left with no
              // way to get the build at all.
              DButton(
                label: Text(context.l10n.openTheReleasesPage),
                onPressed: () => openExternalLink(AppRelease.releasesUrl),
                variant: DButtonVariant.link,
              ),
            ],
          ),
        ],
      ),

      UpdateStatus.idle => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          switch (updates.lastChecked) {
            null => Text(context.l10n.neverCheckedForUpdates, style: muted),
            final at => RelativeTimeBuilder(
              when: at,
              // relativeTime is the compact form the topic list uses -- "2h",
              // "3d", "now" -- so "now" needs its own phrasing rather than
              // reading as "now ago".
              builder: (context, ago) => Text(
                ago == context.l10n.relativeNow
                    ? context.l10n.checkedJustNow
                    : context.l10n.lastCheckedAgo((ago).toString()),
                style: muted,
              ),
            ),
          },
          const SizedBox(height: 16),
          const _CheckButton(),
        ],
      ),
    };
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({this.checking = false, this._label});

  final bool checking;
  final String? _label;
  String get label => _label ?? appL10n.checkForUpdates;

  @override
  Widget build(BuildContext context) {
    final updates = ShellScope.read(context).updates;

    return DButton(
      label: Text(label),
      onPressed: updates.check,
      variant: DButtonVariant.primary,
      loading: checking,
      semanticLabel: checking ? context.l10n.checkingForUpdates : null,
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
    ? appL10n.versionIsOnThisChannel((release.version).toString())
    : appL10n.versionIsAvailable((release.version).toString());

String _humanSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) {
    return appL10n.mB(((bytes / mb).toStringAsFixed(1)).toString());
  }
  return appL10n.kB(((bytes / 1024).round()).toString());
}

/// Read-only download surface. The update controller owns all work and actions;
/// local review fixtures can render this same surface without an updater.
class UpdateDownloadProgress extends StatelessWidget {
  const UpdateDownloadProgress({super.key, required this.progress});
  final double progress;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DProgress(
        key: const ValueKey('update-download-progress'),
        value: progress,
        max: 1,
        semanticsLabel: context.l10n.downloadingUpdate,
      ),
      const SizedBox(height: 8),
      _UpdateStatusAnnouncement(
        label: context.l10n.downloadInProgress,
        child: Text(
          context.l10n.downloadingUpdatesheet(
            ((progress * 100).round()).toString(),
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
