import '../../shell/shell_controller.dart';
import '../plugin_services.dart';
import 'assignment.dart';
import 'assignment_controller.dart';

/// Assign's typed convenience API over its session-owned controller.
///
/// This lives with the plugin so core never needs to import Assign models or
/// controllers merely to expose plugin behavior.
extension AssignmentShellExtension on ShellController {
  AssignmentController get _assignmentController =>
      pluginSession.require(assignmentControllerService);

  Future<AssignmentSuggestions> assignmentSuggestions(
    String siteUrl,
    AssignmentTarget target,
  ) => _assignmentController.suggestions(siteUrl, target);

  Future<List<AssignmentAssignee>> searchAssignmentAssignees(
    String siteUrl,
    AssignmentTarget target,
    AssignmentSuggestions suggestions,
    String term,
  ) => _assignmentController.search(siteUrl, target, suggestions, term);

  Future<String?> assignTarget(
    String siteUrl,
    AssignmentTarget target,
    AssignmentAssignee assignee, {
    String? note,
    String? status,
  }) => _assignmentController.assign(
    siteUrl,
    target,
    assignee,
    note: note,
    status: status,
  );

  Future<String?> unassignTarget(String siteUrl, AssignmentTarget target) =>
      _assignmentController.unassign(siteUrl, target);

  bool assignmentWriteInFlight(String siteUrl, AssignmentTarget target) =>
      _assignmentController.isWriting(siteUrl, target);
}
