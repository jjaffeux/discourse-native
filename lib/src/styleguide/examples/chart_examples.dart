import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../styleguide_example.dart';

// All data, transformations and interactive choices are local to the examples.
const _months = [
  (month: 'January', desktop: 186, mobile: 80),
  (month: 'February', desktop: 305, mobile: 200),
  (month: 'March', desktop: 237, mobile: 120),
  (month: 'April', desktop: 73, mobile: 190),
  (month: 'May', desktop: 209, mobile: 130),
  (month: 'June', desktop: 214, mobile: 140),
];
typedef _Month = ({String month, int desktop, int mobile});

final _config = <String, DChartConfigEntry>{
  'desktop': DChartConfigEntry(
    label: 'Desktop',
    color: (context) => DTokens.of(context).primary,
  ),
  'mobile': DChartConfigEntry(
    label: 'Mobile',
    color: (context) => DChartColors.series(context, 1),
  ),
  'views': const DChartConfigEntry(label: 'Page Views'),
};
final _series = [
  DChartSeries<_Month>(key: 'desktop', value: (datum) => datum.desktop),
  DChartSeries<_Month>(key: 'mobile', value: (datum) => datum.mobile),
];
const _legend = [DChartItem(key: 'desktop'), DChartItem(key: 'mobile')];

final chartExamples = ComponentExamples(
  topLevelExampleIndex: 5,
  status: ComponentStatus.implemented,
  description:
      'Compose themed charts with reusable labels, tooltips and legends.',
  notes:
      'Ports the frozen Chart documentation, including its six-month grouped bars '
      'and interactive daily visitor chart. DChartContainer accepts any drawing widget; '
      'DBarChart supplies the documented native bar plotting owner without a new package. '
      'Config colors are live callbacks (the CSS variable/theme equivalent); data accessors '
      'accept arbitrary Dart models. Literal Flutter Color values replace CSS color syntax. '
      'Chart inspection is not editable form data. Tab enters once, arrows inspect, Home/End '
      'select endpoints and Escape dismisses; touch and hover expose the same values. '
      'Legend entries wrap at narrow widths. Axis ticks skip collisions while all values '
      'remain keyboard accessible. Tooltip content can be independently composed with '
      'another plotting owner. No automatic animation, so reduced motion is honored. '
      'The frozen browser reference and macOS native fixture were independently reviewed; '
      'the documented palette, narrow layout, large text and RTL states are accepted.',
  examples: [
    for (var stage = 0; stage < 5; stage++)
      StyleguideExample(
        title: [
          'Your first chart',
          'Add a grid',
          'Add an axis',
          'Add tooltip',
          'Add legend',
        ][stage],
        description:
            'The reference January–June desktop/mobile values. '
            'All rendered steps use 16:9 with a 200px minimum, including the legend.',
        states: [
          if (stage >= 1) 'Grid',
          if (stage >= 2) 'Axis',
          if (stage >= 3) 'Tooltip',
          if (stage >= 4) 'Legend',
        ],
        code: _firstCode(stage),
        builder: (_) => DChartContainer(
          config: _config,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => DBarChart<_Month>(
                  height:
                      (constraints.maxWidth * 9 / 16).clamp(
                        200,
                        double.infinity,
                      ) -
                      (stage >= 4
                          ? 12 + MediaQuery.textScalerOf(context).scale(16)
                          : 0),
                  data: _months,
                  series: _series,
                  label: (datum) => datum.month,
                  semanticLabel: 'Monthly visitors',
                  grid: stage >= 1,
                  axis: stage >= 2,
                  tooltip: stage >= 3,
                  tickFormatter: (label) => label.substring(0, 3),
                ),
              ),
              if (stage >= 4) const DChartLegendContent(items: _legend),
            ],
          ),
        ),
      ),
    StyleguideExample(
      title: 'Interactive visitors',
      description:
          'The reference April daily values. Select Desktop or Mobile; '
          'the total, series and tooltip follow the local choice.',
      states: const [
        'Series choice',
        'Daily axis',
        'Custom label',
        'Card composition',
      ],
      code: _interactiveCode,
      builder: (_) => const ChartInteractiveExample(),
    ),
    StyleguideExample(
      title: 'Tooltip anatomy and indicators',
      description:
          'Dot, dashed, nested line and hidden-label reference treatments. '
          'The last panel hides the indicator as well.',
      states: const ['Dot', 'Dashed', 'Line', 'Hide label', 'Hide indicator'],
      code: _tooltipCode,
      builder: (context) {
        final textScaler = MediaQuery.textScalerOf(context);
        final tooltipWidth = textScaler.scale(128);
        return DChartContainer(
          config: _config,
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              for (final indicator in DChartIndicator.values)
                SizedBox(
                  width: textScaler.scale(
                    indicator == DChartIndicator.line ? 144 : 128,
                  ),
                  child: DChartTooltipContent(
                    label: 'Page Views',
                    indicator: indicator,
                    items: [
                      DChartItem(
                        key: 'desktop',
                        value: indicator == DChartIndicator.line ? 12486 : 186,
                      ),
                      if (indicator == DChartIndicator.dot)
                        const DChartItem(key: 'mobile', value: 80),
                    ],
                  ),
                ),
              SizedBox(
                width: tooltipWidth,
                child: const DChartTooltipContent(
                  label: 'Page Views',
                  hideLabel: true,
                  indicator: DChartIndicator.dashed,
                  items: [
                    DChartItem(key: 'desktop', value: 1286),
                    DChartItem(key: 'mobile', value: 1000),
                  ],
                ),
              ),
              SizedBox(
                width: tooltipWidth,
                child: const DChartTooltipContent(
                  hideLabel: true,
                  hideIndicator: true,
                  items: [DChartItem(key: 'desktop', value: 1286)],
                ),
              ),
            ],
          ),
        );
      },
    ),
    StyleguideExample(
      title: 'Custom keys, colors and content',
      description:
          'The reference browser/visitors mapping, data-supplied colors, '
          'config icons, top legend and custom value/label/row content.',
      states: const [
        'nameKey',
        'labelKey',
        'Icon',
        'Color override',
        'Formatters',
        'Legend builder',
      ],
      code: _customCode,
      builder: (_) => const _CustomChart(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The reference Arabic months and series labels. Categories '
          'read from right to left; series retain their source order.',
      states: const ['Arabic', 'RTL', 'Grid', 'Tooltip', 'Legend'],
      code: _rtlCode,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DChartContainer(
          config: {
            'desktop': DChartConfigEntry(
              label: 'سطح المكتب',
              color: (context) => DTokens.of(context).primary,
            ),
            'mobile': DChartConfigEntry(
              label: 'الجوال',
              color: (context) => DChartColors.series(context, 1),
            ),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => DBarChart<_Month>(
                  height:
                      (constraints.maxWidth * 9 / 16).clamp(
                        200,
                        double.infinity,
                      ) -
                      12 -
                      MediaQuery.textScalerOf(context).scale(16),
                  tickFormatter: (label) => label.substring(0, 3),
                  data: _months,
                  series: _series,
                  label: (datum) => const [
                    'يناير',
                    'فبراير',
                    'مارس',
                    'أبريل',
                    'مايو',
                    'يونيو',
                  ][_months.indexOf(datum)],
                  semanticLabel: 'الزوار شهريا',
                  grid: true,
                  axis: true,
                ),
              ),
              const DChartLegendContent(items: _legend),
            ],
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Controlled inspection and missing data',
      description:
          'A borrowed controller synchronizes inspection and external actions. '
          'Includes negative, zero and missing values, value axis and empty data.',
      states: const [
        'Controller',
        'Negative',
        'Missing',
        'Empty',
        'Value axis',
      ],
      code: _controlledCode,
      builder: (_) => const _ControlledChart(),
    ),
  ],
);

String _firstCode(int stage) =>
    '''final data = [
  (month: 'January', desktop: 186, mobile: 80),
  (month: 'February', desktop: 305, mobile: 200),
  (month: 'March', desktop: 237, mobile: 120),
  (month: 'April', desktop: 73, mobile: 190),
  (month: 'May', desktop: 209, mobile: 130),
  (month: 'June', desktop: 214, mobile: 140),
];
DChartContainer(config: {
  'desktop': DChartConfigEntry(label: 'Desktop',
    color: (context) => DTokens.of(context).primary),
  'mobile': DChartConfigEntry(label: 'Mobile',
    color: (context) => DChartColors.series(context, 1)),
}, child: Column(mainAxisSize: MainAxisSize.min, children: [
  LayoutBuilder(builder: (context, constraints) =>
    DBarChart<({String month, int desktop, int mobile})>(
    height: (constraints.maxWidth * 9 / 16).clamp(200, double.infinity)${stage >= 4 ? " - 12 - MediaQuery.textScalerOf(context).scale(16)" : ""},
    data: data, label: (datum) => datum.month,
    semanticLabel: 'Monthly visitors',
    series: [
      DChartSeries(key: 'desktop', value: (datum) => datum.desktop),
      DChartSeries(key: 'mobile', value: (datum) => datum.mobile),
    ],
    grid: ${stage >= 1}, axis: ${stage >= 2}, tooltip: ${stage >= 3},
    tickFormatter: (label) => label.substring(0, 3),
  )),${stage >= 4 ? "\n  const DChartLegendContent(items: [\n    DChartItem(key: 'desktop'), DChartItem(key: 'mobile'),\n  ])," : ''}
]));''';

/// Actual production examples are also mounted by the offline review fixture.
class ChartInteractiveExample extends StatefulWidget {
  const ChartInteractiveExample({super.key});
  @override
  State<ChartInteractiveExample> createState() =>
      _ChartInteractiveExampleState();
}

class _ChartInteractiveExampleState extends State<ChartInteractiveExample> {
  var _active = 'desktop';
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 640;
      final tokens = DTokens.of(context);
      final totalWidths = <String, double>{};
      for (final key in ['desktop', 'mobile']) {
        final text = MaterialLocalizations.of(context).formatDecimal(
          _days.fold<int>(
            0,
            (sum, day) => sum + (key == 'desktop' ? day.desktop : day.mobile),
          ),
        );
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
              fontSize: DiscourseTypography.xxxl,
              height: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        totalWidths[key] = painter.width + 65;
      }
      final heading = Padding(
        padding: EdgeInsets.fromLTRB(24, wide ? 0 : 16, 24, wide ? 0 : 12),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              'Bar Chart - Interactive',
              style: TextStyle(
                fontSize: 15,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            DCardDescription(child: Text('Showing total visitors for April')),
          ],
        ),
      );
      final stackChoices =
          !wide && MediaQuery.textScalerOf(context).scale(18) > 24;
      final choices = Wrap(
        children: [
          for (final key in ['desktop', 'mobile'])
            SizedBox(
              width: wide
                  ? totalWidths[key]
                  : constraints.maxWidth / (stackChoices ? 1 : 2),
              child: Semantics(
                selected: _active == key,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _active == key
                        ? tokens.muted.withValues(alpha: tokens.muted.a * .5)
                        : null,
                    border: BorderDirectional(
                      start: BorderSide(
                        color: key == 'mobile' || wide
                            ? tokens.border
                            : Colors.transparent,
                      ),
                      top: BorderSide(
                        color: wide ? Colors.transparent : tokens.border,
                      ),
                    ),
                  ),
                  child: DButton(
                    variant: DButtonVariant.transparent,
                    alignment: AlignmentDirectional.centerStart,
                    borderRadius: BorderRadius.zero,
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 24,
                      vertical: wide ? 24 : 16,
                    ),
                    onPressed: () => setState(() => _active = key),
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          _config[key]!.label,
                          maxLines: null,
                          style: TextStyle(
                            fontSize: DiscourseTypography.xs,
                            height: 16 / 12,
                            color: tokens.mutedForeground,
                          ),
                        ),
                        Text(
                          MaterialLocalizations.of(context).formatDecimal(
                            _days.fold<int>(
                              0,
                              (sum, day) =>
                                  sum +
                                  (key == 'desktop' ? day.desktop : day.mobile),
                            ),
                          ),
                          maxLines: null,
                          style: TextStyle(
                            fontSize: wide
                                ? DiscourseTypography.xxxl
                                : DiscourseTypography.lg,
                            height: 1,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
      return DCard(
        spacing: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: wide
                  ? Row(
                      children: [
                        Expanded(child: heading),
                        SizedBox(
                          width: totalWidths.values.reduce((a, b) => a + b),
                          child: choices,
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [heading, choices],
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? 24 : 8,
                wide ? 48 : 24,
                wide ? 24 : 8,
                40,
              ),
              child: DChartContainer(
                config: _config,
                child: DBarChart<_Day>(
                  data: _days,
                  series: [
                    DChartSeries(
                      key: _active,
                      value: (datum) =>
                          _active == 'desktop' ? datum.desktop : datum.mobile,
                    ),
                  ],
                  label: (datum) => 'April ${datum.day}, 2024',
                  semanticLabel: 'Daily visitors',
                  height: 250,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  tickMargin: 8,
                  minTickGap: 32,
                  grid: true,
                  axis: true,
                  barRadius: 0,
                  tickFormatter: (label) =>
                      label.split(',').first.replaceFirst('April', 'Apr'),
                  tooltipBuilder: (context, label, items) =>
                      DChartTooltipContent(
                        items: items,
                        label: label,
                        nameKey: 'views',
                      ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

typedef _Day = ({int day, int desktop, int mobile});
const _days = <_Day>[
  (day: 1, desktop: 222, mobile: 150),
  (day: 2, desktop: 97, mobile: 180),
  (day: 3, desktop: 167, mobile: 120),
  (day: 4, desktop: 242, mobile: 260),
  (day: 5, desktop: 373, mobile: 290),
  (day: 6, desktop: 301, mobile: 340),
  (day: 7, desktop: 245, mobile: 180),
  (day: 8, desktop: 409, mobile: 320),
  (day: 9, desktop: 59, mobile: 110),
  (day: 10, desktop: 261, mobile: 190),
  (day: 11, desktop: 327, mobile: 350),
  (day: 12, desktop: 292, mobile: 210),
  (day: 13, desktop: 342, mobile: 380),
  (day: 14, desktop: 137, mobile: 220),
  (day: 15, desktop: 120, mobile: 170),
  (day: 16, desktop: 138, mobile: 190),
  (day: 17, desktop: 446, mobile: 360),
  (day: 18, desktop: 364, mobile: 410),
  (day: 19, desktop: 243, mobile: 180),
  (day: 20, desktop: 89, mobile: 150),
  (day: 21, desktop: 137, mobile: 200),
  (day: 22, desktop: 224, mobile: 170),
  (day: 23, desktop: 138, mobile: 230),
  (day: 24, desktop: 387, mobile: 290),
  (day: 25, desktop: 215, mobile: 250),
  (day: 26, desktop: 75, mobile: 130),
  (day: 27, desktop: 383, mobile: 420),
  (day: 28, desktop: 122, mobile: 180),
  (day: 29, desktop: 315, mobile: 240),
  (day: 30, desktop: 454, mobile: 380),
];

class _CustomChart extends StatelessWidget {
  const _CustomChart();
  @override
  Widget build(BuildContext context) => DChartContainer(
    config: {
      'visitors': const DChartConfigEntry(label: 'Total Visitors'),
      'chrome': DChartConfigEntry(
        label: 'Chrome',
        color: (context) => DTokens.of(context).primary,
        icon: (_) => const Icon(Icons.public),
      ),
      'safari': DChartConfigEntry(
        label: 'Safari',
        color: (context) => DChartColors.series(context, 1),
      ),
    },
    child: Builder(
      builder: (context) {
        final items = [
          DChartItem(
            key: 'visitors',
            value: 187,
            payload: const {'browser': 'chrome'},
            color: DTokens.of(context).primary,
          ),
          DChartItem(
            key: 'visitors',
            value: 200,
            payload: const {'browser': 'safari'},
            color: DChartColors.series(context, 1),
          ),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            DChartLegendContent(items: items, nameKey: 'browser', atTop: true),
            DBarChart<DChartItem>(
              data: items,
              series: [
                DChartSeries(
                  key: 'visitors',
                  value: (datum) => datum.value,
                  color: (_, datum) => datum.color,
                ),
              ],
              label: (datum) => datum.payload['browser']! as String,
              payload: (datum) => datum.payload,
              semanticLabel: 'Browser visitors',
              axis: true,
              grid: true,
              tooltipBuilder: (context, label, items) => DChartTooltipContent(
                items: items,
                nameKey: 'browser',
                labelKey: 'visitors',
                indicator: DChartIndicator.line,
                valueFormatter: (value) => '$value people',
              ),
            ),
            SizedBox(
              width: 240,
              child: DChartTooltipContent(
                items: items,
                label: 'Combined visits',
                labelBuilder: (_, label, items) =>
                    Text('$label · ${items.length} browsers'),
                itemBuilder: (_, item, index) => Text(
                  '${index + 1}. ${item.payload['browser']}: ${item.value} people',
                ),
              ),
            ),
            DChartLegendContent(
              items: items,
              nameKey: 'browser',
              hideIcon: true,
            ),
            DChartLegendContent(
              items: items,
              itemBuilder: (_, item) =>
                  Text('${item.payload['browser']} — ${item.value}'),
            ),
          ],
        );
      },
    ),
  );
}

class _ControlledChart extends StatefulWidget {
  const _ControlledChart();
  @override
  State<_ControlledChart> createState() => _ControlledChartState();
}

class _ControlledChartState extends State<_ControlledChart> {
  final _controller = DChartController(1);
  var _empty = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DChartContainer(
    config: _config,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              onPressed: () => _controller.value = 0,
              label: const Text('Inspect first'),
            ),
            DButton(
              onPressed: () => _controller.value = null,
              label: const Text('Dismiss'),
            ),
            DButton(
              onPressed: () => setState(() => _empty = !_empty),
              label: Text(_empty ? 'Restore data' : 'Empty data'),
            ),
          ],
        ),
        DBarChart<num?>(
          data: _empty ? const [] : const [-20, 0, null, 80],
          series: [DChartSeries(key: 'desktop', value: (value) => value)],
          label: (value) => value == null ? 'Missing' : '$value',
          semanticLabel: 'Net change',
          controller: _controller,
          grid: true,
          axis: true,
          valueAxis: true,
        ),
        ValueListenableBuilder<int?>(
          valueListenable: _controller,
          builder: (_, value, _) =>
              Text('Controller index: ${value ?? 'none'}'),
        ),
      ],
    ),
  );
}

const _tooltipCode = '''DChartContainer(config: {
  'desktop': DChartConfigEntry(label: 'Desktop', color: (c) => DTokens.of(c).primary),
  'mobile': DChartConfigEntry(label: 'Mobile', color: (c) => DChartColors.series(c, 1)),
}, child: Wrap(spacing: 24, runSpacing: 24, children: [
  for (final indicator in DChartIndicator.values)
    SizedBox(width: MediaQuery.textScalerOf(context).scale(128),
      child: DChartTooltipContent(
      label: 'Page Views', indicator: indicator,
      items: [DChartItem(key: 'desktop', value: 186),
        if (indicator == DChartIndicator.dot) DChartItem(key: 'mobile', value: 80)],
    )),
  SizedBox(width: MediaQuery.textScalerOf(context).scale(128),
    child: DChartTooltipContent(
    hideLabel: true, hideIndicator: true,
    items: [DChartItem(key: 'desktop', value: 1286)],
  )),
]));''';

const _customCode = r'''final items = [
  DChartItem(key: 'visitors', value: 187, payload: {'browser': 'chrome'}),
  DChartItem(key: 'visitors', value: 200, payload: {'browser': 'safari'}),
];
DChartContainer(config: {
  'visitors': DChartConfigEntry(label: 'Total Visitors'),
  'chrome': DChartConfigEntry(label: 'Chrome', color: (c) => DTokens.of(c).primary,
    icon: (_) => Icon(Icons.public)),
  'safari': DChartConfigEntry(label: 'Safari', color: (c) => DChartColors.series(c, 1)),
}, child: Column(mainAxisSize: MainAxisSize.min, children: [
  DChartLegendContent(items: items, nameKey: 'browser', atTop: true),
  SizedBox(width: 240, child: DChartTooltipContent(items: items,
    labelKey: 'visitors', nameKey: 'browser', indicator: DChartIndicator.line,
    valueFormatter: (value) => '$value people')),
  DChartLegendContent(items: items, nameKey: 'browser', hideIcon: true),
]));''';

const _rtlCode = '''Directionality(textDirection: TextDirection.rtl,
  child: DChartContainer(config: {
    'desktop': DChartConfigEntry(label: 'سطح المكتب', color: (c) => DTokens.of(c).primary),
  }, child: DBarChart<({String month, int visitors})>(
    data: [(month: 'يناير', visitors: 186), (month: 'فبراير', visitors: 305)],
    series: [DChartSeries(key: 'desktop', value: (datum) => datum.visitors)],
    label: (datum) => datum.month, semanticLabel: 'الزوار شهريا',
    axis: true, grid: true,
  )),
);''';

const _controlledCode = r'''class InspectionExample extends StatefulWidget {
  const InspectionExample({super.key});
  @override
  State<InspectionExample> createState() => _InspectionExampleState();
}
class _InspectionExampleState extends State<InspectionExample> {
  final controller = DChartController(1);
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DChartContainer(config: {
    'desktop': DChartConfigEntry(label: 'Desktop'),
  }, child: Column(mainAxisSize: MainAxisSize.min, children: [
    DButton(onPressed: () => controller.value = null, label: Text('Dismiss')),
    DBarChart<num?>(data: [-20, 0, null, 80], controller: controller,
      series: [DChartSeries(key: 'desktop', value: (value) => value)],
      label: (value) => value == null ? 'Missing' : '$value',
      semanticLabel: 'Net change', grid: true, axis: true, valueAxis: true),
  ]));
}''';

const _interactiveCode =
    r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

final _config = <String, DChartConfigEntry>{
  'desktop': DChartConfigEntry(
    label: 'Desktop',
    color: (context) => DTokens.of(context).primary,
  ),
  'mobile': DChartConfigEntry(
    label: 'Mobile',
    color: (context) => DChartColors.series(context, 1),
  ),
  'views': const DChartConfigEntry(label: 'Page Views'),
};
class ChartInteractiveExample extends StatefulWidget {
  const ChartInteractiveExample({super.key});
  @override
  State<ChartInteractiveExample> createState() =>
      _ChartInteractiveExampleState();
}

class _ChartInteractiveExampleState extends State<ChartInteractiveExample> {
  var _active = 'desktop';
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 640;
      final tokens = DTokens.of(context);
      final totalWidths = <String, double>{};
      for (final key in ['desktop', 'mobile']) {
        final text = MaterialLocalizations.of(context).formatDecimal(
          _days.fold<int>(
            0,
            (sum, day) => sum + (key == 'desktop' ? day.desktop : day.mobile),
          ),
        );
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
              fontSize: DiscourseTypography.xxxl,
              height: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        totalWidths[key] = painter.width + 65;
      }
      final heading = Padding(
        padding: EdgeInsets.fromLTRB(24, wide ? 0 : 16, 24, wide ? 0 : 12),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              'Bar Chart - Interactive',
              style: TextStyle(
                fontSize: 15,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            DCardDescription(child: Text('Showing total visitors for April')),
          ],
        ),
      );
      final stackChoices =
          !wide && MediaQuery.textScalerOf(context).scale(18) > 24;
      final choices = Wrap(
        children: [
          for (final key in ['desktop', 'mobile'])
            SizedBox(
              width: wide
                  ? totalWidths[key]
                  : constraints.maxWidth / (stackChoices ? 1 : 2),
              child: Semantics(
                selected: _active == key,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _active == key
                        ? tokens.muted.withValues(alpha: tokens.muted.a * .5)
                        : null,
                    border: BorderDirectional(
                      start: BorderSide(
                        color: key == 'mobile' || wide
                            ? tokens.border
                            : Colors.transparent,
                      ),
                      top: BorderSide(
                        color: wide ? Colors.transparent : tokens.border,
                      ),
                    ),
                  ),
                  child: DButton(
                    variant: DButtonVariant.transparent,
                    alignment: AlignmentDirectional.centerStart,
                    borderRadius: BorderRadius.zero,
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 24,
                      vertical: wide ? 24 : 16,
                    ),
                    onPressed: () => setState(() => _active = key),
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          _config[key]!.label,
                          maxLines: null,
                          style: TextStyle(
                            fontSize: DiscourseTypography.xs,
                            height: 16 / 12,
                            color: tokens.mutedForeground,
                          ),
                        ),
                        Text(
                          MaterialLocalizations.of(context).formatDecimal(
                            _days.fold<int>(
                              0,
                              (sum, day) =>
                                  sum +
                                  (key == 'desktop' ? day.desktop : day.mobile),
                            ),
                          ),
                          maxLines: null,
                          style: TextStyle(
                            fontSize: wide
                                ? DiscourseTypography.xxxl
                                : DiscourseTypography.lg,
                            height: 1,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
      return DCard(
        spacing: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: wide
                  ? Row(
                      children: [
                        Expanded(child: heading),
                        SizedBox(
                          width: totalWidths.values.reduce((a, b) => a + b),
                          child: choices,
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [heading, choices],
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? 24 : 8,
                wide ? 48 : 24,
                wide ? 24 : 8,
                40,
              ),
              child: DChartContainer(
                config: _config,
                child: DBarChart<_Day>(
                  data: _days,
                  series: [
                    DChartSeries(
                      key: _active,
                      value: (datum) =>
                          _active == 'desktop' ? datum.desktop : datum.mobile,
                    ),
                  ],
                  label: (datum) => 'April ${datum.day}, 2024',
                  semanticLabel: 'Daily visitors',
                  height: 250,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  tickMargin: 8,
                  minTickGap: 32,
                  grid: true,
                  axis: true,
                  barRadius: 0,
                  tickFormatter: (label) =>
                      label.split(',').first.replaceFirst('April', 'Apr'),
                  tooltipBuilder: (context, label, items) =>
                      DChartTooltipContent(
                        items: items,
                        label: label,
                        nameKey: 'views',
                      ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

typedef _Day = ({int day, int desktop, int mobile});
const _days = <_Day>[
  (day: 1, desktop: 222, mobile: 150),
  (day: 2, desktop: 97, mobile: 180),
  (day: 3, desktop: 167, mobile: 120),
  (day: 4, desktop: 242, mobile: 260),
  (day: 5, desktop: 373, mobile: 290),
  (day: 6, desktop: 301, mobile: 340),
  (day: 7, desktop: 245, mobile: 180),
  (day: 8, desktop: 409, mobile: 320),
  (day: 9, desktop: 59, mobile: 110),
  (day: 10, desktop: 261, mobile: 190),
  (day: 11, desktop: 327, mobile: 350),
  (day: 12, desktop: 292, mobile: 210),
  (day: 13, desktop: 342, mobile: 380),
  (day: 14, desktop: 137, mobile: 220),
  (day: 15, desktop: 120, mobile: 170),
  (day: 16, desktop: 138, mobile: 190),
  (day: 17, desktop: 446, mobile: 360),
  (day: 18, desktop: 364, mobile: 410),
  (day: 19, desktop: 243, mobile: 180),
  (day: 20, desktop: 89, mobile: 150),
  (day: 21, desktop: 137, mobile: 200),
  (day: 22, desktop: 224, mobile: 170),
  (day: 23, desktop: 138, mobile: 230),
  (day: 24, desktop: 387, mobile: 290),
  (day: 25, desktop: 215, mobile: 250),
  (day: 26, desktop: 75, mobile: 130),
  (day: 27, desktop: 383, mobile: 420),
  (day: 28, desktop: 122, mobile: 180),
  (day: 29, desktop: 315, mobile: 240),
  (day: 30, desktop: 454, mobile: 380),
];
''';
