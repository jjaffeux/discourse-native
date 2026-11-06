import 'dart:ui';

import 'package:discourse_native/src/ui/foundation/overlay_observers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Recorder with WidgetsBindingObserver {
  _Recorder(this.name, this.log);

  final String name;
  final List<String> log;
  VoidCallback? onLifecycle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log.add('$name lifecycle ${state.name}');
    onLifecycle?.call();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) =>
      log.add('$name focus ${event.state.name}');

  @override
  void didChangeMetrics() => log.add('$name metrics');
}

void main() {
  testWidgets('forwards lifecycle, view focus and metrics to triggers', (
    tester,
  ) async {
    final log = <String>[];
    final first = _Recorder('first', log);
    final second = _Recorder('second', log);
    DOverlayObservers.add(first);
    DOverlayObservers.add(second);
    addTearDown(() {
      DOverlayObservers.remove(first);
      DOverlayObservers.remove(second);
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.unfocused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(log, [
      'first lifecycle inactive',
      'second lifecycle inactive',
      'first focus unfocused',
      'second focus unfocused',
      'first metrics',
      'second metrics',
      'first lifecycle resumed',
      'second lifecycle resumed',
    ]);
  });

  testWidgets('a removed trigger hears nothing, even mid-dispatch', (
    tester,
  ) async {
    final log = <String>[];
    final first = _Recorder('first', log);
    final second = _Recorder('second', log);
    final third = _Recorder('third', log);
    // The first trigger's handler unmounts the second, as closing an overlay
    // can dispose its nested triggers.
    first.onLifecycle = () => DOverlayObservers.remove(second);
    for (final observer in [first, second, third]) {
      DOverlayObservers.add(observer);
    }
    addTearDown(() {
      for (final observer in [first, second, third]) {
        DOverlayObservers.remove(observer);
      }
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    DOverlayObservers.remove(third);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(log, [
      'first lifecycle inactive',
      'third lifecycle inactive',
      'first lifecycle resumed',
    ]);
  });
}
