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
  final GlobalKey<DSidebarProviderState> _sidebarKey =
      GlobalKey<DSidebarProviderState>();
  final Map<int, GlobalKey> _sectionKeys = {};
  ComponentReference _selected = _foundations;
  StyleguideTheme _theme = StyleguideTheme.current;
  Brightness? _documentationBrightness;
  double _width = 0;
  double _scale = 1;
  bool _rtl = false;
  bool _reducedMotion = false;
  bool _settingsOpen = false;
  int _activeOutlineIndex = -1;
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
      _activeOutlineIndex = -1;
      _sectionKeys.clear();
    });
    _sidebarKey.currentState?.setOpenMobile(false);
    _detailScroll.jumpTo(0);
  }

  String _normalizedSectionLabel(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  GlobalKey _sectionKey(int index) =>
      _sectionKeys.putIfAbsent(index, GlobalKey.new);

  void _scrollToSection(int index) {
    setState(() => _activeOutlineIndex = index);
    final target = _sectionKey(index).currentContext?.findRenderObject();
    if (target is! RenderBox || !_detailScroll.hasClients) return;
    final offset =
        (_detailScroll.offset + target.localToGlobal(Offset.zero).dy - 100)
            .clamp(
              _detailScroll.position.minScrollExtent,
              _detailScroll.position.maxScrollExtent,
            );
    _detailScroll.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) {
    final hostTheme = Theme.of(context);
    return Theme(
      data: styleguideDocumentationTheme(
        hostTheme,
        _documentationBrightness ?? hostTheme.brightness,
      ),
      child: DSidebarProvider(
        key: _sidebarKey,
        mobileBreakpoint: 900,
        child: Builder(builder: (context) => _page(context, hostTheme)),
      ),
    );
  }

  Widget _page(BuildContext context, ThemeData hostTheme) {
    final tokens = DTokens.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_sidebarKey.currentState!.openMobile) {
            _sidebarKey.currentState!.setOpenMobile(false);
          } else {
            _close();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _focusSearch,
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
                            _sidebar(context, wide),
                            Expanded(child: _detail(context, hostTheme)),
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
              const DSidebarTrigger(
                key: ValueKey('styleguide-navigation'),
                semanticLabel: 'Browse components',
              ),
              const SizedBox(width: 8),
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
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    return DInput(
      key: const ValueKey('styleguide-search'),
      controller: _search,
      focusNode: _searchFocus,
      hintText: 'Search components...',
      prefix: const Icon(Icons.search, size: 16),
      suffix: _search.text.isEmpty
          ? null
          : StyleguideAction(
              label: 'Clear search',
              icon: Icons.close,
              iconOnly: true,
              onPressed: () => setState(_search.clear),
            ),
      onTap: () {
        final sidebar = _sidebarKey.currentState!;
        if (!sidebar.isMobile && !sidebar.open) sidebar.setOpen(true);
      },
      onChanged: (_) => setState(() {}),
    );
  }

  void _focusSearch() {
    final sidebar = _sidebarKey.currentState!;
    if (sidebar.isMobile) {
      sidebar.setOpenMobile(true, initialFocusNode: _searchFocus);
    } else {
      sidebar.setOpen(true);
      _searchFocus.requestFocus();
    }
  }

  Widget _sidebar(BuildContext context, bool wide) {
    final entries = _entries
        .where((entry) => entry.matches(_search.text))
        .toList();
    Widget menu(Iterable<ComponentReference> entries) => DSidebarMenu(
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: DSidebarMenuItem(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: IntrinsicWidth(
                  child: DSidebarMenuButton(
                    key: ValueKey('styleguide-component-${entry.id}'),
                    height: 30,
                    isActive: entry.id == _selected.id,
                    onPressed: () => _select(entry),
                    child: Text(
                      entry.name,
                      style: styleguideText(
                        context,
                        size: 13,
                        height: 18,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return DSidebar(
      key: const ValueKey('styleguide-sidebar'),
      width: 240,
      mobileWidth: 320,
      semanticLabel: 'Component navigation',
      side: Directionality.of(context) == TextDirection.rtl
          ? DSidebarSide.right
          : DSidebarSide.left,
      backgroundColor: DTokens.of(context).background,
      header: wide
          ? null
          : DSidebarHeader(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                child: _searchField(context),
              ),
            ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: wide ? 16 : 8,
          top: 16,
          end: 8,
          bottom: 16,
        ),
        child: DSidebarContent(
          key: const ValueKey('styleguide-component-list'),
          children: [
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No components match your search.',
                  style: styleguideText(context, muted: true),
                ),
              )
            else if (_search.text.isNotEmpty)
              DSidebarGroup(child: menu(entries))
            else ...[
              DSidebarGroup(
                label: const DSidebarGroupLabel(child: Text('Getting started')),
                child: menu([_foundations]),
              ),
              DSidebarGroup(
                label: const DSidebarGroupLabel(child: Text('Components')),
                child: menu(componentCatalogue),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, ThemeData hostTheme) {
    final group = componentExamples[_selected.id];
    final examples = group?.examples ?? const <StyleguideExample>[];
    final sections = _visibleSections;
    final assignments = _assignExamples(sections, examples);
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
              constraints: const BoxConstraints(maxWidth: 640),
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
                  const SizedBox(height: 32),
                  if (examples.isNotEmpty) ...[
                    _previewControls(context),
                    for (
                      var sectionIndex = 0;
                      sectionIndex < sections.length;
                      sectionIndex++
                    ) ...[
                      SizedBox(height: sectionIndex == 0 ? 40 : 56),
                      _sectionHeading(
                        context,
                        sections[sectionIndex],
                        sectionIndex,
                      ),
                      for (final exampleIndex in assignments[sectionIndex]) ...[
                        const SizedBox(height: 20),
                        _exampleDocumentation(
                          context,
                          hostTheme,
                          examples[exampleIndex],
                          exampleIndex,
                          showTitle:
                              _normalizedSectionLabel(
                                examples[exampleIndex].title,
                              ) !=
                              _normalizedSectionLabel(
                                sections[sectionIndex].label,
                              ),
                        ),
                      ],
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

  List<ComponentReferenceSection> get _visibleSections =>
      _selected.documentOutline.toList(growable: false);

  List<List<int>> _assignExamples(
    List<ComponentReferenceSection> sections,
    List<StyleguideExample> examples,
  ) {
    final assignments = List.generate(sections.length, (_) => <int>[]);
    if (sections.isEmpty) return assignments;

    final fallbackSections = <int>[
      for (var index = 0; index < sections.length; index++)
        if (sections[index].depth == 0 &&
            !const {'Composition', 'Changelog'}.contains(sections[index].label))
          index,
    ];

    for (var exampleIndex = 0; exampleIndex < examples.length; exampleIndex++) {
      final example = examples[exampleIndex];
      var bestSection = -1;
      var bestScore = 0;
      for (
        var sectionIndex = 0;
        sectionIndex < sections.length;
        sectionIndex++
      ) {
        final needle = _normalizedSectionLabel(sections[sectionIndex].label);
        final title = _normalizedSectionLabel(example.title);
        final states = example.states.map(_normalizedSectionLabel);
        final score = switch ((title, states)) {
          (final title, _) when title == needle => 100,
          (_, final states) when states.contains(needle) => 90,
          (final title, _) when title.contains(needle) => 80,
          (final title, _) when needle.contains(title) => 70,
          _ => 0,
        };
        if (score > bestScore) {
          bestSection = sectionIndex;
          bestScore = score;
        }
      }
      if (bestSection < 0) {
        final candidates = fallbackSections.isEmpty
            ? List.generate(sections.length, (index) => index)
            : fallbackSections;
        bestSection =
            candidates[(exampleIndex * candidates.length ~/ examples.length)
                .clamp(0, candidates.length - 1)];
      }
      assignments[bestSection].add(exampleIndex);
    }
    return assignments;
  }

  Widget _previewControls(BuildContext context) => Wrap(
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
            for (final mode in StyleguideTheme.values) mode: mode.label,
          },
          onChanged: (mode) => setState(() => _theme = mode),
        ),
      ),
      SizedBox(
        width: 96,
        child: StyleguideChoice<double>(
          label: 'Viewport width',
          value: _width,
          options: {0: 'Fit', 360: '360 px', 768: '768 px', 1024: '1024 px'},
          onChanged: (width) => setState(() => _width = width),
        ),
      ),
      StyleguideAction(
        key: const ValueKey('styleguide-settings'),
        label: 'Preview settings',
        icon: Icons.tune,
        iconOnly: true,
        selected: _settingsOpen,
        onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
      ),
      StyleguideAction(
        key: const ValueKey('styleguide-reset'),
        label: 'Reset examples',
        icon: Icons.refresh,
        iconOnly: true,
        onPressed: () => setState(() => _reset++),
      ),
      if (_settingsOpen) ...[
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
          onPressed: () => setState(() => _reducedMotion = !_reducedMotion),
        ),
      ],
    ],
  );

  Widget _sectionHeading(
    BuildContext context,
    ComponentReferenceSection section,
    int index,
  ) => Align(
    key: _sectionKey(index),
    alignment: AlignmentDirectional.centerStart,
    child: Semantics(
      header: true,
      child: Text(
        section.label,
        key: ValueKey('styleguide-section-heading-$index'),
        style: styleguideText(
          context,
          size: section.depth == 0 ? 24 : 20,
          height: section.depth == 0 ? 32 : 28,
          weight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _exampleDocumentation(
    BuildContext context,
    ThemeData hostTheme,
    StyleguideExample example,
    int exampleIndex, {
    required bool showTitle,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showTitle) ...[
        Semantics(
          header: true,
          child: Text(
            example.title,
            key: ValueKey('styleguide-example-title-$exampleIndex'),
            style: styleguideText(
              context,
              size: 20,
              height: 28,
              weight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      _StyleguideExamplePanel(
        key: ValueKey('${_selected.id}/$exampleIndex'),
        componentId: _selected.id,
        exampleIndex: exampleIndex,
        example: example,
        hostTheme: hostTheme,
        theme: _theme,
        width: _width,
        scale: _scale,
        rtl: _rtl,
        reducedMotion: _reducedMotion,
        reset: _reset,
      ),
    ],
  );

  Widget _tableOfContents(BuildContext context) {
    final sections = _visibleSections;
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
          for (var index = 0; index < sections.length; index++)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: sections[index].depth * 32.0,
              ),
              child: StyleguideAction(
                key: ValueKey('styleguide-section-$index'),
                label: sections[index].label,
                selected: index == _activeOutlineIndex,
                alignment: AlignmentDirectional.centerStart,
                onPressed: () => _scrollToSection(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _StyleguideExamplePanel extends StatefulWidget {
  const _StyleguideExamplePanel({
    super.key,
    required this.componentId,
    required this.exampleIndex,
    required this.example,
    required this.hostTheme,
    required this.theme,
    required this.width,
    required this.scale,
    required this.rtl,
    required this.reducedMotion,
    required this.reset,
  });

  final String componentId;
  final int exampleIndex;
  final StyleguideExample example;
  final ThemeData hostTheme;
  final StyleguideTheme theme;
  final double width;
  final double scale;
  final bool rtl;
  final bool reducedMotion;
  final int reset;

  @override
  State<_StyleguideExamplePanel> createState() =>
      _StyleguideExamplePanelState();
}

class _StyleguideExamplePanelState extends State<_StyleguideExamplePanel> {
  final ScrollController _previewScroll = ScrollController();
  bool _codeOpen = false;
  bool _copied = false;

  @override
  void dispose() {
    _previewScroll.dispose();
    super.dispose();
  }

  ValueKey<String> _key(String base) => ValueKey(
    widget.exampleIndex == 0 ? base : '$base-${widget.exampleIndex}',
  );

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final code =
        "import 'package:discourse_native/discourse_ui.dart';\n\n${widget.example.code}";
    return Container(
      key: _key('styleguide-example-panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = widget.width == 0
                  ? constraints.maxWidth
                  : widget.width;
              final scrollBehavior = ScrollConfiguration.of(context);
              return ColoredBox(
                color: tokens.muted,
                child: DScrollBar(
                  key: _key('styleguide-preview-scrollbar'),
                  axis: Axis.horizontal,
                  controller: _previewScroll,
                  thumbVisibility: width > constraints.maxWidth,
                  child: ScrollConfiguration(
                    behavior: scrollBehavior.copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _previewScroll,
                      scrollDirection: Axis.horizontal,
                      child: ScrollConfiguration(
                        behavior: scrollBehavior,
                        child: SizedBox(
                          width: math.max(width, constraints.maxWidth),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              key: _key(
                                'styleguide-example-viewport-${widget.componentId}',
                              ),
                              width: width,
                              height: switch (widget.componentId) {
                                'accordion' => 800,
                                'card' => 480,
                                'sidebar' => 500,
                                _ => 400,
                              },
                              child: _ExampleViewport(
                                key: ValueKey(
                                  '${widget.componentId}/${widget.exampleIndex}/${widget.reset}',
                                ),
                                previewKey: _key('styleguide-preview'),
                                theme: widget.theme.resolve(widget.hostTheme),
                                scale: widget.scale,
                                rtl: widget.rtl,
                                reducedMotion: widget.reducedMotion,
                                example: widget.example,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: tokens.border),
          ColoredBox(
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
                          key: _key('styleguide-code-toggle'),
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
}

class _ExampleViewport extends StatefulWidget {
  const _ExampleViewport({
    required this.previewKey,
    required this.theme,
    required this.scale,
    required this.rtl,
    required this.reducedMotion,
    required this.example,
    super.key,
  });
  final Key previewKey;
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
            child: DToaster(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Material(
                    key: widget.previewKey,
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
    ),
  );
}
