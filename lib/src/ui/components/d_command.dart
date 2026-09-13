import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/interactive_row.dart';
import '../foundation/tokens.dart';
import 'd_dialog.dart';
import 'd_input.dart';
import 'd_scroll_area.dart';

/// Returns a relevance score from zero (hidden) to one (best match).
typedef DCommandFilter =
    double Function(String value, String query, List<String> keywords);

/// Query, highlight, and imperative activation state for [DCommand].
///
/// A caller-created controller is borrowed and never disposed by the widget.
/// It can attach to one mounted command at a time. Text editing state belongs
/// to [DCommandInput]'s independently owned or borrowed editing controller.
class DCommandController<T> extends ChangeNotifier {
  DCommandController({String initialQuery = '', T? initialValue})
    : _query = initialQuery,
      _value = initialValue;

  String _query;
  T? _value;
  bool _disposed = false;
  Object? _attachment;
  List<_DCommandEntry<T>> _entries = const [];
  final Set<Object> _composingInputs = {};
  ValueChanged<T>? _activate;
  ValueChanged<String>? _queryRequest;
  ValueChanged<T?>? _valueRequest;

  String get query => _query;
  T? get value => _value;

  void updateQuery(String query) {
    final request = _queryRequest;
    if (request == null) {
      _setQuery(query);
    } else {
      request(query);
    }
  }

  void highlight(T? value) {
    final request = _valueRequest;
    if (request == null) {
      _setValue(value);
    } else {
      request(value);
    }
  }

  /// Activates [value], or the currently highlighted item when omitted.
  void activate([T? value]) {
    final target = value ?? _value;
    if (target != null) _activate?.call(target);
  }

  void _attach(
    Object attachment, {
    required ValueChanged<String> queryRequest,
    required ValueChanged<T?> valueRequest,
    required ValueChanged<T> activate,
  }) {
    assert(
      _attachment == null || identical(_attachment, attachment),
      'A DCommandController can attach to only one DCommand at a time.',
    );
    _attachment = attachment;
    _queryRequest = queryRequest;
    _valueRequest = valueRequest;
    _activate = activate;
  }

  void _detach(Object attachment) {
    if (!identical(_attachment, attachment)) return;
    _attachment = null;
    _queryRequest = null;
    _valueRequest = null;
    _activate = null;
    _entries = const [];
    _composingInputs.clear();
  }

  void _setQuery(String query) {
    if (_query == query) return;
    _query = query;
    if (!_disposed) notifyListeners();
  }

  void _setValue(T? value) {
    if (_value == value) return;
    _value = value;
    if (!_disposed) notifyListeners();
  }

  void _setEntries(List<_DCommandEntry<T>> entries) {
    _entries = entries;
  }

  bool get _isComposing => _composingInputs.isNotEmpty;

  void _setInputComposing(Object input, bool composing) {
    if (composing) {
      _composingInputs.add(input);
    } else {
      _composingInputs.remove(input);
    }
  }

  void _selectEntry(_DCommandEntry<T> entry) {
    _valueRequest?.call(entry.value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = entry.key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : DMotion.change,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _move(int delta, {required bool loop}) {
    if (_entries.isEmpty) return;
    var index = _entries.indexWhere((entry) => entry.value == _value);
    if (index < 0) {
      index = delta < 0 ? _entries.length : -1;
    }
    var next = index + delta;
    if (loop) {
      next %= _entries.length;
    } else {
      next = next.clamp(0, _entries.length - 1);
    }
    _selectEntry(_entries[next]);
  }

  void _moveToBoundary({required bool last}) {
    if (_entries.isEmpty) return;
    _selectEntry(last ? _entries.last : _entries.first);
  }

  void _moveGroup(int delta, {required bool loop}) {
    final currentIndex = _entries.indexWhere((entry) => entry.value == _value);
    if (currentIndex < 0 || _entries[currentIndex].group == null) {
      _move(delta, loop: loop);
      return;
    }
    final groups = <Object>[];
    for (final entry in _entries) {
      final group = entry.group;
      if (group != null && !groups.contains(group)) groups.add(group);
    }
    final currentGroup = groups.indexOf(_entries[currentIndex].group!);
    final targetGroup = currentGroup + delta;
    if (targetGroup < 0 || targetGroup >= groups.length) {
      _move(delta, loop: loop);
      return;
    }
    _selectEntry(
      _entries.firstWhere((entry) => entry.group == groups[targetGroup]),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _attachment = null;
    _entries = const [];
    _composingInputs.clear();
    super.dispose();
  }
}

/// A searchable command surface with Flutter-native input and focus behavior.
///
/// [query] and [value] make their respective state controlled. Otherwise the
/// root owns it, seeded by [initialQuery] and [initialValue]. Arrow navigation
/// keeps the editable input focused so selection, composition, and IME state
/// remain native. [controller] is borrowed; an omitted controller is owned.
class DCommand<T> extends StatefulWidget {
  const DCommand({
    super.key,
    required this.child,
    this.controller,
    this.query,
    this.initialQuery = '',
    this.onQueryChanged,
    this.value,
    this.initialValue,
    this.onValueChanged,
    this.onSelected,
    this.filter,
    this.shouldFilter = true,
    this.loop = false,
    this.vimBindings = true,
    this.disablePointerSelection = false,
    this.loading = false,
    this.onEscape,
    this.semanticLabel = 'Commands',
    this.outlined = false,
  }) : assert(query == null || initialQuery == ''),
       assert(value == null || initialValue == null);

  final Widget child;
  final DCommandController<T>? controller;
  final String? query;
  final String initialQuery;
  final ValueChanged<String>? onQueryChanged;
  final T? value;
  final T? initialValue;
  final ValueChanged<T?>? onValueChanged;
  final ValueChanged<T>? onSelected;
  final DCommandFilter? filter;
  final bool shouldFilter;
  final bool loop;
  final bool vimBindings;
  final bool disablePointerSelection;
  final bool loading;
  final VoidCallback? onEscape;
  final String semanticLabel;
  final bool outlined;

  @override
  State<DCommand<T>> createState() => _DCommandState<T>();
}

class _DCommandState<T> extends State<DCommand<T>> {
  final Object _attachment = Object();
  late DCommandController<T> _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        DCommandController<T>(
          initialQuery: widget.query ?? widget.initialQuery,
          initialValue: widget.value ?? widget.initialValue,
        );
    _attach();
    _syncControlled();
  }

  void _attach() => _controller._attach(
    _attachment,
    queryRequest: _changeQuery,
    valueRequest: _changeValue,
    activate: _activate,
  );

  @override
  void didUpdateWidget(DCommand<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller._detach(_attachment);
      if (oldWidget.controller == null) _controller.dispose();
      _controller =
          widget.controller ??
          DCommandController<T>(
            initialQuery: widget.query ?? _controller.query,
            initialValue: widget.value ?? _controller.value,
          );
      _attach();
    }
    _syncControlled();
  }

  void _syncControlled() {
    if (widget.query != null) _controller._setQuery(widget.query!);
    if (widget.value != null) _controller._setValue(widget.value);
  }

  void _changeQuery(String query) {
    _controller._setQuery(query);
    widget.onQueryChanged?.call(query);
  }

  void _changeValue(T? value) {
    _controller._setValue(value);
    widget.onValueChanged?.call(value);
  }

  void _activate(T value) {
    final entry = _controller._entries
        .where((entry) => entry.value == value)
        .firstOrNull;
    if (entry == null || !entry.enabled) return;
    _changeValue(value);
    entry.onSelected?.call(value);
    widget.onSelected?.call(value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_controller._isComposing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        (widget.vimBindings &&
            keyboard.isControlPressed &&
            (key == LogicalKeyboardKey.keyN ||
                key == LogicalKeyboardKey.keyJ))) {
      if (keyboard.isMetaPressed) {
        _controller._moveToBoundary(last: true);
      } else if (keyboard.isAltPressed) {
        _controller._moveGroup(1, loop: widget.loop);
      } else {
        _controller._move(1, loop: widget.loop);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        (widget.vimBindings &&
            keyboard.isControlPressed &&
            (key == LogicalKeyboardKey.keyP ||
                key == LogicalKeyboardKey.keyK))) {
      if (keyboard.isMetaPressed) {
        _controller._moveToBoundary(last: false);
      } else if (keyboard.isAltPressed) {
        _controller._moveGroup(-1, loop: widget.loop);
      } else {
        _controller._move(-1, loop: widget.loop);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _controller._moveToBoundary(last: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _controller._moveToBoundary(last: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final value = _controller.value;
      if (value == null ||
          !_controller._entries.any((entry) => entry.value == value)) {
        return KeyEventResult.ignored;
      }
      _controller.activate(value);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && widget.onEscape != null) {
      widget.onEscape!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final radius = BorderRadius.circular(tokens.radius * 1.4);
    return _DCommandScope<T>(
      controller: _controller,
      filter: widget.filter ?? _defaultCommandFilter,
      shouldFilter: widget.shouldFilter,
      loading: widget.loading,
      disablePointerSelection: widget.disablePointerSelection,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: widget.semanticLabel,
          child: Material(
            animationDuration: Duration.zero,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: widget.outlined
                  ? BorderSide(color: tokens.border)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(DSpacing.xs),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller._detach(_attachment);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }
}

double _defaultCommandFilter(
  String value,
  String query,
  List<String> keywords,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return 1;
  if (value.toLowerCase() == needle) return 1;
  final haystack = [
    value,
    ...keywords,
  ].where((part) => part.isNotEmpty).join(' ').toLowerCase();
  if (haystack == needle) return 1;
  if (haystack.startsWith(needle)) return .9;
  if (haystack.contains(needle)) return .7;
  final tokens = needle.split(RegExp(r'\s+'));
  return tokens.every(haystack.contains) ? .5 : 0;
}

class _DCommandScope<T> extends InheritedWidget {
  const _DCommandScope({
    required this.controller,
    required this.filter,
    required this.shouldFilter,
    required this.loading,
    required this.disablePointerSelection,
    required super.child,
  });

  final DCommandController<T> controller;
  final DCommandFilter filter;
  final bool shouldFilter;
  final bool loading;
  final bool disablePointerSelection;

  static _DCommandScope<T> of<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DCommandScope<T>>();
    assert(scope != null, 'Command parts must be below DCommand<$T>.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DCommandScope<T> oldWidget) =>
      controller != oldWidget.controller ||
      filter != oldWidget.filter ||
      shouldFilter != oldWidget.shouldFilter ||
      loading != oldWidget.loading ||
      disablePointerSelection != oldWidget.disablePointerSelection;
}

/// The native editable query field. Borrowed editing resources are not disposed.
class DCommandInput<T> extends StatefulWidget {
  const DCommandInput({
    super.key,
    this.placeholder = 'Type a command or search...',
    this.controller,
    this.focusNode,
    this.autofocus = true,
    this.enabled = true,
    this.semanticLabel = 'Search commands',
  });

  final String placeholder;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final String semanticLabel;

  @override
  State<DCommandInput<T>> createState() => _DCommandInputState<T>();
}

class _DCommandInputState<T> extends State<DCommandInput<T>> {
  final Object _attachment = Object();
  TextEditingController? _owned;
  DCommandController<T>? _commandController;
  bool _syncing = false;
  TextEditingController get _editing => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _owned = TextEditingController();
    _editing.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _DCommandScope.of<T>(context).controller;
    if (!identical(controller, _commandController)) {
      _commandController?._setInputComposing(_attachment, false);
      _commandController = controller;
    }
    _syncComposing();
    final query = controller.query;
    if (_editing.text != query) _replace(query);
  }

  @override
  void didUpdateWidget(DCommandInput<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller ?? _owned!;
      final value = old.value;
      old.removeListener(_changed);
      if (widget.controller == null) {
        _owned = TextEditingController.fromValue(value);
      } else {
        _owned?.dispose();
        _owned = null;
      }
      _editing.addListener(_changed);
    }
  }

  void _replace(String text) {
    _syncing = true;
    _editing.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
    _syncComposing();
  }

  void _changed() {
    if (!_syncing && mounted) {
      _syncComposing();
      final controller = _commandController!;
      if (_editing.text != controller.query) {
        controller.updateQuery(_editing.text);
      }
    }
  }

  void _syncComposing() {
    _commandController?._setInputComposing(
      _attachment,
      _editing.value.isComposingRangeValid,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = _DCommandScope.of<T>(context);
    return AnimatedBuilder(
      animation: scope.controller,
      builder: (context, _) {
        if (_editing.text != scope.controller.query) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _editing.text != scope.controller.query) {
              _replace(scope.controller.query);
            }
          });
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: DSpacing.xs),
          child: DInput(
            controller: _editing,
            focusNode: widget.focusNode,
            semanticLabel: widget.semanticLabel,
            hintText: widget.placeholder,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            suffix: ExcludeSemantics(
              child: DIcon(
                DIcons.magnifyingGlass,
                size: 16,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _commandController?._setInputComposing(_attachment, false);
    _editing.removeListener(_changed);
    _owned?.dispose();
    super.dispose();
  }
}

/// Scrollable result composition. Children may be groups, items, separators,
/// empty states, or loading states. Filtering and sorting happen here.
class DCommandList<T> extends StatefulWidget {
  const DCommandList({
    super.key,
    required this.children,
    this.controller,
    this.maxHeight = 288,
    this.semanticLabel = 'Command results',
  }) : assert(maxHeight > 0);

  final List<Widget> children;
  final ScrollController? controller;
  final double maxHeight;
  final String semanticLabel;

  @override
  State<DCommandList<T>> createState() => _DCommandListState<T>();
}

class _DCommandListState<T> extends State<DCommandList<T>> {
  ScrollController? _owned;
  final Map<Object, GlobalKey> _itemKeys = {};
  ScrollController get _scroll => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _owned = ScrollController();
  }

  @override
  void didUpdateWidget(DCommandList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final oldOffset = (oldWidget.controller ?? _owned!).hasClients
          ? (oldWidget.controller ?? _owned!).offset
          : 0.0;
      _owned?.dispose();
      _owned = widget.controller == null
          ? ScrollController(initialScrollOffset: oldOffset)
          : null;
    }
  }

  List<_DScoredItem<T>> _score(
    Iterable<DCommandItem<T>> items,
    _DCommandScope<T> scope,
  ) {
    final query = scope.controller.query;
    final result = <_DScoredItem<T>>[];
    var order = 0;
    for (final item in items) {
      final score =
          !scope.shouldFilter || query.trim().isEmpty || item.forceMount
          ? 1.0
          : scope.filter(
              item.effectiveSearchValue.trim(),
              query,
              item.keywords
                  .map((keyword) => keyword.trim())
                  .toList(growable: false),
            );
      if (score > 0) {
        result.add(_DScoredItem(item, score, order));
      }
      order++;
    }
    if (scope.shouldFilter && query.trim().isNotEmpty) {
      result.sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.order.compareTo(b.order) : score;
      });
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _DCommandScope.of<T>(context);
    return AnimatedBuilder(
      animation: scope.controller,
      builder: (context, _) {
        final resultNodes = <_DResultNode<T>>[];
        final emptyNodes = <DCommandEmpty>[];
        final loadingNodes = <DCommandLoading>[];
        for (final child in widget.children) {
          if (child is DCommandGroup<T>) {
            final items = _score(child.items, scope);
            if (items.isNotEmpty || child.forceMount) {
              resultNodes.add(_DGroupNode(child, items));
            }
          } else if (child is DCommandItem<T>) {
            final items = _score([child], scope);
            if (items.isNotEmpty) resultNodes.add(_DItemNode(items.single));
          } else if (child is DCommandSeparator<T>) {
            if (child.alwaysRender || scope.controller.query.isEmpty) {
              resultNodes.add(_DSeparatorNode(child));
            }
          } else if (child is DCommandEmpty) {
            emptyNodes.add(child);
          } else if (child is DCommandLoading) {
            loadingNodes.add(child);
          } else {
            assert(
              false,
              'Unsupported DCommandList child: ${child.runtimeType}',
            );
          }
        }
        while (resultNodes.isNotEmpty &&
            resultNodes.first is _DSeparatorNode<T>) {
          resultNodes.removeAt(0);
        }
        while (resultNodes.isNotEmpty &&
            resultNodes.last is _DSeparatorNode<T>) {
          resultNodes.removeLast();
        }
        for (var index = resultNodes.length - 2; index >= 0; index--) {
          if (resultNodes[index] is _DSeparatorNode<T> &&
              resultNodes[index + 1] is _DSeparatorNode<T>) {
            resultNodes.removeAt(index);
          }
        }
        final entries = <_DCommandEntry<T>>[];
        for (final node in resultNodes) {
          final group = node is _DGroupNode<T> ? node.group : null;
          for (final scored in node.items) {
            final identity = scored.item.identity;
            final key = _itemKeys.putIfAbsent(identity, GlobalKey.new);
            entries.add(
              _DCommandEntry(
                value: scored.item.value,
                enabled: scored.item.enabled,
                onSelected: scored.item.onSelected,
                key: key,
                group: group,
              ),
            );
          }
        }
        final enabledEntries = entries
            .where((entry) => entry.enabled)
            .toList(growable: false);
        scope.controller._setEntries(enabledEntries);
        if ((enabledEntries.isNotEmpty || scope.controller.value != null) &&
            !enabledEntries.any(
              (entry) => entry.value == scope.controller.value,
            )) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              scope.controller.highlight(
                scope.controller._entries.firstOrNull?.value,
              );
            }
          });
        }
        final rendered = <Widget>[];
        if (scope.loading) rendered.addAll(loadingNodes);
        if (entries.isEmpty && !scope.loading) rendered.addAll(emptyNodes);
        if (!scope.loading || entries.isNotEmpty) {
          for (final node in resultNodes) {
            rendered.add(node.build(context, scope, _itemKeys));
          }
        }
        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: widget.semanticLabel,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: DScrollBar(
              controller: _scroll,
              thumbVisibility: false,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: DSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rendered,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }
}

sealed class _DResultNode<T> {
  const _DResultNode();
  Iterable<_DScoredItem<T>> get items;
  Widget build(
    BuildContext context,
    _DCommandScope<T> scope,
    Map<Object, GlobalKey> keys,
  );
}

class _DGroupNode<T> extends _DResultNode<T> {
  const _DGroupNode(this.group, this.scored);
  final DCommandGroup<T> group;
  final List<_DScoredItem<T>> scored;
  @override
  Iterable<_DScoredItem<T>> get items => scored;
  @override
  Widget build(
    BuildContext context,
    _DCommandScope<T> scope,
    Map<Object, GlobalKey> keys,
  ) => Padding(
    padding: const EdgeInsets.all(DSpacing.xs),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group.heading != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: DiscourseTypography.xs,
                fontWeight: FontWeight.w500,
                color: DTokens.of(context).mutedForeground,
              ),
              child: group.heading!,
            ),
          ),
        for (final item in scored)
          KeyedSubtree(
            key: item.item.key,
            child: _DCommandItemSurface<T>(
              key: keys[item.item.identity],
              item: item.item,
              scope: scope,
            ),
          ),
      ],
    ),
  );
}

class _DItemNode<T> extends _DResultNode<T> {
  const _DItemNode(this.scored);
  final _DScoredItem<T> scored;
  @override
  Iterable<_DScoredItem<T>> get items => [scored];
  @override
  Widget build(
    BuildContext context,
    _DCommandScope<T> scope,
    Map<Object, GlobalKey> keys,
  ) => KeyedSubtree(
    key: scored.item.key,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: DSpacing.xs),
      child: _DCommandItemSurface<T>(
        key: keys[scored.item.identity],
        item: scored.item,
        scope: scope,
      ),
    ),
  );
}

class _DSeparatorNode<T> extends _DResultNode<T> {
  const _DSeparatorNode(this.separator);
  final DCommandSeparator<T> separator;
  @override
  Iterable<_DScoredItem<T>> get items => const [];
  @override
  Widget build(
    BuildContext context,
    _DCommandScope<T> scope,
    Map<Object, GlobalKey> keys,
  ) => Divider(
    height: 1,
    thickness: 1,
    color: separator.color ?? DTokens.of(context).border,
  );
}

class _DScoredItem<T> {
  const _DScoredItem(this.item, this.score, this.order);
  final DCommandItem<T> item;
  final double score;
  final int order;
}

class _DCommandEntry<T> {
  const _DCommandEntry({
    required this.value,
    required this.enabled,
    required this.onSelected,
    required this.key,
    required this.group,
  });
  final T value;
  final bool enabled;
  final ValueChanged<T>? onSelected;
  final GlobalKey key;
  final Object? group;
}

/// A labelled result group. Filtering hides empty groups unless [forceMount].
class DCommandGroup<T> extends StatelessWidget {
  const DCommandGroup({
    super.key,
    required this.items,
    this.heading,
    this.forceMount = false,
  });
  final Widget? heading;
  final List<DCommandItem<T>> items;
  final bool forceMount;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A command row. [searchValue] defaults to `value.toString()` because Flutter
/// cannot reliably extract searchable text from an arbitrary child widget.
class DCommandItem<T> extends StatelessWidget {
  const DCommandItem({
    super.key,
    required this.value,
    required this.child,
    this.searchValue,
    this.keywords = const [],
    this.leading,
    this.trailing,
    this.enabled = true,
    this.destructive = false,
    this.checked = false,
    this.forceMount = false,
    this.onSelected,
    this.semanticLabel,
  });

  final T value;
  final Widget child;
  final String? searchValue;
  final List<String> keywords;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;
  final bool destructive;
  final bool checked;
  final bool forceMount;
  final ValueChanged<T>? onSelected;
  final String? semanticLabel;
  String get effectiveSearchValue => searchValue ?? value.toString();
  Object get identity => key ?? value as Object;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DCommandItemSurface<T> extends StatefulWidget {
  const _DCommandItemSurface({
    super.key,
    required this.item,
    required this.scope,
  });
  final DCommandItem<T> item;
  final _DCommandScope<T> scope;
  @override
  State<_DCommandItemSurface<T>> createState() =>
      _DCommandItemSurfaceState<T>();
}

class _DCommandItemSurfaceState<T> extends State<_DCommandItemSurface<T>> {
  bool _focused = false;

  void _activate() {
    if (widget.item.enabled) {
      widget.scope.controller.activate(widget.item.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tokens = DTokens.of(context);
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    return AnimatedBuilder(
      animation: widget.scope.controller,
      builder: (context, _) {
        final selected = widget.scope.controller.value == item.value;
        final interactive = item.enabled && selected;
        final radius = BorderRadius.circular(tokens.radius);
        Widget row = interactiveRowSurface(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: interactive ? tokens.muted : Colors.transparent,
            borderRadius: radius,
            border:
                _focused && interactive && DFocusHighlight.visibleOf(context)
                ? Border.all(color: tokens.focusRing, width: 2)
                : null,
          ),
          child: IconTheme(
            data: IconThemeData(
              size: 16,
              color: interactive ? tokens.foreground : tokens.mutedForeground,
            ),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: DiscourseTypography.sm,
                height: 20 / 14,
                color: item.destructive
                    ? tokens.destructive
                    : tokens.foreground,
              ),
              child: Row(
                children: [
                  if (item.leading != null) ...[
                    item.leading!,
                    const SizedBox(width: DSpacing.sm),
                  ],
                  Expanded(child: item.child),
                  if (item.trailing != null) ...[
                    const SizedBox(width: DSpacing.sm),
                    item.trailing!,
                  ] else if (item.checked)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: DSpacing.sm),
                      child: Icon(Icons.check, size: 16),
                    ),
                ],
              ),
            ),
          ),
        );
        if (touch) {
          row = SizedBox(
            height: DSpacing.touchTarget,
            child: Center(child: row),
          );
        }
        return Semantics(
          button: true,
          selected: selected,
          checked: item.checked ? true : null,
          enabled: item.enabled,
          label: item.semanticLabel,
          excludeSemantics: item.semanticLabel != null,
          onTap: item.enabled ? _activate : null,
          child: FocusableActionDetector(
            enabled: item.enabled,
            mouseCursor: item.enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onShowHoverHighlight: (value) {
              if (value && !widget.scope.disablePointerSelection) {
                widget.scope.controller.highlight(item.value);
              }
            },
            onShowFocusHighlight: (value) {
              setState(() => _focused = value);
              if (value) widget.scope.controller.highlight(item.value);
            },
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.scope.controller.activate();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: item.enabled ? _activate : null,
              child: Opacity(
                opacity: item.enabled ? 1 : .5,
                child: _DCommandItemVisualScope(selected: selected, child: row),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Trailing shortcut text with directional placement and selected-state color.
class DCommandShortcut extends StatelessWidget {
  const DCommandShortcut(this.child, {super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final selected =
        _DCommandItemVisualScope.maybeOf(context)?.selected ?? false;
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!.copyWith(
        fontSize: DiscourseTypography.xs,
        letterSpacing: 1.5,
        color: selected ? tokens.foreground : tokens.mutedForeground,
      ),
      child: child,
    );
  }
}

class _DCommandItemVisualScope extends InheritedWidget {
  const _DCommandItemVisualScope({
    required this.selected,
    required super.child,
  });

  final bool selected;

  static _DCommandItemVisualScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DCommandItemVisualScope>();

  @override
  bool updateShouldNotify(_DCommandItemVisualScope oldWidget) =>
      selected != oldWidget.selected;
}

/// A separator between visible command sections.
class DCommandSeparator<T> extends StatelessWidget {
  const DCommandSeparator({super.key, this.color, this.alwaysRender = false});
  final Color? color;

  /// Keeps the separator visible while a non-empty query is filtering results.
  final bool alwaysRender;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Rendered when filtering produces no enabled or disabled result rows.
class DCommandEmpty extends StatelessWidget {
  const DCommandEmpty({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: DSpacing.xl),
      child: Center(
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: DiscourseTypography.sm,
            color: DTokens.of(context).foreground,
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Rendered while the root's externally owned asynchronous load is active.
class DCommandLoading extends StatelessWidget {
  const DCommandLoading({
    super.key,
    required this.child,
    this.progress,
    this.semanticLabel = 'Loading…',
  }) : assert(progress == null || (progress >= 0 && progress <= 100));
  final Widget child;
  final double? progress;
  final String semanticLabel;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    role: progress == null
        ? SemanticsRole.loadingSpinner
        : SemanticsRole.progressBar,
    liveRegion: true,
    label: semanticLabel,
    value: progress == null ? null : '${progress!.round()}',
    minValue: progress == null ? null : '0',
    maxValue: progress == null ? null : '100',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
      child: Center(child: child),
    ),
  );
}

/// The reference Command/Dialog composition. Dialog owns modality and focus
/// restoration; the nested [DCommand] owns query, filtering, and selection.
class DCommandDialog<T> extends StatelessWidget {
  const DCommandDialog({
    super.key,
    required this.command,
    this.trigger,
    this.controller,
    this.open,
    this.initiallyOpen = false,
    this.onOpenChanged,
    this.title = 'Command Palette',
    this.description = 'Search for a command to run...',
    this.showCloseButton = false,
    this.maxWidth = 384,
    this.initialFocusNode,
    this.finalFocusNode,
  });

  final Widget command;
  final DDialogTrigger? trigger;
  final DDialogController<T>? controller;
  final bool? open;
  final bool initiallyOpen;
  final ValueChanged<DDialogChangeDetails<T>>? onOpenChanged;
  final String title;
  final String description;
  final bool showCloseButton;
  final double maxWidth;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  @override
  Widget build(BuildContext context) => DDialog<T>(
    controller: controller,
    open: open,
    initiallyOpen: initiallyOpen,
    onOpenChanged: onOpenChanged,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    trigger:
        trigger ?? DDialogTrigger(builder: (context, open) => const SizedBox()),
    content: DDialogContent(
      maxWidth: maxWidth,
      showCloseButton: showCloseButton,
      semanticLabel: '$title. $description',
      contentPadding: EdgeInsets.zero,
      verticalPadding: 0,
      spacing: 0,
      children: [command],
    ),
  );
}
