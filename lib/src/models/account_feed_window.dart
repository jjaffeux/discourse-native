import 'package:flutter/foundation.dart';

@immutable
class AccountFeedPacket<T> {
  const AccountFeedPacket({
    required this.start,
    required this.end,
    required this.items,
  });

  final int start;
  final int end;
  final List<T> items;
}

/// A contiguous server range. Cursors count raw slots, including rejected and
/// overlapping rows, so evicting payloads never loses the way back to them.
@immutable
class AccountFeedWindow<T> {
  const AccountFeedWindow({
    this.packets = const [],
    this.lastPageWasPrevious = false,
  });

  static const maximumRows = 300;
  static const maximumPackets = 10;
  static const maximumEstimatedBytes = 4 * 1024 * 1024;

  final List<AccountFeedPacket<T>> packets;
  final bool lastPageWasPrevious;

  int get start => packets.firstOrNull?.start ?? 0;
  int get end => packets.lastOrNull?.end ?? 0;
  List<T> get items =>
      List.unmodifiable([for (final packet in packets) ...packet.items]);

  int estimatedBytes(int Function(T) estimate) => packets.fold(
    0,
    (bytes, packet) =>
        bytes + packet.items.fold(0, (sum, row) => sum + estimate(row)),
  );

  AccountFeedWindow<T> withPage({
    required List<T> incoming,
    required int start,
    required int end,
    required bool prepend,
    required Object Function(T) identity,
    required T Function(T? held, T incoming) merge,
    required int Function(T) estimate,
  }) {
    final heldById = <Object, T>{
      for (final packet in packets)
        for (final row in packet.items) identity(row): row,
    };
    final newById = <Object, T>{};
    for (final row in incoming) {
      final key = identity(row);
      newById[key] = merge(newById[key] ?? heldById[key], row);
    }
    final retained = [
      for (final packet in packets)
        AccountFeedPacket<T>(
          start: packet.start,
          end: packet.end,
          items: List.unmodifiable([
            for (final row in packet.items) newById[identity(row)] ?? row,
          ]),
        ),
    ];
    final added = AccountFeedPacket<T>(
      start: start,
      end: end,
      items: List.unmodifiable([
        for (final entry in newById.entries)
          if (!heldById.containsKey(entry.key)) entry.value,
      ]),
    );
    final bounded = prepend ? [added, ...retained] : [...retained, added];
    var rows = bounded.fold(0, (count, packet) => count + packet.items.length);
    var bytes = bounded.fold(
      0,
      (count, packet) =>
          count + packet.items.fold(0, (sum, row) => sum + estimate(row)),
    );
    while (bounded.length > 1 &&
        (bounded.length > maximumPackets ||
            rows > maximumRows ||
            bytes > maximumEstimatedBytes)) {
      final removed = bounded.removeAt(prepend ? bounded.length - 1 : 0);
      rows -= removed.items.length;
      bytes -= removed.items.fold(0, (sum, row) => sum + estimate(row));
      final activeIndex = prepend ? 0 : bounded.length - 1;
      final active = bounded[activeIndex];
      final survivingIds = {
        for (var index = 0; index < bounded.length; index++)
          if (index != activeIndex)
            for (final row in bounded[index].items) identity(row),
      };
      final activeRows = List<T>.unmodifiable([
        for (final entry in newById.entries)
          if (!survivingIds.contains(entry.key)) entry.value,
      ]);
      rows += activeRows.length - active.items.length;
      bytes +=
          activeRows.fold(0, (sum, row) => sum + estimate(row)) -
          active.items.fold(0, (sum, row) => sum + estimate(row));
      bounded[activeIndex] = AccountFeedPacket(
        start: active.start,
        end: active.end,
        items: activeRows,
      );
    }
    return AccountFeedWindow(
      packets: List.unmodifiable(bounded),
      lastPageWasPrevious: prepend,
    );
  }

  AccountFeedWindow<T> without(Object key, Object Function(T) identity) {
    var shifted = 0;
    final updated = <AccountFeedPacket<T>>[];
    for (final packet in packets) {
      final rows = packet.items.where((row) => identity(row) != key).toList();
      final removed = packet.items.length - rows.length;
      updated.add(
        AccountFeedPacket(
          start: packet.start - shifted,
          end: packet.end - shifted - removed,
          items: List.unmodifiable(rows),
        ),
      );
      shifted += removed;
    }
    return AccountFeedWindow(
      packets: List.unmodifiable(updated),
      lastPageWasPrevious: lastPageWasPrevious,
    );
  }
}

int accountFeedStringBytes(Iterable<String?> strings) =>
    strings.fold(64, (bytes, text) => bytes + (text?.length ?? 0) * 2);
