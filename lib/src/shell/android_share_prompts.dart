import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/android_shares.dart';
import '../models/discourse_instance.dart';
import 'shell_controller.dart';

/// Presents incoming Android shares in order, once the shell can show forums.
class AndroidSharePrompts extends StatefulWidget {
  const AndroidSharePrompts({
    super.key,
    required this.shell,
    required this.navigatorKey,
    required this.child,
  });

  final ShellController shell;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AndroidSharePrompts> createState() => _AndroidSharePromptsState();
}

class _AndroidSharePromptsState extends State<AndroidSharePrompts> {
  static const _maximumPendingShares = 16;

  final _platform = PlatformAndroidShares();
  final _pending = Queue<AndroidShare>();
  late final StreamSubscription<AndroidShare> _subscription;
  bool _scheduled = false;
  bool _presenting = false;

  @override
  void initState() {
    super.initState();
    widget.shell.addListener(_schedule);
    _subscription = _platform.shares.listen((share) {
      _pending.addLast(share);
      if (_pending.length > _maximumPendingShares) _pending.removeFirst();
      _schedule();
    });
  }

  @override
  void didUpdateWidget(AndroidSharePrompts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.shell, oldWidget.shell)) return;
    oldWidget.shell.removeListener(_schedule);
    widget.shell.addListener(_schedule);
    _schedule();
  }

  @override
  void dispose() {
    widget.shell.removeListener(_schedule);
    unawaited(_subscription.cancel());
    _platform.dispose();
    super.dispose();
  }

  void _schedule() {
    if (_scheduled || _presenting || _pending.isEmpty || !widget.shell.loaded) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !widget.shell.loaded) return;
      final context = widget.navigatorKey.currentContext;
      if (context == null) return;
      unawaited(_present(context, _pending.removeFirst()));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _present(BuildContext context, AndroidShare share) async {
    _presenting = true;
    try {
      await _openShare(context, share);
    } finally {
      _presenting = false;
      if (mounted) _schedule();
    }
  }

  Future<void> _openShare(BuildContext context, AndroidShare share) async {
    final shell = widget.shell;
    bool isCurrent() => mounted && identical(widget.shell, shell);

    final toasts = DToast.maybeOf(context);
    void showError(String message) => toasts?.add(
      DToastOptions(description: message, type: DToastType.error),
    );

    if (share.text == null && share.mediaUris.isEmpty) {
      showError(appL10n.androidShareCouldNotRead);
      return;
    }
    final forums = shell.instances
        .where((site) => site.user?.canCreateTopic == true)
        .toList();
    if (forums.isEmpty) {
      showError(appL10n.androidShareNeedsForum);
      return;
    }
    final siteUrl = await _chooseForum(context, forums);
    if (siteUrl == null || !isCurrent()) return;

    final lease = shell.lifecycle.capture(siteUrl);
    ImportedAndroidShareMedia? media;
    if (share.mediaUris.isNotEmpty) {
      final loading = toasts?.add(
        DToastOptions(
          description: appL10n.androidSharePreparingMedia,
          type: DToastType.loading,
        ),
      );
      try {
        media = await _platform.importMedia(share);
      } on PlatformException {
        // Text can still open even when the sender's media isn't readable.
      } on MissingPluginException {
        // A host without media support can still open shared text.
      } finally {
        if (loading != null) toasts?.close(loading);
      }
    }

    try {
      if (!isCurrent()) return;
      if (!lease.isCurrent) {
        showError(appL10n.androidShareCouldNotOpenTopic);
        return;
      }
      final files = media?.files ?? const [];
      if (files.length < share.mediaUris.length) {
        showError(appL10n.androidShareCouldNotRead);
      }
      if (share.text == null && files.isEmpty) return;

      final composer = await shell.openSharedTopic(
        siteUrl: siteUrl,
        text: share.text,
        files: files,
      );
      if (composer == null) {
        if (isCurrent()) showError(appL10n.androidShareCouldNotOpenTopic);
        return;
      }
      if (media case final imported?) {
        unawaited(composer.disposed.then((_) => imported.dispose()));
        media = null;
      }
    } finally {
      await media?.dispose();
    }
  }

  Future<String?> _chooseForum(
    BuildContext context,
    List<DiscourseInstance> forums,
  ) => showDSheet<String>(
    context: context,
    side: DSheetSide.bottom,
    builder: (context, sheet) {
      final title = context.l10n.chooseForumForNewTopic;
      return DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: title,
        topBottomMaxHeightFactor: .85,
        children: [
          DSheetHeader(children: [DSheetTitle(child: Text(title))]),
          DSheetBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final site in forums)
                  DItem(
                    onPressed: () => sheet.close(site.url),
                    children: [
                      DItemContent(
                        children: [
                          DItemTitle(
                            child: Text(
                              site.title.isEmpty ? site.host : site.title,
                            ),
                          ),
                          if (site.title.isNotEmpty)
                            DItemDescription(child: Text(site.host)),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => widget.child;
}
