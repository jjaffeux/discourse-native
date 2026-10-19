import 'package:discourse_native/discourse_plugin_sdk.dart';

enum AssignmentWriteKind {
  applied,
  acceptedRefreshFailed,
  acceptedRetired,
  busy,
  inactive,
  targetUnavailable,
  refused,
  notSent,
  uncertain,
}

final class AssignmentWriteResult {
  const AssignmentWriteResult._(this.kind, [this.failure]);

  const AssignmentWriteResult.applied() : this._(AssignmentWriteKind.applied);
  const AssignmentWriteResult.acceptedRefreshFailed(WriteException failure)
    : this._(AssignmentWriteKind.acceptedRefreshFailed, failure);
  const AssignmentWriteResult.acceptedRetired()
    : this._(AssignmentWriteKind.acceptedRetired);
  const AssignmentWriteResult.busy() : this._(AssignmentWriteKind.busy);
  const AssignmentWriteResult.inactive() : this._(AssignmentWriteKind.inactive);
  const AssignmentWriteResult.targetUnavailable()
    : this._(AssignmentWriteKind.targetUnavailable);
  const AssignmentWriteResult.refused(WriteException failure)
    : this._(AssignmentWriteKind.refused, failure);
  const AssignmentWriteResult.notSent(WriteException failure)
    : this._(AssignmentWriteKind.notSent, failure);
  const AssignmentWriteResult.uncertain(WriteException failure)
    : this._(AssignmentWriteKind.uncertain, failure);

  final AssignmentWriteKind kind;
  final WriteException? failure;

  bool get accepted => switch (kind) {
    AssignmentWriteKind.applied ||
    AssignmentWriteKind.acceptedRefreshFailed ||
    AssignmentWriteKind.acceptedRetired => true,
    _ => false,
  };
}
