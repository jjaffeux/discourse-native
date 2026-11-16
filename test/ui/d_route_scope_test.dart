import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Reads {
  int builds = 0;
  int statusChanges = 0;
  ModalRoute<Object?>? route;
  Listenable? status;
}

class _RouteReader extends StatefulWidget {
  const _RouteReader(this.reads);

  final _Reads reads;

  @override
  State<_RouteReader> createState() => _RouteReaderState();
}

class _RouteReaderState extends State<_RouteReader> {
  @override
  Widget build(BuildContext context) {
    final reads = widget.reads;
    reads.builds++;
    reads.route = DRouteScope.routeOf(context);
    final status = DRouteScope.statusOf(context);
    if (!identical(status, reads.status)) {
      reads.status = status?..addListener(() => reads.statusChanges++);
    }
    return const Text('page');
  }
}

Future<void> _cover(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('page'))).push(
    DialogRoute<void>(
      context: tester.element(find.text('page')),
      builder: (_) => const Text('cover'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _uncover(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('cover'))).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a page under a route scope reads its route status without '
      'rebuilding as another route covers and uncovers it', (tester) async {
    final reads = _Reads();
    await tester.pumpWidget(
      MaterialApp(home: DRouteScope(child: _RouteReader(reads))),
    );
    final route = reads.route!;
    expect(route.isCurrent, isTrue);
    final builds = reads.builds;

    await _cover(tester);
    expect(reads.builds, builds);
    expect(route.isCurrent, isFalse);
    expect(reads.statusChanges, 1);

    await _uncover(tester);
    expect(reads.builds, builds);
    expect(route.isCurrent, isTrue);
    expect(reads.statusChanges, 2);
  });

  testWidgets('without a route scope a page follows its route status by '
      'rebuilding', (tester) async {
    final reads = _Reads();
    await tester.pumpWidget(MaterialApp(home: _RouteReader(reads)));
    final route = reads.route!;
    final builds = reads.builds;
    expect(reads.status, isNull);

    await _cover(tester);
    expect(reads.builds, greaterThan(builds));
    expect(route.isCurrent, isFalse);
    expect(reads.route, same(route));
  });
}
