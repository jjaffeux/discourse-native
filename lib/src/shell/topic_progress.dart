import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'shell_controller.dart';

class TopicProgressButton extends StatelessWidget {
  const TopicProgressButton({
    super.key,
    required this.position,
    required this.total,
    required this.onPressed,
    this.focusNode,
    this.expanded,
    this.floating = false,
  });

  final int position;
  final int total;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool? expanded;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final boundedTotal = total < 1 ? 1 : total;
    final boundedPosition = position.clamp(1, boundedTotal);
    return DButton(
      key: const ValueKey('topic-progress-button'),
      onPressed: onPressed,
      focusNode: focusNode,
      expanded: expanded ?? false,
      hasPopup: true,
      tooltip: context.l10n.topicProgress,
      semanticLabel: context.l10n.topicProgressPostOf(
        (boundedPosition).toString(),
        (boundedTotal).toString(),
      ),
      variant: floating
          ? DButtonVariant.outline
          : DButtonVariant.transparentBackground,
      backgroundColor: floating ? null : Colors.transparent,
      interactiveBackgroundColor: floating ? null : Colors.transparent,
      shape: floating ? DButtonShape.pill : DButtonShape.rounded,
      size: DButtonSize.regular,
      icon: const DIcon(DIcons.chevronDown),
      iconPosition: DButtonIconPosition.end,
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$boundedPosition / $boundedTotal',
          textDirection: TextDirection.ltr,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
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
    this.floating = false,
  });

  final ShellController controller;
  final int position;
  final int total;
  final bool floating;

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
      semanticLabel: context.l10n.postNavigation,
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
        floating: widget.floating,
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
      _error = appL10n.closeAndReopenTopicProgressToJumpInTheCurrentTopic;
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
      _error = appL10n.couldNotOpenThatPostTryAgain;
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
            text: context.l10n.postTopicprogress((_selected).toString()),
            children: [
              TextSpan(
                text: context.l10n.messageOf((widget.total).toString()),
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
          spacing: DSpacing.controlGap,
          runSpacing: 8,
          children: [
            DButton(
              label: Text(context.l10n.firstPost),
              variant: DButtonVariant.ghost,
              onPressed: _jumping ? null : () => unawaited(_jump(1)),
            ),
            DButton(
              label: Text(context.l10n.latestPost),
              variant: DButtonVariant.ghost,
              onPressed: _jumping ? null : () => unawaited(_jump(widget.total)),
            ),
            DButton(
              key: const ValueKey('topic-progress-jump'),
              label: Text(context.l10n.jump),
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
    semanticLabel: context.l10n.post,
    semanticFormatterCallback: (value) =>
        context.l10n.postOf((value.round()).toString(), (total).toString()),
    onChanged: onChanged == null ? null : (value) => onChanged!(value.round()),
  );
}
