import 'dart:convert';
import 'dart:io';

void main() {
  final progress =
      jsonDecode(
            File('docs/component-library/progress.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final foundation = progress['foundation'] as Map<String, dynamic>;
  final components = (progress['components'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .toList();
  final applicationComponents =
      (progress['applicationComponents'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
  String cell(Object? value) =>
      value == null || value == '' ? '—' : '$value'.replaceAll('|', r'\|');
  final output = StringBuffer()
    ..writeln('# Component library progress\n')
    ..writeln(
      'Generated from [progress.json](progress.json). Read the [brief](brief.md), [conventions](conventions.md), [catalogue](catalogue.json) and [inventory](inventory.md).\n',
    )
    ..writeln(
      'Coordinator task: `${progress['coordinatorTaskId']}`. Reference: ${progress['referenceDate']}.\n',
    )
    ..writeln(
      'Foundation: **${foundation['status']}** on `${foundation['branch']}`. Merge: ${cell(foundation['mergeCommit'])}.\n',
    );
  _writeReviewQueue(output, progress, components);
  output
    ..writeln('## Component implementation\n')
    ..writeln(
      '| # | Component | Status | Task | Branch | Dependencies | Merge |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (var i = 0; i < components.length; i++) {
    final row = components[i];
    output.writeln(
      '| ${i + 1} | ${row['id']} | ${row['status']} | ${cell(row['taskId'])} | ${cell(row['branch'])} | ${cell((row['dependencies'] as List<dynamic>).join(', '))} | ${cell(row['mergeCommit'])} |',
    );
  }
  if (applicationComponents.isNotEmpty) {
    output
      ..writeln('\n## Application components\n')
      ..writeln(
        'User-approved extensions outside the frozen upstream catalogue.\n',
      )
      ..writeln('| Component | Status | Task | Branch | Merge |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final row in applicationComponents) {
      output.writeln(
        '| ${row['id']} | ${row['status']} | ${cell(row['taskId'])} | ${cell(row['branch'])} | ${cell(row['mergeCommit'])} |',
      );
    }
  }
  output.writeln('\n## Decisions and evidence\n');
  for (final (name, row) in [
    ('Foundation', foundation),
    if (progress['visualFidelity'] case final Map<String, dynamic> review)
      ('shadcn visual fidelity correction', review),
    if (progress['styleguideFidelity'] case final Map<String, dynamic> review)
      ('Documentation layout and Sidebar adoption', review),
    for (final row in components.where((row) => row['status'] != 'planned'))
      (row['id'] as String, row),
    for (final row in applicationComponents) (row['id'] as String, row),
    ('Final audit', progress['finalAudit'] as Map<String, dynamic>),
  ]) {
    output.writeln('### $name\n');
    output.writeln(
      'Status: ${row['status']}. Task: ${cell(row['taskId'])}. Branch: ${cell(row['branch'])}.\n',
    );
    for (final field in [
      'acceptanceCriteria',
      'decisions',
      'migrations',
      'retainedAlternatives',
      'verification',
      'limitations',
    ]) {
      final values = (row[field] as List<dynamic>?) ?? [];
      if (values.isEmpty) continue;
      output.writeln('**$field**\n');
      for (final value in values) {
        output.writeln('- $value');
      }
      output.writeln();
    }
  }
  File(
    'docs/component-library/progress.md',
  ).writeAsStringSync(output.toString());
}

void _writeReviewQueue(
  StringBuffer output,
  Map<String, dynamic> progress,
  List<Map<String, dynamic>> components,
) {
  final merged = components.where((row) => row['status'] == 'merged').length;
  final planned = components.where((row) => row['status'] == 'planned').length;
  final pending = components
      .where((row) => row['status'] != 'merged' && row['status'] != 'planned')
      .toList();
  output
    ..writeln('## Current review queue\n')
    ..writeln(
      '**$merged of ${components.length} components are merged locally.** '
      '${pending.length} existing components are in progress; $planned are planned.\n',
    );
  final workflow = progress['workflow'] as Map<String, dynamic>? ?? {};
  final reviewPolicy = workflow['reviewPolicy'] as Map<String, dynamic>?;
  if (reviewPolicy?['ownership'] == 'independent_reviewer') {
    output.writeln(
      'Each component has an independent review task that owns fixes, '
      'remaining verification and the local main merge. '
      'See the [review and merge procedure](review-and-merge.md).\n',
    );
  }
  final native = workflow['nativeInspectionBlocker'] as Map<String, dynamic>?;
  final browser = workflow['browserInspectionBlocker'] as Map<String, dynamic>?;
  if (native?['status'] == 'active') {
    output.writeln('Native review is waiting for the Mac to be unlocked.\n');
  }
  if (browser?['status'] == 'active') {
    output.writeln(
      'Reference browsing is blocked because the browser could not verify '
      'its admin-enforced security policy.\n',
    );
  }
  final resume = workflow['resume'] as Map<String, dynamic>? ?? {};
  final tasks = <String, Map<String, dynamic>>{
    for (final field in ['activeTasks', 'nativeReadyTasks'])
      for (final task
          in (resume[field] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>())
        task['component'] as String: task,
  };
  if (pending.isEmpty || tasks.isEmpty) return;
  output
    ..writeln(
      'Branch preparation does not mark a component merged or visually verified.\n',
    )
    ..writeln('| Component | Current stage | Branch head | Reviewer task |')
    ..writeln('| --- | --- | --- | --- |');
  for (final row in pending) {
    final task = tasks[row['id']];
    if (task == null) continue;
    final status = task['status'] as String? ?? 'in_progress';
    final stage = switch (status) {
      'implementation' => 'Implementation and checks',
      'main_integration_preparation' => 'Integration checks',
      'main_integration_and_form_correction' =>
        'Integration and Form correction',
      'awaiting_native_unlock' => 'Native review; Mac locked',
      'awaiting_native_review' => 'Native review',
      'awaiting_browser_and_native_review' => 'Reference and native review',
      'awaiting_browser_native_and_control_reconciliation' ||
      'awaiting_browser_native_and_dependency_reconciliation' =>
        'Control composition, reference and native review',
      'awaiting_browser_native_and_input_group_reconciliation' =>
        'Input Group composition, reference and native review',
      _ => status.replaceAll('_', ' '),
    };
    final head = task['headCommit'] as String?;
    final abbreviated = head == null
        ? '—'
        : head.length > 8
        ? head.substring(0, 8)
        : head;
    final reviewer =
        row['reviewTaskId'] ??
        (row['reviewClientThreadId'] == null ? '—' : 'Worktree setup');
    output.writeln('| ${row['id']} | $stage | $abbreviated | $reviewer |');
  }
  output.writeln();
}
