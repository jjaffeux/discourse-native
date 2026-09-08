import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../discourse_ui.dart';
import 'component_catalogue.dart';
import 'component_examples.dart';
import 'styleguide_chrome.dart';
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
const _entries = [_foundations, ...componentCatalogue];

class ComponentStyleguidePage extends StatefulWidget {
  const ComponentStyleguidePage({super.key, this.onClose});
  final VoidCallback? onClose;

  @override
  State<ComponentStyleguidePage> createState() =>
      _ComponentStyleguidePageState();
}

class _ComponentStyleguidePageState extends State<ComponentStyleguidePage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'Component search');
  final ScrollController _detailScroll = ScrollController();
  final GlobalKey _detailKey = GlobalKey();
  final GlobalKey _codeKey = GlobalKey();
  final GlobalKey _notesKey = GlobalKey();
  ComponentReference _selected = _foundations;
  StyleguideTheme _theme = StyleguideTheme.current;
  Brightness? _documentationBrightness;
  double _width = 0;
  double _scale = 1;
  bool _rtl = false;
  bool _reducedMotion = false;
  bool _settingsOpen = false;
  bool _navigationOpen = false;
  bool _codeOpen = false;
  bool _notesOpen = false;
  bool _copied = false;
  int _exampleIndex = 0;
  int _reset = 0;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.onClose case final close?) {
      close();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _select(ComponentReference reference) {
    setState(() {
      _selected = reference;
      _exampleIndex = 0;
      _navigationOpen = false;
      _codeOpen = false;
      _notesOpen = false;
      _copied = false;
    });
    _detailScroll.jumpTo(0);
  }

  void _selectExample(int index) => setState(() {
    _exampleIndex = index;
    _copied = false;
  });

  @override
  Widget build(BuildContext context) {
    final hostTheme = Theme.of(context);
    return Theme(
      data: styleguideDocumentationTheme(
        hostTheme,
        _documentationBrightness ?? hostTheme.brightness,
      ),
      child: Builder(builder: (context) => _page(context, hostTheme)),
    );
  }

  Widget _page(BuildContext context, ThemeData hostTheme) {
    final tokens = DTokens.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_navigationOpen) {
            setState(() => _navigationOpen = false);
          } else {
            _close();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _searchFocus.requestFocus,
      },
      child: Scaffold(
        key: const ValueKey('component-styleguide'),
        backgroundColor: tokens.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Column(
                children: [
                  _header(context, wide),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (wide)
                              SizedBox(
                                width: 240,
                                child: _componentList(context),
                              ),
                            Expanded(
                              child: Column(
                                children: [
                                  if (!wide && _navigationOpen)
                                    SizedBox(
                                      height: math.min(
                                        240,
                                        constraints.maxHeight * .35,
                                      ),
                                      child: _componentList(context),
                                    ),
                                  Expanded(
                                    child: KeyedSubtree(
                                      key: _detailKey,
                                      child: _detail(context, hostTheme),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (constraints.maxWidth >= 1280)
                              SizedBox(
                                width: 200,
                                child: _tableOfContents(context),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool wide) {
    final tokens = DTokens.of(context);
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    return Container(
      key: const ValueKey('styleguide-header'),
      padding: EdgeInsets.fromLTRB(24, mac ? 28 : 12, 24, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (!wide) ...[
                StyleguideAction(
                  key: const ValueKey('styleguide-navigation'),
                  label: 'Browse components',
                  icon: Icons.menu,
                  iconOnly: true,
                  selected: _navigationOpen,
                  onPressed: () =>
                      setState(() => _navigationOpen = !_navigationOpen),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Row(
                  children: [
                    if (wide) ...[
                      const Icon(Icons.layers_outlined, size: 20),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        'Discourse / ui',
                        style: styleguideText(context, weight: FontWeight.w600),
                      ),
                    ),
                    if (wide) ...[
                      const SizedBox(width: 32),
                      Text(
                        'Components',
                        style: styleguideText(
                          context,
                          size: 13,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (wide) ...[
                SizedBox(width: 250, child: _searchField(context)),
                const SizedBox(width: 16),
              ],
              StyleguideAction(
                key: const ValueKey('styleguide-documentation-theme'),
                label: 'Toggle documentation theme',
                icon: Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                iconOnly: true,
                onPressed: () => setState(
                  () => _documentationBrightness =
                      Theme.of(context).brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
                ),
              ),
              const SizedBox(width: 4),
              StyleguideAction(
                key: const ValueKey('styleguide-close'),
                label: 'Close styleguide',
                icon: Icons.close,
                iconOnly: true,
                onPressed: _close,
              ),
            ],
          ),
          if (!wide) ...[const SizedBox(height: 8), _searchField(context)],
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final tokens = DTokens.of(context);
    return TextField(
      key: const ValueKey('styleguide-search'),
      controller: _search,
      focusNode: _searchFocus,
      style: styleguideText(context, size: 13, height: 18),
      decoration: InputDecoration(
        hintText: 'Search components...',
        hintStyle: styleguideText(context, size: 13, height: 18, muted: true),
        isDense: true,
        filled: true,
        fillColor: tokens.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        prefixIcon: Icon(Icons.search, size: 16, color: tokens.mutedForeground),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        suffixIcon: _search.text.isEmpty
            ? null
            : StyleguideAction(
                label: 'Clear search',
                icon: Icons.close,
                iconOnly: true,
                onPressed: () => setState(_search.clear),
              ),
        border: OutlineInputBorder(
          borderRadius: tokens.borderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: tokens.borderRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: tokens.borderRadius,
          borderSide: BorderSide(color: tokens.foreground),
        ),
      ),
      onChanged: (_) => setState(() => _navigationOpen = true),
    );
  }

  Widget _componentList(BuildContext context) {
    final entries = _entries
        .where((entry) => entry.matches(_search.text))
        .toList();
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No components match your search.',
          style: styleguideText(context, muted: true),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('styleguide-component-list'),
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 32),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_search.text.isEmpty &&
                (entry.id == 'foundations' || index == 1))
              Padding(
                padding: EdgeInsets.fromLTRB(10, index == 1 ? 24 : 0, 0, 8),
                child: Text(
                  index == 0 ? 'Getting started' : 'Components',
                  style: styleguideText(
                    context,
                    size: 12,
                    height: 16,
                    muted: true,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: StyleguideAction(
                key: ValueKey('styleguide-component-${entry.id}'),
                label: entry.name,
                selected: entry.id == _selected.id,
                alignment: AlignmentDirectional.centerStart,
                onPressed: () => _select(entry),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detail(BuildContext context, ThemeData hostTheme) {
    final group = componentExamples[_selected.id];
    final example = group?.examples.elementAtOrNull(_exampleIndex);
    final index = _entries.indexOf(_selected);
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 600 ? 24.0 : 48.0;
        return SingleChildScrollView(
          key: ValueKey('styleguide-detail-${_selected.id}'),
          controller: _detailScroll,
          padding: EdgeInsets.fromLTRB(inset, 40, inset, 64),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 704),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            _selected.name,
                            style: styleguideText(
                              context,
                              size: 30,
                              height: 36,
                              weight: FontWeight.w600,
                            ).copyWith(letterSpacing: -.75),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      StyleguideAction(
                        label: 'Previous component',
                        icon: Icons.arrow_back,
                        iconOnly: true,
                        onPressed: index > 0
                            ? () => _select(_entries[index - 1])
                            : null,
                      ),
                      const SizedBox(width: 4),
                      StyleguideAction(
                        label: 'Next component',
                        icon: Icons.arrow_forward,
                        iconOnly: true,
                        onPressed: index < _entries.length - 1
                            ? () => _select(_entries[index + 1])
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    group?.description.isNotEmpty == true
                        ? group!.description
                        : 'This component is part of the library catalogue.',
                    style: styleguideText(
                      context,
                      size: 16,
                      height: 24,
                      muted: true,
                    ),
                  ),
                  if (group?.status == ComponentStatus.baseline) ...[
                    const SizedBox(height: 12),
                    Text(
                      'App baseline · shadcn implementation pending',
                      style: styleguideText(
                        context,
                        size: 12,
                        height: 18,
                        muted: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (example != null) ...[
                    if (group!.examples.length > 1) ...[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: 320,
                          child: StyleguideChoice<int>(
                            label: 'Example',
                            value: _exampleIndex,
                            options: {
                              for (var i = 0; i < group.examples.length; i++)
                                i: group.examples[i].title,
                            },
                            onChanged: _selectExample,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _examplePanel(context, hostTheme, example),
                    const SizedBox(height: 32),
                    Semantics(
                      header: true,
                      child: Text(
                        example.title,
                        style: styleguideText(
                          context,
                          size: 20,
                          height: 28,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      example.description,
                      style: styleguideText(context, height: 24, muted: true),
                    ),
                    if (example.states.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        example.states.join(' · '),
                        style: styleguideText(
                          context,
                          size: 12,
                          height: 20,
                          muted: true,
                        ),
                      ),
                    ],
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        border: Border.all(color: DTokens.of(context).border),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Its implementation and interactive examples are scheduled.',
                        style: styleguideText(context, muted: true),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Divider(height: 1, color: DTokens.of(context).border),
                  const SizedBox(height: 12),
                  Align(
                    key: _notesKey,
                    alignment: AlignmentDirectional.centerStart,
                    child: StyleguideAction(
                      label: 'Implementation notes',
                      icon: _notesOpen
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      onPressed: () => setState(() => _notesOpen = !_notesOpen),
                    ),
                  ),
                  if (_notesOpen) ...[
                    const SizedBox(height: 12),
                    if (group != null)
                      Text(
                        group.notes,
                        style: styleguideText(context, height: 24, muted: true),
                      ),
                    if (_selected.url.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        _selected.url,
                        style: styleguideText(
                          context,
                          size: 12,
                          height: 20,
                          muted: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selected.sections.join(' · '),
                        style: styleguideText(
                          context,
                          size: 12,
                          height: 20,
                          muted: true,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _examplePanel(
    BuildContext context,
    ThemeData hostTheme,
    StyleguideExample example,
  ) {
    final tokens = DTokens.of(context);
    final code =
        "import 'package:discourse_native/discourse_ui.dart';\n\n${example.code}";
    return Container(
      key: const ValueKey('styleguide-example-panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 136,
                      child: StyleguideChoice<StyleguideTheme>(
                        label: 'Theme',
                        value: _theme,
                        options: {
                          for (final mode in StyleguideTheme.values)
                            mode: mode.label,
                        },
                        onChanged: (mode) => setState(() => _theme = mode),
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: StyleguideChoice<double>(
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
                    StyleguideAction(
                      key: const ValueKey('styleguide-settings'),
                      label: 'Preview settings',
                      icon: Icons.tune,
                      iconOnly: true,
                      selected: _settingsOpen,
                      onPressed: () =>
                          setState(() => _settingsOpen = !_settingsOpen),
                    ),
                    StyleguideAction(
                      key: const ValueKey('styleguide-reset'),
                      label: 'Reset example',
                      icon: Icons.refresh,
                      iconOnly: true,
                      onPressed: () => setState(() => _reset++),
                    ),
                  ],
                ),
                if (_settingsOpen) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 96,
                        child: StyleguideChoice<double>(
                          label: 'Text scale',
                          value: _scale,
                          options: {1: '100%', 1.5: '150%', 2: '200%'},
                          onChanged: (scale) => setState(() => _scale = scale),
                        ),
                      ),
                      StyleguideAction(
                        label: 'Right to left',
                        selected: _rtl,
                        outlined: true,
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      StyleguideAction(
                        label: 'Reduce motion',
                        selected: _reducedMotion,
                        outlined: true,
                        onPressed: () =>
                            setState(() => _reducedMotion = !_reducedMotion),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: tokens.border),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = _width == 0
                  ? constraints.maxWidth
                  : math.min(_width, constraints.maxWidth);
              return ColoredBox(
                color: tokens.muted,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    height: _selected.id == 'card' ? 480 : 400,
                    child: _ExampleViewport(
                      key: ValueKey('${_selected.id}/$_exampleIndex/$_reset'),
                      theme: _theme.resolve(hostTheme),
                      scale: _scale,
                      rtl: _rtl,
                      reducedMotion: _reducedMotion,
                      example: example,
                    ),
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: tokens.border),
          ColoredBox(
            key: _codeKey,
            color: tokens.muted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: StyleguideAction(
                          key: const ValueKey('styleguide-code-toggle'),
                          label: _codeOpen ? 'Hide code' : 'View code',
                          icon: Icons.code,
                          alignment: AlignmentDirectional.centerStart,
                          onPressed: () =>
                              setState(() => _codeOpen = !_codeOpen),
                        ),
                      ),
                      StyleguideAction(
                        label: _copied ? 'Copied' : 'Copy code',
                        icon: _copied ? Icons.check : Icons.copy_outlined,
                        iconOnly: true,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: code));
                          if (mounted) setState(() => _copied = true);
                        },
                      ),
                    ],
                  ),
                ),
                if (_codeOpen)
                  SizedBox(
                    height: 280,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: SelectableText(
                        code,
                        style: styleguideText(
                          context,
                          size: 12,
                          height: 20,
                        ).copyWith(fontFamily: 'JetBrains Mono'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableOfContents(BuildContext context) {
    final examples =
        componentExamples[_selected.id]?.examples ??
        const <StyleguideExample>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 0, 12),
            child: Text(
              'On This Page',
              style: styleguideText(
                context,
                size: 12,
                height: 16,
                weight: FontWeight.w500,
              ),
            ),
          ),
          for (var i = 0; i < examples.length; i++)
            StyleguideAction(
              label: examples[i].title,
              selected: i == _exampleIndex,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () {
                _selectExample(i);
                _detailScroll.jumpTo(0);
              },
            ),
          if (examples.isNotEmpty)
            StyleguideAction(
              label: 'Usage',
              alignment: AlignmentDirectional.centerStart,
              onPressed: () {
                setState(() => _codeOpen = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    final target = _codeKey.currentContext;
                    if (target != null) {
                      unawaited(Scrollable.ensureVisible(target));
                    }
                  }
                });
              },
            ),
          StyleguideAction(
            label: 'Implementation notes',
            alignment: AlignmentDirectional.centerStart,
            onPressed: () {
              setState(() => _notesOpen = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  final target = _notesKey.currentContext;
                  if (target != null) {
                    unawaited(Scrollable.ensureVisible(target));
                  }
                }
              });
            },
          ),
        ],
      ),
    );
  }
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(DSpacing.xl),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 48),
                      ),
                      child: Center(child: widget.example.builder(context)),
                    ),
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
