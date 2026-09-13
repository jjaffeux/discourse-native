import 'dart:ui' as ui;

import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

// Replay the traversal tree sent to the native accessibility bridge. Widget
// finders can still see an overlay whose serialized nodes have become orphaned.
class _NativeSemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _NativeSemanticsUpdateBuilder();
}

class _NativeSemanticsUpdateBuilder extends Fake
    implements ui.SemanticsUpdateBuilder {
  static final nodes = <int, Map<Symbol, dynamic>>{};
  static final orphans = <String>[];
  final updated = <int>[];
  final delegate = ui.SemanticsUpdateBuilder();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final data = invocation.namedArguments;
      final id = data[#id] as int;
      updated.add(id);
      nodes[id] = data;
      return Function.apply(delegate.updateNode, [], data);
    }
    if (invocation.memberName == #updateCustomAction) {
      return Function.apply(
        delegate.updateCustomAction,
        [],
        invocation.namedArguments,
      );
    }
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    final visited = <int>{};
    void visit(int id) {
      if (!visited.add(id)) return;
      for (final child
          in (nodes[id]?[#childrenInTraversalOrder] as Iterable<int>?) ??
              <int>[]) {
        visit(child);
      }
    }

    visit(0);
    for (final id in updated.where((id) => !visited.contains(id))) {
      orphans.add(
        'id=$id label=${nodes[id]?[#label]} traversalParent=${nodes[id]?[#traversalParent]}',
      );
    }
    return delegate.build();
  }
}

void main() {
  _NativeSemanticsBinding();
  testWidgets(
    'event menus keep native accessibility nodes attached when hovered, opened, and selected',
    (tester) async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: SingleChildScrollView(
                child: EventCard(
                  event: PostEvent.decode(eventJson())!,
                  siteUrl: eventSite,
                  zones: ports.zones,
                  onRespond: (_, _) {},
                  onEdit: () {},
                  onInvite: () {},
                  onExport: () {},
                  onWeb: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(find.byTooltip('Event actions')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byTooltip('Event actions'));
        await tester.pumpAndSettle();
        expect(find.text('Edit event'), findsOneWidget);
        await tester.tap(find.text('Edit event'));
        await tester.pumpAndSettle();
        await mouse.moveTo(
          tester.getCenter(find.byTooltip('Choose recurring attendance')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byTooltip('Choose recurring attendance'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Every occurrence'));
        await tester.pumpAndSettle();
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
        expect(
          _NativeSemanticsUpdateBuilder.orphans,
          isEmpty,
          reason:
              'Every updated accessibility node must remain reachable from the native root.',
        );
      } finally {
        handle.dispose();
      }
    },
  );
}
