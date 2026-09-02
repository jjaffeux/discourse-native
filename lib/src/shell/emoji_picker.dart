import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/site_emoji.dart';
import '../plugin_api/emoji_preferences.dart';
import '../plugin_api/emoji_usage.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'curved_animation_builder.dart';
import 'emoji.dart';
import 'emoji_picker_controller.dart';
import 'platform.dart';
import 'shell_sheet.dart';

Future<String?> showEmojiPicker({
  required BuildContext context,
  required String siteUrl,
  required EmojiUsageContext pickerContext,
  required EmojiPreferenceStore store,
  required EmojiCatalogLoader loadCatalog,
  required EmojiSearchAliasLoader loadSearchAliases,
  String initialQuery = '',
  Rect? anchor,
  BuildContext? anchorContext,
}) async {
  final resolvedAnchorContext = anchorContext ?? context;
  final anchorPresence = EmojiPickerAnchor.maybePresenceOf(
    resolvedAnchorContext,
  );
  final controller = EmojiPickerController(
    siteUrl: siteUrl,
    context: pickerContext,
    store: store,
    loadCatalog: loadCatalog,
    loadSearchAliases: loadSearchAliases,
    initialQuery: initialQuery,
  );
  unawaited(controller.load());

  try {
    if (context.isTouch) {
      return await showShellSheet<String>(
        context: context,
        title: 'Emoji',
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        builder: (sheetContext) => SizedBox(
          height: _pickerHeight(sheetContext),
          child: EmojiPicker(
            controller: controller,
            touch: true,
            onPicked: (code) {
              Navigator.of(sheetContext).pop(code);
            },
            onDismiss: Navigator.of(sheetContext).pop,
          ),
        ),
      );
    }

    final resolvedAnchor = anchor ?? _anchorRect(resolvedAnchorContext);
    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss emoji picker',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, _, _) => _LiveAnchoredPickerDialog(
        initialAnchor: resolvedAnchor,
        anchorPresence: anchorPresence,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(dialogContext).pop(),
          },
          child: _DesktopPickerCard(
            controller: controller,
            onPicked: (code) {
              Navigator.of(dialogContext).pop(code);
            },
            onDismiss: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondary, child) =>
          CurvedAnimationBuilder(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
            builder: (context, curved) => FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                alignment: Alignment.bottomLeft,
                child: child,
              ),
            ),
          ),
    );
  } finally {
    controller.dispose();
  }
}

class EmojiPickerAnchor extends StatefulWidget {
  const EmojiPickerAnchor({super.key, required this.child});

  final Widget child;

  static ValueListenable<bool>? maybePresenceOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_EmojiPickerAnchorPresence>()
      ?.presence;

  @override
  State<EmojiPickerAnchor> createState() => _EmojiPickerAnchorState();
}

class _EmojiPickerAnchorState extends State<EmojiPickerAnchor> {
  final ValueNotifier<bool> _presence = ValueNotifier(true);

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presence.value = false;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _EmojiPickerAnchorPresence(presence: _presence, child: widget.child);
}

class _EmojiPickerAnchorPresence extends InheritedWidget {
  const _EmojiPickerAnchorPresence({
    required this.presence,
    required super.child,
  });

  final ValueListenable<bool> presence;

  @override
  bool updateShouldNotify(_EmojiPickerAnchorPresence oldWidget) =>
      oldWidget.presence != presence;
}

class _LiveAnchoredPickerDialog extends StatelessWidget {
  const _LiveAnchoredPickerDialog({
    required this.initialAnchor,
    required this.anchorPresence,
    required this.child,
  });

  final Rect? initialAnchor;
  final ValueListenable<bool>? anchorPresence;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final presence = anchorPresence;
    if (presence == null) return _layout(anchor: initialAnchor);
    return ValueListenableBuilder<bool>(
      valueListenable: presence,
      builder: (context, present, _) =>
          _layout(anchor: present ? initialAnchor : null),
    );
  }

  Widget _layout({required Rect? anchor}) => CustomSingleChildLayout(
    delegate: AnchoredLayout(
      anchor: anchor,
      maxWidth: _desktopPickerWidth,
      preferAbove: true,
    ),
    child: child,
  );
}

const double _desktopPickerWidth = 405;
const double _desktopPickerHeight = 360;
const double _cellExtent = 44;
const double _sectionHeaderExtent = 32;
const String _frequentGroup = '__frequently-used';

double _pickerHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.7).clamp(360.0, 540.0).toDouble();

Rect? _anchorRect(BuildContext context) => anchorRect(
  anchor: context.findRenderObject() as RenderBox?,
  overlay:
      Navigator.of(
            context,
            rootNavigator: true,
          ).overlay?.context.findRenderObject()
          as RenderBox?,
);

class _DesktopPickerCard extends StatelessWidget {
  const _DesktopPickerCard({
    required this.controller,
    required this.onPicked,
    required this.onDismiss,
  });

  final EmojiPickerController controller;
  final ValueChanged<String> onPicked;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('emoji-picker-desktop-popover'),
      elevation: 8,
      color: theme.shell.floating,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: _desktopPickerWidth,
        height: _desktopPickerHeight,
        decoration: BoxDecoration(
          border: Border.all(color: theme.shell.divider),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Emoji',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('emoji-picker-close'),
                      onPressed: onDismiss,
                      icon: const DIcon(DIcons.xmark, size: 17),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: theme.shell.divider),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: EmojiPicker(
                  controller: controller,
                  touch: false,
                  onPicked: onPicked,
                  onDismiss: onDismiss,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmojiPicker extends StatefulWidget {
  const EmojiPicker({
    super.key,
    required this.controller,
    required this.onPicked,
    required this.onDismiss,
    this.touch,
  });

  final EmojiPickerController controller;
  final ValueChanged<String> onPicked;
  final VoidCallback onDismiss;
  final bool? touch;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  late final TextEditingController _search;
  final FocusNode _searchFocus = FocusNode(debugLabel: 'emoji picker search');
  final ScrollController _scroll = ScrollController();
  final Map<String, FocusNode> _cellFocus = {};
  final Map<int, double> _cellOffsets = {};
  final List<_GridPosition> _navigationPositions = [];
  final Map<String, double> _groupOffsets = {};
  List<String> _navigationKeys = const [];
  List<String> _visibleGroupIds = const [];
  String? _activeGroup;
  int _columns = 1;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.controller.query);
    _scroll.addListener(_syncActiveGroup);
  }

  @override
  void didUpdateWidget(EmojiPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _search.text = widget.controller.query;
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_syncActiveGroup)
      ..dispose();
    _search.dispose();
    _searchFocus.dispose();
    for (final node in _cellFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.touch ?? context.isTouch;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: Focus(
        canRequestFocus: false,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchAndTone(
                controller: widget.controller,
                search: _search,
                searchFocus: _searchFocus,
                onSearchKey: _onSearchKey,
              ),
              const SizedBox(height: 8),
              Expanded(child: touch ? _touchContent() : _desktopContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopContent() {
    final groups = _groups();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.controller.hasQuery && groups.isNotEmpty) ...[
          SizedBox(
            width: _cellExtent,
            child: _CategoryNavigation(
              groups: groups,
              activeGroup: _activeGroup ?? groups.first.id,
              vertical: true,
              onSelected: _scrollToGroup,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(child: _content(groups)),
      ],
    );
  }

  Widget _touchContent() {
    final groups = _groups();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _content(groups)),
        if (!widget.controller.hasQuery && groups.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: _cellExtent,
            child: _CategoryNavigation(
              groups: groups,
              activeGroup: _activeGroup ?? groups.first.id,
              vertical: false,
              onSelected: _scrollToGroup,
            ),
          ),
        ],
      ],
    );
  }

  Widget _content(List<_PickerGroup> groups) {
    final controller = widget.controller;
    if (controller.error case final error?) {
      return _PickerMessage(
        icon: DIcons.triangleExclamation,
        message: error,
        liveRegion: true,
        action: DButton(
          key: const ValueKey('emoji-picker-retry'),
          label: const Text('Try again'),
          onPressed: controller.retry,
        ),
      );
    }
    if (controller.loading && controller.catalog == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final catalog = controller.catalog;
    if (catalog == null || catalog.isEmpty) {
      return const _PickerMessage(
        icon: DIcons.farFaceSmile,
        message: 'No emoji are available.',
      );
    }

    if (controller.hasQuery) return _searchContent();
    if (groups.isEmpty) {
      return const _PickerMessage(
        icon: DIcons.farFaceSmile,
        message: 'No emoji are available.',
      );
    }
    return _groupedContent(groups);
  }

  Widget _searchContent() {
    final controller = widget.controller;
    if ((controller.searchPending || controller.aliasesLoading) &&
        controller.searchResults.isEmpty) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (controller.searchResults.isEmpty) {
      return const _PickerMessage(
        icon: DIcons.magnifyingGlass,
        message: 'No emoji found.',
        liveRegion: true,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final choices = [
          for (final emoji in controller.searchResults)
            _EmojiChoice(emoji: emoji, tone: controller.tone),
        ];
        _prepareNavigation(
          choices: choices,
          contentWidth: constraints.maxWidth,
          sectionId: 'search',
          headerOffset: 0,
        );
        return CustomScrollView(
          key: const ValueKey('emoji-picker-search-results'),
          controller: _scroll,
          slivers: [_emojiGrid(choices, sectionId: 'search', baseIndex: 0)],
        );
      },
    );
  }

  Widget _groupedContent(List<_PickerGroup> groups) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _columns = math.max(1, (constraints.maxWidth / _cellExtent).floor());
        _groupOffsets.clear();
        _cellOffsets.clear();
        _navigationPositions.clear();
        final keys = <String>[];
        final slivers = <Widget>[];
        var offset = 0.0;
        var baseIndex = 0;
        var visualRow = 0;

        for (final group in groups) {
          _groupOffsets[group.id] = offset;
          slivers.add(
            SliverToBoxAdapter(
              child: SizedBox(
                height: _sectionHeaderExtent,
                child: _SectionHeader(
                  label: group.label,
                  frequent: group.id == _frequentGroup,
                  clearing: widget.controller.clearingHistory,
                  onClear: widget.controller.clearHistory,
                ),
              ),
            ),
          );
          offset += _sectionHeaderExtent;
          for (var index = 0; index < group.choices.length; index++) {
            final globalIndex = baseIndex + index;
            keys.add(_cellKey(group.id, index, group.choices[index].code));
            _navigationPositions.add(
              _GridPosition(
                visualRow: visualRow + index ~/ _columns,
                column: index % _columns,
              ),
            );
            _cellOffsets[globalIndex] =
                offset + (index ~/ _columns) * _cellExtent;
          }
          slivers.add(
            _emojiGrid(
              group.choices,
              sectionId: group.id,
              baseIndex: baseIndex,
            ),
          );
          offset +=
              ((group.choices.length + _columns - 1) ~/ _columns) * _cellExtent;
          visualRow += (group.choices.length + _columns - 1) ~/ _columns;
          baseIndex += group.choices.length;
        }
        _navigationKeys = List.unmodifiable(keys);
        _visibleGroupIds = List.unmodifiable(groups.map((group) => group.id));
        if (!_visibleGroupIds.contains(_activeGroup)) {
          _activeGroup = groups.first.id;
        }

        return CustomScrollView(
          key: const ValueKey('emoji-picker-groups'),
          controller: _scroll,
          slivers: slivers,
        );
      },
    );
  }

  SliverGrid _emojiGrid(
    List<_EmojiChoice> choices, {
    required String sectionId,
    required int baseIndex,
  }) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        final choice = choices[index];
        final navigationIndex = baseIndex + index;
        final key = _cellKey(sectionId, index, choice.code);
        final node = _cellFocus.putIfAbsent(
          key,
          () => FocusNode(debugLabel: 'emoji $key'),
        );
        return _EmojiCell(
          key: ValueKey('emoji-picker-cell-$key'),
          choice: choice,
          focusNode: node,
          onPicked: widget.onPicked,
          onKey: (event) => _onCellKey(navigationIndex, event),
        );
      }, childCount: choices.length),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisExtent: _cellExtent,
      ),
    );
  }

  void _prepareNavigation({
    required List<_EmojiChoice> choices,
    required double contentWidth,
    required String sectionId,
    required double headerOffset,
  }) {
    _columns = math.max(1, (contentWidth / _cellExtent).floor());
    _cellOffsets.clear();
    _navigationPositions.clear();
    _groupOffsets.clear();
    _visibleGroupIds = const [];
    _navigationKeys = List.unmodifiable([
      for (var index = 0; index < choices.length; index++)
        _cellKey(sectionId, index, choices[index].code),
    ]);
    for (var index = 0; index < choices.length; index++) {
      _cellOffsets[index] = headerOffset + (index ~/ _columns) * _cellExtent;
      _navigationPositions.add(
        _GridPosition(visualRow: index ~/ _columns, column: index % _columns),
      );
    }
  }

  List<_PickerGroup> _groups() {
    final controller = widget.controller;
    final catalog = controller.catalog;
    if (catalog == null) return const [];
    return [
      if (controller.favorites.isNotEmpty)
        _PickerGroup(
          id: _frequentGroup,
          label: 'Frequently used',
          choices: [
            for (final favorite in controller.favorites)
              _EmojiChoice(emoji: favorite.emoji, tone: favorite.tone),
          ],
        ),
      for (final group in catalog.groups)
        if (group.isNotEmpty)
          _PickerGroup(
            id: group.id,
            label: _groupLabel(group.id),
            choices: [
              for (final emoji in group.emojis)
                _EmojiChoice(emoji: emoji, tone: controller.tone),
            ],
          ),
    ];
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _navigationKeys.isNotEmpty) {
      _focusCell(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onCellKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final nodeKey = _navigationKeys.elementAtOrNull(index);
      final context = nodeKey == null ? null : _cellFocus[nodeKey]?.context;
      final cell = context?.findAncestorWidgetOfExactType<_EmojiCell>();
      if (cell != null) widget.onPicked(cell.choice.code);
      return KeyEventResult.handled;
    }

    final target = switch (key) {
      LogicalKeyboardKey.arrowLeft => index - 1,
      LogicalKeyboardKey.arrowRight => index + 1,
      LogicalKeyboardKey.arrowUp => _verticalTarget(index, -1),
      LogicalKeyboardKey.arrowDown => _verticalTarget(index, 1),
      _ => null,
    };
    if (target == null) return KeyEventResult.ignored;
    if (target < 0) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (target >= _navigationKeys.length) return KeyEventResult.handled;
    _focusCell(target);
    return KeyEventResult.handled;
  }

  int _verticalTarget(int index, int direction) {
    if (index < 0 || index >= _navigationPositions.length) return index;
    final current = _navigationPositions[index];

    var cursor = index + direction;
    int? nearest;
    var nearestDistance = 1 << 30;
    while (cursor >= 0 && cursor < _navigationPositions.length) {
      final candidate = _navigationPositions[cursor];
      final rowDirection = candidate.visualRow.compareTo(current.visualRow);
      if ((direction < 0 && rowDirection >= 0) ||
          (direction > 0 && rowDirection <= 0)) {
        cursor += direction;
        continue;
      }

      final targetVisualRow = candidate.visualRow;
      while (cursor >= 0 && cursor < _navigationPositions.length) {
        final inRow = _navigationPositions[cursor];
        if (inRow.visualRow != targetVisualRow) break;
        final distance = (inRow.column - current.column).abs();
        if (distance < nearestDistance) {
          nearest = cursor;
          nearestDistance = distance;
        }
        cursor += direction;
      }
      return nearest ?? index;
    }
    return direction < 0 ? -1 : _navigationKeys.length;
  }

  void _focusCell(int index) {
    if (index < 0 || index >= _navigationKeys.length) return;
    final offset = _cellOffsets[index];
    if (offset != null && _scroll.hasClients) {
      final viewport = _scroll.position.viewportDimension;
      final current = _scroll.offset;
      if (offset < current || offset + _cellExtent > current + viewport) {
        _scroll.jumpTo(
          offset.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        );
      }
    }
    final node = _cellFocus.putIfAbsent(
      _navigationKeys[index],
      () => FocusNode(debugLabel: 'emoji ${_navigationKeys[index]}'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _scrollToGroup(String id) {
    final offset = _groupOffsets[id];
    if (offset == null || !_scroll.hasClients) return;
    setState(() => _activeGroup = id);
    unawaited(
      _scroll.animateTo(
        offset.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  void _syncActiveGroup() {
    if (!_scroll.hasClients || _visibleGroupIds.isEmpty) return;
    final position = _scroll.position;
    var active = position.extentAfter <= 1
        ? _visibleGroupIds.last
        : _visibleGroupIds.first;
    if (position.extentAfter > 1) {
      final marker = _scroll.offset + 8;
      for (final id in _visibleGroupIds) {
        final offset = _groupOffsets[id];
        if (offset != null && offset <= marker) active = id;
      }
    }
    if (active == _activeGroup || !mounted) return;
    setState(() => _activeGroup = active);
  }
}

class _SearchAndTone extends StatelessWidget {
  const _SearchAndTone({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.onSearchKey,
  });

  final EmojiPickerController controller;
  final TextEditingController search;
  final FocusNode searchFocus;
  final FocusOnKeyEventCallback onSearchKey;

  @override
  Widget build(BuildContext context) {
    if (search.text != controller.query) {
      search.value = TextEditingValue(
        text: controller.query,
        selection: TextSelection.collapsed(offset: controller.query.length),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Focus(
            onKeyEvent: onSearchKey,
            child: TextField(
              key: const ValueKey('emoji-picker-search'),
              controller: search,
              focusNode: searchFocus,
              autofocus: true,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              textInputAction: TextInputAction.search,
              onChanged: controller.updateQuery,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search emoji',
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(11),
                  child: DIcon(DIcons.magnifyingGlass, size: 17),
                ),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('emoji-picker-clear-search'),
                        onPressed: () {
                          search.clear();
                          controller.updateQuery('');
                          searchFocus.requestFocus();
                        },
                        icon: const DIcon(DIcons.xmark, size: 15),
                        tooltip: 'Clear search',
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _ToneMenu(controller: controller),
      ],
    );
  }
}

class _ToneMenu extends StatelessWidget {
  const _ToneMenu({required this.controller});

  final EmojiPickerController controller;

  @override
  Widget build(BuildContext context) {
    final sample =
        controller.catalog?.emojiNamed('wave') ??
        controller.catalog?.emojiNamed('clap') ??
        controller.catalog?.all.where((emoji) => emoji.tonable).firstOrNull;
    return Semantics(
      button: true,
      label: 'Skin tone: ${_toneLabel(controller.tone)}',
      child: PopupMenuButton<EmojiSkinTone>(
        key: const ValueKey('emoji-picker-tone'),
        tooltip: 'Choose skin tone',
        popUpAnimationStyle: discoursePopupMenuAnimationStyle(context),
        initialValue: controller.tone,
        onSelected: controller.setTone,
        itemBuilder: (context) => [
          for (final tone in EmojiSkinTone.values)
            PopupMenuItem(
              key: ValueKey('emoji-picker-tone-${tone.code}'),
              value: tone,
              height: _cellExtent,
              child: Semantics(
                selected: tone == controller.tone,
                label: _toneLabel(tone),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      _TonePreview(sample: sample, tone: tone),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_toneLabel(tone))),
                      if (tone == controller.tone)
                        const DIcon(DIcons.check, size: 16),
                    ],
                  ),
                ),
              ),
            ),
        ],
        child: SizedBox.square(
          dimension: _cellExtent,
          child: Center(
            child: _TonePreview(sample: sample, tone: controller.tone),
          ),
        ),
      ),
    );
  }
}

class _TonePreview extends StatelessWidget {
  const _TonePreview({required this.sample, required this.tone});

  final SiteEmoji? sample;
  final EmojiSkinTone tone;

  @override
  Widget build(BuildContext context) {
    final emoji = sample;
    if (emoji == null) return const DIcon(DIcons.hand, size: 21);
    return EmojiImage(
      url: emoji.urlFor(tone),
      size: 22,
      alt: ':${emoji.codeFor(tone)}:',
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _CategoryNavigation extends StatelessWidget {
  const _CategoryNavigation({
    required this.groups,
    required this.activeGroup,
    required this.vertical,
    required this.onSelected,
  });

  final List<_PickerGroup> groups;
  final String activeGroup;
  final bool vertical;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final group in groups)
        _CategoryButton(
          group: group,
          selected: group.id == activeGroup,
          onPressed: () => onSelected(group.id),
        ),
    ];
    if (vertical) {
      return SingleChildScrollView(
        key: const ValueKey('emoji-picker-category-nav-desktop'),
        child: Column(children: children),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('emoji-picker-category-nav-touch'),
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.group,
    required this.selected,
    required this.onPressed,
  });

  final _PickerGroup group;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: group.label,
      child: Tooltip(
        message: group.label,
        child: InkWell(
          key: ValueKey('emoji-picker-category-${group.id}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: ExcludeSemantics(
            child: Container(
              width: _cellExtent,
              height: _cellExtent,
              decoration: BoxDecoration(
                color: selected ? theme.shell.selected : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: DIcon(
                  _groupIcon(group.id),
                  size: 18,
                  color: selected
                      ? theme.shell.selectedForeground
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.frequent,
    required this.clearing,
    required this.onClear,
  });

  final String label;
  final bool frequent;
  final bool clearing;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      if (frequent)
        IconButton(
          key: const ValueKey('emoji-picker-clear-history'),
          onPressed: clearing ? null : onClear,
          visualDensity: VisualDensity.compact,
          icon: clearing
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const DIcon(DIcons.trashCan, size: 14),
          tooltip: 'Clear frequently used emoji',
        ),
    ],
  );
}

class _EmojiCell extends StatelessWidget {
  const _EmojiCell({
    super.key,
    required this.choice,
    required this.focusNode,
    required this.onPicked,
    required this.onKey,
  });

  final _EmojiChoice choice;
  final FocusNode focusNode;
  final ValueChanged<String> onPicked;
  final KeyEventResult Function(KeyEvent) onKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKey(event),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Semantics(
            button: true,
            label: 'Insert :${choice.code}:',
            child: Tooltip(
              message: ':${choice.code}:',
              child: InkWell(
                canRequestFocus: false,
                onTap: () => onPicked(choice.code),
                borderRadius: BorderRadius.circular(8),
                child: ExcludeSemantics(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: _cellExtent,
                    height: _cellExtent,
                    decoration: BoxDecoration(
                      color: focused ? theme.shell.selected : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: EmojiImage(
                        url: choice.url,
                        size: 25,
                        alt: ':${choice.code}:',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({
    required this.icon,
    required this.message,
    this.liveRegion = false,
    this.action,
  });

  final DIconData icon;
  final String message;
  final bool liveRegion;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: liveRegion,
    label: message,
    child: ExcludeSemantics(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DIcon(
                icon,
                size: 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (action case final action?) ...[
                const SizedBox(height: 12),
                action,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

@immutable
class _EmojiChoice {
  const _EmojiChoice({required this.emoji, required this.tone});

  final SiteEmoji emoji;
  final EmojiSkinTone tone;

  String get code => emoji.codeFor(tone);
  String get url => emoji.urlFor(tone);
}

@immutable
class _GridPosition {
  const _GridPosition({required this.visualRow, required this.column});

  final int visualRow;
  final int column;
}

@immutable
class _PickerGroup {
  const _PickerGroup({
    required this.id,
    required this.label,
    required this.choices,
  });

  final String id;
  final String label;
  final List<_EmojiChoice> choices;
}

String _cellKey(String section, int index, String code) =>
    '$section-$index-$code';

String _groupLabel(String id) => switch (id) {
  'smileys_&_emotion' => 'Smileys & emotion',
  'people_&_body' => 'People & body',
  'animals_&_nature' => 'Animals & nature',
  'food_&_drink' => 'Food & drink',
  'travel_&_places' => 'Travel & places',
  'activities' => 'Activities',
  'objects' => 'Objects',
  'symbols' => 'Symbols',
  'flags' => 'Flags',
  'default' || 'custom' => 'Custom emojis',
  _ => id,
};

DIconData _groupIcon(String id) => switch (id) {
  _frequentGroup => DIcons.farClock,
  'smileys_&_emotion' => DIcons.farFaceSmile,
  'people_&_body' => DIcons.hand,
  'animals_&_nature' => DIcons.heart,
  'food_&_drink' ||
  'travel_&_places' ||
  'activities' ||
  'objects' ||
  'symbols' => DIcons.globe,
  'flags' => DIcons.flag,
  _ => DIcons.layerGroup,
};

String _toneLabel(EmojiSkinTone tone) => switch (tone) {
  EmojiSkinTone.neutral => 'Neutral',
  EmojiSkinTone.t2 => 'Light',
  EmojiSkinTone.t3 => 'Medium-light',
  EmojiSkinTone.t4 => 'Medium',
  EmojiSkinTone.t5 => 'Medium-dark',
  EmojiSkinTone.t6 => 'Dark',
};
