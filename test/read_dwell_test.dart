// Kept free of testWidgets: the owner has to run with no Flutter binding, which
// the private state it replaced in the chat view could not.
import 'package:discourse_native/src/foundation/read_dwell.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDownAll(() => expect(BindingBase.debugBindingType(), isNull));

  test('credits once after the whole interval', () {
    _run((reader) {
      reader.dwell.restart();
      reader.elapse(_ms(499));
      expect(reader.credits, 0);
      reader.elapse(_ms(1));
      expect(reader.credits, 1);
      reader.elapse(_ms(2000));
      expect(reader.credits, 1);
    });
  });

  test('restart abandons the time already spent', () {
    _run((reader) {
      reader.dwell.restart();
      reader.elapse(_ms(300));
      reader.dwell.restart();
      reader.elapse(_ms(499));
      expect(reader.credits, 0);
      reader.elapse(_ms(1));
      expect(reader.credits, 1);
    });
  });

  test('startIfIdle leaves a dwell under way to keep its time', () {
    _run((reader) {
      reader.dwell.startIfIdle();
      reader.elapse(_ms(300));
      reader.dwell.startIfIdle();
      reader.elapse(_ms(200));
      expect(reader.credits, 1);

      reader.dwell.startIfIdle();
      reader.elapse(_ms(499));
      expect(reader.credits, 1);
      reader.elapse(_ms(1));
      expect(reader.credits, 2);
    });
  });

  test('startIfIdle keeps a held dwell from gaining time', () {
    _run((reader) {
      reader.dwell.restart();
      reader.elapse(_ms(200));
      reader.setActive(false);

      reader.dwell.startIfIdle();
      reader.setActive(true);
      reader.elapse(_ms(299));
      expect(reader.credits, 0);
      reader.elapse(_ms(1));
      expect(reader.credits, 1);
    });
  });

  test('time spent inactive does not count', () {
    _run((reader) {
      reader.dwell.restart();
      reader.elapse(_ms(200));
      reader.setActive(false);
      reader.elapse(_ms(5000));
      expect(reader.credits, 0);

      reader.setActive(true);
      reader.elapse(_ms(299));
      expect(reader.credits, 0);
      reader.elapse(_ms(1));
      expect(reader.credits, 1);
    });
  });

  test('a dwell started while inactive waits for the reader', () {
    _run((reader) {
      reader.setActive(false);
      reader.dwell.restart();
      reader.elapse(_ms(5000));
      expect(reader.credits, 0);

      reader.setActive(true);
      reader.elapse(_ms(499));
      expect(reader.credits, 0);
      reader.elapse(_ms(1));
      expect(reader.credits, 1);
    });
  });

  test(
    'a timer firing for an inactive reader costs a full dwell on return',
    () {
      _run((reader) {
        reader.dwell.restart();
        reader.active = false;
        reader.elapse(_ms(500));
        expect(reader.credits, 0);

        reader.setActive(true);
        reader.elapse(_ms(499));
        expect(reader.credits, 0);
        reader.elapse(_ms(1));
        expect(reader.credits, 1);
      });
    },
  );

  test('creditIfIdle credits an active reader at once', () {
    _run((reader) {
      reader.dwell.creditIfIdle();
      expect(reader.credits, 1);
    });
  });

  test('creditIfIdle leaves a dwell under way to credit by itself', () {
    _run((reader) {
      reader.dwell.restart();
      reader.dwell.creditIfIdle();
      expect(reader.credits, 0);
      reader.elapse(_ms(500));
      expect(reader.credits, 1);
    });
  });

  test('creditIfIdle owes an inactive reader a full dwell on return', () {
    _run((reader) {
      reader.setActive(false);
      reader.dwell.creditIfIdle();
      reader.elapse(_ms(5000));
      expect(reader.credits, 0);

      reader.setActive(true);
      reader.elapse(_ms(499));
      expect(reader.credits, 0);
      reader.elapse(_ms(1));
      expect(reader.credits, 1);
    });
  });

  for (final (name, jump) in [
    ('back', const Duration(hours: -1)),
    ('forward', const Duration(hours: 1)),
  ]) {
    test('a clock moved $name during a dwell leaves nothing to spend', () {
      _run((reader) {
        reader.dwell.restart();
        reader.moveClock(jump);
        reader.setActive(false);
        reader.setActive(true);
        expect(reader.credits, 0);
        reader.elapse(Duration.zero);
        expect(reader.credits, 1);
      });
    });
  }

  test('cancel forgets the dwell for good', () {
    _run((reader) {
      reader.dwell.restart();
      reader.elapse(_ms(200));
      reader.dwell.cancel();
      reader.setActive(false);
      reader.setActive(true);
      reader.elapse(_ms(5000));
      expect(reader.credits, 0);
    });
  });

  test('sync while nothing changed leaves one timer running', () {
    _run((reader) {
      reader.dwell
        ..restart()
        ..sync()
        ..sync();
      reader.elapse(_ms(500));
      expect(reader.credits, 1);
    });
  });

  test('the credit can begin the next dwell from inside the callback', () {
    _run((reader) {
      reader.afterCredit = reader.dwell.restart;
      reader.dwell.restart();
      reader.elapse(_ms(500));
      expect(reader.credits, 1);
      reader.afterCredit = null;
      reader.elapse(_ms(500));
      expect(reader.credits, 2);
    });
  });
}

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

void _run(void Function(_Reader reader) body) {
  fakeAsync((async) => body(_Reader(async)));
}

final class _Reader {
  _Reader(this._async);

  final FakeAsync _async;
  DateTime _now = DateTime.utc(2026, 8, 31, 12);
  bool active = true;
  int credits = 0;
  void Function()? afterCredit;

  late final dwell = ReadDwell(
    isActive: () => active,
    onCredit: () {
      credits++;
      afterCredit?.call();
    },
    clock: () => _now,
  );

  void elapse(Duration duration) {
    _now = _now.add(duration);
    _async.elapse(duration);
  }

  void moveClock(Duration jump) => _now = _now.add(jump);

  void setActive(bool value) {
    active = value;
    dwell.sync();
  }
}
