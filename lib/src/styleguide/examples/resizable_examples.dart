import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final resizableExamples = ComponentExamples(
  description: 'Resizable horizontal, vertical and nested panel layouts.',
  status: ComponentStatus.implemented,
  notes:
      'Base Nova: 1px divider, optional 4×36px rounded pill. Sizes use explicit '
      'DResizableSize.pixels or .percent; percentages exclude divider space. '
      'IDs retain sizes and child state across reorder. Removed IDs are forgotten. '
      'Controllers are borrowed and attach to one group; dispose them in the host. '
      'Arrow keys resize, Shift accelerates, Home/End reach limits, Enter toggles '
      'collapse, double-click restores the default. RTL mirrors horizontal input. '
      'Resize gestures start on the divider or anywhere in a 12px workspace gutter. '
      'Infeasible minima are clipped and excess maximum space stays empty; switch '
      'responsive modes before that point. Layout is not a Form input.',
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
          fontSize: DiscourseTypography.sm,
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

                child: nested
                    ? const DResizablePanelGroup(
                        orientation: Axis.vertical,
                        children: [
                          DResizablePanel(id: 'two', child: _Label('Two')),
                          DResizableHandle(withHandle: true),
                          DResizablePanel(id: 'three', child: _Label('Three')),
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
  bool _extra = true;
  DResizableLayout _reported = {};
  @override
  void dispose() {
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
            label: Text(_extra ? 'Remove middle' : 'Insert middle'),
            onPressed: () => setState(() => _extra = !_extra),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 200,
        child: DResizablePanelGroup(
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

              minSize: DResizableSize.pixels(60),

              child: _Label('Left'),
            ),
            const DResizableHandle(withHandle: true),
            if (_extra) ...[
              const DResizablePanel(id: 'middle', child: _Label('Fixed')),
              const DResizableHandle(withHandle: true),
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
            gap: DResizableHandle.workspaceGutterExtent,
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
      final hitExtent = DResizableHandle.visualExtent();
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
                      PositionedDirectional(
                        top: 0,
                        bottom: 0,
                        end: 0,
                        width: DResizableHandle.visualExtent(),
                        child: DResizableHandle.standalone(
                          semanticLabel: 'Resize local User column',
                          value: _column.clamp(100, maximum),
                          min: 100,
                          max: maximum,
                          onChangeStart: () {},
                          onChanged: (v) => setState(() => _column = v),
                          onChangeEnd: () => setState(() => _commits++),
                        ),
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

const _referenceUsage =
    "import 'package:discourse_native/discourse_ui.dart';\nimport 'package:flutter/material.dart';\n\nvoid main() => runApp(\n  const MaterialApp(\n    home: Scaffold(\n      body: Center(\n        child: SizedBox(width: 640, child: _Reference(variant: 'REFERENCE_VARIANT')),\n      ),\n    ),\n  ),\n);\n\nclass _Label extends StatelessWidget {\n  const _Label(this.text);\n  final String text;\n  @override\n  Widget build(BuildContext context) => Center(\n    child: Padding(\n      padding: const EdgeInsets.all(24),\n      child: Text(\n        text,\n        style: TextStyle(\n          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,\n          fontSize: DiscourseTypography.sm,\n          height: 20 / 14,\n          fontWeight: FontWeight.w600,\n        ),\n      ),\n    ),\n  );\n}\n\nclass _Reference extends StatelessWidget {\n  const _Reference({required this.variant});\n  final String variant;\n  @override\n  Widget build(BuildContext context) {\n    final t = DTokens.of(context);\n    final nested = variant == 'Nested';\n    return Center(\n      child: ConstrainedBox(\n        constraints: const BoxConstraints(maxWidth: 384),\n        child: Container(\n          height: 200,\n          clipBehavior: Clip.antiAlias,\n          decoration: BoxDecoration(\n            border: Border.all(color: t.border),\n            borderRadius: BorderRadius.circular(t.radius),\n          ),\n          child: DResizablePanelGroup(\n            orientation: variant == 'Vertical'\n                ? Axis.vertical\n                : Axis.horizontal,\n            children: [\n              DResizablePanel(\n                id: 'first',\n                \n                child: _Label(\n                  nested\n                      ? 'One'\n                      : variant == 'Vertical'\n                      ? 'Header'\n                      : 'Sidebar',\n                ),\n              ),\n              DResizableHandle(withHandle: variant == 'Handle' || nested),\n              DResizablePanel(\n                id: 'content',\n                \n                child: nested\n                    ? const DResizablePanelGroup(\n                        orientation: Axis.vertical,\n                        children: [\n                          DResizablePanel(\n                            id: 'two',\n                            \n                            child: _Label('Two'),\n                          ),\n                          DResizableHandle(withHandle: true),\n                          DResizablePanel(\n                            id: 'three',\n                            \n                            child: _Label('Three'),\n                          ),\n                        ],\n                      )\n                    : const _Label('Content'),\n              ),\n            ],\n          ),\n        ),\n      ),\n    );\n  }\n}\n";

const _controlledUsage =
    "import 'package:discourse_native/discourse_ui.dart';\nimport 'package:flutter/material.dart';\n\nvoid main() => runApp(\n  const MaterialApp(\n    home: Scaffold(\n      body: Center(child: SizedBox(width: 640, child: _Controlled())),\n    ),\n  ),\n);\n\nclass _Label extends StatelessWidget {\n  const _Label(this.text);\n  final String text;\n  @override\n  Widget build(BuildContext context) => Center(\n    child: Padding(\n      padding: const EdgeInsets.all(24),\n      child: Text(\n        text,\n        style: TextStyle(\n          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,\n          fontSize: DiscourseTypography.sm,\n          height: 20 / 14,\n          fontWeight: FontWeight.w600,\n        ),\n      ),\n    ),\n  );\n}\n\nclass _Controlled extends StatefulWidget {\n  const _Controlled();\n  @override\n  State<_Controlled> createState() => _ControlledState();\n}\n\nclass _ControlledState extends State<_Controlled> {\n\n  bool _extra = true;\n  DResizableLayout _reported = {};\n  @override\n  void dispose() {\n\n    super.dispose();\n  }\n\n  @override\n  Widget build(BuildContext context) => Column(\n    children: [\n      Wrap(\n        spacing: 8,\n        runSpacing: 8,\n        children: [\n          DButton(\n            label: const Text('Collapse'),\n            onPressed: () => _controller.collapse('left'),\n          ),\n          DButton(\n            label: const Text('Expand'),\n            onPressed: () => _controller.expand('left'),\n          ),\n          DButton(\n            label: const Text('30%'),\n            onPressed: () =>\n                _controller.resize('left', const DResizableSize.percent(30)),\n          ),\n          DButton(\n            label: Text(_extra ? 'Remove middle' : 'Insert middle'),\n            onPressed: () => setState(() => _extra = !_extra),\n          ),\n          DButton(\n            label: Text(_disabled ? 'Enable' : 'Disable'),\n            onPressed: () => setState(() => _disabled = !_disabled),\n          ),\n        ],\n      ),\n      const SizedBox(height: 12),\n      SizedBox(\n        height: 200,\n        child: DResizablePanelGroup(\n          \n          \n          layout: _reported.isEmpty\n              ? null\n              : {\n                  for (final e in _reported.entries)\n                    e.key: DResizableSize.pixels(e.value),\n                },\n          onLayoutChange: (v) => setState(() => _reported = v),\n          children: [\n            const DResizablePanel(\n              id: 'left',\n              \n              minSize: DResizableSize.pixels(60),\n              \n              child: _Label('Left'),\n            ),\n            const DResizableHandle(withHandle: true),\n            if (_extra) ...[\n              const DResizablePanel(\n                id: 'middle',\n                \n                \n                \n                child: _Label('Fixed'),\n              ),\n              const DResizableHandle(withHandle: true),\n            ],\n            const DResizablePanel(\n              id: 'right',\n              minSize: DResizableSize.pixels(60),\n              child: _Label('Right'),\n            ),\n          ],\n        ),\n      ),\n      Text(\n        _reported.entries\n            .map((e) => '\${e.key}: \${e.value.round()}px')\n            .join(' · '),\n      ),\n    ],\n  );\n}\n";

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
          fontSize: DiscourseTypography.sm,
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
            gap: DResizableHandle.workspaceGutterExtent,
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

const _adapterUsage = r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
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
          fontSize: DiscourseTypography.sm,
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
    final hitExtent = DResizableHandle.visualExtent();
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
                      PositionedDirectional(top: 0, bottom: 0, end: 0,
                        width: DResizableHandle.visualExtent(),
                        child: DResizableHandle.standalone(
                        semanticLabel: 'Resize local User column',
                        value: _column.clamp(100, maximum),
                        min: 100,
                        max: maximum,
                        onChangeStart: () {},
                        onChanged: (v) => setState(() => _column = v),
                        onChangeEnd: () => setState(() => _commits++),
                      )),
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
