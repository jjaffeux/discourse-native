import 'package:flutter/foundation.dart';

import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';

@immutable
final class GroupUpdateCommand {
  GroupUpdateCommand(Map<String, Object?> values)
    : values = freezeGroupValues(values);

  final Map<String, Object?> values;
}

@immutable
final class GroupAddMembersCommand {
  GroupAddMembersCommand({
    Iterable<String> usernames = const [],
    Iterable<String> emails = const [],
  }) : usernames = List.unmodifiable(usernames),
       emails = List.unmodifiable(emails);

  final List<String> usernames;
  final List<String> emails;
}

Map<String, Object?> freezeGroupValues(Map<String, Object?> values) =>
    Map.unmodifiable(values.map((key, value) => MapEntry(key, _freeze(value))));

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?> value => freezeGroupValues(value),
  Iterable<Object?> value => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

enum GroupWriteAdmission { inactive, busy, noCredentials, expiredConfirmation }

enum GroupProjectionFreshness { notRequested, refreshed, stale, retired }

enum GroupWriteDelivery { refused, notSent, uncertain }

sealed class GroupWriteOutcome<T> {
  const GroupWriteOutcome();

  bool get canApplyLocally => switch (this) {
    GroupWriteAccepted<T> accepted => accepted.isCurrent,
    _ => false,
  };
}

final class GroupWriteAccepted<T> extends GroupWriteOutcome<T> {
  const GroupWriteAccepted(
    this.value, {
    this.projection = GroupProjectionFreshness.notRequested,
    this.current = true,
    this.account,
  });

  final T value;
  final GroupProjectionFreshness projection;
  final bool current;
  final SiteLease? account;

  GroupWriteAccepted<T> withProjection(
    GroupProjectionFreshness projection, {
    bool current = true,
  }) => GroupWriteAccepted(
    value,
    projection: projection,
    current: this.current && current,
    account: account,
  );

  bool get isCurrent => current && (account?.isCurrent ?? true);
}

final class GroupWriteNotAdmitted<T> extends GroupWriteOutcome<T> {
  const GroupWriteNotAdmitted(this.reason);

  final GroupWriteAdmission reason;
}

final class GroupWriteFailed<T> extends GroupWriteOutcome<T> {
  GroupWriteFailed(this.error, {required bool dispatched})
    : delivery = switch (error) {
        WriteException(notSent: true) => GroupWriteDelivery.notSent,
        WriteException(failure: final failure)
            when failure != WriteFailure.unreachable =>
          GroupWriteDelivery.refused,
        _ when !dispatched => GroupWriteDelivery.notSent,
        _ => GroupWriteDelivery.uncertain,
      };

  final Object error;
  final GroupWriteDelivery delivery;
}

final class GroupUpdateConfirmation extends GroupWriteOutcome<void> {
  const GroupUpdateConfirmation(this.affectedUserCount);

  final int affectedUserCount;
}
