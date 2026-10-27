import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/app_text_scaler.dart';
import '../foundation/control_style.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/interactive_row.dart';
import '../foundation/surface_depth.dart';
import '../foundation/tokens.dart';
import '../foundation/touch_target.dart';
import 'd_button.dart';
import 'd_dialog.dart';
import 'd_filter_token.dart';
import 'd_input.dart';
import 'd_scroll_area.dart';
import 'd_sheet.dart';
import 'd_toggle.dart';

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
      _queryChanges = ValueNotifier(initialQuery),
      _value = initialValue;

  String _query;
  final ValueNotifier<String> _queryChanges;
  T? _value;
  bool _disposed = false;
  Object? _attachment;
  List<_DCommandEntry<T>> _entries = const [];
  final Set<Object> _composingInputs = {};
  ValueChanged<T>? _activate;
  KeyEventResult Function(KeyEvent)? _handleKey;
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

  /// Routes keys from an external editor without moving focus into the menu.
  /// Call before the editor's own shortcuts. IME composition stays with the
  /// editor; detached controllers never consume events.
  KeyEventResult handleKeyEvent(KeyEvent event, {bool isComposing = false}) =>
      isComposing
      ? KeyEventResult.ignored
      : _handleKey?.call(event) ?? KeyEventResult.ignored;

  void _attach(
    Object attachment, {
    required ValueChanged<String> queryRequest,
    required ValueChanged<T?> valueRequest,
    required ValueChanged<T> activate,
    required KeyEventResult Function(KeyEvent) handleKey,
  }) {
    assert(
      _attachment == null || identical(_attachment, attachment),
      'A DCommandController can attach to only one DCommand at a time.',
    );
    _attachment = attachment;
    _queryRequest = queryRequest;
    _valueRequest = valueRequest;
    _activate = activate;
    _handleKey = handleKey;
  }

  void _detach(Object attachment) {
    if (!identical(_attachment, attachment)) return;
    _attachment = null;
    _queryRequest = null;
    _valueRequest = null;
    _activate = null;
    _handleKey = null;
    _entries = const [];
    _composingInputs.clear();
  }

  void _setQuery(String query) {
    if (_query == query) return;
    _query = query;
    if (!_disposed) {
      _queryChanges.value = query;
      notifyListeners();
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) => entry.reveal());
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
    _handleKey = null;
    _entries = const [];
    _composingInputs.clear();
    _queryChanges.dispose();
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

    this.onQueryChanged,
    this.value,

    this.onValueChanged,
    this.onSelected,

    this.shouldFilter = true,
    this.loop = false,
    this.vimBindings = true,

    this.loading = false,
    this.onEscape,
    this._semanticLabel,
    this.outlined = false,
    this.backgroundColor,
    this.depth,
  });

  final Widget child;
  final DCommandController<T>? controller;
  final String? query;

  final ValueChanged<String>? onQueryChanged;
  final T? value;

  final ValueChanged<T?>? onValueChanged;
  final ValueChanged<T>? onSelected;

  final bool shouldFilter;
  final bool loop;
  final bool vimBindings;

  final bool loading;
  final VoidCallback? onEscape;
  final String? _semanticLabel;
  String get semanticLabel => _semanticLabel ?? appL10n.commands;
  final bool outlined;

  /// The background of the command surface and its results scrollbar.
  ///
  /// Defaults to transparent inside [DCommandDialog], where the overlay owns
  /// the surface, and [DTokens.surface] for an embedded command.
  final Color? backgroundColor;

  /// How an embedded command floats over what is under it. Null lies flat.
  final DSurfaceDepth? depth;

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
          initialQuery: widget.query ?? '',
          initialValue: widget.value,
        );
    _attach();
    _syncControlled();
  }

  void _attach() => _controller._attach(
    _attachment,
    queryRequest: _changeQuery,
    valueRequest: _changeValue,
    activate: _activate,
    handleKey: _handleKey,
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
    if (entry == null) return;
    _changeValue(value);
    entry.onSelected?.call(value);
    widget.onSelected?.call(value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Header actions such as token edit/remove buttons own their activation
    // keys. Let their Native shortcuts run before interpreting menu commands.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<DButton>() != null ||
        focused?.findAncestorWidgetOfExactType<DFilterToken>() != null ||
        focused?.findAncestorWidgetOfExactType<DToggle>() != null) {
      return KeyEventResult.ignored;
    }
    return _handleKey(event);
  }

  KeyEventResult _handleKey(KeyEvent event) {
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
    final radius = BorderRadius.circular(DRadius.panel);
    final inOverlay =
        context.dependOnInheritedWidgetOfExactType<_DCommandOverlayScope>() !=
        null;
    final backgroundColor =
        widget.backgroundColor ??
        (inOverlay ? Colors.transparent : tokens.surface);
    return _DCommandScope<T>(
      controller: _controller,
      shouldFilter: widget.shouldFilter,
      loading: widget.loading,

      backgroundColor: backgroundColor,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: widget.semanticLabel,
          child: CustomPaint(
            painter: switch (widget.depth) {
              final depth? => DSurfaceEdges.resolve(
                context,
                depth,
              ).castPainter(radius),
              null => null,
            },
            child: Material(
              animationDuration: Duration.zero,
              color: backgroundColor,
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

class _DCommandScope<T> extends InheritedWidget {
  const _DCommandScope({
    required this.controller,
    required this.shouldFilter,
    required this.loading,

    required this.backgroundColor,
    required super.child,
  });

  final DCommandController<T> controller;
  final bool shouldFilter;
  final bool loading;

  final Color backgroundColor;

  static _DCommandScope<T> of<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DCommandScope<T>>();
    assert(scope != null, 'Command parts must be below DCommand<$T>.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DCommandScope<T> oldWidget) =>
      (controller != oldWidget.controller ||
          shouldFilter != oldWidget.shouldFilter ||
          loading != oldWidget.loading) ||
      backgroundColor != oldWidget.backgroundColor;
}

/// Query geometry for ordinary command palettes and compact filter menus.
enum DCommandInputDensity { standard, menuFilter }

/// The native editable query field. Borrowed editing resources are not disposed.
class DCommandInput<T> extends StatefulWidget {
  const DCommandInput({
    super.key,
    this._placeholder,
    this.controller,
    this.focusNode,

    this.enabled = true,
    this.borderless = false,
    this.density = DCommandInputDensity.standard,
    this.tokens = const [],
    this.autofocus = true,
    this.onEmptyBackspace,
    this._semanticLabel,
  });

  final String? _placeholder;
  String get placeholder => _placeholder ?? appL10n.typeACommandOrSearch;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  final bool enabled;

  /// An inline query with no field frame or search glyph, for menu surfaces.
  final bool borderless;

  /// The menu preset uses a 13px borderless editor with 3px/4px insets.
  /// Tokens precede it in a wrapping row; the query fills the remaining space
  /// or starts a new row when less than 90px remains.
  final DCommandInputDensity density;
  final List<Widget> tokens;

  /// Whether the query requests focus when it mounts.
  final bool autofocus;

  /// Called when Backspace is pressed in an empty query, including on mobile.
  final VoidCallback? onEmptyBackspace;
  final String? _semanticLabel;
  String get semanticLabel => _semanticLabel ?? appL10n.searchCommands;

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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.enabled &&
        widget.onEmptyBackspace != null &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _editing.text.isEmpty &&
        _editing.selection.isCollapsed &&
        !_editing.value.isComposingRangeValid) {
      widget.onEmptyBackspace!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.tokens.isEmpty ||
          widget.density == DCommandInputDensity.menuFilter,
    );
    final scope = _DCommandScope.of<T>(context);
    return AnimatedBuilder(
      animation: scope.controller._queryChanges,
      builder: (context, _) {
        if (_editing.text != scope.controller.query) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _editing.text != scope.controller.query) {
              _replace(scope.controller.query);
            }
          });
        }
        final menu = widget.density == DCommandInputDensity.menuFilter;
        final borderless = widget.borderless || menu;
        final input = Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: DInput(
            borderless: borderless,
            style: menu
                ? Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: DiscourseTypography.control,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: DTokens.of(context).foreground,
                  )
                : null,
            controller: _editing,
            focusNode: widget.focusNode,
            semanticLabel: widget.semanticLabel,
            hintText: widget.placeholder,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            onEmptyBackspace: widget.onEmptyBackspace,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            suffix: borderless
                ? null
                : ExcludeSemantics(
                    child: DIcon(
                      DIcons.magnifyingGlass,
                      size: 16,
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
          ),
        );
        if (menu) {
          return DReferenceTextScale(
            child: _DCommandInputWrap(
              children: [
                ...widget.tokens,
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  child: input,
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: widget.borderless
              ? const EdgeInsets.symmetric(
                  horizontal: DSpacing.sm,
                  vertical: DSpacing.sm,
                )
              : const EdgeInsets.only(bottom: DSpacing.xs),
          child: input,
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

// CSS flex-wrap with an expanding final query: ordinary Wrap gives the
// editor the whole available width and would always place it on another row.
class _DCommandInputWrap extends MultiChildRenderObjectWidget {
  const _DCommandInputWrap({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCommandInputWrap(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCommandInputWrap renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _CommandInputParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCommandInputWrap extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderCommandInputWrap(this._textDirection);
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _CommandInputParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final runs = <List<RenderBox>>[];
    var run = <RenderBox>[];
    var used = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final gap = run.isEmpty ? 0.0 : 5.0;
      if (child == lastChild) {
        if (run.isNotEmpty && width - used - gap < 90) {
          runs.add(run);
          run = [];
          used = 0;
        }
        child.layout(
          BoxConstraints.tightFor(
            width: math.max(0, width - used - (run.isEmpty ? 0 : 5)),
          ),
          parentUsesSize: true,
        );
      } else {
        child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
        if (run.isNotEmpty && used + gap + child.size.width > width) {
          runs.add(run);
          run = [];
          used = 0;
        }
      }
      used += (run.isEmpty ? 0 : 5) + child.size.width;
      run.add(child);
    }
    if (run.isNotEmpty) runs.add(run);
    var y = 0.0;
    for (final row in runs) {
      final height = row.fold(
        0.0,
        (height, child) => math.max(height, child.size.height),
      );
      var x = 0.0;
      for (final child in row) {
        final data = child.parentData! as ContainerBoxParentData<RenderBox>;
        data.offset = Offset(
          _textDirection == TextDirection.ltr
              ? x
              : width - x - child.size.width,
          y + (height - child.size.height) / 2,
        );
        x += child.size.width + 5;
      }
      y += height + 5;
    }
    size = constraints.constrain(Size(width, math.max(0, y - 5)));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Scrollable result composition. Children may be groups, items, separators,
/// empty states, or loading states. Filtering and sorting happen here.
class DCommandList<T> extends StatefulWidget {
  const DCommandList({
    super.key,
    required this.children,

    this.maxHeight = 288,
    this.height,
    this._semanticLabel,
  }) : assert(maxHeight > 0),
       assert(height == null || height > 0);

  final List<Widget> children;

  final double maxHeight;

  /// When set, the list occupies exactly this height whatever its results,
  /// with empty and loading states centred in it, so a surface whose results
  /// change on every keystroke keeps its geometry. Otherwise the list
  /// shrink-wraps its rows up to [maxHeight].
  final double? height;
  final String? _semanticLabel;
  String get semanticLabel => _semanticLabel ?? appL10n.commandResults;

  @override
  State<DCommandList<T>> createState() => _DCommandListState<T>();
}

class _DCommandListState<T> extends State<DCommandList<T>> {
  ScrollController? _owned;
  final Map<Object, GlobalKey> _itemKeys = {};
  final Expando<_DCommandSearchData> _searchData = Expando();
  final Map<Object, int> _lazyIndices = {};
  int _revealGeneration = 0;
  ScrollController get _scroll => (_owned!);

  @override
  void initState() {
    super.initState();
    _owned = ScrollController();
  }

  @override
  void didUpdateWidget(DCommandList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _revealItem(Object identity) async {
    final generation = ++_revealGeneration;
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted || generation != _revealGeneration || !_scroll.hasClients) {
        return;
      }
      final targetContext = _itemKeys[identity]?.currentContext;
      final position = _scroll.position;
      if (targetContext != null && targetContext.mounted) {
        final target = targetContext.findRenderObject()!;
        final viewport = RenderAbstractViewport.of(target);
        final top = viewport.getOffsetToReveal(target, 0).offset;
        final bottom = viewport.getOffsetToReveal(target, 1).offset;
        if (position.pixels <= top && position.pixels >= bottom) return;
        await position.ensureVisible(
          target,
          alignmentPolicy: position.pixels > top
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: MediaQuery.disableAnimationsOf(targetContext)
              ? Duration.zero
              : DMotion.change,
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final index = _lazyIndices[identity];
      if (index == null) return;
      // Estimate from laid-out rows, then reveal the exact variable-height
      // target once the lazy viewport has mounted it.
      final visible = <({int index, double offset, double height})>[];
      for (final item in _itemKeys.entries) {
        final context = item.value.currentContext;
        final itemIndex = _lazyIndices[item.key];
        if (context == null || !context.mounted || itemIndex == null) continue;
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        visible.add((
          index: itemIndex,
          offset: RenderAbstractViewport.of(
            box,
          ).getOffsetToReveal(box, 0).offset,
          height: box.size.height,
        ));
      }
      if (visible.isEmpty) return;
      visible.sort((a, b) => a.index.compareTo(b.index));
      final first = visible.first;
      final last = visible.last;
      final height = last.index == first.index
          ? first.height
          : (last.offset - first.offset) / (last.index - first.index);
      final nearest = index < first.index ? first : last;
      position.jumpTo(
        (nearest.offset + (index - nearest.index) * height).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  List<_DCommandLazyRow> _lazyRows(
    List<_DResultNode<T>> nodes,
    _DCommandScope<T> scope,
    List<DCommandLoading> loading,
  ) {
    final rows = <_DCommandLazyRow>[
      for (var i = 0; i < loading.length; i++)
        _DCommandLazyRow(ValueKey((#loading, i)), (_) => loading[i]),
    ];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is _DGroupNode<T>) {
        if (node.group.heading case final heading?) {
          rows.add(
            _DCommandLazyRow(
              ValueKey((#heading, i)),
              (context) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: _commandGroupHeading(context, heading),
              ),
            ),
          );
        }
        for (var j = 0; j < node.scored.length; j++) {
          final item = node.scored[j].item;
          rows.add(
            _DCommandLazyRow(
              ValueKey((#item, item.identity)),
              (context) => KeyedSubtree(
                key: item.key,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    4,
                    j == 0 && node.group.heading == null ? 4 : 0,
                    4,
                    j == node.scored.length - 1 ? 4 : 0,
                  ),
                  child: _DCommandItemSurface<T>(
                    key: _itemKeys.putIfAbsent(item.identity, GlobalKey.new),
                    item: item,
                    scope: scope,
                  ),
                ),
              ),
              identity: item.identity,
            ),
          );
        }
      } else {
        final identity = node is _DItemNode<T>
            ? node.scored.item.identity
            : null;
        rows.add(
          _DCommandLazyRow(
            ValueKey((identity == null ? #separator : #item, identity ?? i)),
            (context) => node.build(context, scope, _itemKeys),
            identity: identity,
          ),
        );
      }
    }
    return rows;
  }

  List<_DScoredItem<T>> _score(
    Iterable<DCommandItem<T>> items,
    _DCommandScope<T> scope,
    _DCommandSearchQuery query,
  ) {
    final result = <_DScoredItem<T>>[];
    var order = 0;
    for (final item in items) {
      var score = 1.0;
      if (scope.shouldFilter && query.needle.isNotEmpty && !item.forceMount) {
        final value = item.effectiveSearchValue;
        var data = _searchData[item];
        if (data == null || !data.matchesSource(value, item.keywords)) {
          data = _DCommandSearchData(value, item.keywords);
          _searchData[item] = data;
        }
        score = data.score(query);
      }
      if (score > 0) {
        result.add(_DScoredItem(item, score, order));
      }
      order++;
    }
    if (scope.shouldFilter && query.needle.isNotEmpty) {
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
      animation: scope.controller._queryChanges,
      builder: (context, _) {
        final query = _DCommandSearchQuery(scope.controller.query);
        final resultNodes = <_DResultNode<T>>[];
        final emptyNodes = <DCommandEmpty>[];
        final loadingNodes = <DCommandLoading>[];
        for (final child in widget.children) {
          if (child is DCommandGroup<T>) {
            final items = _score(child.items, scope, query);
            if (items.isNotEmpty) {
              resultNodes.add(_DGroupNode(child, items));
            }
          } else if (child is DCommandItem<T>) {
            final items = _score([child], scope, query);
            if (items.isNotEmpty) resultNodes.add(_DItemNode(items.single));
          } else if (child is DCommandSeparator<T>) {
            if ((scope.controller.query.isEmpty)) {
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
        final enabledEntries = <_DCommandEntry<T>>[];
        var resultCount = 0;
        for (final node in resultNodes) {
          final group = node is _DGroupNode<T> ? node.group : null;
          for (final scored in node.items) {
            resultCount++;
            if (!scored.item.enabled) continue;
            final identity = scored.item.identity;
            enabledEntries.add(
              _DCommandEntry(
                value: scored.item.value,
                onSelected: scored.item.onSelected,
                group: group,
                reveal: () => unawaited(_revealItem(identity)),
              ),
            );
          }
        }
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
        if (resultCount == 0 && !scope.loading) rendered.addAll(emptyNodes);
        final showsResults = !scope.loading || resultCount > 0;
        final lazy = resultCount > 64
            ? _lazyRows(
                resultNodes,
                scope,
                scope.loading ? loadingNodes : const [],
              )
            : null;
        _lazyIndices.clear();
        if (lazy != null) {
          for (var i = 0; i < lazy.length; i++) {
            if (lazy[i].identity case final identity?) {
              _lazyIndices[identity] = i;
            }
          }
        }
        if (showsResults && lazy == null) {
          for (final node in resultNodes) {
            rendered.add(node.build(context, scope, _itemKeys));
          }
        }
        const padding = EdgeInsets.symmetric(vertical: DSpacing.xs);
        final rowIndices = lazy == null
            ? null
            : {for (var i = 0; i < lazy.length; i++) lazy[i].key: i};
        Widget scroll({double minHeight = 0}) => DScrollBar(
          backgroundColor: scope.backgroundColor,
          controller: _scroll,
          thumbVisibility: false,
          child: lazy != null
              ? ListView.builder(
                  controller: _scroll,
                  primary: false,
                  // Long results fill the bounded menu viewport. Shrink
                  // wrapping can repeatedly correct fractional iOS offsets
                  // while an adaptive sheet changes its height.
                  padding: padding,
                  itemCount: lazy.length,
                  findChildIndexCallback: (key) => rowIndices![key],
                  itemBuilder: (context, index) => KeyedSubtree(
                    key: lazy[index].key,
                    child: lazy[index].builder(context),
                  ),
                )
              : SingleChildScrollView(
                  controller: _scroll,
                  padding: padding,
                  // Scrolling and edge fades only move/composite these rows. Keep
                  // their text and icons cached until a row or the results change.
                  child: RepaintBoundary(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment:
                            showsResults && resultNodes.isNotEmpty
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: rendered,
                      ),
                    ),
                  ),
                ),
        );
        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: widget.semanticLabel,
          child: switch (widget.height) {
            final height? => SizedBox(
              height: height,
              child: LayoutBuilder(
                builder: (context, constraints) => scroll(
                  minHeight: math.max(
                    0,
                    constraints.maxHeight - padding.vertical,
                  ),
                ),
              ),
            ),
            null => ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: scroll(),
            ),
          },
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

class _DCommandLazyRow {
  const _DCommandLazyRow(this.key, this.builder, {this.identity});
  final Key key;
  final WidgetBuilder builder;
  final Object? identity;
}

Widget _commandGroupHeading(BuildContext context, Widget heading) => Padding(
  padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
  child: DefaultTextStyle(
    style: Theme.of(context).textTheme.bodySmall!.copyWith(
      fontSize: DiscourseTypography.xs,
      fontWeight: FontWeight.w500,
      color: DTokens.of(context).mutedForeground,
    ),
    child: heading,
  ),
);

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
          _commandGroupHeading(context, group.heading!),
        for (final item in scored)
          KeyedSubtree(
            key: item.item.key,
            child: _DCommandItemSurface<T>(
              key: keys.putIfAbsent(item.item.identity, GlobalKey.new),
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
        key: keys.putIfAbsent(scored.item.identity, GlobalKey.new),
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
  ) => Divider(height: 1, thickness: 1, color: (DTokens.of(context).border));
}

class _DScoredItem<T> {
  const _DScoredItem(this.item, this.score, this.order);
  final DCommandItem<T> item;
  final double score;
  final int order;
}

class _DCommandSearchQuery {
  _DCommandSearchQuery(String query) : needle = query.trim().toLowerCase();

  static final _whitespace = RegExp(r'\s+');
  final String needle;
  late final List<String> tokens = needle.split(_whitespace);
}

class _DCommandSearchData {
  _DCommandSearchData(String value, List<String> keywords)
    : rawValue = value,
      rawKeywords = List<String>.of(keywords, growable: false),
      normalizedValue = value.trim().toLowerCase(),
      haystack = [
        value.trim(),
        for (final keyword in keywords) keyword.trim(),
      ].where((part) => part.isNotEmpty).join(' ').toLowerCase();

  final String rawValue;
  final List<String> rawKeywords;
  final String normalizedValue;
  final String haystack;

  bool matchesSource(String value, List<String> keywords) {
    if (rawValue != value || rawKeywords.length != keywords.length) {
      return false;
    }
    for (var i = 0; i < keywords.length; i++) {
      if (rawKeywords[i] != keywords[i]) return false;
    }
    return true;
  }

  double score(_DCommandSearchQuery query) {
    final needle = query.needle;
    if (normalizedValue == needle || haystack == needle) return 1;
    if (haystack.startsWith(needle)) return .9;
    if (haystack.contains(needle)) return .7;
    return query.tokens.every(haystack.contains) ? .5 : 0;
  }
}

class _DCommandEntry<T> {
  const _DCommandEntry({
    required this.value,
    required this.onSelected,
    required this.group,
    required this.reveal,
  });
  final T value;
  final ValueChanged<T>? onSelected;
  final Object? group;
  final VoidCallback reveal;
}

/// A labelled result group. Filtering hides empty groups unless [forceMount].
class DCommandGroup<T> extends StatelessWidget {
  const DCommandGroup({super.key, required this.items, this.heading});
  final Widget? heading;
  final List<DCommandItem<T>> items;

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
  late final ValueNotifier<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = ValueNotifier(
      widget.scope.controller.value == widget.item.value,
    );
    widget.scope.controller.addListener(_syncHighlight);
  }

  void _syncHighlight() {
    _selected.value = widget.scope.controller.value == widget.item.value;
  }

  @override
  void didUpdateWidget(_DCommandItemSurface<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.controller != widget.scope.controller) {
      oldWidget.scope.controller.removeListener(_syncHighlight);
      widget.scope.controller.addListener(_syncHighlight);
    }
    _syncHighlight();
  }

  @override
  void dispose() {
    widget.scope.controller.removeListener(_syncHighlight);
    _selected.dispose();
    super.dispose();
  }

  void _activate() {
    if (widget.item.enabled) {
      widget.scope.controller.activate(widget.item.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tokens = DTokens.of(context);
    return AnimatedBuilder(
      animation: _selected,
      builder: (context, _) {
        final selected = _selected.value;
        final interactive = item.enabled && selected;
        final radius = BorderRadius.circular(DControlStyle.rowRadius);
        Widget row = interactiveRowSurface(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: interactive
                ? DControlStyle.rowHover(tokens)
                : Colors.transparent,
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
                fontSize: DControlStyle.labelFontSize,
                height:
                    DControlStyle.labelLineHeight / DControlStyle.labelFontSize,
                color: tokens.foreground,
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
            child: MouseRegion(
              // Scrolling a keyboard-selected row into view can move another
              // row beneath a stationary mouse. Only actual pointer movement
              // should take selection back from the keyboard.
              onHover: (event) {
                if (item.enabled && event.delta != Offset.zero) {
                  widget.scope.controller.highlight(item.value);
                }
              },
              child: DTouchTarget(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: item.enabled ? _activate : null,
                  child: Opacity(
                    opacity: item.enabled ? 1 : .5,
                    child: _DCommandItemVisualScope(
                      selected: selected,
                      child: row,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Trailing shortcut text with directional placement and selected-state color.
/// Hidden on mobile; use ordinary text for non-keyboard details.
class DCommandShortcut extends StatelessWidget {
  const DCommandShortcut(this.child, {super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (DControlStyle.isTouch(context)) return const SizedBox.shrink();
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
  const DCommandSeparator({super.key});

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
  const DCommandLoading({super.key, required this.child});
  final Widget child;

  String get semanticLabel => appL10n.loading;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    role: SemanticsRole.loadingSpinner,
    liveRegion: true,
    label: semanticLabel,
    value: null,
    minValue: null,
    maxValue: null,
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
      child: Center(child: child),
    ),
  );
}

/// An adaptive command palette: a Native menu sheet on touch platforms and a
/// centered dialog on desktop. The overlay owns its surface and focus lifecycle;
/// the nested [DCommand] owns query, filtering, and selection.
class DCommandDialog<T> extends StatefulWidget {
  const DCommandDialog({
    super.key,
    required this.command,
    this.trigger,
    this.controller,
    this.open,
    this.initiallyOpen = false,
    this.onOpenChanged,
    this._title,
    this._description,
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
  final String? _title;
  String get title => _title ?? appL10n.commandPalette;
  final String? _description;
  String get description => _description ?? appL10n.searchForACommandToRun;
  final bool showCloseButton;
  final double maxWidth;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  @override
  State<DCommandDialog<T>> createState() => _DCommandDialogState<T>();
}

class _DCommandDialogState<T> extends State<DCommandDialog<T>> {
  late DDialogController<T> _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        DDialogController<T>(initiallyOpen: widget.initiallyOpen);
  }

  @override
  void didUpdateWidget(DCommandDialog<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      final wasOpen = _controller.isOpen;
      if (oldWidget.controller == null) _controller.dispose();
      _controller =
          widget.controller ?? DDialogController<T>(initiallyOpen: wasOpen);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final command = _DCommandOverlayScope(child: widget.command);
    final semanticLabel = '${widget.title}. ${widget.description}';
    if (DControlStyle.isTouch(context)) {
      return DSheet<T>(
        controller: _controller,
        open: widget.open,
        onOpenChanged: widget.onOpenChanged,
        initialFocusNode: widget.initialFocusNode,
        finalFocusNode: widget.finalFocusNode,
        trigger: DSheetTrigger(
          builder:
              widget.trigger?.builder ??
              (context, open) => const SizedBox.shrink(),
        ),
        content: DSheetContent(
          side: DSheetSide.bottom,
          variant: DSheetVariant.adaptiveMenu,
          showCloseButton: false,
          semanticLabel: semanticLabel,
          scrollWholeSheet: false,
          children: [Flexible(child: command)],
        ),
      );
    }
    return DDialog<T>(
      controller: _controller,
      open: widget.open,
      onOpenChanged: widget.onOpenChanged,
      initialFocusNode: widget.initialFocusNode,
      finalFocusNode: widget.finalFocusNode,
      trigger:
          widget.trigger ??
          DDialogTrigger(builder: (context, open) => const SizedBox.shrink()),
      content: DDialogContent(
        maxWidth: widget.maxWidth,
        showCloseButton: widget.showCloseButton,
        semanticLabel: semanticLabel,
        contentPadding: EdgeInsets.zero,
        verticalPadding: 0,
        spacing: 0,
        children: [command],
      ),
    );
  }
}

class _DCommandOverlayScope extends InheritedWidget {
  const _DCommandOverlayScope({required super.child});

  @override
  bool updateShouldNotify(_DCommandOverlayScope oldWidget) => false;
}
