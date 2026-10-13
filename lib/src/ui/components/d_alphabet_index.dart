import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/d_icon.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_card.dart';

@immutable
class DAlphabetIndexEntry<T> {
  const DAlphabetIndexEntry({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final DIconData? icon;
}

/// A compact press/drag index. Entry bounds meet without expanded hit targets.
/// The caller owns scrolling and can suspend list interaction during a scrub.
class DAlphabetIndex<T> extends StatefulWidget {
  const DAlphabetIndex({
    super.key,
    required this.entries,
    required this.onSelected,
    this.onScrubChanged,
  });

  final List<DAlphabetIndexEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final ValueChanged<bool>? onScrubChanged;

  @override
  State<DAlphabetIndex<T>> createState() => _DAlphabetIndexState<T>();
}

class _DAlphabetIndexState<T> extends State<DAlphabetIndex<T>> {
  final _focus = FocusNode();
  int? _pointer;
  int? _held;
  int _keyboardIndex = 0;
  double _rowHeight = 20;
  bool _focused = false;

  @override
  void didUpdateWidget(DAlphabetIndex<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _keyboardIndex = _keyboardIndex.clamp(
      0,
      widget.entries.isEmpty ? 0 : widget.entries.length - 1,
    );
    if (_pointer != null &&
        !listEquals(
          [for (final entry in oldWidget.entries) entry.value],
          [for (final entry in widget.entries) entry.value],
        )) {
      _pointer = null;
      _held = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onScrubChanged?.call(false);
      });
    }
  }

  void _select(int index, {bool show = true}) {
    if (widget.entries.isEmpty) return;
    index = index.clamp(0, widget.entries.length - 1);
    if (show && _held == index) return;
    setState(() {
      _held = show ? index : null;
      _keyboardIndex = index;
    });
    widget.onSelected(widget.entries[index].value);
  }

  void _at(double y) => _select((y / _rowHeight).floor());

  void _finish() {
    if (_pointer == null) return;
    _pointer = null;
    setState(() => _held = null);
    widget.onScrubChanged?.call(false);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.entries.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _select(
        _keyboardIndex + (key == LogicalKeyboardKey.arrowDown ? 1 : -1),
        show: false,
      );
    } else if (key == LogicalKeyboardKey.home) {
      _select(0, show: false);
    } else if (key == LogicalKeyboardKey.end) {
      _select(widget.entries.length - 1, show: false);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _select(_keyboardIndex, show: false);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final tokens = DTokens.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    _rowHeight = 20 * scale;
    final width = 20 * scale;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointer != null || event.buttons != kPrimaryButton) return;
            _pointer = event.pointer;
            _focus.requestFocus();
            widget.onScrubChanged?.call(true);
            _at(event.localPosition.dy);
          },
          onPointerMove: (event) {
            if (event.pointer == _pointer) _at(event.localPosition.dy);
          },
          onPointerUp: (event) {
            if (event.pointer == _pointer) _finish();
          },
          onPointerCancel: (event) {
            if (event.pointer == _pointer) _finish();
          },
          child: SizedBox(
            width: width,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.entries.length; i++)
                      Semantics(
                        button: true,
                        label: widget.entries[i].label,
                        onTap: () => _select(i, show: false),
                        child: SizedBox(
                          width: width,
                          height: _rowHeight,
                          child: Center(
                            child: ExcludeSemantics(
                              child: widget.entries[i].icon != null
                                  ? DIcon(
                                      widget.entries[i].icon!,
                                      size: 11 * scale,
                                      color: tokens.mutedForeground,
                                    )
                                  : Text(
                                      widget.entries[i].label,
                                      style: TextStyle(
                                        fontSize: DiscourseTypography.micro,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            (_held == i ||
                                                (_focused &&
                                                    _keyboardIndex == i))
                                            ? tokens.primary
                                            : tokens.mutedForeground,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_held case final held?)
                  PositionedDirectional(
                    end: width + 8,
                    width: 44 * scale,
                    height: 44 * scale,
                    top: (held + .5) * _rowHeight - 22 * scale,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: DCard(
                          variant: DCardVariant.capsule,
                          spacing: 0,
                          border: false,
                          backgroundColor: tokens.primary,
                          child: SizedBox(
                            width: 44 * scale,
                            height: 44 * scale,
                            child: Center(
                              child: widget.entries[held].icon != null
                                  ? DIcon(
                                      widget.entries[held].icon!,
                                      size: 16 * scale,
                                      color: tokens.primaryForeground,
                                    )
                                  : Text(
                                      widget.entries[held].label,
                                      style: TextStyle(
                                        fontSize: DiscourseTypography.magnifier,
                                        fontWeight: FontWeight.w800,
                                        color: tokens.primaryForeground,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
