import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum PolicyReminder { none, daily, weekly }

enum PolicyCalendarInterval { monthly, quarterly, yearly }

sealed class PolicyRenewal {
  const PolicyRenewal();
  String? get markup;
}

final class PolicyNoRenewal extends PolicyRenewal {
  const PolicyNoRenewal();
  @override
  String? get markup => null;
}

final class PolicyRenewAfterDays extends PolicyRenewal {
  const PolicyRenewAfterDays(this.days) : assert(days > 0);
  final int days;
  @override
  String get markup => '$days';
}

final class PolicyRenewByCalendar extends PolicyRenewal {
  const PolicyRenewByCalendar(this.interval);
  final PolicyCalendarInterval interval;
  @override
  String get markup => interval.name;
}

@immutable
final class PolicyDefinition {
  PolicyDefinition({
    required List<String> audienceGroups,
    this.version = '1',
    this.renewal = const PolicyNoRenewal(),
    this.reminder = PolicyReminder.none,
    this.privateStatistics = false,
    this.renewStartDate,
    this.acceptLabel,
    this.revokeLabel,
    this.targetGroup,
  }) : audienceGroups = List.unmodifiable(audienceGroups);

  final List<String> audienceGroups;
  final String version;
  final PolicyRenewal renewal;
  final PolicyReminder reminder;
  final bool privateStatistics;
  final String? renewStartDate;
  final String? acceptLabel;
  final String? revokeLabel;
  final String? targetGroup;

  factory PolicyDefinition.fromAttributes(Map<String, String> attrs) {
    final renew = attrs['renew'];
    final days = int.tryParse(renew ?? '');
    final interval = PolicyCalendarInterval.values
        .where((v) => v.name == renew)
        .firstOrNull;
    return PolicyDefinition(
      audienceGroups: {
        for (final field in ['group', 'groups'])
          for (final name in (attrs[field] ?? '').split(','))
            if (name.trim().isNotEmpty) name.trim(),
      }.toList(),
      version: _present(attrs['version']) ?? '1',
      renewal: days != null && days > 0
          ? PolicyRenewAfterDays(days)
          : interval != null
          ? PolicyRenewByCalendar(interval)
          : const PolicyNoRenewal(),
      reminder:
          PolicyReminder.values
              .where(
                (v) => v != PolicyReminder.none && v.name == attrs['reminder'],
              )
              .firstOrNull ??
          PolicyReminder.none,
      privateStatistics: attrs['private'] == 'true',
      renewStartDate: _present(attrs['renew-start']),
      acceptLabel: _present(attrs['accept']),
      revokeLabel: _present(attrs['revoke']),
      targetGroup: _present(attrs['add-users-to-group']),
    );
  }

  factory PolicyDefinition.fromCookedAttributes(Map<String, String> attrs) =>
      PolicyDefinition.fromAttributes({
        for (final entry in attrs.entries)
          if (entry.key.startsWith('data-'))
            entry.key.substring(5): entry.value,
      });

  Map<String, String> get attributes => {
    'groups': audienceGroups.join(','),
    'version': version,
    'renew': ?renewal.markup,
    'renew-start': ?_present(renewStartDate),
    if (reminder != PolicyReminder.none) 'reminder': reminder.name,
    'accept': ?_present(acceptLabel),
    'revoke': ?_present(revokeLabel),
    'add-users-to-group': ?_present(targetGroup),
    if (privateStatistics) 'private': 'true',
  };
}

String? _present(String? value) =>
    value == null || value.isEmpty ? null : value;

@immutable
final class PolicySourceOccurrence {
  PolicySourceOccurrence({
    required this.range,
    required this.openingTagRange,
    required this.bodyRange,
    required this.source,
    required this.definition,
    required Map<String, String> preservedAttributes,
    required List<PolicyMarkupAttribute> attributes,
  }) : preservedAttributes = Map.unmodifiable(preservedAttributes),
       attributes = List.unmodifiable(attributes);
  final TextRange range;
  final TextRange openingTagRange;
  final TextRange bodyRange;
  final String source;
  final PolicyDefinition definition;
  final Map<String, String> preservedAttributes;
  final List<PolicyMarkupAttribute> attributes;
  int get start => range.start;
  int get end => range.end;
  String get body =>
      source.substring(bodyRange.start - start, bodyRange.end - start);
}

@immutable
final class PolicyMarkupAttribute {
  const PolicyMarkupAttribute({
    required this.name,
    required this.value,
    required this.range,
    required this.valueRange,
  });
  final String name;
  final String value;
  final TextRange range;
  final TextRange valueRange;
}

/// Values use an upstream-supported quote pair. BBCode does not interpret
/// backslash escapes, so adding one would silently change the author's label.
String policyMarkupValue(String value) {
  if (value.contains('\n') || value.contains('\r')) {
    throw const FormatException(
      'Policy attribute values cannot contain line breaks.',
    );
  }
  for (final pair in _quotes) {
    if (!value.contains(pair.$2)) return '${pair.$1}$value${pair.$2}';
  }
  throw const FormatException(
    'Policy attribute value cannot be quoted safely.',
  );
}

const _quotes = [
  ('"', '"'),
  ("'", "'"),
  ('«', '»'),
  ('“', '”'),
  ('”', '”'),
  ('‘', '’'),
  ('„', '“'),
  ('‚', '’'),
  ('‹', '›'),
];
final _opening = RegExp(r'^ {0,3}\[policy(?=[\s\]])', caseSensitive: false);
final _closing = RegExp(r'^ {0,3}\[/policy\]\s*$', caseSensitive: false);
final _attributeName = RegExp(r'[-\w]+');

final class PolicySourceCodec {
  const PolicySourceCodec();

  List<PolicySourceOccurrence> find(String markdown) {
    final code = markdownCodeRanges(markdown);
    final occurrences = <PolicySourceOccurrence>[];
    ({int start, int openEnd, List<PolicyMarkupAttribute> attrs})? pending;
    var nested = 0;
    var invalidNested = false;
    var quoted = 0;
    var bbCode = 0;
    var htmlQuote = 0;
    var offset = 0;
    for (final line in markdown.split('\n')) {
      final trimmed = line.trim();
      final end = offset + line.length;
      if (!code.contains(offset + line.length - line.trimLeft().length)) {
        if (RegExp(r'^\[/quote\]', caseSensitive: false).hasMatch(trimmed)) {
          if (quoted > 0) quoted--;
        } else if (RegExp(
          r'^\[quote(?=[\s=\]])',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
          quoted++;
        } else if (RegExp(
          r'^\[/code\]',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
          if (bbCode > 0) bbCode--;
        } else if (RegExp(
          r'^\[code(?=[\s=\]])',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
          bbCode++;
        } else if (RegExp(
          r'^</blockquote\s*>',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
          if (htmlQuote > 0) htmlQuote--;
        } else if (RegExp(
          r'^<blockquote(?:\s|>)',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
          htmlQuote++;
        } else if (quoted == 0 &&
            bbCode == 0 &&
            htmlQuote == 0 &&
            !RegExp(r'^ {0,3}>').hasMatch(line)) {
          final opening = _opening.firstMatch(line);
          if (opening != null) {
            final start = offset + line.indexOf('[');
            final openEnd = _tagEnd(markdown, start + 7, end);
            if (openEnd != null &&
                markdown.substring(openEnd, end).trim().isEmpty) {
              final attrs = _attributes(markdown, start + 7, openEnd - 1);
              if (pending != null) {
                nested++;
                invalidNested = true;
              } else if (attrs != null &&
                  attrs.any(
                    (a) =>
                        (a.name == 'group' || a.name == 'groups') &&
                        a.value.isNotEmpty,
                  )) {
                pending = (start: start, openEnd: openEnd, attrs: attrs);
                invalidNested = false;
              }
            }
          } else if (_closing.hasMatch(line) && pending != null) {
            if (nested > 0) {
              nested--;
            } else {
              if (!invalidNested) {
                final start = pending.start;
                final closeStart = offset + line.indexOf('[');
                final closeEnd = closeStart + '[/policy]'.length;
                final attrs = {for (final a in pending.attrs) a.name: a.value};
                occurrences.add(
                  PolicySourceOccurrence(
                    range: TextRange(start: start, end: closeEnd),
                    openingTagRange: TextRange(
                      start: start,
                      end: pending.openEnd,
                    ),
                    bodyRange: TextRange(
                      start: pending.openEnd,
                      end: closeStart,
                    ),
                    source: markdown.substring(start, closeEnd),
                    definition: PolicyDefinition.fromAttributes(attrs),
                    preservedAttributes: attrs,
                    attributes: pending.attrs,
                  ),
                );
              }
              pending = null;
            }
          }
        }
      }
      offset = end + 1;
    }
    return List.unmodifiable(occurrences);
  }

  String openingTag(PolicyDefinition definition) =>
      '[policy${definition.attributes.entries.map((e) => ' ${e.key}=${policyMarkupValue(e.value)}').join()}]';

  TextEditingValue replaceSettings({
    required TextEditingValue document,
    required PolicySourceOccurrence occurrence,
    required PolicyDefinition replacement,
  }) {
    final before = occurrence.definition.attributes;
    final after = replacement.attributes;
    final changes = <String, String?>{
      for (final name in {...before.keys, ...after.keys})
        if (before[name] != after[name]) name: after[name],
    };
    if (changes.containsKey('groups')) changes['group'] = null;
    return replaceAttributes(
      document: document,
      occurrence: occurrence,
      changes: changes,
    );
  }

  TextEditingValue replaceAttributes({
    required TextEditingValue document,
    required PolicySourceOccurrence occurrence,
    required Map<String, String?> changes,
  }) {
    if (occurrence.end > document.text.length ||
        document.text.substring(occurrence.start, occurrence.end) !=
            occurrence.source) {
      throw StateError('The policy source changed before this edit.');
    }
    final remaining = Map<String, String?>.of(changes);
    final edits = <({int start, int end, String text})>[];
    for (final attr in occurrence.attributes) {
      if (!remaining.containsKey(attr.name)) continue;
      final value = remaining.remove(attr.name);
      if (value == attr.value) continue;
      edits.add(
        value == null || value.isEmpty
            ? (start: attr.range.start, end: attr.range.end, text: '')
            : (
                start: attr.valueRange.start,
                end: attr.valueRange.end,
                text:
                    '${attr.valueRange.isCollapsed ? '=' : ''}${policyMarkupValue(value)}',
              ),
      );
    }
    final additions = [
      for (final e in remaining.entries)
        if (e.value != null && e.value!.isNotEmpty)
          ' ${e.key}=${policyMarkupValue(e.value!)}',
    ].join();
    if (additions.isNotEmpty) {
      edits.add((
        start: occurrence.openingTagRange.end - 1,
        end: occurrence.openingTagRange.end - 1,
        text: additions,
      ));
    }
    if (edits.isEmpty) return document;
    edits.sort((a, b) => b.start.compareTo(a.start));
    var text = document.text;
    for (final edit in edits) {
      text = text.replaceRange(edit.start, edit.end, edit.text);
    }
    return document.copyWith(
      text: text,
      selection: TextSelection.collapsed(
        offset:
            occurrence.openingTagRange.end + text.length - document.text.length,
      ),
      composing: TextRange.empty,
    );
  }
}

int? _tagEnd(String source, int start, int limit) {
  String? quote;
  for (var i = start; i < limit; i++) {
    final char = source[i];
    final openingQuote = source[i - 1] == '='
        ? _quotes.where((pair) => pair.$1 == char).firstOrNull
        : null;
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (openingQuote case final pair?) {
      quote = pair.$2;
    } else if (char == ']') {
      return i + 1;
    }
  }
  return null;
}

List<PolicyMarkupAttribute>? _attributes(String source, int offset, int end) {
  final attrs = <PolicyMarkupAttribute>[];
  final names = <String>{};
  while (offset < end) {
    final start = offset;
    while (offset < end && source[offset].trim().isEmpty) {
      offset++;
    }
    if (offset == end) break;
    final nameMatch = _attributeName.matchAsPrefix(source, offset);
    if (nameMatch == null) return null;
    final name = nameMatch[0]!.toLowerCase();
    if (!names.add(name)) return null;
    offset = nameMatch.end;
    var value = '';
    var valueStart = offset;
    if (offset < end && source[offset] == '=') {
      offset++;
      valueStart = offset;
      if (offset == end) return null;
      final quote = _quotes.where((p) => p.$1 == source[offset]).firstOrNull;
      if (quote != null) {
        final contentStart = ++offset;
        while (offset < end && source[offset] != quote.$2) {
          offset++;
        }
        if (offset == end) return null;
        value = source.substring(contentStart, offset).trim();
        offset++;
      } else {
        final contentStart = offset;
        while (offset < end && source[offset].trim().isNotEmpty) {
          offset++;
        }
        value = source.substring(contentStart, offset);
      }
    }
    if (offset < end && source[offset].trim().isNotEmpty) return null;
    attrs.add(
      PolicyMarkupAttribute(
        name: name,
        value: value,
        range: TextRange(start: start, end: offset),
        valueRange: TextRange(start: valueStart, end: offset),
      ),
    );
  }
  return attrs;
}
