import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/shell/cooked_document.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import 'cooked_projection_benchmark_test.dart'
    show tableHtml, consumeTableProjection;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cooked projection CPU and retained heap diagnostic', () async {
    final info = await developer.Service.getInfo();
    final isolate = developer.Service.getIsolateId(Isolate.current)!;
    final service = await vmServiceConnectUri(
      info.serverWebSocketUri!.toString(),
    );
    addTearDown(service.dispose);
    final source = tableHtml(1000);
    Widget build() {
      final table = parser.parseFragment(source).querySelector('table')!;
      return cookedTableWidgetBuilder(
        table,
        content: CookedDocument(
          source,
        ).bind((_, fragment, style) => Text(fragment.html)),
      )!;
    }

    for (var i = 0; i < 12; i++) {
      build();
    }
    final before = await service.getAllocationProfile(isolate, gc: true);
    final retained = <Widget>[];
    final start = developer.Timeline.now;
    for (var i = 0; i < 12; i++) {
      final widget = build();
      expect(consumeTableProjection(widget), greaterThan(0));
      retained.add(widget);
    }
    final extent = developer.Timeline.now - start;
    final after = await service.getAllocationProfile(isolate, gc: true);
    final cpu = await service.getCpuSamples(isolate, start, extent);
    expect(cpu.sampleCount, greaterThan(0));
    final prior = {for (final row in before.members!) row.classRef!.id: row};
    final heap = <Map<String, Object?>>[];
    for (final row in after.members!) {
      final old = prior[row.classRef!.id];
      final count = (row.instancesCurrent ?? 0) - (old?.instancesCurrent ?? 0);
      final bytes = (row.bytesCurrent ?? 0) - (old?.bytesCurrent ?? 0);
      if (count != 0 || bytes != 0) {
        heap.add({
          'class': row.classRef!.name,
          'instances_current_delta': count,
          'bytes_current_delta': bytes,
        });
      }
    }
    heap.sort(
      (a, b) => (b['bytes_current_delta'] as int).compareTo(
        a['bytes_current_delta'] as int,
      ),
    );
    final functions = [
      ...?cpu.functions,
    ]..sort((a, b) => (b.exclusiveTicks ?? 0).compareTo(a.exclusiveTicks ?? 0));
    expect(retained, hasLength(12));
    expect(retained.every((widget) => widget.key != null), isTrue);
    final result = {
      'kind': 'retained heap after forced GC, not total allocated bytes',
      'retained_tables': retained.length,
      'profile_interval_us': extent,
      'cpu_sample_count': cpu.sampleCount,
      'cpu_top': [
        for (final fn in functions.take(25))
          {
            'name': switch (fn.function) {
              vm.FuncRef(:final name) => name,
              vm.NativeFunction(:final name) => name,
              _ => null,
            },
            'url': fn.resolvedUrl,
            'inclusive': fn.inclusiveTicks,
            'exclusive': fn.exclusiveTicks,
          },
      ],
      'retained_heap_delta': heap,
    };
    File(
      Platform.environment['COOKED_PROJECTION_PROFILE']!,
    ).writeAsStringSync(jsonEncode(result));
  }, skip: Platform.environment['COOKED_PROJECTION_PROFILE'] == null);
}
