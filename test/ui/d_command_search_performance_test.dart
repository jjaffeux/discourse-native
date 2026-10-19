import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final count in [250, 2000, 10000]) {
    testWidgets('command search workload with $count options', (tester) async {
      final samples = <Map<String, Object>>[];
      for (var run = 0; run < 6; run++) {
        final controller = DCommandController<int>();
        final selected = <int>[];
        final items = List.generate(
          count,
          (i) => DCommandItem<int>(
            value: i,
            searchValue: ' Category $i sailing discussion ',
            keywords: [' alias-$i ', ' navigation ', 'community ${i % 20}'],
            onSelected: selected.add,
            child: Text('Category $i'),
          ),
        );
        final watch = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 384,
                  child: DCommand<int>(
                    controller: controller,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const DCommandInput<int>(autofocus: false),
                        DCommandList<int>(
                          height: 288,
                          children: [DCommandGroup<int>(items: items)],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final open = watch.elapsedMicroseconds;
        final queries = <String, int>{};
        for (final query in [
          'c',
          'category',
          'category 19',
          'navigation',
          'sailing 19',
          'ALIAS-${count - 1}',
          'missing',
          '',
        ]) {
          watch.reset();
          controller.updateQuery(query);
          await tester.pump();
          await tester.pump();
          queries[query] = watch.elapsedMicroseconds;
          if (query.startsWith('ALIAS-')) {
            expect(controller.value, count - 1);
          }
          if (query == 'missing') expect(controller.value, isNull);
        }
        watch.reset();
        controller.handleKeyEvent(
          const KeyDownEvent(
            logicalKey: LogicalKeyboardKey.arrowDown,
            physicalKey: PhysicalKeyboardKey.arrowDown,
            timeStamp: Duration.zero,
          ),
        );
        await tester.pump();
        controller.activate();
        final selection = watch.elapsedMicroseconds;
        expect(selected, [1]);
        expect(tester.takeException(), isNull);
        samples.add({
          'run': run,
          'count': count,
          'openUs': open,
          'queryUs': queries,
          'selectionUs': selection,
          'selected': selected.single,
        });
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
      debugPrint('COMMAND_SEARCH_WIDGET ${jsonEncode(samples)}');
    });
  }
}
