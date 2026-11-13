import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_room_row.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_rooms.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Rooms extends ChangeNotifier {
  _Rooms(this.people);

  final Map<int, int> people;

  void change(int id, int count) {
    people[id] = count;
    notifyListeners();
  }

  List<ChatInboxRoom> get rooms => [
    for (final MapEntry(key: id, value: count) in people.entries)
      ChatInboxRoom(
        id: id,
        name: 'Room $id',
        people: count,
        open: (_) async {},
      ),
  ];
}

Future<_Rooms> _pumpRows(
  WidgetTester tester,
  Map<int, int> people, {
  required bool compact,
}) async {
  final rooms = _Rooms(people);
  addTearDown(rooms.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: rooms,
          builder: (context, _) => Column(
            children: [
              for (final room in rooms.rooms)
                ChatInboxRoomRow(room: room, compact: compact),
            ],
          ),
        ),
      ),
    ),
  );
  return rooms;
}

TextStyle _drawnStyle(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Color _muted(WidgetTester tester) => DTokens.of(
  tester.element(find.byType(ChatInboxRoomRow).first),
).mutedForeground;

Color _foreground(WidgetTester tester) =>
    DTokens.of(tester.element(find.byType(ChatInboxRoomRow).first)).foreground;

void main() {
  for (final compact in [false, true]) {
    group(compact ? 'sidebar room row' : 'page room row', () {
      testWidgets('says quietly that nobody is in', (tester) async {
        await _pumpRows(tester, {1: 0}, compact: compact);

        final style = _drawnStyle(tester, 'Empty');
        expect(style.fontWeight, FontWeight.w400);
        expect(style.color, _muted(tester));
        expect(style.fontSize, DiscourseTypography.preview);
        final name = tester.getRect(find.text('Room 1'));
        final status = tester.getRect(find.text('Empty'));
        expect(status.top, greaterThanOrEqualTo(name.bottom));
        expect(status.left, name.left);
      });

      testWidgets('counts one person in the singular', (tester) async {
        await _pumpRows(tester, {1: 1}, compact: compact);

        final style = _drawnStyle(tester, '1 person here');
        expect(style.fontWeight, FontWeight.w600);
        expect(style.color, _foreground(tester));
        expect(find.text('Empty'), findsNothing);
      });

      testWidgets('counts several people in the plural', (tester) async {
        await _pumpRows(tester, {1: 3}, compact: compact);

        expect(
          _drawnStyle(tester, '3 people here').fontWeight,
          FontWeight.w600,
        );
      });

      testWidgets('follows people joining and leaving', (tester) async {
        final rooms = await _pumpRows(tester, {1: 0}, compact: compact);

        rooms.change(1, 1);
        await tester.pump();
        expect(find.text('1 person here'), findsOneWidget);
        expect(find.text('Empty'), findsNothing);

        rooms.change(1, 2);
        await tester.pump();
        expect(find.text('2 people here'), findsOneWidget);

        rooms.change(1, 0);
        await tester.pump();
        expect(find.text('Empty'), findsOneWidget);
        expect(_drawnStyle(tester, 'Empty').fontWeight, FontWeight.w400);
      });

      testWidgets('a join redraws only the room it happened in', (
        tester,
      ) async {
        final rooms = await _pumpRows(tester, {1: 0, 2: 2}, compact: compact);
        const joined = ValueKey('chat-inbox-room-1');
        const other = ValueKey('chat-inbox-room-2');
        final redrawn = <Key>{};
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          final key = element.widget.key;
          if (key == joined || key == other) redrawn.add(key!);
          previous?.call(element, builtOnce);
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);

        rooms.change(1, 1);
        await tester.pump();

        expect(redrawn, {joined});
        expect(find.text('1 person here'), findsOneWidget);
        expect(find.text('2 people here'), findsOneWidget);
      });
    });
  }
}
