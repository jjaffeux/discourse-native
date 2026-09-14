import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/styleguide/examples/tabs_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Preview());
}

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    home: DFocusHighlight(
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (final theme in [AppTheme.light, AppTheme.dark])
                Theme(data: theme, child: const _Sample()),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Sample extends StatefulWidget {
  const _Sample();
  @override
  State<_Sample> createState() => _SampleState();
}

class _SampleState extends State<_Sample> {
  final _items = [
    const ForumTabItem(id: 'review', title: 'Review', icon: DIcons.layerGroup),
    const ForumTabItem(id: 'chat', title: 'Side chat', icon: DIcons.comment),
  ];
  String _selected = 'chat';
  int _next = 0;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).shell.sidebar,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${Theme.of(context).brightness.name} · Forum tabs'),
          const SizedBox(height: 16),
          if (_items.isNotEmpty)
            ForumTabsBar(
              forumName: 'Preview',
              items: _items,
              selectedId: _selected,
              onAdd: () => setState(() {
                final id = 'new-${_next++}';
                _items.add(
                  ForumTabItem(id: id, title: 'Messages', icon: DIcons.inbox),
                );
                _selected = id;
              }),
              onSelect: (id) => setState(() => _selected = id),
              onClose: (id) => setState(() {
                _items.removeWhere((item) => item.id == id);
                if (_selected == id && _items.isNotEmpty) {
                  _selected = _items.first.id;
                }
              }),
              onCloseOthers: (id) => setState(() {
                _items.removeWhere((item) => item.id != id);
                _selected = id;
              }),
              onRename: (id, title) => setState(() {
                final index = _items.indexWhere((item) => item.id == id);
                _items[index] = ForumTabItem(
                  id: id,
                  title: title,
                  icon: _items[index].icon,
                );
              }),
              onReorder: (id, index) => setState(() {
                final item = _items.firstWhere((item) => item.id == id);
                _items.remove(item);
                _items.insert(index, item);
              }),
            ),
          const SizedBox(height: 24),
          const Text('Native styleguide · Document tabs'),
          const SizedBox(height: 16),
          SizedBox(
            width: 400,
            child: Builder(builder: tabsExamples.examples.first.builder),
          ),
        ],
      ),
    ),
  );
}
