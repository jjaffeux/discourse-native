import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final resizableExamples = ComponentExamples(
  description: 'Resizable horizontal, vertical and nested panel layouts.',
  status: ComponentStatus.baseline,
  notes:
      'Base Nova: 1px divider, optional 4×24px rounded pill. Sizes use explicit '
      'DResizableSize.pixels or .percent; percentages exclude divider space. '
      'IDs retain sizes and child state across reorder. Removed IDs are forgotten. '
      'Controllers are borrowed and attach to one group; dispose them in the host. '
      'Arrow keys resize, Shift accelerates, Home/End reach limits, Enter toggles '
      'collapse, double-click restores the default. RTL mirrors horizontal input. '
      'Native transparent targets are 24px on desktop and at least 48px on iOS/Android; hitExtent can enlarge them further. '
      'Infeasible minima are clipped and excess maximum space stays empty; switch '
      'responsive modes before that point. Layout is not a Form input. '
      'Native and reference-rendered comparison is awaiting the desktop slot.',
  examples: [
    for (final variant in ['Horizontal', 'Vertical', 'Handle', 'Nested'])
      StyleguideExample(
        title: variant,
        description:
            'Frozen reference composition. Drag the divider or Tab to it and use arrow keys. Preview RTL, large text and live themes.',
        states: const ['Reference', 'Keyboard', 'RTL', 'Live tokens'],
        code: _referenceUsage.replaceAll('REFERENCE_VARIANT', variant),
        builder: (_) => _Reference(variant: variant),
      ),
    StyleguideExample(
      title: 'Controlled, constrained and dynamic',
      description:
          'Three panels, a fixed middle panel, collapse/expand, programmatic sizing and dynamic insertion. Changes stay local.',
      states: const [
        'Controlled',
        'Collapsed',
        'Disabled panel',
        'Dynamic IDs',
      ],
      code: _controlledUsage,
      builder: (_) => const _Controlled(),
    ),
    StyleguideExample(
      title: 'Production column and Chat split — local data',
      description:
          'Actual UsersColumnResizeHandle and ChatThreadPaneDivider adapters, using local widths and commit counters. No services or saved settings.',
      states: const ['App migration', 'Matrix columns', 'Chat thread'],
      code: _adapterUsage,
      builder: (_) => const _OtherAdapters(),
    ),
    StyleguideExample(
      title: 'Production pane adapter — local data',
      description:
          'Actual ResizablePane used by sidebar, inbox and diagnostics; this fixture uses an in-memory width controller and never writes preferences.',
      states: const [
        'App migration',
        'Persistence boundary',
        'Temporary maximum',
      ],
      code: _paneUsage,
      builder: (_) => const ResizableProductionFixture(),
    ),
  ],
);

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _Reference extends StatelessWidget {
  const _Reference({required this.variant});
  final String variant;
  @override
  Widget build(BuildContext context) {
    final t = DTokens.of(context);
    final nested = variant == 'Nested';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Container(
          height: 200,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(t.radius),
          ),
          child: DResizablePanelGroup(
            orientation: variant == 'Vertical'
                ? Axis.vertical
                : Axis.horizontal,
            children: [
              DResizablePanel(
                id: 'first',
                defaultSize: DResizableSize.percent(nested ? 50 : 25),
                child: _Label(
                  nested
                      ? 'One'
                      : variant == 'Vertical'
                      ? 'Header'
                      : 'Sidebar',
                ),
              ),
              DResizableHandle(withHandle: variant == 'Handle' || nested),
              DResizablePanel(
                id: 'content',
                defaultSize: DResizableSize.percent(nested ? 50 : 75),
                child: nested
                    ? const DResizablePanelGroup(
                        orientation: Axis.vertical,
                        children: [
                          DResizablePanel(
                            id: 'two',
                            defaultSize: DResizableSize.percent(25),
                            child: _Label('Two'),
                          ),
                          DResizableHandle(withHandle: true),
                          DResizablePanel(
                            id: 'three',
                            defaultSize: DResizableSize.percent(75),
                            child: _Label('Three'),
                          ),
                        ],
                      )
                    : const _Label('Content'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controlled extends StatefulWidget {
  const _Controlled();
  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  final _controller = DResizableController();
  bool _extra = true, _disabled = false;
  DResizableLayout _reported = {};
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: const Text('Collapse'),
            onPressed: () => _controller.collapse('left'),
          ),
          DButton(
            label: const Text('Expand'),
            onPressed: () => _controller.expand('left'),
          ),
          DButton(
            label: const Text('30%'),
            onPressed: () =>
                _controller.resize('left', const DResizableSize.percent(30)),
          ),
          DButton(
            label: Text(_extra ? 'Remove middle' : 'Insert middle'),
            onPressed: () => setState(() => _extra = !_extra),
          ),
          DButton(
            label: Text(_disabled ? 'Enable' : 'Disable'),
            onPressed: () => setState(() => _disabled = !_disabled),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 200,
        child: DResizablePanelGroup(
          controller: _controller,
          disabled: _disabled,
          layout: _reported.isEmpty
              ? null
              : {
                  for (final e in _reported.entries)
                    e.key: DResizableSize.pixels(e.value),
                },
          onLayoutChange: (v) => setState(() => _reported = v),
          children: [
            const DResizablePanel(
              id: 'left',
              collapsible: true,
              minSize: DResizableSize.pixels(60),
              defaultSize: DResizableSize.percent(30),
              child: _Label('Left'),
            ),
            const DResizableHandle(withHandle: true, hitExtent: 44),
            if (_extra) ...[
              const DResizablePanel(
                id: 'middle',
                disabled: true,
                defaultSize: DResizableSize.pixels(60),
                preservePixelSize: true,
                child: _Label('Fixed'),
              ),
              const DResizableHandle(withHandle: true, hitExtent: 44),
            ],
            const DResizablePanel(
              id: 'right',
              minSize: DResizableSize.pixels(60),
              child: _Label('Right'),
            ),
          ],
        ),
      ),
      Text(
        _reported.entries
            .map((e) => '${e.key}: ${e.value.round()}px')
            .join(' · '),
      ),
    ],
  );
}

/// Native review fixture using the migrated production adapter with local state.
class ResizableProductionFixture extends StatefulWidget {
  const ResizableProductionFixture({super.key});
  @override
  State<ResizableProductionFixture> createState() =>
      _ResizableProductionFixtureState();
}

class _ResizableProductionFixtureState
    extends State<ResizableProductionFixture> {
  final _width = PanelWidthController(
    initialWidth: 208,
    minimumWidth: 100,
    maximumWidth: 320,
  );
  @override
  void dispose() {
    _width.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 240,
    child: LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          ResizablePane(
            controller: _width,
            edge: ResizablePaneEdge.trailing,
            resizeKey: 'fixture',
            semanticsLabel: 'Resize local sidebar',
            dividerWidth: 1,
            maximumWidth: (c.maxWidth - 80).clamp(100, 320),
            child: ColoredBox(
              color: DTokens.of(context).muted,
              child: const _Label('Local sidebar'),
            ),
          ),
          const Expanded(child: _Label('Local topic content')),
        ],
      ),
    ),
  );
}

class _OtherAdapters extends StatefulWidget {
  const _OtherAdapters();
  @override
  State<_OtherAdapters> createState() => _OtherAdaptersState();
}

class _OtherAdaptersState extends State<_OtherAdapters> {
  double _column = 160, _thread = 160;
  int _commits = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maximum = (constraints.maxWidth - 80).clamp(100.0, 320.0);
      final hitExtent = DResizableHandle.resolveHitExtent(context, 24);
      return Column(
        children: [
          SizedBox(
            height: 96,
            child: Row(
              children: [
                SizedBox(
                  width: _column.clamp(100, maximum),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: _Label('User column')),
                      UsersColumnResizeHandle(
                        resizeKey: 'local-users',
                        semanticsLabel: 'Resize local User column',
                        width: _column.clamp(100, maximum),
                        minimumWidth: 100,
                        maximumWidth: maximum,
                        onResizeStart: () {},
                        onResize: (v) => setState(() => _column = v),
                        onResizeEnd: () => setState(() => _commits++),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: _Label('Posts')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  const Expanded(child: _Label('Local channel')),
                  SizedBox(
                    width: hitExtent,
                    child: ChatThreadPaneDivider(
                      width: _thread.clamp(100, maximum),
                      minimumWidth: 100,
                      maximumWidth: maximum,
                      onDelta: (delta) => setState(
                        () => _thread = (_thread - delta).clamp(100, maximum),
                      ),
                      onCommit: () => setState(() => _commits++),
                    ),
                  ),
                  SizedBox(
                    width: (_thread - hitExtent).clamp(
                      100 - hitExtent,
                      maximum - hitExtent,
                    ),
                    child: const _Label('Local thread'),
                  ),
                ],
              ),
            ),
          ),
          Text('Local commits: $_commits'),
        ],
      );
    },
  );
}

const _referenceUsage = r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 640, child: _Reference(variant: 'REFERENCE_VARIANT')),
      ),
    ),
  ),
);

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _Reference extends StatelessWidget {
  const _Reference({required this.variant});
  final String variant;
  @override
  Widget build(BuildContext context) {
    final t = DTokens.of(context);
    final nested = variant == 'Nested';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Container(
          height: 200,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(t.radius),
          ),
          child: DResizablePanelGroup(
            orientation: variant == 'Vertical'
                ? Axis.vertical
                : Axis.horizontal,
            children: [
              DResizablePanel(
                id: 'first',
                defaultSize: DResizableSize.percent(nested ? 50 : 25),
                child: _Label(
                  nested
                      ? 'One'
                      : variant == 'Vertical'
                      ? 'Header'
                      : 'Sidebar',
                ),
              ),
              DResizableHandle(withHandle: variant == 'Handle' || nested),
              DResizablePanel(
                id: 'content',
                defaultSize: DResizableSize.percent(nested ? 50 : 75),
                child: nested
                    ? const DResizablePanelGroup(
                        orientation: Axis.vertical,
                        children: [
                          DResizablePanel(
                            id: 'two',
                            defaultSize: DResizableSize.percent(25),
                            child: _Label('Two'),
                          ),
                          DResizableHandle(withHandle: true),
                          DResizablePanel(
                            id: 'three',
                            defaultSize: DResizableSize.percent(75),
                            child: _Label('Three'),
                          ),
                        ],
                      )
                    : const _Label('Content'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''';

const _controlledUsage =
    r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 640, child: _Controlled())),
    ),
  ),
);

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _Controlled extends StatefulWidget {
  const _Controlled();
  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  final _controller = DResizableController();
  bool _extra = true, _disabled = false;
  DResizableLayout _reported = {};
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: const Text('Collapse'),
            onPressed: () => _controller.collapse('left'),
          ),
          DButton(
            label: const Text('Expand'),
            onPressed: () => _controller.expand('left'),
          ),
          DButton(
            label: const Text('30%'),
            onPressed: () =>
                _controller.resize('left', const DResizableSize.percent(30)),
          ),
          DButton(
            label: Text(_extra ? 'Remove middle' : 'Insert middle'),
            onPressed: () => setState(() => _extra = !_extra),
          ),
          DButton(
            label: Text(_disabled ? 'Enable' : 'Disable'),
            onPressed: () => setState(() => _disabled = !_disabled),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 200,
        child: DResizablePanelGroup(
          controller: _controller,
          disabled: _disabled,
          layout: _reported.isEmpty
              ? null
              : {
                  for (final e in _reported.entries)
                    e.key: DResizableSize.pixels(e.value),
                },
          onLayoutChange: (v) => setState(() => _reported = v),
          children: [
            const DResizablePanel(
              id: 'left',
              collapsible: true,
              minSize: DResizableSize.pixels(60),
              defaultSize: DResizableSize.percent(30),
              child: _Label('Left'),
            ),
            const DResizableHandle(withHandle: true, hitExtent: 44),
            if (_extra) ...[
              const DResizablePanel(
                id: 'middle',
                disabled: true,
                defaultSize: DResizableSize.pixels(60),
                preservePixelSize: true,
                child: _Label('Fixed'),
              ),
              const DResizableHandle(withHandle: true, hitExtent: 44),
            ],
            const DResizablePanel(
              id: 'right',
              minSize: DResizableSize.pixels(60),
              child: _Label('Right'),
            ),
          ],
        ),
      ),
      Text(
        _reported.entries
            .map((e) => '${e.key}: ${e.value.round()}px')
            .join(' · '),
      ),
    ],
  );
}
''';

const _paneUsage = r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 640, child: ResizableProductionFixture()),
      ),
    ),
  ),
);

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class ResizableProductionFixture extends StatefulWidget {
  const ResizableProductionFixture({super.key});
  @override
  State<ResizableProductionFixture> createState() =>
      _ResizableProductionFixtureState();
}

class _ResizableProductionFixtureState
    extends State<ResizableProductionFixture> {
  final _width = PanelWidthController(
    initialWidth: 208,
    minimumWidth: 100,
    maximumWidth: 320,
  );
  @override
  void dispose() {
    _width.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 240,
    child: LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          ResizablePane(
            controller: _width,
            edge: ResizablePaneEdge.trailing,
            resizeKey: 'fixture',
            semanticsLabel: 'Resize local sidebar',
            dividerWidth: 1,
            maximumWidth: (c.maxWidth - 80).clamp(100, 320),
            child: ColoredBox(
              color: DTokens.of(context).muted,
              child: const _Label('Local sidebar'),
            ),
          ),
          const Expanded(child: _Label('Local topic content')),
        ],
      ),
    ),
  );
}
''';

const _adapterUsage =
    r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 640, child: _OtherAdapters())),
    ),
  ),
);

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _OtherAdapters extends StatefulWidget {
  const _OtherAdapters();
  @override
  State<_OtherAdapters> createState() => _OtherAdaptersState();
}

class _OtherAdaptersState extends State<_OtherAdapters> {
  double _column = 160, _thread = 160;
  int _commits = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maximum = (constraints.maxWidth - 80).clamp(100.0, 320.0);
    final hitExtent = DResizableHandle.resolveHitExtent(context, 24);
      return Column(
        children: [
          SizedBox(
            height: 96,
            child: Row(
              children: [
                SizedBox(
                  width: _column.clamp(100, maximum),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: _Label('User column')),
                      UsersColumnResizeHandle(
                        resizeKey: 'local-users',
                        semanticsLabel: 'Resize local User column',
                        width: _column.clamp(100, maximum),
                        minimumWidth: 100,
                        maximumWidth: maximum,
                        onResizeStart: () {},
                        onResize: (v) => setState(() => _column = v),
                        onResizeEnd: () => setState(() => _commits++),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: _Label('Posts')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  const Expanded(child: _Label('Local channel')),
                  SizedBox(
                    width: hitExtent,
                    child: ChatThreadPaneDivider(
                      width: _thread.clamp(100, maximum),
                      minimumWidth: 100,
                      maximumWidth: maximum,
                      onDelta: (delta) => setState(
                        () => _thread = (_thread - delta).clamp(100, maximum),
                      ),
                      onCommit: () => setState(() => _commits++),
                    ),
                  ),
                  SizedBox(
                    width: (_thread - hitExtent).clamp(100 - hitExtent, maximum - hitExtent),
                    child: const _Label('Local thread'),
                  ),
                ],
              ),
            ),
          ),
          Text('Local commits: $_commits'),
        ],
      );
    },
  );
}
''';
