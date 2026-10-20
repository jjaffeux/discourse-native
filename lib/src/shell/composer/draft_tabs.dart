import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../theme/d_icons.dart';
import '../shell_controller.dart';
import '../shell_scope.dart';
import 'controller.dart';
import 'discard.dart';
import 'presentation.dart';

String composerDraftLabel(ComposerController composer) =>
    composer.target.createsTopic
    ? (composer.title.text.trim().isEmpty
          ? composer.target.topicTitle
          : composer.title.text.trim())
    : composer.target.topicTitle;

/// Open draft tabs borrow the live, account-scoped editors from the shell.
class ComposerDraftTabs extends StatefulWidget {
  const ComposerDraftTabs({super.key, required this.composer});
  final ComposerController composer;
  @override
  State<ComposerDraftTabs> createState() => _ComposerDraftTabsState();
}

class _ComposerDraftTabsState extends State<ComposerDraftTabs> {
  static const _tabWidth = 170.0;
  static const _tabGap = 6.0;
  final _scroll = ScrollController();
  final _tabs = <ComposerController, _DraftTabFocus>{};
  late final _traversal = _DraftTabTraversalPolicy(
    _moveFocus,
    () => _focusOrder,
  );
  List<ComposerController> _drafts = const [];
  ComposerController? _revealedComposer;
  List<FocusNode> _focusOrder = const [];
  int _revealGeneration = 0;
  ({FocusNode source, FocusNode target})? _pendingTraversal;
  double _viewportWidth = 0;
  ({int first, int last}) _window = (first: 0, last: -1);
  bool _focusRebuildScheduled = false;

  ComposerController get composer => widget.composer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
  }

  ({int first, int last}) _windowFor(double offset, double width) {
    if (_drafts.isEmpty) return (first: 0, last: -1);
    const cacheExtent = 250.0;
    const step = _tabWidth + _tabGap;
    return (
      first: ((offset - cacheExtent) / step)
          .floor()
          .clamp(0, _drafts.length - 1)
          .toInt(),
      last: ((offset + width + cacheExtent) / step)
          .floor()
          .clamp(0, _drafts.length - 1)
          .toInt(),
    );
  }

  void _scrolled() {
    final next = _windowFor(_scroll.offset, _viewportWidth);
    if (next != _window) setState(() => _window = next);
  }

  void _focusChanged(ComposerController draft) {
    if (!_focusRebuildScheduled) {
      _focusRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusRebuildScheduled = false;
        if (mounted) setState(() {});
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    final tab = _tabs[draft];
    if (tab != null &&
        (tab.selection.hasPrimaryFocus || tab.close.hasPrimaryFocus)) {
      _reveal(draft);
    }
  }

  FocusNode _navigationOrigin(FocusNode current) {
    final pending = _pendingTraversal;
    return pending != null && identical(pending.source, current)
        ? pending.target
        : current;
  }

  bool _moveFocus(FocusNode current, bool forward) {
    final index = _focusOrder.indexOf(_navigationOrigin(current));
    if (index < 0) return false;
    final next = index + (forward ? 1 : -1);
    if (next < 0 || next >= _focusOrder.length) return false;
    _reveal(
      _drafts[next ~/ 2],
      navigation: (source: current, target: _focusOrder[next]),
    );
    return true;
  }

  void _reveal(
    ComposerController draft, {
    ({FocusNode source, FocusNode target})? navigation,
  }) {
    if (navigation != null && navigation.target.context?.mounted == true) {
      navigation.target.requestFocus();
      _reveal(draft);
      return;
    }
    _pendingTraversal = navigation;
    final generation = ++_revealGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _revealGeneration || !_scroll.hasClients) {
        return;
      }
      if (navigation != null &&
          !identical(FocusManager.instance.primaryFocus, navigation.source)) {
        _pendingTraversal = null;
        return;
      }
      final index = _drafts.indexOf(draft);
      if (index < 0) {
        _pendingTraversal = null;
        return;
      }
      final position = _scroll.position;
      final start = index * (_tabWidth + _tabGap);
      final end = start + _tabWidth;
      final offset = start < position.pixels
          ? start
          : end > position.pixels + position.viewportDimension
          ? end - position.viewportDimension
          : position.pixels;
      final targetOffset = offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (targetOffset != position.pixels) _scroll.jumpTo(targetOffset);
      if (navigation == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _revealGeneration) return;
        _pendingTraversal = null;
        if (identical(FocusManager.instance.primaryFocus, navigation.source) &&
            _drafts.contains(draft) &&
            _focusOrder.contains(navigation.target) &&
            navigation.target.context?.mounted == true) {
          navigation.target.requestFocus();
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final tab in _tabs.values) {
      tab.dispose();
    }
    _tabs.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell, shell.draftList]),
      builder: (context, _) {
        final site = composer.target.siteUrl;
        final drafts = shell.liveComposers
            .where((c) => c.target.siteUrl == site && c.canSaveDraft)
            .toList();
        final revealSelected =
            !identical(_revealedComposer, composer) ||
            !listEquals(_drafts, drafts);
        _revealedComposer = composer;
        _drafts = List.unmodifiable(drafts);
        for (final draft in drafts) {
          _tabs.putIfAbsent(
            draft,
            () => _DraftTabFocus(() => _focusChanged(draft)),
          );
        }
        _focusOrder = [
          for (final draft in drafts) ...[
            _tabs[draft]!.selection,
            _tabs[draft]!.close,
          ],
        ];
        for (final entry in _tabs.entries.toList()) {
          if (drafts.contains(entry.key)) continue;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                !_drafts.contains(entry.key) &&
                identical(_tabs[entry.key], entry.value)) {
              _tabs.remove(entry.key);
              entry.value.dispose();
            }
          });
        }
        if (revealSelected) _reveal(composer);
        final instance = shell.currentInstance;
        final feed = shell.draftList.feedFor(site);
        return FocusTraversalGroup(
          policy: _traversal,
          child: Row(
            children: [
              DDropdownMenu(
                onOpenChange: (open, _) {
                  if (open && instance?.url == site) {
                    unawaited(shell.draftList.load(instance!, refresh: true));
                  }
                },
                content: DDropdownMenuContent(
                  semanticLabel: context.l10n.allDrafts,
                  children: [
                    for (final draft in drafts)
                      DDropdownMenuItem(
                        leading: const DIcon(DIcons.pen),
                        onPressed: () => shell.selectComposer(draft),
                        child: Text(composerDraftLabel(draft)),
                      ),
                    for (final draft in feed.drafts.where(
                      (d) => !drafts.any((c) => c.target.draftKey == d.key),
                    ))
                      DDropdownMenuItem(
                        onPressed: draft.canResume
                            ? () => unawaited(shell.resumeDraft(site, draft))
                            : null,
                        child: Text(draft.displayTitle),
                      ),
                    if (feed.loading)
                      DDropdownMenuLabel(
                        child: Text(
                          context.l10n.loadingDraftsTopiccreatebutton,
                        ),
                      ),
                    if (feed.error != null)
                      DDropdownMenuItem(
                        onPressed: () => unawaited(
                          shell.draftList.load(instance!, refresh: true),
                        ),
                        child: Text(context.l10n.couldnTLoadDrafts),
                      ),
                    const DDropdownMenuSeparator(),
                    DDropdownMenuItem(
                      onPressed: () {
                        ComposerPresentationHost.redockForNavigation(context);
                        shell.openDrafts(site);
                      },
                      child: Text(context.l10n.allDrafts),
                    ),
                  ],
                ),
                child: DDropdownMenuTrigger(
                  builder: (context, trigger) => DButton.iconOnly(
                    key: const ValueKey('composer-all-drafts'),
                    icon: const DIcon(DIcons.chevronDown),
                    tooltip: context.l10n.allDrafts,
                    hasPopup: true,
                    expanded: trigger.open,
                    focusNode: trigger.focusNode,
                    size: DControlSize.toolbar,
                    shape: DButtonShape.pill,
                    variant: DButtonVariant.ghost,
                    onPressed: trigger.toggle,
                  ),
                ),
              ),
              const SizedBox(width: DSpacing.controlGap),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final resized = _viewportWidth != constraints.maxWidth;
                    _viewportWidth = constraints.maxWidth;
                    if (resized) _reveal(composer);
                    _window = _windowFor(
                      _scroll.hasClients ? _scroll.offset : 0,
                      _viewportWidth,
                    );
                    final indices = {
                      if (drafts.isNotEmpty) 0,
                      for (
                        var index = _window.first;
                        index <= _window.last;
                        index++
                      )
                        index,
                      for (var index = 0; index < drafts.length; index++)
                        if (_tabs[drafts[index]]!.selection.hasFocus ||
                            _tabs[drafts[index]]!.close.hasFocus)
                          index,
                      if (drafts.length > 1) drafts.length - 1,
                    }.toList()..sort();
                    return SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (position, index) in indices.indexed) ...[
                            if (position > 0)
                              SizedBox(
                                width:
                                    (index - indices[position - 1]) *
                                        (_tabWidth + _tabGap) -
                                    _tabWidth,
                              ),
                            _tab(context, shell, drafts[index]),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tab(
    BuildContext context,
    ShellController shell,
    ComposerController draft,
  ) => SizedBox(
    key: ObjectKey(draft),
    width: _tabWidth,
    child: DDocumentTab(
      key: _tabs[draft]!.key,
      selected: identical(draft, composer),
      selectionFocusNode: _tabs[draft]!.selection,
      closeFocusNode: _tabs[draft]!.close,
      size: DControlSize.documentTab,
      onSelect: () => shell.selectComposer(draft),
      onClose: () => unawaited(
        saveComposerFromPanel(
          context: context,
          composer: draft,
          controller: shell,
        ),
      ),
      closeLabel: context.l10n.saveAndClose,
      closeKey: ValueKey(('composer-draft-close', draft)),
      child: Text(
        composerDraftLabel(draft),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

class _DraftTabFocus {
  _DraftTabFocus(VoidCallback onFocus) {
    selection.addListener(onFocus);
    close.addListener(onFocus);
  }

  final key = GlobalKey();
  final selection = FocusNode();
  final close = FocusNode();

  void dispose() {
    selection.dispose();
    close.dispose();
  }
}

class _DraftTabTraversalPolicy extends WidgetOrderTraversalPolicy {
  _DraftTabTraversalPolicy(this.move, this.order);
  final bool Function(FocusNode, bool) move;
  final List<FocusNode> Function() order;

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final nodes = order();
    final present = descendants.toSet();
    return [
      for (final node in descendants)
        if (!nodes.contains(node)) node,
      for (final node in nodes)
        if (present.contains(node)) node,
    ];
  }

  @override
  bool next(FocusNode currentNode) =>
      move(currentNode, true) || super.next(currentNode);

  @override
  bool previous(FocusNode currentNode) =>
      move(currentNode, false) || super.previous(currentNode);
}
