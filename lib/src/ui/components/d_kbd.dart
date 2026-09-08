import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';
import 'd_typography.dart';

/// A keyboard hint, with no tap target, focus node, or shortcut binding.
///
/// Text uses the host's small label role and code font, with intrinsic height
/// and the inherited text scaler. Symbols have spoken defaults; override
/// [semanticLabel] for localization or a longer explanation. Compose custom
/// icons with [DKbd.child], keeping the surrounding control as the action owner.
class DKbd extends StatelessWidget {
  const DKbd(
    String this.label, {
    super.key,
    this.semanticLabel,
    this.highlighted = false,
    this.style,
  }) : child = null;

  const DKbd.child({
    super.key,
    required Widget this.child,
    required String this.semanticLabel,
    this.highlighted = false,
    this.style,
  }) : label = null;

  final String? label;
  final Widget? child;
  final String? semanticLabel;

  /// Optional presentation feedback. This never dispatches a shortcut.
  final bool highlighted;

  /// Optional text emphasis; sizes and leading normally remain theme-owned.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final textStyle = Theme.of(context).textTheme.labelSmall!
        .copyWith(
          fontFamily: DText.styleOf(
            context,
            DTextVariant.inlineCode,
          ).fontFamily,
          color: highlighted ? tokens.primaryForeground : tokens.foreground,
          fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
          decoration: highlighted ? TextDecoration.underline : null,
        )
        .merge(style);
    final duration = DMotion.duration(context, DMotion.exit);
    return Semantics(
      label: semanticLabel ?? _spokenLabel(label!),
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(
          minWidth: DSpacing.xl,
          minHeight: DSpacing.xl,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DSpacing.xs * 1.5,
          vertical: DSpacing.xs / 2,
        ),
        decoration: BoxDecoration(
          color: highlighted ? tokens.primary : tokens.muted,
          border: Border.all(
            color: highlighted ? tokens.primary : tokens.border,
          ),
          borderRadius: tokens.borderRadius,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Curves.easeOut,
            style: textStyle,
            textAlign: TextAlign.center,
            child: IconTheme.merge(
              data: IconThemeData(
                color: textStyle.color,
                size: textStyle.fontSize,
                applyTextScaling: true,
              ),
              child: child ?? Text(label!),
            ),
          ),
        ),
      ),
    );
  }
}

/// A directional, wrapping flow of keycaps and optional separators or text.
///
/// Supply bounded width (for example Flexible inside a Row) to permit wrapping.
/// Nested groups keep chords together while they fit and wrap individual keys
/// when needed. Direction defaults to the ambient direction; override it for
/// keyboard notation islands. [semanticLabel] replaces descendant speech when
/// a whole chord or sequence should be read as a single hint.
class DKbdGroup extends StatelessWidget {
  const DKbdGroup({
    super.key,
    required this.children,
    this.spacing = DSpacing.xs,
    this.runSpacing = DSpacing.xs,
    this.textDirection,
    this.semanticLabel,
  }) : assert(spacing >= 0),
       assert(runSpacing >= 0);

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final TextDirection? textDirection;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: semanticLabel != null,
    textDirection: textDirection,
    child: Directionality(
      textDirection: textDirection ?? Directionality.of(context),
      child: Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    ),
  );
}

/// Presentation of an existing logical shortcut or ordered key sequence.
///
/// This model does not register bindings. Keep a sequence’s following list immutable, like a
/// widget's children list. Platform formatting never changes the activators.
@immutable
class DShortcut {
  const DShortcut(this._first) : _following = const [];

  const DShortcut.sequence(this._first, List<SingleActivator> following)
    : _following = following;

  final SingleActivator _first;
  final List<SingleActivator> _following;

  int get length => _following.length + 1;

  SingleActivator operator [](int index) =>
      index == 0 ? _first : _following[index - 1];

  /// English spoken defaults. A keycap group's label can localize this text.
  String semanticLabel(TargetPlatform platform) => [
    for (var i = 0; i < length; i++)
      _shortcutKeys(this[i], platform).map((key) => key.spoken).join(' + '),
  ].join(', then ');

  @override
  bool operator ==(Object other) =>
      other is DShortcut &&
      length == other.length &&
      Iterable<int>.generate(
        length,
      ).every((i) => _sameActivator(this[i], other[i]));

  @override
  int get hashCode => Object.hashAll([
    for (var i = 0; i < length; i++)
      Object.hash(
        this[i].trigger,
        this[i].control,
        this[i].alt,
        this[i].shift,
        this[i].meta,
        this[i].numLock,
        this[i].includeRepeats,
      ),
  ]);
}

/// Platform-formatted hints with optional, non-consuming hardware feedback.
///
/// Existing Shortcuts/Actions remain the interaction owner. By default key-down
/// feedback preserves the app's tooltip behavior, including completed sequence
/// steps. Unrelated keys, the final key-up, changed bindings, hidden TickerMode,
/// app inactivity and window focus loss reset feedback. No focus is acquired.
/// Set [listenToKeyboard] false for a static hint. All handlers are removed when
/// disabled or disposed. [platform] affects labels only, never key matching.
class DShortcutKeycaps extends StatefulWidget {
  const DShortcutKeycaps({
    super.key,
    required this.shortcut,
    this.listenToKeyboard = true,
    this.platform,
    this.textDirection,
    this.semanticLabel,
  });

  final DShortcut shortcut;
  final bool listenToKeyboard;
  final TargetPlatform? platform;
  final TextDirection? textDirection;
  final String? semanticLabel;

  @override
  State<DShortcutKeycaps> createState() => _ShortcutKeycapsState();
}

class _ShortcutKeycapsState extends State<DShortcutKeycaps>
    with WidgetsBindingObserver {
  int _completedSteps = 0;
  bool _listening = false;
  bool _active = true;
  bool _viewFocused = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _active = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateListening();
  }

  @override
  void didUpdateWidget(DShortcutKeycaps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shortcut != widget.shortcut) _completedSteps = 0;
    _updateListening();
  }

  void _updateListening() {
    final enabled =
        widget.listenToKeyboard &&
        _active &&
        _viewFocused &&
        TickerMode.valuesOf(context).enabled;
    if (enabled == _listening) return;
    _listening = enabled;
    _completedSteps = 0;
    if (enabled) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    } else {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _active = state == AppLifecycleState.resumed;
      _updateListening();
    });
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    setState(() {
      _viewFocused = event.state == ViewFocusState.focused;
      _updateListening();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_listening) HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted || !_listening) return false;
    var completedSteps = _completedSteps;
    final shortcut = widget.shortcut;
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent && !_isModifierKey(event.logicalKey)) {
      final expected = completedSteps < shortcut.length
          ? shortcut[completedSteps]
          : null;
      if (expected?.accepts(event, keyboard) == true) {
        completedSteps++;
      } else if (shortcut[0].accepts(event, keyboard)) {
        completedSteps = 1;
      } else {
        completedSteps = 0;
      }
    } else if (event is KeyUpEvent &&
        completedSteps == shortcut.length &&
        event.logicalKey == shortcut[completedSteps - 1].trigger) {
      completedSteps = 0;
    }
    setState(() => _completedSteps = completedSteps);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shortcut = widget.shortcut;
    final platform = widget.platform ?? Theme.of(context).platform;
    return DKbdGroup(
      textDirection: widget.textDirection,
      semanticLabel: widget.semanticLabel ?? shortcut.semanticLabel(platform),
      spacing: DSpacing.sm,
      children: [
        for (var step = 0; step < shortcut.length; step++) ...[
          if (step > 0) const Text('then'),
          DKbdGroup(
            children: [
              for (final (index, key) in _shortcutKeys(
                shortcut[step],
                platform,
              ).indexed)
                DKbd(
                  key.visual,
                  key: ValueKey('shortcut-key-$step-$index'),
                  semanticLabel: key.spoken,
                  highlighted:
                      _listening &&
                      (step < _completedSteps ||
                          (step == _completedSteps &&
                              _isPressed(key, HardwareKeyboard.instance))),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

typedef _ShortcutKey = ({String visual, String spoken, LogicalKeyboardKey key});

List<_ShortcutKey> _shortcutKeys(
  SingleActivator shortcut,
  TargetPlatform platform,
) {
  final apple =
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
  return [
    if (shortcut.control)
      (
        visual: apple ? '⌃' : 'Ctrl',
        spoken: 'Control',
        key: LogicalKeyboardKey.control,
      ),
    if (shortcut.alt)
      (
        visual: apple ? '⌥' : 'Alt',
        spoken: apple ? 'Option' : 'Alt',
        key: LogicalKeyboardKey.alt,
      ),
    if (shortcut.shift)
      (
        visual: apple ? '⇧' : 'Shift',
        spoken: 'Shift',
        key: LogicalKeyboardKey.shift,
      ),
    if (shortcut.meta)
      (
        visual: apple ? '⌘' : 'Meta',
        spoken: apple ? 'Command' : 'Meta',
        key: LogicalKeyboardKey.meta,
      ),
    (
      visual: _logicalKeyLabel(shortcut.trigger),
      spoken: _spokenLabel(_logicalKeyLabel(shortcut.trigger)),
      key: shortcut.trigger,
    ),
  ];
}

bool _isPressed(_ShortcutKey key, HardwareKeyboard keyboard) =>
    switch (key.key) {
      LogicalKeyboardKey.control => keyboard.isControlPressed,
      LogicalKeyboardKey.alt => keyboard.isAltPressed,
      LogicalKeyboardKey.shift => keyboard.isShiftPressed,
      LogicalKeyboardKey.meta => keyboard.isMetaPressed,
      _ => keyboard.isLogicalKeyPressed(key.key),
    };

bool _isModifierKey(LogicalKeyboardKey key) =>
    LogicalKeyboardKey.collapseSynonyms({key}).any(
      (key) => const [
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.meta,
      ].contains(key),
    );

String _logicalKeyLabel(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.enter => 'Enter',
  LogicalKeyboardKey.numpadEnter => 'Numpad Enter',
  LogicalKeyboardKey.escape => 'Esc',
  LogicalKeyboardKey.space => 'Space',
  LogicalKeyboardKey.tab => 'Tab',
  LogicalKeyboardKey.backspace => 'Backspace',
  LogicalKeyboardKey.delete => 'Delete',
  LogicalKeyboardKey.arrowUp => '↑',
  LogicalKeyboardKey.arrowDown => '↓',
  LogicalKeyboardKey.arrowLeft => '←',
  LogicalKeyboardKey.arrowRight => '→',
  _ =>
    key.keyLabel.isNotEmpty
        ? key.keyLabel.toUpperCase()
        : key.debugName ?? 'Key',
};

String _spokenLabel(String label) => switch (label) {
  '⌘' => 'Command',
  '⌃' || 'Ctrl' => 'Control',
  '⌥' => 'Option',
  '⇧' => 'Shift',
  '⏎' || '↵' => 'Enter',
  'Esc' || '⎋' => 'Escape',
  '⌫' => 'Backspace',
  '⌦' => 'Delete',
  '⇥' => 'Tab',
  '↑' => 'Arrow Up',
  '↓' => 'Arrow Down',
  '←' => 'Arrow Left',
  '→' => 'Arrow Right',
  '?' => 'Question mark',
  _ => label,
};

bool _sameActivator(SingleActivator a, SingleActivator b) =>
    a.trigger == b.trigger &&
    a.control == b.control &&
    a.alt == b.alt &&
    a.shift == b.shift &&
    a.meta == b.meta &&
    a.numLock == b.numLock &&
    a.includeRepeats == b.includeRepeats;
