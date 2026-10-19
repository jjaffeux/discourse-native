import 'package:discourse_native/discourse_plugin_sdk.dart';

enum ReactionToggleKind {
  applied,
  unchanged,
  busy,
  inactive,
  acceptedRetired,
  refused,
  notSent,
  uncertain,
  unavailable,
}

final class ReactionToggleResult {
  const ReactionToggleResult._(this.kind, this.failure, this.isCurrent);

  const ReactionToggleResult.applied()
    : this._(ReactionToggleKind.applied, null, true);

  const ReactionToggleResult.unchanged()
    : this._(ReactionToggleKind.unchanged, null, true);

  const ReactionToggleResult.busy()
    : this._(ReactionToggleKind.busy, null, true);

  const ReactionToggleResult.inactive()
    : this._(ReactionToggleKind.inactive, null, false);

  const ReactionToggleResult.acceptedRetired()
    : this._(ReactionToggleKind.acceptedRetired, null, false);

  const ReactionToggleResult.refused(
    WriteException failure, {
    required bool isCurrent,
  }) : this._(ReactionToggleKind.refused, failure, isCurrent);

  const ReactionToggleResult.notSent(
    WriteException failure, {
    required bool isCurrent,
  }) : this._(ReactionToggleKind.notSent, failure, isCurrent);

  const ReactionToggleResult.uncertain(
    WriteException failure, {
    required bool isCurrent,
  }) : this._(ReactionToggleKind.uncertain, failure, isCurrent);

  const ReactionToggleResult.unavailable(
    WriteException failure, {
    required bool isCurrent,
  }) : this._(ReactionToggleKind.unavailable, failure, isCurrent);

  final ReactionToggleKind kind;
  final WriteException? failure;
  final bool isCurrent;
}
