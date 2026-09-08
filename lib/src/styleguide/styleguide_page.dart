import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../discourse_ui.dart';
import 'component_catalogue.dart';
import 'component_examples.dart';
import 'styleguide_example.dart';
import 'styleguide_theme.dart';

/// Opens a route so the app workspace stays mounted and retains its state.
Future<void> showComponentStyleguide(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/styleguide'),
        builder: (_) => const ComponentStyleguidePage(),
      ),
    );

const _foundations = ComponentReference(
  id: 'foundations',
  name: 'Foundations',
  url: '',
  sections: ['Theme tokens', 'Typography', 'Motion', 'Spacing'],
);

class ComponentStyleguidePage extends StatefulWidget {
  const ComponentStyleguidePage({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<ComponentStyleguidePage> createState() =>
      _ComponentStyleguidePageState();
}

class _ComponentStyleguidePageState extends State<ComponentStyleguidePage> {
  final TextEditingController _search = TextEditingController();
  ComponentReference _selected = _foundations;
  StyleguideTheme _theme = StyleguideTheme.current;
  double _width = 0;
  double _scale = 1;
  bool _rtl = false;
  bool _reducedMotion = false;
  int _exampleIndex = 0;
  int _reset = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(ComponentReference reference) {
    setState(() {
      _selected = reference;
      _exampleIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (widget.onClose case final close?) {
            close();
          } else {
            unawaited(Navigator.of(context).maybePop());
          }
        },
      },
      child: Scaffold(
        key: const ValueKey('component-styleguide'),
        backgroundColor: tokens.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Component library'),
          actions: [
            IconButton(
              key: const ValueKey('styleguide-close'),
              tooltip: 'Close styleguide',
              onPressed:
                  widget.onClose ??
                  () => unawaited(Navigator.of(context).maybePop()),
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: DSpacing.sm),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(DSpacing.lg),
                      child: _searchField(),
                    ),
                    if (_search.text.isNotEmpty)
                      SizedBox(height: 160, child: _componentList())
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DSpacing.lg,
                        ),
                        child: _Choice<String>(
                          label: 'Component',
                          value: _selected.id,
                          options: {
                            for (final entry in [
                              _foundations,
                              ...componentCatalogue,
                            ])
                              entry.id: entry.name,
                          },
                          onChanged: (id) => _select(
                            [
                              _foundations,
                              ...componentCatalogue,
                            ].firstWhere((entry) => entry.id == id),
                          ),
                        ),
                      ),
                    const SizedBox(height: DSpacing.sm),
                    Expanded(child: _detail()),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 252,
                    child: Material(
                      color: tokens.muted,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(DSpacing.lg),
                            child: _searchField(),
                          ),
                          Expanded(child: _componentList()),
                          const Padding(
                            padding: EdgeInsets.all(DSpacing.lg),
                            child: Text(
                              '64 components · $componentReferenceDate',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DSeparator(orientation: Axis.vertical, color: tokens.border),
                  Expanded(child: _detail()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _searchField() => TextField(
    key: const ValueKey('styleguide-search'),
    controller: _search,
    decoration: InputDecoration(
      labelText: 'Search components',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: _search.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: () => setState(_search.clear),
              icon: const Icon(Icons.close),
            ),
      border: const OutlineInputBorder(),
    ),
    onChanged: (_) => setState(() {}),
  );

  Widget _componentList() {
    final entries = [
      _foundations,
      ...componentCatalogue,
    ].where((entry) => entry.matches(_search.text)).toList();
    if (entries.isEmpty) {
      return const Center(child: Text('No components match your search.'));
    }
    return ListView.builder(
      key: const ValueKey('styleguide-component-list'),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final status =
            componentExamples[entry.id]?.status ?? ComponentStatus.planned;
        return ListTile(
          key: ValueKey('styleguide-component-${entry.id}'),
          selected: entry.id == _selected.id,
          title: Text(entry.name),
          subtitle: Text(status.name),
          onTap: () => _select(entry),
        );
      },
    );
  }

  Widget _detail() {
    final group = componentExamples[_selected.id];
    final example = group?.examples.elementAtOrNull(_exampleIndex);
    final theme = Theme.of(context);
    return ListView(
      key: ValueKey('styleguide-detail-${_selected.id}'),
      padding: const EdgeInsets.all(DSpacing.xl),
      children: [
        Text(_selected.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: DSpacing.sm),
        Text(
          group?.notes ??
              'This component is in the frozen catalogue. '
                  'Its implementation and interactive examples are scheduled.',
        ),
        if (_selected.url.isNotEmpty) ...[
          const SizedBox(height: DSpacing.sm),
          SelectableText(_selected.url, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: DSpacing.xl),
        if (example != null) ...[
          _previewSettings(),
          const SizedBox(height: DSpacing.xl),
          if (group!.examples.length > 1) ...[
            _Choice<int>(
              label: 'Example',
              value: _exampleIndex,
              options: {
                for (var i = 0; i < group.examples.length; i++)
                  i: group.examples[i].title,
              },
              onChanged: (index) => setState(() => _exampleIndex = index),
            ),
            const SizedBox(height: DSpacing.lg),
          ],
          Text(example.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: DSpacing.sm),
          Text(example.description),
          const SizedBox(height: DSpacing.md),
          Wrap(
            spacing: DSpacing.sm,
            runSpacing: DSpacing.xs,
            children: [
              for (final state in example.states) Chip(label: Text(state)),
            ],
          ),
          const SizedBox(height: DSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = _width == 0
                  ? constraints.maxWidth
                  : math.min(_width, constraints.maxWidth);
              return Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(
                  width: width,
                  height: 340,
                  child: _ExampleViewport(
                    key: ValueKey('${_selected.id}/$_exampleIndex/$_reset'),
                    theme: _theme.resolve(theme),
                    scale: _scale,
                    rtl: _rtl,
                    reducedMotion: _reducedMotion,
                    example: example,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: DSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _reset++),
              icon: const Icon(Icons.refresh),
              label: const Text('Reset example'),
            ),
          ),
          const SizedBox(height: DSpacing.lg),
          Text('Usage', style: theme.textTheme.titleMedium),
          const SizedBox(height: DSpacing.sm),
          Container(
            padding: const EdgeInsets.all(DSpacing.lg),
            color: DTokens.of(context).muted,
            child: SelectableText(
              "import 'package:discourse_native/discourse_ui.dart';\n\n${example.code}",
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ],
        if (_selected.id != 'foundations') ...[
          const SizedBox(height: DSpacing.xl),
          Text('Reference coverage', style: theme.textTheme.titleMedium),
          const SizedBox(height: DSpacing.sm),
          Text(_selected.sections.join(' · ')),
        ],
      ],
    );
  }

  Widget _previewSettings() => ExpansionTile(
    key: const PageStorageKey('styleguide-preview-settings'),
    title: const Text('Preview settings'),
    tilePadding: EdgeInsets.zero,
    initiallyExpanded: true,
    children: [
      Wrap(
        spacing: DSpacing.md,
        runSpacing: DSpacing.md,
        children: [
          SizedBox(
            width: 180,
            child: _Choice<StyleguideTheme>(
              label: 'Theme',
              value: _theme,
              options: {
                for (final mode in StyleguideTheme.values) mode: mode.label,
              },
              onChanged: (mode) => setState(() => _theme = mode),
            ),
          ),
          SizedBox(
            width: 180,
            child: _Choice<double>(
              label: 'Viewport width',
              value: _width,
              options: {
                0: 'Fit',
                360: '360 px',
                768: '768 px',
                1024: '1024 px',
              },
              onChanged: (width) => setState(() => _width = width),
            ),
          ),
          SizedBox(
            width: 180,
            child: _Choice<double>(
              label: 'Text scale',
              value: _scale,
              options: {1: '100%', 1.5: '150%', 2: '200%'},
              onChanged: (scale) => setState(() => _scale = scale),
            ),
          ),
          FilterChip(
            label: const Text('Right to left'),
            selected: _rtl,
            onSelected: (selected) => setState(() => _rtl = selected),
          ),
          FilterChip(
            label: const Text('Reduce motion'),
            selected: _reducedMotion,
            onSelected: (selected) => setState(() => _reducedMotion = selected),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
    ],
  );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    key: ValueKey('styleguide-$label'),
    initialValue: value,
    isExpanded: true,
    itemHeight: null,
    menuMaxHeight: 360,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final option in options.entries)
        DropdownMenuItem(value: option.key, child: Text(option.value)),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _ExampleViewport extends StatefulWidget {
  const _ExampleViewport({
    required this.theme,
    required this.scale,
    required this.rtl,
    required this.reducedMotion,
    required this.example,
    super.key,
  });
  final ThemeData theme;
  final double scale;
  final bool rtl;
  final bool reducedMotion;
  final StyleguideExample example;

  @override
  State<_ExampleViewport> createState() => _ExampleViewportState();
}

class _ExampleViewportState extends State<_ExampleViewport> {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ClipRect(
      child: Theme(
        data: widget.theme,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            textScaler: TextScaler.linear(widget.scale),
            disableAnimations:
                widget.reducedMotion || MediaQuery.disableAnimationsOf(context),
          ),
          child: DDirection(
            textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Material(
                  key: const ValueKey('styleguide-preview'),
                  color: DTokens.of(context).background,
                  shape: Border.all(color: DTokens.of(context).border),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(DSpacing.lg),
                    child: widget.example.builder(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
