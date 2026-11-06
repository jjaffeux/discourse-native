#!/usr/bin/env python3
"""What a mounted desktop topic row costs: render objects, elements, heap.

  python3 tool/topic_row_cost.py [--output /tmp/row-cost.json]

Writes a probe test beside the topic-list scroll fixture, runs it with the
VM service enabled, and removes it. The probe mounts the desktop widget-test
list with semantics off and reports, per topic row:

  - the render objects and elements it mounts, by render object type and by
    the nearest app widget that created them,
  - the heap it keeps alive, by class: the list is shown, hidden and shown
    again, so every path is compiled, and the live heap after a forced
    collection is compared before and after the second showing.

Every attached render object also keeps a semantics configuration in this
Flutter build (RenderObject.attach reads it), so render objects dominate a
row's heap; see docs/performance/live-topic-list-scrolling.md. Two runs of
the same tree agree to about 0.01% on bytes per row.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

PROBE = Path("test/topic_row_cost_probe_test.dart")

SOURCE = r"""
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import 'support/topic_list_scroll_fixture.dart';

bool _isRow(Widget widget) => '${widget.runtimeType}' == '_TopicRow';

void main() {
  testWidgets('topic row cost probe', semanticsEnabled: false, (tester) async {
    tester.view.physicalSize = const Size(2560, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final controller = await topicListScrollController(count: 120, posters: 5);
    addTearDown(() async {
      controller.dispose();
      await controller.pluginTeardown;
      await controller.plugins.close();
    });
    final service = (await tester.runAsync(() async {
      final info = await developer.Service.controlWebServer(enable: true);
      final uri = info.serverUri!;
      return vmServiceConnectUri('ws://localhost:${uri.port}${uri.path}ws');
    }))!;
    final isolateId = developer.Service.getIsolateId(Isolate.current)!;
    Future<Map<String, (int, int)>> heap() async {
      final profile = (await tester.runAsync(
        () => service.getAllocationProfile(isolateId, gc: true),
      ))!;
      return {
        for (final member in profile.members!)
          if ((member.bytesCurrent ?? 0) > 0)
            '${member.classRef!.name}': (
              member.bytesCurrent!,
              member.instancesCurrent!,
            ),
      };
    }

    final show = ValueNotifier(false);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: show,
        builder: (context, value, _) => TopicListScrollFixture(
          controller: controller,
          width: 1000,
          height: value ? 1980 : 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    show.value = true;
    await tester.pumpAndSettle();
    show.value = false;
    await tester.pumpAndSettle();
    final hiddenRows = find.byWidgetPredicate(_isRow).evaluate().length;
    final before = await heap();
    show.value = true;
    await tester.pumpAndSettle();
    final rows = find.byWidgetPredicate(_isRow).evaluate().toList();
    final after = await heap();

    var elements = 0;
    var renderObjects = 0;
    final byType = <String, int>{};
    final byOwner = <String, int>{};
    for (final row in rows) {
      void visit(Element element, String owner) {
        elements++;
        final type = '${element.widget.runtimeType}';
        var next = owner;
        if ((element is StatelessElement || element is StatefulElement) &&
            !_framework.contains(type)) {
          next = type;
        }
        if (element is RenderObjectElement) {
          renderObjects++;
          final render = '${element.renderObject.runtimeType}';
          byType.update(render, (n) => n + 1, ifAbsent: () => 1);
          byOwner.update(owner, (n) => n + 1, ifAbsent: () => 1);
        }
        element.visitChildren((child) => visit(child, next));
      }

      visit(row, '_TopicRow');
    }
    final shown = rows.length - hiddenRows;
    final retained = <String, List<int>>{};
    for (final MapEntry(:key, :value) in after.entries) {
      final was = before[key] ?? (0, 0);
      final bytes = value.$1 - was.$1;
      if (bytes != 0) retained[key] = [bytes, value.$2 - was.$2];
    }
    debugPrint('ROW_COST ${jsonEncode({
      'rows': rows.length,
      'shownRows': shown,
      'elements': elements,
      'renderObjects': renderObjects,
      'byRenderObject': byType,
      'byOwner': byOwner,
      'retained': retained,
    })}', wrapWidth: 1 << 30);
    await tester.runAsync(service.dispose);
  });
}

// Framework widgets that do not name what a row is made of.
const _framework = {
  'Builder', 'StatefulBuilder', 'LayoutBuilder', 'ValueListenableBuilder',
  'ListenableBuilder', 'AnimatedBuilder', 'Semantics', 'Focus', 'MouseRegion',
  'GestureDetector', 'RawGestureDetector', 'Actions', 'Shortcuts',
  'DefaultTextStyle', 'IconTheme', 'Padding', 'SizedBox', 'Container', 'Row',
  'Column', 'Flex', 'Text', 'RichText', 'Icon', 'OverlayPortal', 'KeyedSubtree',
  'Listener', 'Opacity', 'ExcludeSemantics', 'MergeSemantics', 'Expanded',
  'Flexible', 'Align', 'Center', 'ConstrainedBox', 'DecoratedBox', 'ClipRRect',
  'Stack', 'Positioned', 'CustomPaint', 'Image', 'RawImage', 'IgnorePointer',
  'FocusTraversalGroup',
};
"""


def top(counts, divisor, limit):
    return sorted(((k, v / divisor) for k, v in counts.items()), key=lambda kv: -kv[1])[:limit]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, help="write the raw report as JSON")
    parser.add_argument("--top", type=int, default=25)
    args = parser.parse_args()
    if PROBE.exists():
        raise SystemExit(f"{PROBE} already exists; remove it first")
    PROBE.write_text(SOURCE)
    try:
        run = subprocess.run(
            ["flutter", "test", "--enable-vmservice", str(PROBE), "--reporter", "expanded"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    finally:
        PROBE.unlink()
    match = re.search(r"ROW_COST (\{.*\})", run.stdout)
    if run.returncode or not match:
        print(run.stdout)
        raise SystemExit(run.returncode or 1)
    report = json.loads(match.group(1))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2))
    rows, shown = report["rows"], report["shownRows"]
    retained = report["retained"]
    total = sum(bytes_ for bytes_, _ in retained.values())
    print(f"rows {rows}: {report['renderObjects'] / rows:.1f} render objects and "
          f"{report['elements'] / rows:.1f} elements per row")
    print(f"retained heap per shown row: {total / shown / 1000:.0f} KB ({shown} rows shown)")
    print("\nrender objects per row, by type:")
    for name, value in top(report["byRenderObject"], rows, args.top):
        print(f"  {value:6.1f}  {name}")
    print("\nrender objects per row, by the app widget that made them:")
    for name, value in top(report["byOwner"], rows, args.top):
        print(f"  {value:6.1f}  {name}")
    print("\nretained bytes per shown row, by class:")
    for name, (bytes_, count) in sorted(retained.items(), key=lambda kv: -kv[1][0])[:args.top]:
        print(f"  {bytes_ / shown:9.0f}  {count / shown:7.1f}  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
