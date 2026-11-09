import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../foundation/icons/d_icons.dart';
import '../models/post.dart';
import '../theme/discourse_typography.dart';
import 'avatar_image.dart';
import 'platform.dart';
import 'post_plain_text.dart';
import 'shell_controller.dart';
import 'stream_day_separator.dart';
import 'topic_corner_controls.dart';
import 'topic_viewport_coordinator.dart';

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

  /// The floating control's height, for whoever settles it into a corner.
  static double floatingHeightOf(BuildContext context) =>
      TopicCornerControls.heightOf(context);

  @override
  Widget build(BuildContext context) {
    final boundedTotal = total < 1 ? 1 : total;
    final boundedPosition = position.clamp(1, boundedTotal);
    final mobile = floating && context.isTouch;
    final chip = StreamChip.of(context, floating: floating);
    return DButton(
      key: const ValueKey('topic-progress-button'),
      variant: mobile ? DButtonVariant.tool : DButtonVariant.outline,
      density: !mobile && floating
          ? DButtonDensity.floatingDate
          : DButtonDensity.standard,
      size: mobile ? DButtonSize.floating : DButtonSize.chip,
      shape: DButtonShape.pill,
      backgroundColor: mobile ? DTokens.of(context).wellFill : chip.background,
      interactiveBackgroundColor: chip.hover,
      foregroundColor: chip.foreground,
      borderColor: mobile ? Colors.transparent : chip.border,
      onPressed: onPressed,
      focusNode: focusNode,
      expanded: expanded ?? false,
      hasPopup: true,
      tooltip: context.l10n.topicProgress,
      semanticLabel: context.l10n.topicProgressPostOf(
        (boundedPosition).toString(),
        (boundedTotal).toString(),
      ),
      label: DefaultTextStyle.merge(
        style: TextStyle(
          fontWeight: mobile ? FontWeight.w400 : FontWeight.w600,
        ),
        child: FittedBox(
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
    this.viewport,
  });

  final ShellController controller;
  final int position;
  final int total;
  final bool floating;

  /// The reader a drag moves as it goes. Without one a drag still reaches the
  /// topic, only by way of a route each time.
  final TopicScrubViewport? viewport;

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
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: _TopicProgressEditor(
                key: ValueKey(_session),
                controller: widget.controller,
                position: widget.position,
                total: widget.total < 1 ? 1 : widget.total,
                isOpen: () => _sheet.isOpen,
                onJumpCommitted: _sheet.close,
                viewport: widget.viewport,
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
            floating: widget.floating,
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
          viewport: widget.viewport,
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

/// One drag along the timeline, reduced to the moves the reader can keep up
/// with.
///
/// A position already laid out is shown at once. Anywhere else costs a load,
/// so only the newest position is ever loaded, one at a time and no more often
/// than [_interval]. A load landing after the drag has moved on is still used
/// when it lies between the reader and the drag, which keeps a drag faster
/// than the network moving, and otherwise takes the reader nowhere.
final class _TimelineDrag {
  _TimelineDrag({
    required this.viewport,
    required this.origin,
    required this.revision,
    required this.load,
  }) : _shown = origin,
       _scrub = viewport?.beginScrub();

  final TopicScrubViewport? viewport;
  final int origin;
  final int revision;
  final Future<bool> Function(int position, {required bool Function() isWanted})
  load;
  final Object? _scrub;

  static const _interval = Duration(milliseconds: 120);

  int _shown;
  int? _target;
  Timer? _wait;
  bool _loading = false;

  bool _show(int position) {
    final shown = viewport?.showScrubPosition(position) ?? false;
    if (shown) _shown = position;
    return shown;
  }

  bool _isOnTheWay(int position) {
    final target = _target;
    if (target == null) return false;
    return position == target ||
        (position > _shown && position < target) ||
        (position < _shown && position > target);
  }

  void moveTo(int position) {
    _target = position;
    if (_show(position)) {
      _wait?.cancel();
      _wait = null;
      return;
    }
    _schedule();
  }

  void stop() {
    _target = null;
    _wait?.cancel();
    _wait = null;
  }

  bool restoreOrigin() => viewport?.restoreScrubOrigin() ?? false;

  void end() {
    if (_scrub case final scrub?) viewport?.endScrub(scrub);
  }

  void _schedule() {
    if (_wait != null || _loading || _target == null) return;
    _wait = Timer(_interval, () => unawaited(_loadNewest()));
  }

  Future<void> _loadNewest() async {
    _wait = null;
    final position = _target;
    if (position == null || _show(position)) return;
    _loading = true;
    final moved = await load(position, isWanted: () => _isOnTheWay(position));
    if (moved) _shown = position;
    _loading = false;
    if (_target != position) _schedule();
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
    this.viewport,
  });

  final ShellController controller;
  final int position;
  final int total;
  final bool Function() isOpen;
  final VoidCallback? onJumpCommitted;
  final TopicScrubViewport? viewport;

  @override
  State<_TopicProgressEditor> createState() => _TopicProgressEditorState();
}

class _TopicProgressEditorState extends State<_TopicProgressEditor> {
  late int _selected = widget.position.clamp(1, widget.total);
  int _request = 0;
  _TimelineDrag? _drag;
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
    _cancelScrub();
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

  void _scrub(int position) {
    if (!mounted || !widget.isOpen() || !_checkSource()) {
      _cancelScrub();
      return;
    }
    var drag = _drag;
    if (drag == null) {
      // A release still waiting for its post belongs to an earlier gesture.
      _request++;
      widget.controller.abandonCurrentTopicJump();
      drag = _drag = _TimelineDrag(
        viewport: widget.viewport,
        origin: widget.position.clamp(1, widget.total),
        revision: widget.controller.topicNavigationRevision,
        load: widget.controller.scrubCurrentTopicToIndex,
      );
    }
    drag.moveTo(position.clamp(1, widget.total));
  }

  void _cancelScrub() {
    final drag = _drag;
    if (drag == null) return;
    _drag = null;
    drag.stop();
    unawaited(_returnToOrigin(drag));
  }

  Future<void> _returnToOrigin(_TimelineDrag drag) async {
    final controller = widget.controller;
    if (!drag.restoreOrigin() &&
        controller.topicNavigationRevision != drag.revision &&
        _ownsSource()) {
      await controller.jumpToCurrentTopicIndex(drag.origin);
    }
    drag.end();
  }

  Future<void> _jump(int position) async {
    // Reading stays off until the release has landed. Waiting for its post
    // can outlast a read dwell, and the sheet may close in the meantime, and
    // neither may credit the place the drag happened to stop.
    final drag = _drag;
    _drag = null;
    drag?.stop();
    if (!mounted || !widget.isOpen() || !_checkSource()) {
      drag?.end();
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
    drag?.end();
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
    onScrub: _scrub,
    onScrubCancel: _cancelScrub,
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
    this.onScrub,
    this.onScrubCancel,
    this.error,
    this.postAt,
    this.firstPostedAt,
    this.lastPostedAt,
  });

  final int position;
  final int total;

  /// Where a release, or either end of the timeline, lands.
  final ValueChanged<int> onJump;

  /// Each position a drag passes through, before its release reaches [onJump].
  final ValueChanged<int>? onScrub;
  final VoidCallback? onScrubCancel;
  final String? error;
  final Post? Function(int position)? postAt;
  final DateTime? firstPostedAt;
  final DateTime? lastPostedAt;

  @override
  State<TopicProgressPanel> createState() => _TopicProgressPanelState();
}

class _TopicProgressPanelState extends State<TopicProgressPanel> {
  late int _preview = widget.position;

  /// The total a drag started with. A reply landing mid-drag would otherwise
  /// change the slider's range, which cancels the drag under the finger.
  int? _dragTotal;

  @override
  void didUpdateWidget(TopicProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragTotal != null) return;
    if (oldWidget.position != widget.position ||
        oldWidget.total != widget.total) {
      _preview = widget.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final heldTotal = _dragTotal ?? widget.total;
    final total = heldTotal < 1 ? 1 : heldTotal;
    final at = _preview.clamp(1, total);
    final post = widget.postAt?.call(at);
    final words = post == null || post.hidden || post.isDeleted
        ? ''
        : postPlainText(post);
    final excerpt = words.isEmpty ? null : words;
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
                  // What the post says, so dragging finds a post by its words
                  // as well as its place.
                  if (excerpt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      excerpt,
                      key: const ValueKey('topic-progress-excerpt'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color.lerp(
                          tokens.background,
                          tokens.foreground,
                          .62,
                        ),
                        fontSize: DiscourseTypography.preview,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
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
              : (value) {
                  setState(() => _preview = value);
                  widget.onScrub?.call(value);
                },
          onChangeStart: () => _dragTotal = total,
          onChangeEnd: (value) {
            setState(() => _dragTotal = null);
            widget.onJump(value);
          },
          onChangeCancel: () {
            setState(() {
              _dragTotal = null;
              _preview = widget.position;
            });
            widget.onScrubCancel?.call();
          },
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
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangeCancel,
  });
  final int position;
  final int total;
  final ValueChanged<int>? onChanged;
  final VoidCallback? onChangeStart;
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
    onChangeStart: onChangeStart == null ? null : (_) => onChangeStart!(),
    onChangeEnd: onChangeEnd == null
        ? null
        : (values) => onChangeEnd!(values.single.round()),
    onChangeCancel: onChangeCancel,
  );
}
