import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import '../../models/json.dart';
import '../../models/post.dart';
import '../../plugin_api/plugin_data.dart';

const pollsDataKey = PluginDataKey<Polls>(owner: 'poll', name: 'post');

extension PollPostPluginData on PluginData {
  Polls? get polls => get(pollsDataKey);
}

extension PostPolls on Post {
  Polls? get polls => plugins.polls;

  bool get hasPolls => polls != null;
}

/// Preserves unknown future wire values for a read-only web fallback.
@immutable
class PollType {
  const PollType._(this.value);

  static const regular = PollType._('regular');
  static const multiple = PollType._('multiple');
  static const number = PollType._('number');
  static const rankedChoice = PollType._('ranked_choice');

  factory PollType.fromValue(Object? value) => switch (value) {
    'regular' => regular,
    'multiple' => multiple,
    'number' => number,
    'ranked_choice' => rankedChoice,
    final String value when value.isNotEmpty => PollType._(value),
    _ => regular,
  };

  final String value;

  bool get isKnown =>
      this == regular ||
      this == multiple ||
      this == number ||
      this == rankedChoice;

  bool get supportsNativeVoting =>
      this == regular || this == multiple || this == number;

  @override
  bool operator ==(Object other) => other is PollType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PollType($value)';
}

@immutable
class PollStatus {
  const PollStatus._(this.value);

  static const open = PollStatus._('open');
  static const closed = PollStatus._('closed');

  factory PollStatus.fromValue(Object? value) => switch (value) {
    'open' => open,
    'closed' => closed,
    final String value when value.isNotEmpty => PollStatus._(value),
    _ => open,
  };

  final String value;

  bool get isKnown => this == open || this == closed;

  @override
  bool operator ==(Object other) => other is PollStatus && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PollStatus($value)';
}

@immutable
class PollResults {
  const PollResults._(this.value);

  static const always = PollResults._('always');
  static const onVote = PollResults._('on_vote');
  static const onClose = PollResults._('on_close');
  static const staffOnly = PollResults._('staff_only');

  factory PollResults.fromValue(Object? value) => switch (value) {
    'always' => always,
    'on_vote' => onVote,
    'on_close' => onClose,
    'staff_only' => staffOnly,
    final String value when value.isNotEmpty => PollResults._(value),
    _ => always,
  };

  final String value;

  bool get isKnown =>
      this == always || this == onVote || this == onClose || this == staffOnly;

  @override
  bool operator ==(Object other) =>
      other is PollResults && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PollResults($value)';
}

@immutable
class PollChartType {
  const PollChartType._(this.value);

  static const bar = PollChartType._('bar');
  static const pie = PollChartType._('pie');

  factory PollChartType.fromValue(Object? value) => switch (value) {
    'bar' => bar,
    'pie' => pie,
    final String value when value.isNotEmpty => PollChartType._(value),
    _ => bar,
  };

  final String value;

  bool get isKnown => this == bar || this == pie;

  @override
  bool operator ==(Object other) =>
      other is PollChartType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PollChartType($value)';
}

/// Null [votes] means results are confidential, not zero.
@immutable
class PollOption {
  const PollOption({required this.id, required this.html, this.votes})
    : _plainText = null;

  PollOption._parsed({required this.id, required this.html, this.votes})
    : _plainText = _normalizedHtmlText(html);

  static PollOption? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = jsonText(value['id']);
    final cooked = value['html'];
    if (id == null || cooked is! String) return null;
    return PollOption._parsed(
      id: id,
      html: cooked,
      votes: value.containsKey('votes') ? jsonIntOrNull(value['votes']) : null,
    );
  }

  final String id;
  final String html;
  final int? votes;
  final String? _plainText;

  String get plainText => _plainText ?? _normalizedHtmlText(html);

  num? get numericValue {
    return int.tryParse(plainText) ?? double.tryParse(plainText);
  }

  @override
  bool operator ==(Object other) =>
      other is PollOption &&
      other.id == id &&
      other.html == html &&
      other.votes == votes;

  @override
  int get hashCode => Object.hash(id, html, votes);
}

@immutable
class RankedPollSelection {
  const RankedPollSelection({required this.digest, required this.rank});

  final String digest;
  final int rank;

  @override
  bool operator ==(Object other) =>
      other is RankedPollSelection &&
      other.digest == digest &&
      other.rank == rank;

  @override
  int get hashCode => Object.hash(digest, rank);
}

@immutable
class PollSelection {
  const PollSelection({
    this.optionIds = const [],
    this.rankedChoices = const [],
  });

  static const none = PollSelection();

  factory PollSelection.fromJson(Object? value, {required PollType type}) {
    if (value is! List) return none;
    if (type != PollType.rankedChoice) {
      return PollSelection(
        optionIds: List.unmodifiable([
          for (final option in value)
            if (option is String && option.isNotEmpty) option,
        ]),
      );
    }

    return PollSelection(
      rankedChoices: List.unmodifiable([
        for (final choice in value)
          if (choice is Map<String, dynamic>)
            if (jsonText(choice['digest']) case final digest?)
              if (jsonIntOrNull(choice['rank']) case final rank?)
                RankedPollSelection(digest: digest, rank: rank),
      ]),
    );
  }

  final List<String> optionIds;
  final List<RankedPollSelection> rankedChoices;

  bool get hasVote => optionIds.isNotEmpty || rankedChoices.isNotEmpty;

  bool contains(String optionId) => optionIds.contains(optionId);

  @override
  bool operator ==(Object other) =>
      other is PollSelection &&
      listEquals(other.optionIds, optionIds) &&
      listEquals(other.rankedChoices, rankedChoices);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(optionIds), Object.hashAll(rankedChoices));
}

@immutable
class PollRankedCandidate {
  const PollRankedCandidate({required this.digest, required this.html})
    : _plainText = null;

  PollRankedCandidate._parsed({required this.digest, required this.html})
    : _plainText = _normalizedHtmlText(html);

  static PollRankedCandidate? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final digest = jsonText(value['digest']);
    final cooked = value['html'];
    if (digest == null || cooked is! String) return null;
    return PollRankedCandidate._parsed(digest: digest, html: cooked);
  }

  final String digest;
  final String html;
  final String? _plainText;

  String get plainText => _plainText ?? _normalizedHtmlText(html);

  @override
  bool operator ==(Object other) =>
      other is PollRankedCandidate &&
      other.digest == digest &&
      other.html == html;

  @override
  int get hashCode => Object.hash(digest, html);
}

@immutable
class PollRankedRound {
  const PollRankedRound({
    required this.round,
    this.majority,
    this.eliminated = const [],
  });

  static PollRankedRound? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final round = jsonIntOrNull(value['round']);
    if (round == null) return null;
    return PollRankedRound(
      round: round,
      majority: PollRankedCandidate.fromJson(value['majority']),
      eliminated: List.unmodifiable(
        jsonArray(
          value['eliminated'],
        ).map(PollRankedCandidate.fromJson).whereType<PollRankedCandidate>(),
      ),
    );
  }

  final int round;
  final PollRankedCandidate? majority;
  final List<PollRankedCandidate> eliminated;

  @override
  bool operator ==(Object other) =>
      other is PollRankedRound &&
      other.round == round &&
      other.majority == majority &&
      listEquals(other.eliminated, eliminated);

  @override
  int get hashCode => Object.hash(round, majority, Object.hashAll(eliminated));
}

@immutable
class RankedChoiceOutcome {
  const RankedChoiceOutcome({
    this.tied = false,
    this.winner = false,
    this.winningCandidate,
    this.tiedCandidates = const [],
    this.rounds = const [],
  });

  static RankedChoiceOutcome? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return RankedChoiceOutcome(
      tied: value['tied'] == true,
      winner: value['winner'] == true,
      winningCandidate: PollRankedCandidate.fromJson(
        value['winning_candidate'],
      ),
      tiedCandidates: List.unmodifiable(
        jsonArray(
          value['tied_candidates'],
        ).map(PollRankedCandidate.fromJson).whereType<PollRankedCandidate>(),
      ),
      rounds: List.unmodifiable(
        jsonArray(
          value['round_activity'],
        ).map(PollRankedRound.fromJson).whereType<PollRankedRound>(),
      ),
    );
  }

  final bool tied;
  final bool winner;
  final PollRankedCandidate? winningCandidate;
  final List<PollRankedCandidate> tiedCandidates;
  final List<PollRankedRound> rounds;

  @override
  bool operator ==(Object other) =>
      other is RankedChoiceOutcome &&
      other.tied == tied &&
      other.winner == winner &&
      other.winningCandidate == winningCandidate &&
      listEquals(other.tiedCandidates, tiedCandidates) &&
      listEquals(other.rounds, rounds);

  @override
  int get hashCode => Object.hash(
    tied,
    winner,
    winningCandidate,
    Object.hashAll(tiedCandidates),
    Object.hashAll(rounds),
  );
}

@immutable
class PollClosedBy {
  const PollClosedBy({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
  });

  static PollClosedBy? fromJson(Object? value, String siteUrl) {
    if (value is! Map<String, dynamic>) return null;
    final id = jsonIntOrNull(value['id']);
    final username = jsonText(value['username']);
    if (id == null || username == null) return null;
    return PollClosedBy(
      id: id,
      username: username,
      name: jsonText(value['name']),
      avatarUrl: resolveAvatarUrl(jsonText(value['avatar_template']), siteUrl),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is PollClosedBy &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl);
}

@immutable
class Poll {
  const Poll({
    this.id,
    required this.name,
    this.type = PollType.regular,
    this.status = PollStatus.open,
    this.results = PollResults.always,
    this.isPublic = false,
    this.isDynamic = false,
    this.min,
    this.max,
    this.step,
    this.options = const [],
    this.voters = 0,
    this.closeAt,
    this.preloadedVoters,
    this.chartType = PollChartType.bar,
    this.groups = const [],
    this.title,
    this.rankedChoiceOutcome,
    this.closedAt,
    this.closedBy,
    this.selection = PollSelection.none,
  });

  /// Core's maximum site setting and the client parsing ceiling.
  static const int maximumOptions = 100;

  static Poll? fromJson(Object? value, String siteUrl, {Object? selection}) {
    if (value is! Map<String, dynamic>) return null;
    final name = jsonText(value['name']);
    if (name == null) return null;

    final type = PollType.fromValue(value['type']);
    return Poll(
      id: jsonIntOrNull(value['id']),
      name: name,
      type: type,
      status: PollStatus.fromValue(value['status']),
      results: PollResults.fromValue(value['results']),
      isPublic: value['public'] == true,
      isDynamic: value['dynamic'] == true,
      min: jsonIntOrNull(value['min']),
      max: jsonIntOrNull(value['max']),
      step: jsonIntOrNull(value['step']),
      options: List.unmodifiable(
        jsonArray(
          value['options'],
        ).take(maximumOptions).map(PollOption.fromJson).whereType<PollOption>(),
      ),
      voters: jsonInt(value['voters']),
      closeAt: jsonDate(value['close']),
      preloadedVoters: _freezeJson(value['preloaded_voters']),
      chartType: PollChartType.fromValue(value['chart_type']),
      groups: List.unmodifiable(
        (jsonText(value['groups']) ?? '')
            .split(',')
            .map((group) => group.trim())
            .where((group) => group.isNotEmpty),
      ),
      title: value['title'] is String ? value['title'] as String : null,
      rankedChoiceOutcome: RankedChoiceOutcome.fromJson(
        value['ranked_choice_outcome'],
      ),
      closedAt: jsonDate(value['closed_at']),
      closedBy: PollClosedBy.fromJson(value['closed_by'], siteUrl),
      selection: PollSelection.fromJson(selection, type: type),
    );
  }

  final int? id;
  final String name;
  final PollType type;
  final PollStatus status;
  final PollResults results;
  final bool isPublic;
  final bool isDynamic;
  final int? min;
  final int? max;
  final int? step;
  final List<PollOption> options;
  final int voters;
  final DateTime? closeAt;

  final Object? preloadedVoters;

  final PollChartType chartType;
  final List<String> groups;

  final String? title;

  final RankedChoiceOutcome? rankedChoiceOutcome;
  final DateTime? closedAt;
  final PollClosedBy? closedBy;
  final PollSelection selection;

  bool get isOpen => status == PollStatus.open;

  bool get hasVisibleResults => options.any((option) => option.votes != null);

  bool get supportsNativeVoting => type.supportsNativeVoting && status.isKnown;

  List<String> get selectedOptionIds => selection.optionIds;

  Poll withSelection(PollSelection next) => Poll(
    id: id,
    name: name,
    type: type,
    status: status,
    results: results,
    isPublic: isPublic,
    isDynamic: isDynamic,
    min: min,
    max: max,
    step: step,
    options: options,
    voters: voters,
    closeAt: closeAt,
    preloadedVoters: preloadedVoters,
    chartType: chartType,
    groups: groups,
    title: title,
    rankedChoiceOutcome: rankedChoiceOutcome,
    closedAt: closedAt,
    closedBy: closedBy,
    selection: next,
  );

  @override
  bool operator ==(Object other) =>
      other is Poll &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.status == status &&
      other.results == results &&
      other.isPublic == isPublic &&
      other.isDynamic == isDynamic &&
      other.min == min &&
      other.max == max &&
      other.step == step &&
      listEquals(other.options, options) &&
      other.voters == voters &&
      other.closeAt == closeAt &&
      _sameFrozenJson(other.preloadedVoters, preloadedVoters) &&
      other.chartType == chartType &&
      listEquals(other.groups, groups) &&
      other.title == title &&
      other.rankedChoiceOutcome == rankedChoiceOutcome &&
      other.closedAt == closedAt &&
      other.closedBy == closedBy &&
      other.selection == selection;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    type,
    status,
    results,
    isPublic,
    isDynamic,
    min,
    max,
    step,
    Object.hashAll(options),
    voters,
    closeAt,
    _frozenJsonKey(preloadedVoters),
    chartType,
    Object.hashAll(groups),
    title,
    rankedChoiceOutcome,
    closedAt,
    closedBy,
    selection,
  ]);
}

@immutable
class Polls {
  const Polls({this.byName = const {}});

  /// Null means the plugin did not attach a `polls` key. An empty [Polls]
  /// means it did attach one but none of its entries were usable.
  static Polls? fromJson(Map<String, dynamic> json, String siteUrl) {
    if (json['polls'] is! List) return null;
    final votes = json['polls_votes'] is Map<String, dynamic>
        ? json['polls_votes'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final parsed = <String, Poll>{};
    for (final value in json['polls'] as List) {
      if (value is! Map<String, dynamic>) continue;
      final name = jsonText(value['name']);
      if (name == null || parsed.containsKey(name)) continue;
      final poll = Poll.fromJson(value, siteUrl, selection: votes[name]);
      if (poll != null) parsed[name] = poll;
    }
    return Polls(byName: Map.unmodifiable(parsed));
  }

  final Map<String, Poll> byName;

  Poll? operator [](String name) => byName[name];

  List<Poll> get values => List.unmodifiable(byName.values);

  bool get isEmpty => byName.isEmpty;

  Polls withPoll(Poll poll) =>
      Polls(byName: Map.unmodifiable({...byName, poll.name: poll}));

  Polls without(String name) {
    if (!byName.containsKey(name)) return this;
    final next = Map<String, Poll>.of(byName)..remove(name);
    return Polls(byName: Map.unmodifiable(next));
  }

  @override
  bool operator ==(Object other) =>
      other is Polls && mapEquals(other.byName, byName);

  @override
  int get hashCode => Object.hashAllUnordered(
    byName.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

@immutable
class PollVoteResponse {
  const PollVoteResponse({required this.poll, required this.selection});

  final Poll poll;
  final PollSelection selection;
}

Object? _freezeJson(Object? value) => switch (value) {
  final Map<Object?, Object?> map => Map<String, Object?>.unmodifiable({
    for (final entry in map.entries)
      if (entry.key is String) entry.key as String: _freezeJson(entry.value),
  }),
  final List<Object?> list => List<Object?>.unmodifiable(list.map(_freezeJson)),
  final String value => value,
  final num value => value,
  final bool value => value,
  _ => null,
};

bool _sameFrozenJson(Object? a, Object? b) =>
    identical(a, b) || _frozenJsonKey(a) == _frozenJsonKey(b);

String _frozenJsonKey(Object? value) => jsonEncode(value);

final RegExp _htmlWhitespace = RegExp(r'\s+');

String _normalizedHtmlText(String cooked) =>
    (html.parseFragment(cooked).text ?? cooked).trim().replaceAll(
      _htmlWhitespace,
      ' ',
    );
