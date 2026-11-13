import 'package:flutter/foundation.dart';

@immutable
class AccountFeedPacket<T> {
  AccountFeedPacket({
    required this.start,
    required this.end,
    required Iterable<T> items,
  }) : items = List.unmodifiable(items);

  AccountFeedPacket._shifted(AccountFeedPacket<T> held, int shift)
    : start = held.start - shift,
      end = held.end - shift,
      items = held.items;

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
  List<T> get items {
    if (packets.length == 1) return packets.first.items;
    return List.unmodifiable([for (final packet in packets) ...packet.items]);
  }

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
    final keyedIncoming = [for (final row in incoming) (identity(row), row)];
    final incomingIds = {for (final (key, _) in keyedIncoming) key};
    final heldById = <Object, T>{};
    final overlappingPackets = <int>{};
    for (var index = 0; index < packets.length; index++) {
      for (final row in packets[index].items) {
        final key = identity(row);
        if (incomingIds.contains(key)) {
          heldById[key] = row;
          overlappingPackets.add(index);
        }
      }
    }
    final newById = <Object, T>{};
    for (final (key, row) in keyedIncoming) {
      newById[key] = merge(newById[key] ?? heldById[key], row);
    }
    final retained = <AccountFeedPacket<T>>[];
    for (var packetIndex = 0; packetIndex < packets.length; packetIndex++) {
      final packet = packets[packetIndex];
      if (!overlappingPackets.contains(packetIndex)) {
        retained.add(packet);
        continue;
      }
      List<T>? updated;
      for (var index = 0; index < packet.items.length; index++) {
        final row = packet.items[index];
        final next = newById[identity(row)] ?? row;
        if (!identical(next, row)) {
          updated ??= List<T>.of(packet.items);
          updated[index] = next;
        }
      }
      retained.add(
        updated == null
            ? packet
            : AccountFeedPacket<T>(
                start: packet.start,
                end: packet.end,
                items: updated,
              ),
      );
    }
    final added = AccountFeedPacket<T>(
      start: start,
      end: end,
      items: [
        for (final entry in newById.entries)
          if (!heldById.containsKey(entry.key)) entry.value,
      ],
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
      final activeRows = [
        for (final entry in newById.entries)
          if (!survivingIds.contains(entry.key)) entry.value,
      ];
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
    List<AccountFeedPacket<T>>? updated;
    for (var index = 0; index < packets.length; index++) {
      final packet = packets[index];
      final first = packet.items.indexWhere((row) => identity(row) == key);
      if (first < 0) {
        updated?.add(AccountFeedPacket._shifted(packet, shifted));
        continue;
      }
      updated ??= packets.take(index).toList();
      final rows = [
        ...packet.items.take(first),
        for (final row in packet.items.skip(first + 1))
          if (identity(row) != key) row,
      ];
      final removed = packet.items.length - rows.length;
      updated.add(
        AccountFeedPacket(
          start: packet.start - shifted,
          end: packet.end - shifted - removed,
          items: rows,
        ),
      );
      shifted += removed;
    }
    if (updated == null) return this;
    return AccountFeedWindow(
      packets: List.unmodifiable(updated),
      lastPageWasPrevious: lastPageWasPrevious,
    );
  }
}

int accountFeedStringBytes(Iterable<String?> strings) =>
    strings.fold(64, (bytes, text) => bytes + (text?.length ?? 0) * 2);
