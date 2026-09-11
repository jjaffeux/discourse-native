import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';

class TopicProgressButton extends StatelessWidget {
  const TopicProgressButton({
    super.key,
    required this.position,
    required this.total,
    required this.onPressed,
    this.focusNode,
    this.expanded,
  });

  final int position;
  final int total;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boundedPosition = position.clamp(1, total);
    return DTooltip(
      message: 'Topic progress',
      child: Semantics(
        button: true,
        expanded: expanded,
        label: 'Topic progress, post $boundedPosition of $total',
        child: Material(
          color: theme.shell.floating,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('topic-progress-button'),
            onTap: onPressed,
            focusNode: focusNode,
            child: SizedBox(
              height: topicBottomBarControlHeight(context),
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
                            fontSize: DButton.fontSizeFor(DButtonSize.small),
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

class TopicProgressPopover extends StatefulWidget {
  const TopicProgressPopover({
    super.key,
    required this.controller,
    required this.position,
    required this.total,
  });

  final ShellController controller;
  final int position;
  final int total;

  @override
  State<TopicProgressPopover> createState() => _TopicProgressPopoverState();
}

class _TopicProgressPopoverState extends State<TopicProgressPopover> {
  final _popover = DPopoverController();
  int _session = 0;

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DPopover(
    controller: _popover,
    onOpenChange: (open, _) {
      if (open) setState(() => _session++);
    },
    content: DPopoverContent(
      side: DPopoverSide.top,
      align: DPopoverAlign.end,
      width: 360,
      padding: const EdgeInsets.all(16),
      semanticLabel: 'Post navigation',
      child: _TopicProgressEditor(
        key: ValueKey(_session),
        controller: widget.controller,
        position: widget.position,
        total: widget.total,
        isOpen: () => _popover.isOpen,
        close: _popover.close,
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => TopicProgressButton(
        position: widget.position,
        total: widget.total,
        onPressed: trigger.toggle,
        focusNode: trigger.focusNode,
        expanded: trigger.open,
      ),
    ),
  );
}

class _TopicProgressEditor extends StatefulWidget {
  const _TopicProgressEditor({
    required this.controller,
    required this.position,
    required this.total,
    super.key,
    required this.isOpen,
    required this.close,
  });

  final ShellController controller;
  final int position;
  final int total;
  final bool Function() isOpen;
  final VoidCallback close;

  @override
  State<_TopicProgressEditor> createState() => _TopicProgressEditorState();
}

class _TopicProgressEditorState extends State<_TopicProgressEditor> {
  late int _selected = widget.position.clamp(1, widget.total);
  bool _jumping = false;
  String? _error;

  late final bool Function() _ownsSource;
  late final VoidCallback _sourceListener;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    final siteUrl = controller.currentInstance?.url;
    final topicId = controller.currentContent?.topicId;
    final tabId = controller.activeTabId;
    if (controller.accountSessionDisposed ||
        siteUrl == null ||
        topicId == null ||
        tabId == null) {
      _ownsSource = () => false;
      _sourceListener = () {};
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

    _sourceListener = checkSource;
    _ownsSource = () {
      checkSource();
      return sourceIsCurrent;
    };
    controller.addListener(_sourceListener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sourceListener);
    super.dispose();
  }

  bool _checkSource() {
    if (_ownsSource()) return true;
    setState(() {
      _jumping = false;
      _error = 'Close and reopen topic progress to jump in the current topic.';
    });
    return false;
  }

  Future<void> _jump([int? position]) async {
    if (!mounted || _jumping || !widget.isOpen() || !_checkSource()) {
      return;
    }
    final target = (position ?? _selected).clamp(1, widget.total);
    setState(() {
      _selected = target;
      _jumping = true;
      _error = null;
    });
    final opened = await widget.controller.jumpToCurrentTopicIndex(target);
    if (!mounted || !widget.isOpen() || !_checkSource()) return;
    if (opened) {
      widget.close();
      return;
    }
    setState(() {
      _jumping = false;
      _error = 'Could not open that post. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: 'Post $_selected ',
            children: [
              TextSpan(
                text: 'of ${widget.total}',
                style: TextStyle(
                  color: DTokens.of(context).mutedForeground,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          key: const ValueKey('topic-progress-selection'),
          textAlign: TextAlign.start,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
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
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('First post'),
              variant: DButtonVariant.ghost,
              onPressed: _jumping ? null : () => unawaited(_jump(1)),
            ),
            DButton(
              label: const Text('Latest post'),
              variant: DButtonVariant.ghost,
              onPressed: _jumping ? null : () => unawaited(_jump(widget.total)),
            ),
            DButton(
              key: const ValueKey('topic-progress-jump'),
              label: const Text('Jump'),
              onPressed: () => unawaited(_jump()),
              variant: DButtonVariant.primary,
              loading: _jumping,
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
