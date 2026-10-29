import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../foundation/count_label.dart';
import '../models/content_route.dart';
import '../theme/d_icons.dart';
import 'platform.dart';

enum _View { latest, unread, newActivity, unseen, top, trending }

_View _viewOf(TopicListMode mode) => switch (mode) {
  TopicListMode.latest => _View.latest,
  TopicListMode.unread => _View.unread,
  TopicListMode.newActivity ||
  TopicListMode.newTopics ||
  TopicListMode.newReplies => _View.newActivity,
  TopicListMode.unseen => _View.unseen,
  TopicListMode.popular => _View.trending,
  _ => _View.top,
};

/// The adaptive topic views, using the same feed routes as the full menu.
///
/// A bounded parent controls the available room. [maxVisibleViews] can reserve
/// room for adjacent filters; [compact] uses icons while retaining counts and
/// accessible names. The current view always remains visible.
class TopicFeedMenu extends StatefulWidget {
  const TopicFeedMenu({
    super.key,
    required this.mode,
    required this.onSelected,
    this.signedIn = true,
    this.unreadCount = 0,
    this.newCount = 0,
    this.unifiedNew = false,
    this.topicCount = 0,
    this.replyCount = 0,
    this.maxVisibleViews = 3,
    this.compact = false,
  }) : assert(maxVisibleViews >= 1 && maxVisibleViews <= 3);

  final TopicListMode mode;
  final ValueChanged<TopicListMode> onSelected;
  final bool signedIn;
  final bool unifiedNew;
  final int unreadCount, newCount, topicCount, replyCount;
  final int maxVisibleViews;
  final bool compact;

  static String label(TopicListMode mode) => switch (mode) {
    TopicListMode.latest => appL10n.latest,
    TopicListMode.unread => appL10n.unread,
    TopicListMode.newActivity => appL10n.messageNew,
    TopicListMode.newTopics => appL10n.newTopics,
    TopicListMode.newReplies => appL10n.newReplies,
    TopicListMode.unseen => appL10n.unseen,
    TopicListMode.popular => appL10n.trending,
    _ => appL10n.top(mode.topPeriod!.label),
  };

  @override
  State<TopicFeedMenu> createState() => _TopicFeedMenuState();
}

class _TopicFeedMenuState extends State<TopicFeedMenu> {
  final _measureKeys = <Object, GlobalKey>{};
  final _menuKeys = <Object, GlobalKey>{};
  final _toggleKeys = <_View, GlobalKey>{};
  Map<Object, double> _widths = {};
  Object? _measurementIdentity;

  bool get _compact =>
      widget.compact || (context.isTouch && DFitRow.tightOf(context));

  _View get _current => _viewOf(widget.mode);
  List<_View> get _views => [
    for (final view in _View.values)
      if (widget.signedIn ||
          view == _View.latest ||
          view == _View.top ||
          view == _View.trending ||
          view == _current)
        view,
  ];

  TopicListMode _mode(_View view) => view == _current
      ? widget.mode
      : switch (view) {
          _View.latest => TopicListMode.latest,
          _View.unread => TopicListMode.unread,
          _View.newActivity => TopicListMode.newActivity,
          _View.unseen => TopicListMode.unseen,
          _View.top => TopicListMode.topYearly,
          _View.trending => TopicListMode.popular,
        };

  int _count(TopicListMode mode) => switch (mode) {
    TopicListMode.unread => widget.unreadCount,
    TopicListMode.newActivity => widget.newCount,
    TopicListMode.newTopics => widget.topicCount,
    TopicListMode.newReplies => widget.replyCount,
    _ => 0,
  };

  int _hiddenCount(Iterable<_View> hidden) {
    final unread = hidden.contains(_View.unread) ? widget.unreadCount : 0;
    final fresh = hidden.contains(_View.newActivity) ? widget.newCount : 0;
    // Unified New includes Unread's replies. Legacy New contains only new
    // topics, which are disjoint from Unread. Both totals already share scope.
    return widget.unifiedNew ? math.max(unread, fresh) : unread + fresh;
  }

  String _segmentLabel(_View view) => view == _View.top && view != _current
      ? context.l10n.topTopiclistnavigation
      : TopicFeedMenu.label(_mode(view));

  String _semantics(String label, int count) =>
      '$label${count > 0 ? ', ${countLabel(count, CountNoun.topic)}' : ''}';

  Widget _countedLabel(Widget label, int count) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: label),
      if (count > 0) ...[
        const SizedBox(width: DSpacing.xs),
        DBadge(variant: DBadgeVariant.secondary, child: Text('$count')),
      ],
    ],
  );

  Widget _toggle(_View view, {FocusNode? focusNode, VoidCallback? activate}) {
    final label = _segmentLabel(view);
    final count = _count(_mode(view));
    final icon = DIcon(switch (view) {
      _View.latest => DIcons.farClock,
      _View.unread => DIcons.envelope,
      _View.newActivity => DIcons.certificate,
      _View.unseen => DIcons.farEyeSlash,
      _View.top => DIcons.medal,
      _View.trending => DIcons.fire,
    }, size: 14);
    final toggle = DToggle(
      key: ValueKey('topic-list-view-${view.name}'),
      pressed: view == _current,
      size: DToggleSize.filter,
      variant: DToggleVariant.segmented,
      semanticLabel: _semantics(label, count),
      focusNode: focusNode,
      onPressedChanged: activate == null ? null : (_) => activate(),
      child: _countedLabel(_compact ? icon : Text(label), count),
    );
    return activate == null
        ? toggle
        : KeyedSubtree(
            key: _toggleKeys.putIfAbsent(view, GlobalKey.new),
            child: toggle,
          );
  }

  Widget _overflow(int count, {DDropdownMenuTriggerState? trigger}) {
    final name = _semantics(context.l10n.chooseTopicFeed, count);
    if (count == 0) {
      return DButton.iconOnly(
        tooltip: context.l10n.chooseTopicFeed,
        key: const ValueKey('topic-list-feed-menu'),
        size: DButtonSize.filter,
        variant: DButtonVariant.ghost,
        semanticLabel: name,
        focusNode: trigger?.focusNode,
        hasPopup: true,
        expanded: trigger?.open ?? false,
        onPressed: trigger?.toggle,
        icon: const DIcon(DIcons.ellipsis, size: 14),
      );
    }
    return DButton(
      key: const ValueKey('topic-list-feed-menu'),
      size: DButtonSize.filter,
      variant: DButtonVariant.ghost,
      semanticLabel: name,
      focusNode: trigger?.focusNode,
      hasPopup: true,
      expanded: trigger?.open ?? false,
      onPressed: trigger?.toggle,
      label: _countedLabel(const DIcon(DIcons.ellipsis, size: 14), count),
    );
  }

  Widget _menu(
    Object id,
    List<_View> views,
    Widget Function(DDropdownMenuTriggerState) trigger,
  ) => DDropdownMenu(
    key: _menuKeys.putIfAbsent(id, GlobalKey.new),
    sheetOnMobile: true,
    mobileSheetVariant: DSheetVariant.adaptiveMenu,
    content: DDropdownMenuContent(
      width: 304,
      semanticLabel: context.l10n.chooseTopicFeed,
      children: [for (final view in views) ..._items(view)],
    ),
    child: DDropdownMenuTrigger(builder: (_, state) => trigger(state)),
  );

  Iterable<Widget> _items(_View view) sync* {
    if (view == _View.top) {
      yield DDropdownMenuLabel(
        child: Text(context.l10n.topTopiclistnavigation),
      );
      yield DDropdownMenuGroup(
        showGuide: true,
        semanticLabel: context.l10n.topPeriods,
        children: [
          for (final period in [
            TopPeriod.yearly,
            TopPeriod.quarterly,
            TopPeriod.monthly,
            TopPeriod.weekly,
            TopPeriod.daily,
            TopPeriod.all,
          ])
            _item(TopicListMode.top(period)),
        ],
      );
    } else if (view == _View.newActivity && widget.unifiedNew) {
      yield DDropdownMenuLabel(child: Text(context.l10n.messageNew));
      yield DDropdownMenuGroup(
        showGuide: true,
        semanticLabel: context.l10n.newActivity,
        children: [
          _item(TopicListMode.newActivity),
          _item(TopicListMode.newTopics),
          _item(TopicListMode.newReplies),
        ],
      );
    } else {
      yield _item(_mode(view));
    }
  }

  Widget _item(TopicListMode mode) {
    final label = switch (mode) {
      TopicListMode.newActivity when widget.unifiedNew => context.l10n.all,
      TopicListMode.newTopics => context.l10n.topics,
      TopicListMode.newReplies => context.l10n.replies,
      _ => mode.isTop ? mode.topPeriod!.label : TopicFeedMenu.label(mode),
    };
    final count = _count(mode);
    final selected = mode == widget.mode;
    return DDropdownMenuItem(
      key: ValueKey(
        mode.isTop
            ? 'topic-list-top-period-${mode.topPeriod!.queryValue}'
            : 'topic-list-${mode == TopicListMode.newActivity
                  ? (widget.unifiedNew ? 'new-all' : 'new')
                  : mode == TopicListMode.newTopics
                  ? 'new-topics'
                  : mode == TopicListMode.newReplies
                  ? 'new-replies'
                  : mode == TopicListMode.popular
                  ? 'popular'
                  : mode.name}',
      ),
      onPressed: () => widget.onSelected(mode),
      semanticLabel:
          '${_semantics(label, count)}${selected ? context.l10n.selectedTopiclistnavigation : ''}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) const DIcon(DIcons.check, size: 14),
          if (count > 0) ...[
            if (selected) const SizedBox(width: DSpacing.sm),
            DBadge(variant: DBadgeVariant.secondary, child: Text('$count')),
          ],
        ],
      ),
      child: Text(label),
    );
  }

  List<_View> _fit(double room, double overflowWidth) {
    if (_views.any((view) => !_widths.containsKey(view))) return [_current];
    if (_views.length <= widget.maxVisibleViews &&
        _views.fold<double>(0, (sum, view) => sum + _widths[view]!) <= room) {
      return _views;
    }
    final keep = {_current};
    var used = (_widths[_current] ?? room) + overflowWidth;
    for (final view in _views) {
      if (view == _current) continue;
      if (keep.length >= widget.maxVisibleViews ||
          used + (_widths[view] ?? room) > room) {
        break;
      }
      used += _widths[view]!;
      keep.add(view);
    }
    return [
      for (final view in _views)
        if (keep.contains(view)) view,
    ];
  }

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final widths = <Object, double>{
        for (final entry in _measureKeys.entries)
          if (entry.value.currentContext?.findRenderObject() case RenderBox box
              when box.hasSize)
            entry.key: box.size.width,
      };
      if (!mapEquals(widths, _widths)) setState(() => _widths = widths);
    });
  }

  @override
  Widget build(BuildContext context) {
    final identity = (
      widget.mode,
      widget.unreadCount,
      widget.newCount,
      widget.topicCount,
      widget.replyCount,
      widget.signedIn,
      widget.unifiedNew,
      _compact,
      MediaQuery.textScalerOf(context),
      Localizations.localeOf(context),
      Theme.of(context).textTheme,
      Theme.of(context).platform,
    );
    if (identity != _measurementIdentity) {
      _measurementIdentity = identity;
      _widths = {};
    }
    _measure();
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        var shown = _fit(room, _widths['bare'] ?? 0);
        if (_hiddenCount(_views.where((view) => !shown.contains(view))) > 0) {
          shown = _fit(room, _widths['counted'] ?? 0);
        }
        final hidden = _views.where((view) => !shown.contains(view)).toList();
        final overflowCount = _hiddenCount(hidden);
        final overflowWidth = hidden.isEmpty
            ? 0.0
            : _widths[overflowCount > 0 ? 'counted' : 'bare'] ?? 0;
        final naturalWidth = shown.fold<double>(
          overflowWidth,
          (sum, view) => sum + (_widths[view] ?? 0),
        );
        Widget measured(Object id, Widget child) => KeyedSubtree(
          key: _measureKeys.putIfAbsent(id, GlobalKey.new),
          child: child,
        );
        Widget segment(_View view) =>
            view == _View.top ||
                (view == _View.newActivity && widget.unifiedNew)
            ? _menu(
                view,
                [view],
                (trigger) => Semantics(
                  expanded: trigger.open,
                  child: _toggle(
                    view,
                    focusNode: trigger.focusNode,
                    activate: trigger.toggle,
                  ),
                ),
              )
            : _toggle(view, activate: () => widget.onSelected(_mode(view)));
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: room.isFinite && _widths.isNotEmpty
                  ? math.min(room, naturalWidth)
                  : null,
              child: DButtonGroup.quiet(
                key: const ValueKey('topic-list-view-switch'),
                semanticLabel: context.l10n.topicLists,
                children: [
                  for (final view in shown)
                    if (view == _current && room.isFinite && _widths.isNotEmpty)
                      DButtonGroupExpanded(child: segment(view))
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: room),
                        child: segment(view),
                      ),
                  if (hidden.isNotEmpty)
                    Offstage(
                      offstage: _widths.isEmpty,
                      child: _menu(
                        'more',
                        context.isTouch ? _views : hidden,
                        (trigger) => _overflow(overflowCount, trigger: trigger),
                      ),
                    ),
                ],
              ),
            ),
            // Measure actual Native controls so localization, counts, platform
            // and text scaling determine how many fit, without copying kit metrics.
            Offstage(
              child: ExcludeFocus(
                child: OverflowBox(
                  maxWidth: double.infinity,
                  fit: OverflowBoxFit.deferToChild,
                  child: DButtonGroup.quiet(
                    children: [
                      for (final view in _views) measured(view, _toggle(view)),
                      measured('bare', _overflow(0)),
                      measured('counted', _overflow(_hiddenCount(_views))),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
