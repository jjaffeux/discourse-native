import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/post.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'avatar_image.dart';
import 'platform.dart';
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
    return NativeGlassScope(
      child: DButton(
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
        variant: DButtonVariant.ghost,
        density: floating
            ? DButtonDensity.floatingCall
            : DButtonDensity.topicProgress,
        shape: DButtonShape.pill,
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$boundedPosition / $boundedTotal',
            textDirection: TextDirection.ltr,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
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
  final _sheet = DSheetController<void>();
  int _session = 0;

  @override
  void dispose() {
    _popover.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return DSheet<void>(
        controller: _sheet,
        onOpenChanged: (details) {
          if (details.open) setState(() => _session++);
        },
        content: DSheetContent(
          key: const ValueKey('topic-progress-sheet'),
          variant: DSheetVariant.menu,
          side: DSheetSide.bottom,
          inset: true,
          showCloseButton: false,
          semanticLabel: context.l10n.postNavigation,
          topBottomMaxHeightFactor: .9,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: _TopicProgressEditor(
                key: ValueKey(_session),
                controller: widget.controller,
                position: widget.position,
                total: widget.total < 1 ? 1 : widget.total,
                isOpen: () => _sheet.isOpen,
                onJumpCommitted: _sheet.close,
              ),
            ),
          ],
        ),
        trigger: DSheetTrigger(
          builder: (context, open) => TopicProgressButton(
            position: widget.position,
            total: widget.total,
            expanded: _sheet.isOpen,
            onPressed: open,
          ),
        ),
      );
    }
    return DPopover(
      controller: _popover,
      onOpenChange: (open, _) {
        if (open) setState(() => _session++);
      },
      content: DPopoverContent(
        variant: DPopoverVariant.timeline,
        side: DPopoverSide.top,
        align: DPopoverAlign.end,
        width: 300,
        sideOffset: 8,
        cornerRadius: 16,
        padding: const EdgeInsets.all(14),
        semanticLabel: context.l10n.postNavigation,
        child: _TopicProgressEditor(
          key: ValueKey(_session),
          controller: widget.controller,
          position: widget.position,
          total: widget.total < 1 ? 1 : widget.total,
          isOpen: () => _popover.isOpen,
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
}

class _TopicProgressEditor extends StatefulWidget {
  const _TopicProgressEditor({
    required this.controller,
    required this.position,
    required this.total,
    super.key,
    required this.isOpen,
    this.onJumpCommitted,
  });

  final ShellController controller;
  final int position;
  final int total;
  final bool Function() isOpen;
  final VoidCallback? onJumpCommitted;

  @override
  State<_TopicProgressEditor> createState() => _TopicProgressEditorState();
}

class _TopicProgressEditorState extends State<_TopicProgressEditor> {
  late int _selected = widget.position.clamp(1, widget.total);
  int _request = 0;
  String? _error;
  String? _siteUrl;
  TopicDetail? _topic;
  List<int> _stream = const [];
  List<int>? _indexedStream;
  Object? _indexedPostStructure;
  final Map<int, int> _postIdsByNumber = {};

  late final bool Function() _ownsSource;
  late final VoidCallback _sourceListener;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    final siteUrl = controller.currentInstance?.url;
    final topicId = controller.currentContent?.topicId;
    _siteUrl = siteUrl;
    _topic = controller.currentTopic;
    _stream = List.of(controller.currentTopicStreamIds);
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
      _error = appL10n.closeAndReopenTopicProgressToJumpInTheCurrentTopic;
    });
    return false;
  }

  Future<void> _jump(int position) async {
    if (!mounted || !widget.isOpen() || !_checkSource()) {
      return;
    }
    final target = position.clamp(1, widget.total);
    final request = ++_request;
    setState(() {
      _selected = target;
      _error = null;
    });
    final navigation = widget.controller.jumpToCurrentTopicIndex(target);
    widget.onJumpCommitted?.call();
    final opened = await navigation;
    if (!mounted ||
        request != _request ||
        !widget.isOpen() ||
        !_checkSource()) {
      return;
    }
    if (opened) {
      setState(() {});
      return;
    }
    setState(() {
      _error = appL10n.couldNotOpenThatPostTryAgain;
    });
  }

  Post? _postAt(int position) {
    final site = _siteUrl;
    if (site == null) return null;
    if (_topic?.isMegaTopic == true && !widget.controller.currentTopicSummary) {
      final store = widget.controller.store;
      final stream = widget.controller.currentTopicStreamIds;
      final structure = store.structureGenerationOf<Post>(site);
      if (!identical(_indexedStream, stream) ||
          !identical(_indexedPostStructure, structure)) {
        _postIdsByNumber.clear();
        for (final id in stream) {
          final post = store.read<Post>(site, id);
          if (post != null) {
            _postIdsByNumber.putIfAbsent(post.postNumber, () => id);
          }
        }
        _indexedStream = stream;
        _indexedPostStructure = structure;
      }
      final id = _postIdsByNumber[position];
      return id == null ? null : store.read<Post>(site, id);
    }
    if (position < 1 || position > _stream.length) return null;
    return widget.controller.store.read<Post>(site, _stream[position - 1]);
  }

  @override
  Widget build(BuildContext context) => TopicProgressPanel(
    position: _selected,
    total: widget.total,
    error: _error,
    postAt: _postAt,
    firstPostedAt: _postAt(1)?.createdAt ?? _topic?.createdAt,
    lastPostedAt: _postAt(widget.total)?.createdAt ?? _topic?.lastPostedAt,
    onJump: (value) => unawaited(_jump(value)),
  );
}

/// The production timeline layout, also used by the offline visual fixture.
/// Its owner handles navigation and error state; Native controls own artwork.
class TopicProgressPanel extends StatefulWidget {
  const TopicProgressPanel({
    super.key,
    required this.position,
    required this.total,
    required this.onJump,
    this.error,
    this.postAt,
    this.firstPostedAt,
    this.lastPostedAt,
  });

  final int position;
  final int total;
  final ValueChanged<int> onJump;
  final String? error;
  final Post? Function(int position)? postAt;
  final DateTime? firstPostedAt;
  final DateTime? lastPostedAt;

  @override
  State<TopicProgressPanel> createState() => _TopicProgressPanelState();
}

class _TopicProgressPanelState extends State<TopicProgressPanel> {
  late int _preview = widget.position;

  @override
  void didUpdateWidget(TopicProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position ||
        oldWidget.total != widget.total) {
      _preview = widget.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final total = widget.total < 1 ? 1 : widget.total;
    final at = _preview.clamp(1, total);
    final post = widget.postAt?.call(at);
    final muted = Color.lerp(tokens.background, tokens.foreground, .50)!;
    final dayStyle = TextStyle(
      color: muted,
      fontSize: DiscourseTypography.metadata,
      height: 1.5,
    );
    String day(DateTime? value) => value == null
        ? ''
        : DateFormat(
            context.l10n.calendarDatePattern,
            context.l10n.localeName,
          ).format(value.toLocal());
    final fallback = DAvatarFallback(
      child: Text(post?.username.characters.firstOrNull?.toUpperCase() ?? ''),
    );
    Widget endButton(bool first) => DButton(
      label: Text(first ? context.l10n.firstPost : context.l10n.latestPost),
      icon: RotatedBox(
        quarterTurns: first ? 0 : 2,
        child: const DIcon(DIcons.arrowUp),
      ),
      variant: DButtonVariant.ghost,
      density: DButtonDensity.timelineEnd,
      onPressed: at == (first ? 1 : total) && widget.error == null
          ? null
          : () {
              final target = first ? 1 : total;
              setState(() => _preview = target);
              widget.onJump(target);
            },
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (post != null) ...[
              DAvatar(
                border: false,
                decorative: true,
                fallback: fallback,
                child: AvatarImage(
                  url: post.avatarUrl,
                  size: 32,
                  fallback: fallback,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post?.username ??
                        context.l10n.postTopicprogress(at.toString()),
                    key: const ValueKey('topic-progress-author'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.foreground,
                      fontSize: DiscourseTypography.compact,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (post?.createdAt != null) ...[
                    const SizedBox(height: 1),
                    Text(day(post!.createdAt), style: dayStyle),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              label: context.l10n.postOf(at.toString(), total.toString()),
              excludeSemantics: true,
              child: Text.rich(
                TextSpan(
                  text: at.toString(),
                  style: TextStyle(
                    color: tokens.foreground,
                    fontSize: DiscourseTypography.lg,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    TextSpan(
                      text: ' / $total',
                      style: TextStyle(
                        color: muted,
                        fontSize: DiscourseTypography.control,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                key: const ValueKey('topic-progress-selection'),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  height: 1.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TopicPositionSlider(
          position: at,
          total: total,
          onChanged: total <= 1
              ? null
              : (value) => setState(() => _preview = value),
          onChangeEnd: widget.onJump,
          onChangeCancel: () => setState(() => _preview = widget.position),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Text(day(widget.firstPostedAt), style: dayStyle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                day(widget.lastPostedAt),
                style: dayStyle,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.error case final message?) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.destructive),
            ),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, bounds) {
            // Larger accessibility text stacks the full buttons within the panel.
            if (MediaQuery.textScalerOf(context).scale(12.5) > 18) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  endButton(true),
                  const SizedBox(height: 8),
                  endButton(false),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: endButton(true)),
                const SizedBox(width: 8),
                Expanded(child: endButton(false)),
              ],
            );
          },
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
    this.onChangeEnd,
    this.onChangeCancel,
  });
  final int position;
  final int total;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int>? onChangeEnd;
  final VoidCallback? onChangeCancel;
  @override
  Widget build(BuildContext context) => DMultiSlider(
    key: const ValueKey('topic-progress-slider'),
    variant: DSliderVariant.timeline,
    values: [position.toDouble()],
    min: 1,
    max: total.toDouble(),
    semanticLabels: [context.l10n.post],
    semanticFormatter: (value, _) =>
        context.l10n.postOf((value.round()).toString(), (total).toString()),
    onChanged: onChanged == null
        ? null
        : (values) => onChanged!(values.single.round()),
    onChangeEnd: onChangeEnd == null
        ? null
        : (values) => onChangeEnd!(values.single.round()),
    onChangeCancel: onChangeCancel,
  );
}
