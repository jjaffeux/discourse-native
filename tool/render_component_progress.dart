import 'dart:convert';
import 'dart:io';

void main() {
  final progress =
      jsonDecode(
            File('docs/component-library/progress.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final foundation = progress['foundation'] as Map<String, dynamic>;
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
    )
    ..writeln('## Component implementation\n')
    ..writeln(
      '| # | Component | Status | Task | Branch | Dependencies | Merge |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  final components = (progress['components'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .toList();
  for (var i = 0; i < components.length; i++) {
    final row = components[i];
    output.writeln(
      '| ${i + 1} | ${row['id']} | ${row['status']} | ${cell(row['taskId'])} | ${cell(row['branch'])} | ${cell((row['dependencies'] as List<dynamic>).join(', '))} | ${cell(row['mergeCommit'])} |',
    );
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
