import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_field.dart';
import 'd_input.dart';
import 'd_questionnaire_controller.dart';

export 'd_questionnaire_controller.dart';

typedef DQuestionnaireSubmitCallback =
    FutureOr<void> Function(DQuestionnaireSnapshot answers);
typedef DQuestionnaireItemBuilder =
    Widget Function(
      BuildContext context,
      DQuestionnaireItem item,
      Widget defaultItem,
    );
typedef DQuestionnaireProgressBuilder =
    Widget Function(
      BuildContext context,
      DQuestionnaireProgressState state,
      Widget defaultProgress,
    );
typedef DQuestionnaireActionsBuilder =
    Widget Function(
      BuildContext context,
      DQuestionnaireProgressState state,
      Widget defaultActions,
    );

/// A styled, one-question-at-a-time form backed by the reusable headless
/// [DQuestionnaireController]. The host owns persistence, transport, dialog
/// dismissal and domain branching.
class DQuestionnaire extends StatefulWidget {
  const DQuestionnaire({
    super.key,
    required this.items,
    this.controller,
    this.initialState,
    this.initialItemId,
    this.currentItemId,
    this.onCurrentItemChanged,
    this.onSubmit,
    this.shortcuts,
    this.itemBuilder,
    this.progressBuilder,
    this.actionsBuilder,
    this.showProgress = true,
    this.showActions = true,
    this.showReset = false,
    this.animateItems = false,
    this.autofocus = true,
    this.submitLabel = 'Submit',
    this.emptyBuilder,
  }) : assert(
         controller == null || (initialState == null && initialItemId == null),
       );

  final List<DQuestionnaireItem> items;

  /// Borrowed and never disposed. Without one, the widget owns its controller.
  final DQuestionnaireController? controller;
  final DQuestionnaireSavedState? initialState;
  final String? initialItemId;

  /// Parent-updated active item. Navigation changes are accepted only when
  /// [onCurrentItemChanged] returns true; a false result leaves the item open.
  final String? currentItemId;
  final FutureOr<bool> Function(String itemId)? onCurrentItemChanged;
  final DQuestionnaireSubmitCallback? onSubmit;
  final DQuestionnaireShortcutMode? shortcuts;
  final DQuestionnaireItemBuilder? itemBuilder;
  final DQuestionnaireProgressBuilder? progressBuilder;
  final DQuestionnaireActionsBuilder? actionsBuilder;
  final bool showProgress;
  final bool showActions;
  final bool showReset;
  final bool animateItems;
  final bool autofocus;
  final String submitLabel;
  final WidgetBuilder? emptyBuilder;

  @override
  State<DQuestionnaire> createState() => _DQuestionnaireState();
}

class _DQuestionnaireState extends State<DQuestionnaire> {
  DQuestionnaireController? _ownedController;
  final _formKey = GlobalKey<FormState>();
  final Map<String, List<FocusNode>> _choiceFocus = {};
  final Map<String, FocusNode> _inputFocus = {};
  final Map<String, TextEditingController> _textControllers = {};
  String? _lastItemId;
  bool _forward = true;

  DQuestionnaireController get _controller =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _createOwnedController();
    _attach();
    _reconcileResources();
    _lastItemId = _controller.currentItemId;
    if (widget.currentItemId != null) {
      _controller.setControlledItem(widget.currentItemId!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) _focusCurrent();
    });
  }

  void _createOwnedController() {
    if (widget.controller != null) return;
    _ownedController = DQuestionnaireController(
      items: widget.items,
      initialState: widget.initialState,
      initialItemId: widget.initialItemId,
    );
  }

  void _attach() {
    _controller
      ..addListener(_changed)
      ..navigationDelegate = _navigate;
  }

  void _detach(DQuestionnaireController controller) {
    controller.removeListener(_changed);
    if (controller.navigationDelegate == _navigate) {
      controller.navigationDelegate = null;
    }
  }

  Future<bool> _navigate(
    String from,
    String to,
    DQuestionnaireNavigationReason reason,
  ) async {
    final callback = widget.onCurrentItemChanged;
    if (callback == null) return true;
    return callback(to);
  }

  @override
  void didUpdateWidget(covariant DQuestionnaire oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller ?? _ownedController!);
      _ownedController?.dispose();
      _ownedController = null;
      _createOwnedController();
      _attach();
    }
    _controller.updateItems(widget.items);
    _controller.navigationDelegate = _navigate;
    if (widget.currentItemId != null &&
        widget.currentItemId != _controller.currentItemId) {
      _controller.setControlledItem(widget.currentItemId!);
    }
    _reconcileResources();
  }

  void _changed() {
    for (final item in widget.items) {
      final textController = _textControllers[item.id];
      if (textController == null) continue;
      final desired = _controller.answerFor(item.id).freeform ?? '';
      if (textController.text != desired) {
        textController.value = TextEditingValue(
          text: desired,
          selection: TextSelection.collapsed(offset: desired.length),
        );
      }
    }
    final current = _controller.currentItemId;
    if (current != _lastItemId) {
      final ids = _controller.visibleItems.map((item) => item.id).toList();
      _forward = ids.indexOf(current ?? '') >= ids.indexOf(_lastItemId ?? '');
      _lastItemId = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusCurrent();
      });
    }
    if (mounted) setState(() {});
  }

  void _reconcileResources() {
    final ids = widget.items.map((item) => item.id).toSet();
    for (final id in _choiceFocus.keys.toList()) {
      if (!ids.contains(id)) {
        for (final node in _choiceFocus.remove(id)!) {
          node.dispose();
        }
      }
    }
    for (final id in _inputFocus.keys.toList()) {
      if (!ids.contains(id)) _inputFocus.remove(id)?.dispose();
    }
    for (final id in _textControllers.keys.toList()) {
      if (!ids.contains(id)) _textControllers.remove(id)?.dispose();
    }
    for (final item in widget.items) {
      final nodes = _choiceFocus.putIfAbsent(item.id, () => []);
      while (nodes.length < item.choices.length) {
        nodes.add(FocusNode());
      }
      while (nodes.length > item.choices.length) {
        nodes.removeLast().dispose();
      }
      if (item.input != null) {
        _inputFocus.putIfAbsent(item.id, FocusNode.new);
        _textControllers.putIfAbsent(
          item.id,
          () => TextEditingController(
            text:
                _controller.answerFor(item.id).freeform ??
                item.input!.initialValue,
          ),
        );
      }
    }
  }

  void _focusCurrent() {
    final item = _controller.currentItem;
    if (item == null) return;
    final choice = item.choices.where((choice) => choice.enabled).firstOrNull;
    if (choice != null) {
      final index = item.choices.indexOf(choice);
      _choiceFocus[item.id]?[index].requestFocus();
    } else {
      _inputFocus[item.id]?.requestFocus();
    }
  }

  Future<void> _next() async {
    final moved = await _controller.next();
    if (!moved && mounted && _controller.currentItem != null) _focusCurrent();
  }

  Future<void> _previous() async => _controller.previous();

  Future<void> _skip() async {
    final wasLast = !_controller.canGoNext;
    if (await _controller.skip() && wasLast) await _submit();
  }

  Future<void> _submit() async {
    _formKey.currentState?.save();
    final answers = await _controller.validateForSubmission();
    if (answers == null || !mounted) {
      _focusCurrent();
      return;
    }
    await widget.onSubmit?.call(answers);
  }

  void _reset() {
    _controller.reset();
    for (final item in widget.items) {
      final text =
          _controller.answerFor(item.id).freeform ??
          item.input?.initialValue ??
          '';
      final textController = _textControllers[item.id];
      if (textController != null && textController.text != text) {
        textController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusCurrent();
    });
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings(
    DQuestionnaireItem item,
  ) {
    final mode = widget.shortcuts;
    final enabled = [
      for (var index = 0; index < item.choices.length; index++)
        if (item.choices[index].enabled)
          (index: index, choice: item.choices[index]),
    ];
    final limit = mode == DQuestionnaireShortcutMode.numbers ? 9 : 26;
    return {
      const _QuestionnaireShortcutActivator(
        SingleActivator(LogicalKeyboardKey.enter, control: true),
        allowEditable: true,
      ): () =>
          _controller.canGoNext ? _next() : _submit(),
      const _QuestionnaireShortcutActivator(
        SingleActivator(LogicalKeyboardKey.enter, meta: true),
        allowEditable: true,
      ): () =>
          _controller.canGoNext ? _next() : _submit(),
      for (
        var index = 0;
        mode != null && index < enabled.length && index < limit;
        index++
      )
        _QuestionnaireShortcutActivator(
          SingleActivator(
            mode == DQuestionnaireShortcutMode.letters
                ? LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + index)
                : LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + index),
          ),
        ): () {
          final choice = enabled[index];
          _choiceFocus[item.id]![choice.index].requestFocus();
          item.multiple
              ? _controller.toggle(item.id, choice.choice.value)
              : _controller.setSingle(item.id, choice.choice.value);
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final item = _controller.currentItem;
    if (item == null) {
      return widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
    }
    final progress = _controller.progress;
    final defaultProgress = DQuestionnaireProgress(state: progress);
    final itemView = DQuestionnaireItemView(
      item: item,
      controller: _controller,
      choiceFocusNodes: _choiceFocus[item.id]!,
      inputFocusNode: _inputFocus[item.id],
      textController: _textControllers[item.id],
      shortcutMode: widget.shortcuts,
    );
    final builtItem =
        widget.itemBuilder?.call(context, item, itemView) ?? itemView;
    final defaultActions = DQuestionnaireActions(
      previous: _controller.canGoPrevious ? _previous : null,
      skip: _controller.canSkip ? _skip : null,
      next: _controller.canGoNext ? _next : null,
      submit: !_controller.canGoNext ? _submit : null,
      reset: widget.showReset ? _reset : null,
      validating: _controller.isValidating,
      submitLabel: widget.submitLabel,
    );
    return _DQuestionnaireScope(
      controller: _controller,
      next: _next,
      previous: _previous,
      skip: _skip,
      submit: _submit,
      reset: _reset,
      child: CallbackShortcuts(
        bindings: _shortcutBindings(item),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showProgress) ...[
                  widget.progressBuilder?.call(
                        context,
                        progress,
                        defaultProgress,
                      ) ??
                      defaultProgress,
                  const SizedBox(height: 16),
                ],
                AnimatedSwitcher(
                  duration: widget.animateItems
                      ? DMotion.duration(context, DMotion.change)
                      : Duration.zero,
                  transitionBuilder: (child, animation) =>
                      _QuestionnaireItemTransition(
                        animation: animation,
                        forward: _forward,
                        child: child,
                      ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.topStart,
                    children: [...previous, ?current],
                  ),
                  child: KeyedSubtree(key: ValueKey(item.id), child: builtItem),
                ),
                if (widget.showActions) ...[
                  const SizedBox(height: 16),
                  widget.actionsBuilder?.call(
                        context,
                        progress,
                        defaultActions,
                      ) ??
                      defaultActions,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _detach(_controller);
    _ownedController?.dispose();
    for (final nodes in _choiceFocus.values) {
      for (final node in nodes) {
        node.dispose();
      }
    }
    for (final node in _inputFocus.values) {
      node.dispose();
    }
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _QuestionnaireShortcutActivator implements ShortcutActivator {
  const _QuestionnaireShortcutActivator(
    this.activator, {
    this.allowEditable = false,
  });

  final SingleActivator activator;
  final bool allowEditable;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => activator.triggers;

  @override
  String debugDescribeKeys() => activator.debugDescribeKeys();

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (!activator.accepts(event, state)) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final editable = focusContext?.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return true;
    if (!allowEditable) return false;
    final composing = editable.widget.controller.value.composing;
    return !composing.isValid || composing.isCollapsed;
  }
}

class _DQuestionnaireScope extends InheritedNotifier<DQuestionnaireController> {
  const _DQuestionnaireScope({
    required DQuestionnaireController controller,
    required this.next,
    required this.previous,
    required this.skip,
    required this.submit,
    required this.reset,
    required super.child,
  }) : super(notifier: controller);

  final Future<void> Function() next;
  final Future<void> Function() previous;
  final Future<void> Function() skip;
  final Future<void> Function() submit;
  final VoidCallback reset;

  static _DQuestionnaireScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DQuestionnaireScope>();
    assert(scope != null, 'Questionnaire parts require DQuestionnaire.');
    return scope!;
  }
}

class _QuestionnaireItemTransition extends StatelessWidget {
  const _QuestionnaireItemTransition({
    required this.animation,
    required this.forward,
    required this.child,
  });

  final Animation<double> animation;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: Offset(forward ? .04 : -.04, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class DQuestionnaireProgress extends StatelessWidget {
  const DQuestionnaireProgress({
    super.key,
    this.state,
    this.builder,
    this.semanticLabel = 'Questionnaire progress',
  });

  final DQuestionnaireProgressState? state;
  final Widget Function(
    BuildContext context,
    DQuestionnaireProgressState state,
  )?
  builder;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final value = state ?? _DQuestionnaireScope.of(context).notifier!.progress;
    if (builder != null) return builder!(context, value);
    return Semantics(
      liveRegion: true,
      role: SemanticsRole.progressBar,
      label: '$semanticLabel, question ${value.current} of ${value.total}',
      value: value.total == 0 ? null : '${value.current}',
      // Flutter requires min < max; zero is the native range floor while the
      // visible/current question remains one-based like the web reference.
      minValue: value.total == 0 ? null : '0',
      maxValue: value.total == 0 ? null : '${value.total}',
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: DiscourseTypography.xs,
          height: 16 / DiscourseTypography.xs,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: DTokens.of(context).mutedForeground,
        ),
        child: Text('Question ${value.current} of ${value.total}'),
      ),
    );
  }
}

class DQuestionnaireItemView extends StatelessWidget {
  const DQuestionnaireItemView({
    super.key,
    required this.item,
    required this.controller,
    required this.choiceFocusNodes,
    this.inputFocusNode,
    this.textController,
    this.shortcutMode,
  });

  final DQuestionnaireItem item;
  final DQuestionnaireController controller;
  final List<FocusNode> choiceFocusNodes;
  final FocusNode? inputFocusNode;
  final TextEditingController? textController;
  final DQuestionnaireShortcutMode? shortcutMode;

  @override
  Widget build(BuildContext context) {
    final error = controller.errorFor(item.id);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DQuestionnaireTitle(child: item.title),
          if (item.description != null) ...[
            const SizedBox(height: 16),
            DQuestionnaireDescription(child: item.description!),
          ],
          const SizedBox(height: 16),
          DQuestionnaireChoices(
            children: [
              for (var index = 0; index < item.choices.length; index++)
                DQuestionnaireChoiceTile(
                  item: item,
                  choice: item.choices[index],
                  controller: controller,
                  focusNode: choiceFocusNodes[index],
                  onMovePrevious: () => _moveChoice(index, -1),
                  onMoveNext: () => _moveChoice(index, 1),
                  shortcut: _shortcut(index),
                ),
              if (item.input case final input?)
                DField(
                  invalid: error != null,
                  enabled: input.enabled,
                  children: [
                    DFieldControl(
                      label: input.label,
                      required: item.required,
                      errors: [error],
                      child: DInput(
                        controller: textController,
                        focusNode: inputFocusNode,
                        hintText: input.placeholder,
                        enabled: input.enabled,
                        invalid: error != null,
                        isRequired: item.required,
                        keyboardType: switch (input.type) {
                          DQuestionnaireInputType.email =>
                            TextInputType.emailAddress,
                          DQuestionnaireInputType.phone => TextInputType.phone,
                          DQuestionnaireInputType.url => TextInputType.url,
                          DQuestionnaireInputType.number =>
                            TextInputType.number,
                          DQuestionnaireInputType.date ||
                          DQuestionnaireInputType.dateTime ||
                          DQuestionnaireInputType.month ||
                          DQuestionnaireInputType.time ||
                          DQuestionnaireInputType.week =>
                            TextInputType.datetime,
                          _ => TextInputType.text,
                        },
                        obscureText:
                            input.type == DQuestionnaireInputType.password,
                        textInputAction: TextInputAction.done,
                        onChanged: (value) =>
                            controller.setFreeform(item.id, value),
                        onSubmitted: (_) {
                          final scope = _DQuestionnaireScope.of(context);
                          unawaited(
                            scope.notifier!.canGoNext
                                ? scope.next()
                                : scope.submit(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            DQuestionnaireError(message: error),
          ],
        ],
      ),
    );
  }

  String? _shortcut(int rawIndex) {
    if (shortcutMode == null || !item.choices[rawIndex].enabled) return null;
    final enabledIndex = item.choices
        .take(rawIndex)
        .where((choice) => choice.enabled)
        .length;
    return switch (shortcutMode!) {
      DQuestionnaireShortcutMode.letters when enabledIndex < 26 =>
        String.fromCharCode(65 + enabledIndex),
      DQuestionnaireShortcutMode.numbers when enabledIndex < 9 =>
        '${enabledIndex + 1}',
      _ => null,
    };
  }

  void _moveChoice(int index, int delta) {
    if (item.choices.isEmpty) return;
    var candidate = index;
    do {
      candidate = (candidate + delta) % item.choices.length;
      if (candidate < 0) candidate += item.choices.length;
      if (item.choices[candidate].enabled) {
        choiceFocusNodes[candidate].requestFocus();
        if (!item.multiple) {
          controller.setSingle(item.id, item.choices[candidate].value);
        }
        return;
      }
    } while (candidate != index);
  }
}

class DQuestionnaireTitle extends StatelessWidget {
  const DQuestionnaireTitle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: DefaultTextStyle.merge(
      style: TextStyle(
        fontSize: DiscourseTypography.base,
        height: 22 / DiscourseTypography.base,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: DTokens.of(context).foreground,
      ),
      child: child,
    ),
  );
}

class DQuestionnaireDescription extends StatelessWidget {
  const DQuestionnaireDescription({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      fontSize: DiscourseTypography.sm,
      height: 20 / DiscourseTypography.sm,
      color: DTokens.of(context).mutedForeground,
    ),
    child: child,
  );
}

class DQuestionnaireChoices extends StatelessWidget {
  const DQuestionnaireChoices({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(height: 8),
        children[index],
      ],
    ],
  );
}

class DQuestionnaireChoiceTile extends StatefulWidget {
  const DQuestionnaireChoiceTile({
    super.key,
    required this.item,
    required this.choice,
    required this.controller,
    required this.focusNode,
    required this.onMovePrevious,
    required this.onMoveNext,
    this.shortcut,
  });

  final DQuestionnaireItem item;
  final DQuestionnaireChoice<Object> choice;
  final DQuestionnaireController controller;
  final FocusNode focusNode;
  final VoidCallback onMovePrevious;
  final VoidCallback onMoveNext;
  final String? shortcut;

  @override
  State<DQuestionnaireChoiceTile> createState() =>
      _DQuestionnaireChoiceTileState();
}

class _DQuestionnaireChoiceTileState extends State<DQuestionnaireChoiceTile> {
  bool _hovered = false;
  bool _focused = false;
  FocusNode get _focus => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() => _focused = _focus.hasFocus);

  @override
  void didUpdateWidget(covariant DQuestionnaireChoiceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode.removeListener(_focusChanged);
    _focus.addListener(_focusChanged);
  }

  void _activate() {
    if (!widget.choice.enabled) return;
    widget.item.multiple
        ? widget.controller.toggle(widget.item.id, widget.choice.value)
        : widget.controller.setSingle(widget.item.id, widget.choice.value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final answer = widget.controller.answerFor(widget.item.id);
    final checked = answer.values.contains(widget.choice.value);
    final invalid = widget.controller.errorFor(widget.item.id) != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(tokens.radius);
    final background = checked
        ? tokens.muted
        : _hovered
        ? tokens.muted.withValues(alpha: tokens.muted.a * .5)
        : dark
        ? tokens.colors.outlineVariant.withValues(
            alpha: tokens.colors.outlineVariant.a * .2,
          )
        : Colors.transparent;
    final border = invalid
        ? tokens.destructive
        : checked
        ? tokens.primary.withValues(alpha: tokens.primary.a * .4)
        : tokens.colors.outlineVariant;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final semanticLabel =
        widget.choice.semanticLabel ??
        switch (widget.choice.label) {
          Text(data: final text?) => text,
          _ => null,
        };
    return Semantics(
      container: true,
      button: true,
      enabled: widget.choice.enabled,
      checked: checked,
      inMutuallyExclusiveGroup: !widget.item.multiple,
      label: semanticLabel,
      onTap: widget.choice.enabled ? _activate : null,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          focusNode: _focus,
          enabled: widget.choice.enabled,
          mouseCursor: widget.choice.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
              TraversalDirection.up,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (checked) {
                  final scope = _DQuestionnaireScope.of(context);
                  unawaited(
                    scope.notifier!.canGoNext ? scope.next() : scope.submit(),
                  );
                } else {
                  _activate();
                }
                return null;
              },
            ),
            DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
              onInvoke: (intent) {
                intent.direction == TraversalDirection.up
                    ? widget.onMovePrevious()
                    : widget.onMoveNext();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.choice.enabled ? _activate : null,
            child: CustomPaint(
              foregroundPainter: _focused
                  ? _QuestionnaireFocusRingPainter(
                      color: tokens.focusRing.withValues(
                        alpha: tokens.focusRing.a * .5,
                      ),
                      radius: tokens.radius,
                    )
                  : null,
              child: AnimatedContainer(
                duration: DMotion.duration(context, DMotion.change),
                constraints: BoxConstraints(minHeight: touch ? 48 : 44),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: background,
                  border: Border.all(
                    color: _focused ? tokens.focusRing : border,
                  ),
                  borderRadius: radius,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: widget.choice.description == null ? 1.8 : 2,
                      ),
                      child: _QuestionnaireIndicator(
                        checked: checked,
                        radio: !widget.item.multiple,
                        enabled: widget.choice.enabled,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: DiscourseTypography.sm,
                          height: 20 / DiscourseTypography.sm,
                          color: tokens.foreground,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            widget.choice.label,
                            if (widget.choice.description != null) ...[
                              const SizedBox(height: 2),
                              DefaultTextStyle.merge(
                                style: TextStyle(color: tokens.mutedForeground),
                                child: widget.choice.description!,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (widget.shortcut != null) ...[
                      const SizedBox(width: 8),
                      _QuestionnaireShortcut(widget.shortcut!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    super.dispose();
  }
}

class _QuestionnaireFocusRingPainter extends CustomPainter {
  const _QuestionnaireFocusRingPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ).inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_QuestionnaireFocusRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _QuestionnaireIndicator extends StatelessWidget {
  const _QuestionnaireIndicator({
    required this.checked,
    required this.radio,
    required this.enabled,
  });

  final bool checked;
  final bool radio;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: AnimatedContainer(
        duration: DMotion.duration(context, DMotion.change),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: checked ? tokens.primary : Colors.transparent,
          border: Border.all(
            color: checked ? tokens.primary : tokens.colors.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(radio ? 8 : 4),
        ),
        child: checked
            ? CustomPaint(
                painter: _QuestionnaireIndicatorPainter(
                  color: tokens.primaryForeground,
                  radio: radio,
                ),
              )
            : null,
      ),
    );
  }
}

class _QuestionnaireIndicatorPainter extends CustomPainter {
  const _QuestionnaireIndicatorPainter({
    required this.color,
    required this.radio,
  });
  final Color color;
  final bool radio;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = radio ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (radio) {
      canvas.drawCircle(size.center(Offset.zero), 4, paint);
    } else {
      final path = Path()
        ..moveTo(3.5, 8)
        ..lineTo(6.7, 11)
        ..lineTo(12.5, 5);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_QuestionnaireIndicatorPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radio != radio;
}

class _QuestionnaireShortcut extends StatelessWidget {
  const _QuestionnaireShortcut(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.background,
        border: Border.all(color: tokens.colors.outlineVariant),
        borderRadius: BorderRadius.circular(tokens.radius * .8),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w500,
          color: tokens.mutedForeground,
        ),
      ),
    );
  }
}

class DQuestionnaireError extends StatelessWidget {
  const DQuestionnaireError({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(
        fontSize: DiscourseTypography.sm,
        height: 20 / DiscourseTypography.sm,
        color: DTokens.of(context).destructive,
      ),
    ),
  );
}

class DQuestionnaireActions extends StatelessWidget {
  const DQuestionnaireActions({
    super.key,
    this.previous,
    this.skip,
    this.next,
    this.submit,
    this.reset,
    this.validating = false,
    this.submitLabel = 'Submit',
  });

  final FutureOr<void> Function()? previous;
  final FutureOr<void> Function()? skip;
  final FutureOr<void> Function()? next;
  final FutureOr<void> Function()? submit;
  final VoidCallback? reset;
  final bool validating;
  final String submitLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaled = MediaQuery.textScalerOf(context).scale(14) > 21;
      final narrow = constraints.maxWidth < 320 || scaled;
      final leading = <Widget>[
        if (reset != null)
          DButton(
            onPressed: validating ? null : reset,
            variant: DButtonVariant.outline,
            label: const Text('Reset'),
          ),
        if (previous != null)
          DButton(
            onPressed: validating ? null : () => previous!(),
            variant: DButtonVariant.outline,
            label: const Text('Previous'),
          ),
      ];
      final trailing = <Widget>[
        if (skip != null)
          DButton(
            onPressed: validating ? null : () => skip!(),
            variant: DButtonVariant.outline,
            label: const Text('Skip'),
          ),
        if (next != null)
          DButton(
            onPressed: validating ? null : () => next!(),
            label: const Text('Next'),
            loading: validating,
          ),
        if (submit != null)
          DButton(
            onPressed: validating ? null : () => submit!(),
            label: Text(submitLabel),
            loading: validating,
          ),
      ];
      if (narrow) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [...leading, ...trailing],
        );
      }
      return Row(
        children: [..._spaced(leading), const Spacer(), ..._spaced(trailing)],
      );
    },
  );

  static Iterable<Widget> _spaced(List<Widget> children) sync* {
    for (var index = 0; index < children.length; index++) {
      if (index > 0) yield const SizedBox(width: 8);
      yield children[index];
    }
  }
}

class DQuestionnairePrevious extends StatelessWidget {
  const DQuestionnairePrevious({super.key, this.label = 'Previous'});
  final String label;
  @override
  Widget build(BuildContext context) {
    final scope = _DQuestionnaireScope.of(context);
    return DButton(
      onPressed: scope.notifier!.canGoPrevious ? scope.previous : null,
      variant: DButtonVariant.outline,
      label: Text(label),
    );
  }
}

class DQuestionnaireSkip extends StatelessWidget {
  const DQuestionnaireSkip({super.key, this.label = 'Skip'});
  final String label;
  @override
  Widget build(BuildContext context) {
    final scope = _DQuestionnaireScope.of(context);
    return DButton(
      onPressed: scope.notifier!.canSkip ? scope.skip : null,
      variant: DButtonVariant.outline,
      label: Text(label),
    );
  }
}

class DQuestionnaireNext extends StatelessWidget {
  const DQuestionnaireNext({super.key, this.label = 'Next'});
  final String label;
  @override
  Widget build(BuildContext context) {
    final scope = _DQuestionnaireScope.of(context);
    return DButton(
      onPressed: scope.notifier!.canGoNext ? scope.next : null,
      loading: scope.notifier!.isValidating,
      label: Text(label),
    );
  }
}

class DQuestionnaireSubmit extends StatelessWidget {
  const DQuestionnaireSubmit({super.key, this.label = 'Submit'});
  final String label;
  @override
  Widget build(BuildContext context) {
    final scope = _DQuestionnaireScope.of(context);
    return DButton(
      onPressed: scope.notifier!.canGoNext ? null : scope.submit,
      loading: scope.notifier!.isValidating,
      label: Text(label),
    );
  }
}

class DQuestionnaireReset extends StatelessWidget {
  const DQuestionnaireReset({super.key, this.label = 'Reset'});
  final String label;
  @override
  Widget build(BuildContext context) {
    final scope = _DQuestionnaireScope.of(context);
    return DButton(
      onPressed: scope.notifier!.isValidating ? null : scope.reset,
      variant: DButtonVariant.outline,
      label: Text(label),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
