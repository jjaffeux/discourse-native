import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'shell_controller.dart';
import 'shell_sheet.dart';

class TopicProgressButton extends StatelessWidget {
  const TopicProgressButton({
    super.key,
    required this.position,
    required this.total,
    required this.onPressed,
  });

  final int position;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boundedPosition = position.clamp(1, total);
    return DTooltip(
      message: 'Topic progress',
      child: Semantics(
        button: true,
        label: 'Topic progress, post $boundedPosition of $total',
        child: Material(
          color: theme.shell.floating,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('topic-progress-button'),
            onTap: onPressed,
            child: SizedBox(
              height: 32,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 72),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: boundedPosition / total,
                          child: ColoredBox(
                            key: const ValueKey('topic-progress-fill'),
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$boundedPosition / $total',
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showTopicProgress({
  required BuildContext context,
  required ShellController controller,
  required int position,
  required int total,
}) async {
  final siteUrl = controller.currentInstance?.url;
  final topicId = controller.currentContent?.topicId;
  final tabId = controller.activeTabId;
  if (controller.accountSessionDisposed ||
      siteUrl == null ||
      topicId == null ||
      tabId == null) {
    return;
  }
  final lease = controller.lifecycle.capture(siteUrl);
  final accountIdentity = controller.currentAccountIdentity;
  final rootMode = controller.rootMode;
  var sourceIsCurrent = true;
  void checkSource() {
    sourceIsCurrent =
        sourceIsCurrent &&
        !controller.accountSessionDisposed &&
        lease.isCurrent &&
        controller.currentInstance?.url == siteUrl &&
        controller.currentContent?.topicId == topicId &&
        controller.activeTabId == tabId &&
        controller.currentAccountIdentity == accountIdentity &&
        controller.rootMode == rootMode;
  }

  // Returning to the same topic must not revive a sheet from an earlier visit.
  controller.addListener(checkSource);
  try {
    await showShellSheet<void>(
      context: context,
      title: 'Topic progress',
      dialogOnDesktop: true,
      builder: (context) => _TopicProgressEditor(
        controller: controller,
        position: position,
        total: total,
        route: ModalRoute.of<void>(context)!,
        ownsSource: () {
          checkSource();
          return sourceIsCurrent;
        },
      ),
    );
  } finally {
    controller.removeListener(checkSource);
  }
}

class _TopicProgressEditor extends StatefulWidget {
  const _TopicProgressEditor({
    required this.controller,
    required this.position,
    required this.total,
    required this.route,
    required this.ownsSource,
  });

  final ShellController controller;
  final int position;
  final int total;
  final ModalRoute<void> route;
  final bool Function() ownsSource;

  @override
  State<_TopicProgressEditor> createState() => _TopicProgressEditorState();
}

class _TopicProgressEditorState extends State<_TopicProgressEditor> {
  late int _selected = widget.position.clamp(1, widget.total);
  bool _jumping = false;
  String? _error;

  bool _checkSource() {
    if (widget.ownsSource()) return true;
    setState(() {
      _jumping = false;
      _error = 'Close and reopen topic progress to jump in the current topic.';
    });
    return false;
  }

  Future<void> _jump([int? position]) async {
    if (!mounted || _jumping || !widget.route.isCurrent || !_checkSource()) {
      return;
    }
    final target = (position ?? _selected).clamp(1, widget.total);
    setState(() {
      _selected = target;
      _jumping = true;
      _error = null;
    });
    final opened = await widget.controller.jumpToCurrentTopicIndex(target);
    // Dismissal leaves the editor mounted during its exit animation; only an
    // active route may receive the result, and only a current one may pop.
    if (!mounted || !widget.route.isActive || !_checkSource()) return;
    if (opened && widget.route.isCurrent) {
      widget.route.navigator!.pop();
      return;
    }
    setState(() {
      _jumping = false;
      _error = opened ? null : 'Could not open that post. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Post $_selected of ${widget.total}',
          key: const ValueKey('topic-progress-selection'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        TopicPositionSlider(
          position: _selected,
          total: widget.total,
          onChanged: _jumping
              ? null
              : (value) => setState(() => _selected = value),
        ),
        if (_error case final error?) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('First post'),
              onPressed: _jumping ? null : () => unawaited(_jump(1)),
            ),
            DButton(
              key: const ValueKey('topic-progress-jump'),
              label: const Text('Jump'),
              onPressed: () => unawaited(_jump()),
              variant: DButtonVariant.primary,
              loading: _jumping,
            ),
            DButton(
              label: const Text('Latest post'),
              onPressed: _jumping ? null : () => unawaited(_jump(widget.total)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Topic-position input shared by the jump editor and offline review fixture.
class TopicPositionSlider extends StatelessWidget {
  const TopicPositionSlider({
    super.key,
    required this.position,
    required this.total,
    required this.onChanged,
  });
  final int position;
  final int total;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) => DSlider(
    key: const ValueKey('topic-progress-slider'),
    value: position.toDouble(),
    min: 1,
    max: total.toDouble(),
    semanticLabel: 'Post',
    semanticFormatterCallback: (value) => 'Post ${value.round()} of $total',
    onChanged: onChanged == null ? null : (value) => onChanged!(value.round()),
  );
}
