import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'assignment_write_result.dart';

String? assignmentWriteMessage(AssignmentWriteResult result) =>
    switch (result.kind) {
      AssignmentWriteKind.applied ||
      AssignmentWriteKind.acceptedRetired => null,
      AssignmentWriteKind.busy => appL10n.anAssignmentUpdateIsAlreadyInProgress,
      AssignmentWriteKind.inactive => const WriteException(
        WriteFailure.forbidden,
      ).message,
      AssignmentWriteKind.targetUnavailable =>
        appL10n.thisAssignmentTargetIsNoLongerAvailable,
      AssignmentWriteKind.acceptedRefreshFailed ||
      AssignmentWriteKind.refused ||
      AssignmentWriteKind.notSent ||
      AssignmentWriteKind.uncertain => result.failure!.message,
    };
