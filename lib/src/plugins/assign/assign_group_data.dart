import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import '../../plugin_api/plugin_data.dart';

const assignGroupDataKey = PluginDataKey<AssignGroupData>(
  owner: 'discourse-assign',
  name: 'group',
);

@immutable
final class AssignGroupData {
  const AssignGroupData({
    required this.assignableLevel,
    required this.canShowAssignedTab,
    this.assignmentCount,
  });

  static AssignGroupData? fromWire(Map<String, dynamic> json) {
    if (!json.containsKey('assignable_level') &&
        !json.containsKey('can_show_assigned_tab') &&
        !json.containsKey('assignment_count')) {
      return null;
    }
    final count = jsonIntOrNull(json['assignment_count']);
    return AssignGroupData(
      assignableLevel: jsonInt(json['assignable_level']),
      canShowAssignedTab: json['can_show_assigned_tab'] == true,
      assignmentCount: count == null || count < 0 ? null : count,
    );
  }

  final int assignableLevel;
  final bool canShowAssignedTab;
  final int? assignmentCount;
}
