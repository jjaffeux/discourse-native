import 'package:discourse_native/discourse_plugin_sdk.dart';

enum SolvedChangeKind {
  applied,
  unchanged,
  busy,
  inactive,
  acceptedRetired,
  acceptedRefreshFailed,
  refused,
  notSent,
  uncertain,
}

final class SolvedChangeResult {
  const SolvedChangeResult._(this.kind, this.failure, this.isCurrent);

  const SolvedChangeResult.applied()
    : this._(SolvedChangeKind.applied, null, true);

  const SolvedChangeResult.unchanged()
    : this._(SolvedChangeKind.unchanged, null, true);

  const SolvedChangeResult.busy() : this._(SolvedChangeKind.busy, null, true);

  const SolvedChangeResult.inactive()
    : this._(SolvedChangeKind.inactive, null, false);

  const SolvedChangeResult.acceptedRetired()
    : this._(SolvedChangeKind.acceptedRetired, null, false);

  const SolvedChangeResult.acceptedRefreshFailed(WriteException failure)
    : this._(SolvedChangeKind.acceptedRefreshFailed, failure, true);

  const SolvedChangeResult.refused(
    WriteException failure, {
    required bool isCurrent,
  }) : this._(SolvedChangeKind.refused, failure, isCurrent);

  const SolvedChangeResult.notSent(
    WriteException failure, {
    required bool isCurrent,
  }) : this._(SolvedChangeKind.notSent, failure, isCurrent);

  const SolvedChangeResult.uncertain(
    WriteException failure, {
    required bool isCurrent,
  }) : this._(SolvedChangeKind.uncertain, failure, isCurrent);

  final SolvedChangeKind kind;
  final WriteException? failure;
  final bool isCurrent;
}
