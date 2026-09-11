import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'keyboard_navigation.dart';

/// The owning navigation supplies the scope; the editor contains only text.
class TopicListSearch extends StatefulWidget {
  const TopicListSearch({
    super.key,
    required this.query,
    required this.onChanged,
    this.categoryName,
  });

  final String query;
  final String? categoryName;
  final ValueChanged<String> onChanged;

  @override
  State<TopicListSearch> createState() => _TopicListSearchState();
}

class _TopicListSearchState extends State<TopicListSearch> {
  late final _text = TextEditingController(text: widget.query);
  Timer? _debounce;
  final _focus = FocusNode(debugLabel: 'Topic search');

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleSearchShortcut);
  }

  KeyEventResult _handleSearchShortcut(KeyEvent event) {
    if (!mounted ||
        !const CharacterActivator(
          '/',
        ).accepts(event, HardwareKeyboard.instance) ||
        event is! KeyDownEvent ||
        !navigationShortcutsAllowed(context)) {
      return KeyEventResult.ignored;
    }
    _focus.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(TopicListSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query && widget.query != _text.text.trim()) {
      _debounce?.cancel();
      _text.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  void _submit() {
    _debounce?.cancel();
    widget.onChanged(_text.text.trim());
  }

  void _clear() {
    _text.clear();
    _submit();
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    FocusManager.instance.removeEarlyKeyEventHandler(_handleSearchShortcut);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      child: DInputGroup(
        children: [
          DInputGroupInput(
            key: const ValueKey('topic-list-search'),
            controller: _text,
            focusNode: _focus,
            semanticLabel: 'Search topics in the current category and tags',
            hintText: widget.categoryName == null
                ? 'Search topics…'
                : 'Search in ${widget.categoryName}…',
            textInputAction: TextInputAction.search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _submit);
              setState(() {});
            },
            onSubmitted: (_) => _submit(),
          ),
          const DInputGroupAddon(
            child: ExcludeSemantics(
              child: DIcon(DIcons.magnifyingGlass, size: 16),
            ),
          ),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DKbd('/'),
          ),
          if (_text.text.isNotEmpty)
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: DInputGroupButton(
                label: const Text('Clear'),
                onPressed: _clear,
              ),
            ),
        ],
      ),
    ),
  );
}
