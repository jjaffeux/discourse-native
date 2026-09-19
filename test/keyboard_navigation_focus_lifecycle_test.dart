import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation waits for deactivated focus to be reattached', (
    tester,
  ) async {
    final focusNode = ReadingFocusNode();
    addTearDown(focusNode.dispose);
    final focusKey = GlobalKey();
    late StateSetter update;
    late BuildContext navigationContext;
    var moved = false;
    bool? allowedDuringMove;

    Widget target() =>
        Focus(key: focusKey, focusNode: focusNode, child: const SizedBox());

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            navigationContext = context;
            return Column(
              children: [
                SizedBox(child: moved ? null : target()),
                Builder(
                  builder: (context) {
                    if (!moved) return const SizedBox();
                    expect(focusNode.hasPrimaryFocus, isTrue);
                    expect(focusNode.context!.mounted, isTrue);
                    expect(
                      (focusNode.context! as Element).renderObject!.attached,
                      isFalse,
                    );
                    allowedDuringMove = navigationShortcutsAllowed(
                      navigationContext,
                    );
                    return target();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    expect(navigationShortcutsAllowed(navigationContext), isTrue);

    update(() => moved = true);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(allowedDuringMove, isFalse);
    expect(focusNode.hasPrimaryFocus, isTrue);
    expect(navigationShortcutsAllowed(navigationContext), isTrue);
  });
}
