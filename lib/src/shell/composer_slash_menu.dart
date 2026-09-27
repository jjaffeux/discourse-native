import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import 'composer_controller.dart';
import 'markdown_highlight.dart';

/// A composer action uses the same callback and availability as its toolbar.
class ComposerSlashAction {
  const ComposerSlashAction({
    required this.label,
    this.icon,
    this.leadingText,
    this.hint,
    required this.onInvoke,
    this.group = 'Insert',
    this.keywords = const [],
  });

  final String label;
  final DIconData? icon;
  final String? leadingText;
  final String? hint;
  final VoidCallback onInvoke;
  final String group;
  final List<String> keywords;
}

typedef ComposerSlashActions = List<ComposerSlashAction> Function(BuildContext);

typedef ComposerSlashQuery = ({int start, int end, String query});

/// Slash commands start at a word boundary, never inside URLs or code.
ComposerSlashQuery? composerSlashQuery(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid ||
      !selection.isCollapsed ||
      selection.end > value.text.length ||
      !value.composing.isCollapsed) {
    return null;
  }
  final before = value.text.substring(0, selection.end);
  final match = RegExp(r'(?:^|\s)/([a-zA-Z0-9-]{0,40})$').firstMatch(before);
  if (match == null) return null;
  final start = before.lastIndexOf('/');
  if (selection.end < value.text.length &&
      !RegExp(r'\s').hasMatch(value.text[selection.end])) {
    return null;
  }
  final prefix = before.substring(0, start);
  if (RegExp(r'^(?: {4}|\t)').hasMatch(prefix.split('\n').last) ||
      markdownCodeRanges(value.text).contains(start) ||
      '`'.allMatches(prefix.split('\n').last).length.isOdd) {
    return null;
  }
  return (start: start, end: selection.end, query: match.group(1)!);
}

class ComposerSlashMenu extends StatefulWidget {
  const ComposerSlashMenu({
    super.key,
    required this.composer,
    required this.actions,
    required this.renderEditable,
    required this.scroll,
    required this.child,
    this.hintStyle,
  });

  final ComposerController composer;
  final ComposerSlashActions actions;
  final RenderEditable? Function() renderEditable;
  final Listenable scroll;
  final Widget child;
  final TextStyle? hintStyle;

  @override
  State<ComposerSlashMenu> createState() => ComposerSlashMenuState();
}

class ComposerSlashMenuState extends State<ComposerSlashMenu> {
  final _command = DCommandController<String>();
  final _stack = GlobalKey();
  ComposerSlashQuery? _query;
  int? _dismissed;
  Rect? _caret;
  Rect? _lastVisibleCaret;
  String _lastVisibleQuery = '';
  List<ComposerSlashAction> _lastVisibleActions = const [];
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _schedule();
  }

  void _listen() {
    widget.composer.text.addListener(_schedule);
    widget.composer.focus.addListener(_schedule);
    widget.composer.addListener(_schedule);
    widget.scroll.addListener(_schedule);
  }

  void _unlisten(ComposerSlashMenu old) {
    old.composer.text.removeListener(_schedule);
    old.composer.focus.removeListener(_schedule);
    old.composer.removeListener(_schedule);
    old.scroll.removeListener(_schedule);
  }

  @override
  void didUpdateWidget(ComposerSlashMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composer != widget.composer ||
        oldWidget.scroll != widget.scroll) {
      _unlisten(oldWidget);
      _listen();
      _dismissed = null;
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final composer = widget.composer;
      var query = composerSlashQuery(composer.text.value);
      if (query == null) _dismissed = null;
      if (!composer.isEditing ||
          composer.loadingBody ||
          !composer.focus.hasFocus ||
          query?.start == _dismissed) {
        query = null;
      }
      Rect? caret;
      final editable = query == null ? null : widget.renderEditable();
      final box = _stack.currentContext?.findRenderObject();
      if (query != null &&
          editable != null &&
          box is RenderBox &&
          box.hasSize) {
        final local = editable.getLocalRectForCaret(
          TextPosition(offset: query.end),
        );
        caret = Rect.fromPoints(
          box.globalToLocal(editable.localToGlobal(local.topLeft)),
          box.globalToLocal(editable.localToGlobal(local.bottomRight)),
        );
        if (!(Offset.zero & box.size).overlaps(caret)) query = null;
      }
      if (query != _query || caret != _caret) {
        setState(() {
          _query = query;
          _caret = caret;
        });
      }
    });
  }

  void _dismiss() {
    if (!mounted) return;
    setState(() {
      _dismissed = _query?.start;
      _query = null;
    });
  }

  void _cancel() {
    if (!mounted) return;
    final query = _query;
    final composer = widget.composer;
    final value = composer.text.value;
    _dismiss();
    // Only an unused trigger is disposable. A typed query is ordinary draft
    // text, and a delayed dismissal must never remove a newer edit.
    if (query != null &&
        query.query.isEmpty &&
        composer.isEditing &&
        composerSlashQuery(value) == query) {
      composer.text.value = TextEditingValue(
        text: value.text.replaceRange(query.start, query.end, ''),
        selection: TextSelection.collapsed(offset: query.start),
      );
    }
    if (composer.isEditing) composer.focus.requestFocus();
  }

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (_query == null || !widget.composer.text.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.space) {
      _dismiss();
      // Leave insertion to the editor so the space and slash remain literal.
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final result = _command.handleKeyEvent(event);
    if (result == KeyEventResult.handled) return result;
    // An empty search must not submit chat or insert a newline behind the menu.
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.handled;
    }
    return result;
  }

  void _activate(ComposerSlashAction action) {
    final query = _query;
    final composer = widget.composer;
    if (query == null ||
        !composer.isEditing ||
        composerSlashQuery(composer.text.value) != query) {
      return;
    }
    _dismiss();
    final value = composer.text.value;
    composer.text.value = TextEditingValue(
      text: value.text.replaceRange(query.start, query.end, ''),
      selection: TextSelection.collapsed(offset: query.start),
    );
    composer.focus.requestFocus();
    // Plugin actions may capture source offsets (for example Edit event).
    // Resolve them against the document after removing the command query.
    final refreshed = widget
        .actions(context)
        .where((item) => item.label == action.label)
        .firstOrNull;
    refreshed?.onInvoke();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final text = widget.composer.text.text;
    final open = query != null && _caret != null;
    // The dropdown stays mounted during its exit animation. Keep its anchor
    // and contents stable after the live query closes, until the next opening.
    if (open) {
      _lastVisibleCaret = _caret;
      _lastVisibleQuery = query.query;
      _lastVisibleActions = widget.actions(context);
    }
    final actions = _lastVisibleActions;
    final caret = _lastVisibleCaret;
    return DDropdownMenu(
      open: open,
      restoreFocus: false,
      onOpenChange: (open, reason) {
        if (!open) {
          if (reason == DPopoverChangeReason.escape) {
            _cancel();
          } else {
            _dismiss();
          }
        }
      },
      content: DDropdownMenuContent(
        semanticLabel: 'Composer commands',
        autofocus: false,
        width: 320,
        children: [
          TextFieldTapRegion(
            child: DCommand<String>(
              controller: _command,
              query: _lastVisibleQuery,
              loop: true,
              onEscape: _cancel,
              onSelected: (label) =>
                  _activate(actions.firstWhere((a) => a.label == label)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DCommandList<String>(
                    children: [
                      const DCommandEmpty(child: Text('No matching commands.')),
                      for (final group in actions.map((a) => a.group).toSet())
                        DCommandGroup<String>(
                          heading: Text(group),
                          items: [
                            for (final action in actions.where(
                              (a) => a.group == group,
                            ))
                              DCommandItem<String>(
                                value: action.label,
                                searchValue: action.label,
                                keywords: action.keywords,
                                leading: action.leadingText != null
                                    ? Text(action.leadingText!)
                                    : action.icon != null
                                    ? DIcon(action.icon!)
                                    : null,
                                trailing: action.hint == null
                                    ? null
                                    : DCommandShortcut(Text(action.hint!)),
                                child: Text(action.label),
                              ),
                          ],
                        ),
                    ],
                  ),
                  const DSeparator(),
                  DButton(
                    variant: DButtonVariant.ghost,
                    label: const Text('Close menu'),
                    onPressed: _cancel,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      child: Stack(
        key: _stack,
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned(
            left: caret?.left ?? 0,
            top: caret?.top ?? 0,
            child: DPopoverAnchor(
              child: SizedBox(width: 1, height: caret?.height ?? 1),
            ),
          ),
          // Layout can rebuild before the cached query catches up with edits.
          if (query != null &&
              query.query.isEmpty &&
              caret != null &&
              (query.end == text.length ||
                  (query.end < text.length && text[query.end] == '\n')))
            Positioned(
              left: caret.right + 2,
              top: caret.top,
              right: 0,
              child: IgnorePointer(
                child: Text(
                  'Type to search',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style:
                      (widget.hintStyle ?? DefaultTextStyle.of(context).style)
                          .copyWith(color: DTokens.of(context).mutedForeground),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _unlisten(widget);
    _command.dispose();
    super.dispose();
  }
}
