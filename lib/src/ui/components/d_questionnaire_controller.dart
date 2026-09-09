import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum DQuestionnaireItemStatus { unanswered, answered, skipped }

enum DQuestionnaireShortcutMode { letters, numbers }

enum DQuestionnaireInputType {
  text,
  email,
  phone,
  url,
  number,
  password,
  date,
  dateTime,
  month,
  time,
  week,
  search,
}

enum DQuestionnaireNavigationReason {
  next,
  previous,
  submitError,
  controlled,
  visibilityChanged,
}

typedef DQuestionnaireEnabledPredicate =
    bool Function(DQuestionnaireSnapshot snapshot);
typedef DQuestionnaireValidator =
    FutureOr<String?> Function(
      DQuestionnaireAnswer answer,
      DQuestionnaireSnapshot snapshot,
    );
typedef DQuestionnaireNavigationDelegate =
    FutureOr<bool> Function(
      String fromItemId,
      String toItemId,
      DQuestionnaireNavigationReason reason,
    );

@immutable
class DQuestionnaireChoice<T extends Object> {
  const DQuestionnaireChoice({
    required this.value,
    required this.label,
    this.description,
    this.enabled = true,
    this.semanticLabel,
  });

  final T value;
  final Widget label;
  final Widget? description;
  final bool enabled;
  final String? semanticLabel;
}

@immutable
class DQuestionnaireInputConfiguration {
  const DQuestionnaireInputConfiguration({
    required this.label,
    this.placeholder,
    this.initialValue = '',
    this.enabled = true,
    this.type = DQuestionnaireInputType.text,
  });

  /// A visible or screen-reader accessible name. A placeholder is not a label.
  final String label;
  final String? placeholder;
  final String initialValue;
  final bool enabled;
  final DQuestionnaireInputType type;
}

@immutable
class DQuestionnaireItem {
  const DQuestionnaireItem({
    required this.id,
    required this.title,
    this.description,
    this.choices = const [],
    this.input,
    this.multiple = false,
    this.required = false,
    this.enabledWhen,
    this.validator,
    this.errorMessage,
  }) : assert(id != '');

  final String id;
  final Widget title;
  final Widget? description;
  final List<DQuestionnaireChoice<Object>> choices;
  final DQuestionnaireInputConfiguration? input;
  final bool multiple;
  final bool required;

  /// Disabled items retain their draft but are excluded from navigation,
  /// progress, validation and submitted answers.
  final DQuestionnaireEnabledPredicate? enabledWhen;
  final DQuestionnaireValidator? validator;
  final String? errorMessage;
}

@immutable
class DQuestionnaireAnswer {
  const DQuestionnaireAnswer._({
    required this.status,
    this.values = const [],
    this.freeform,
  });

  const DQuestionnaireAnswer.unanswered()
    : this._(status: DQuestionnaireItemStatus.unanswered);

  const DQuestionnaireAnswer.skipped()
    : this._(status: DQuestionnaireItemStatus.skipped);

  factory DQuestionnaireAnswer.fixed(Iterable<Object> values) {
    final copy = List<Object>.unmodifiable(values);
    return copy.isEmpty
        ? const DQuestionnaireAnswer.unanswered()
        : DQuestionnaireAnswer._(
            status: DQuestionnaireItemStatus.answered,
            values: copy,
          );
  }

  factory DQuestionnaireAnswer.freeform(String value) {
    return value.trim().isEmpty
        ? const DQuestionnaireAnswer.unanswered()
        : DQuestionnaireAnswer._(
            status: DQuestionnaireItemStatus.answered,
            freeform: value,
          );
  }

  final DQuestionnaireItemStatus status;
  final List<Object> values;
  final String? freeform;

  bool get isAnswered => status == DQuestionnaireItemStatus.answered;
  bool get isSkipped => status == DQuestionnaireItemStatus.skipped;
  bool get isEmpty => status == DQuestionnaireItemStatus.unanswered;

  T? valueAs<T extends Object>() {
    if (freeform case final String text when T == String) return text as T;
    if (values case [final value, ...] when value is T) return value;
    return null;
  }

  List<T> valuesAs<T extends Object>() =>
      values.whereType<T>().toList(growable: false);

  Map<String, Object?> toJson({Object? Function(Object value)? encodeValue}) {
    final encode = encodeValue ?? _jsonValue;
    return <String, Object?>{
      'status': status.name,
      if (values.isNotEmpty)
        'values': [for (final value in values) encode(value)],
      if (freeform != null) 'freeform': freeform,
    };
  }

  factory DQuestionnaireAnswer.fromJson(
    Map<String, Object?> json, {
    Object Function(Object? value)? decodeValue,
  }) {
    final decode = decodeValue ?? (Object? value) => value as Object;
    final status = DQuestionnaireItemStatus.values.firstWhere(
      (candidate) => candidate.name == json['status'],
      orElse: () => DQuestionnaireItemStatus.unanswered,
    );
    if (status == DQuestionnaireItemStatus.skipped) {
      return const DQuestionnaireAnswer.skipped();
    }
    final freeform = json['freeform'];
    if (freeform is String && freeform.trim().isNotEmpty) {
      return DQuestionnaireAnswer.freeform(freeform);
    }
    final values = json['values'];
    if (values is List) {
      return DQuestionnaireAnswer.fixed([
        for (final value in values) decode(value),
      ]);
    }
    return const DQuestionnaireAnswer.unanswered();
  }

  static Object? _jsonValue(Object value) => switch (value) {
    String() || num() || bool() => value,
    _ => throw ArgumentError.value(
      value,
      'value',
      'Provide encodeValue for non-JSON questionnaire choices.',
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is DQuestionnaireAnswer &&
      other.status == status &&
      other.freeform == freeform &&
      listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(status, freeform, Object.hashAll(values));
}

@immutable
class DQuestionnaireSavedState {
  DQuestionnaireSavedState({
    required this.currentItemId,
    required Map<String, DQuestionnaireAnswer> answers,
    Iterable<String> visitedItemIds = const [],
  }) : answers = Map.unmodifiable(answers),
       visitedItemIds = Set.unmodifiable(visitedItemIds);

  final String? currentItemId;
  final Map<String, DQuestionnaireAnswer> answers;
  final Set<String> visitedItemIds;

  Map<String, Object?> toJson({Object? Function(Object value)? encodeValue}) =>
      {
        'version': 1,
        'currentItemId': currentItemId,
        'answers': {
          for (final entry in answers.entries)
            entry.key: entry.value.toJson(encodeValue: encodeValue),
        },
        'visitedItemIds': visitedItemIds.toList(growable: false),
      };

  factory DQuestionnaireSavedState.fromJson(
    Map<String, Object?> json, {
    Object Function(Object? value)? decodeValue,
  }) {
    final rawAnswers = json['answers'];
    final answers = <String, DQuestionnaireAnswer>{};
    if (rawAnswers is Map) {
      for (final entry in rawAnswers.entries) {
        if (entry.key is String && entry.value is Map) {
          answers[entry.key as String] = DQuestionnaireAnswer.fromJson(
            Map<String, Object?>.from(entry.value as Map),
            decodeValue: decodeValue,
          );
        }
      }
    }
    final rawVisited = json['visitedItemIds'];
    return DQuestionnaireSavedState(
      currentItemId: json['currentItemId'] as String?,
      answers: answers,
      visitedItemIds: rawVisited is List
          ? rawVisited.whereType<String>()
          : const [],
    );
  }
}

@immutable
class DQuestionnaireProgressState {
  const DQuestionnaireProgressState({
    required this.current,
    required this.total,
    required this.itemId,
  });

  final int current;
  final int total;
  final String? itemId;
  double get fraction => total == 0 ? 0 : current / total;
}

@immutable
class DQuestionnaireSnapshot {
  DQuestionnaireSnapshot({
    required this.currentItemId,
    required Map<String, DQuestionnaireAnswer> answers,
    required Iterable<String> visibleItemIds,
    required Iterable<String> visitedItemIds,
  }) : answers = Map.unmodifiable(answers),
       visibleItemIds = List.unmodifiable(visibleItemIds),
       visitedItemIds = Set.unmodifiable(visitedItemIds);

  final String? currentItemId;
  final Map<String, DQuestionnaireAnswer> answers;
  final List<String> visibleItemIds;
  final Set<String> visitedItemIds;

  DQuestionnaireAnswer answerFor(String itemId) =>
      answers[itemId] ?? const DQuestionnaireAnswer.unanswered();

  T? valueFor<T extends Object>(String itemId) =>
      answerFor(itemId).valueAs<T>();

  List<T> valuesFor<T extends Object>(String itemId) =>
      answerFor(itemId).valuesAs<T>();
}

/// Headless Questionnaire behavior. Persistence and transport stay with the
/// host: use [savedState] to serialize a draft and [submission] for enabled
/// answers only.
class DQuestionnaireController extends ChangeNotifier {
  DQuestionnaireController({
    required List<DQuestionnaireItem> items,
    DQuestionnaireSavedState? initialState,
    String? initialItemId,
    this.navigationDelegate,
  }) : _items = List.unmodifiable(items) {
    _assertUniqueItems(_items);
    final defaults = <String, DQuestionnaireAnswer>{};
    for (final item in _items) {
      final initialText = item.input?.initialValue ?? '';
      if (initialText.trim().isNotEmpty) {
        defaults[item.id] = DQuestionnaireAnswer.freeform(initialText);
      }
    }
    _initialState =
        initialState ??
        DQuestionnaireSavedState(
          currentItemId: initialItemId,
          answers: defaults,
        );
    _answers.addAll(_initialState.answers);
    _visited.addAll(_initialState.visitedItemIds);
    _currentItemId = _initialState.currentItemId ?? initialItemId;
    _normalizeCurrent(markVisited: true);
  }

  List<DQuestionnaireItem> _items;
  late final DQuestionnaireSavedState _initialState;
  final Map<String, DQuestionnaireAnswer> _answers = {};
  final Set<String> _visited = {};
  final Map<String, String> _internalErrors = {};
  final Map<String, String> _externalErrors = {};
  String? _currentItemId;
  int _answerRevision = 0;
  int _validationGeneration = 0;
  bool _validating = false;

  DQuestionnaireNavigationDelegate? navigationDelegate;

  List<DQuestionnaireItem> get items => _items;
  String? get currentItemId => _currentItemId;
  bool get isValidating => _validating;
  Set<String> get visitedItemIds => Set.unmodifiable(_visited);

  DQuestionnaireSnapshot get snapshot => DQuestionnaireSnapshot(
    currentItemId: _currentItemId,
    answers: _answers,
    visibleItemIds: visibleItems.map((item) => item.id),
    visitedItemIds: _visited,
  );

  List<DQuestionnaireItem> get visibleItems {
    final base = DQuestionnaireSnapshot(
      currentItemId: _currentItemId,
      answers: _answers,
      visibleItemIds: const [],
      visitedItemIds: _visited,
    );
    return [
      for (final item in _items)
        if (item.enabledWhen?.call(base) ?? true) item,
    ];
  }

  DQuestionnaireItem? get currentItem {
    final id = _currentItemId;
    if (id == null) return null;
    for (final item in visibleItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  DQuestionnaireAnswer answerFor(String itemId) =>
      _answers[itemId] ?? const DQuestionnaireAnswer.unanswered();

  String? errorFor(String itemId) =>
      _externalErrors[itemId] ?? _internalErrors[itemId];

  DQuestionnaireProgressState get progress {
    final visible = visibleItems;
    final index = visible.indexWhere((item) => item.id == _currentItemId);
    return DQuestionnaireProgressState(
      current: index < 0 ? 0 : index + 1,
      total: visible.length,
      itemId: _currentItemId,
    );
  }

  bool get canGoPrevious => _adjacent(-1) != null;
  bool get canGoNext => _adjacent(1) != null;
  bool get canSkip {
    final item = currentItem;
    return item != null && !item.required;
  }

  /// Reconciles presentation changes without discarding saved answers.
  void updateItems(List<DQuestionnaireItem> items) {
    _assertUniqueItems(items);
    _items = List.unmodifiable(items);
    final changed = _normalizeCurrent(markVisited: true);
    _validationGeneration++;
    if (changed) notifyListeners();
  }

  void setControlledItem(String itemId) {
    if (_currentItemId == itemId || !_isVisible(itemId)) return;
    _currentItemId = itemId;
    _visited.add(itemId);
    _validationGeneration++;
    notifyListeners();
  }

  void setSingle(String itemId, Object value) {
    final item = _item(itemId);
    if (item == null || item.multiple || !_choiceEnabled(item, value)) return;
    _setAnswer(itemId, DQuestionnaireAnswer.fixed([value]));
  }

  void toggle(String itemId, Object value) {
    final item = _item(itemId);
    if (item == null || !item.multiple || !_choiceEnabled(item, value)) return;
    final values = answerFor(itemId).values.toList(growable: true);
    values.contains(value) ? values.remove(value) : values.add(value);
    _setAnswer(itemId, DQuestionnaireAnswer.fixed(values));
  }

  void setFreeform(String itemId, String value) {
    final item = _item(itemId);
    if (item?.input?.enabled != true) return;
    _setAnswer(itemId, DQuestionnaireAnswer.freeform(value));
  }

  void clear(String itemId) =>
      _setAnswer(itemId, const DQuestionnaireAnswer.unanswered());

  Future<bool> skip() async {
    final item = currentItem;
    if (item == null || item.required) return false;
    _setAnswer(item.id, const DQuestionnaireAnswer.skipped());
    final target = _adjacent(1);
    return target == null ||
        await _requestNavigation(
          target.id,
          DQuestionnaireNavigationReason.next,
        );
  }

  Future<bool> next() async {
    final item = currentItem;
    if (item == null || !await validate(item.id)) return false;
    final target = _adjacent(1);
    if (target == null) return false;
    return _requestNavigation(target.id, DQuestionnaireNavigationReason.next);
  }

  Future<bool> previous() async {
    final target = _adjacent(-1);
    if (target == null) return false;
    return _requestNavigation(
      target.id,
      DQuestionnaireNavigationReason.previous,
    );
  }

  Future<bool> goTo(
    String itemId, {
    DQuestionnaireNavigationReason reason =
        DQuestionnaireNavigationReason.controlled,
  }) => _requestNavigation(itemId, reason);

  Future<bool> validate(String itemId) async {
    final item = _item(itemId);
    if (item == null || !_isVisible(itemId)) return true;
    final answer = _effectiveAnswer(item);
    final external = _externalErrors[itemId];
    if (external != null) {
      _internalErrors.remove(itemId);
      notifyListeners();
      return false;
    }
    if (!answer.isAnswered && !(answer.isSkipped && !item.required)) {
      _internalErrors[itemId] =
          item.errorMessage ??
          (item.required
              ? 'Choose an answer to continue.'
              : 'Choose an answer or skip this question.');
      notifyListeners();
      return false;
    }
    final validator = item.validator;
    if (validator == null) {
      if (_internalErrors.remove(itemId) != null) notifyListeners();
      return true;
    }
    final generation = ++_validationGeneration;
    final revision = _answerRevision;
    _validating = true;
    notifyListeners();
    String? error;
    try {
      error = await validator(answer, snapshot);
    } finally {
      if (generation == _validationGeneration && revision == _answerRevision) {
        _validating = false;
      }
    }
    if (generation != _validationGeneration || revision != _answerRevision) {
      return false;
    }
    _validating = false;
    if (error == null) {
      _internalErrors.remove(itemId);
    } else {
      _internalErrors[itemId] = error;
    }
    notifyListeners();
    return error == null;
  }

  Future<DQuestionnaireSnapshot?> validateForSubmission() async {
    for (final item in visibleItems) {
      if (!await validate(item.id)) {
        await _requestNavigation(
          item.id,
          DQuestionnaireNavigationReason.submitError,
        );
        return null;
      }
    }
    return submission;
  }

  DQuestionnaireSnapshot get submission {
    final visible = visibleItems;
    final visibleIds = visible.map((item) => item.id).toSet();
    return DQuestionnaireSnapshot(
      currentItemId: _currentItemId,
      answers: {
        for (final item in visible)
          if (!_effectiveAnswer(item).isEmpty) item.id: _effectiveAnswer(item),
      },
      visibleItemIds: visibleIds,
      visitedItemIds: _visited,
    );
  }

  DQuestionnaireSavedState get savedState => DQuestionnaireSavedState(
    currentItemId: _currentItemId,
    answers: _answers,
    visitedItemIds: _visited,
  );

  void setExternalError(String itemId, String? error) {
    if (error == null) {
      _externalErrors.remove(itemId);
    } else {
      _externalErrors[itemId] = error;
    }
    notifyListeners();
  }

  void reset() {
    _validationGeneration++;
    _validating = false;
    _answers
      ..clear()
      ..addAll(_initialState.answers);
    _visited
      ..clear()
      ..addAll(_initialState.visitedItemIds);
    _internalErrors.clear();
    _externalErrors.clear();
    _currentItemId = _initialState.currentItemId;
    _answerRevision++;
    _normalizeCurrent(markVisited: true);
    notifyListeners();
  }

  void _setAnswer(String itemId, DQuestionnaireAnswer answer) {
    if (answer == answerFor(itemId)) return;
    _answers[itemId] = answer;
    _answerRevision++;
    _validationGeneration++;
    _validating = false;
    _internalErrors.remove(itemId);
    _normalizeCurrent(markVisited: true);
    notifyListeners();
  }

  Future<bool> _requestNavigation(
    String target,
    DQuestionnaireNavigationReason reason,
  ) async {
    if (!_isVisible(target)) return false;
    final from = _currentItemId;
    if (from == target) return true;
    final delegate = navigationDelegate;
    if (delegate != null && from != null) {
      final accepted = await delegate(from, target, reason);
      if (!accepted) return false;
    }
    _currentItemId = target;
    _visited.add(target);
    _validationGeneration++;
    _validating = false;
    notifyListeners();
    return true;
  }

  DQuestionnaireItem? _adjacent(int offset) {
    final visible = visibleItems;
    final index = visible.indexWhere((item) => item.id == _currentItemId);
    final target = index + offset;
    return index < 0 || target < 0 || target >= visible.length
        ? null
        : visible[target];
  }

  DQuestionnaireItem? _item(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool _isVisible(String id) => visibleItems.any((item) => item.id == id);

  bool _choiceEnabled(DQuestionnaireItem item, Object value) =>
      item.choices.any((choice) => choice.value == value && choice.enabled);

  DQuestionnaireAnswer _effectiveAnswer(DQuestionnaireItem item) {
    final answer = answerFor(item.id);
    if (answer.isSkipped) return answer;
    if (answer.freeform != null && item.input?.enabled == true) return answer;
    return DQuestionnaireAnswer.fixed(
      answer.values.where((value) => _choiceEnabled(item, value)),
    );
  }

  bool _normalizeCurrent({required bool markVisited}) {
    final visible = visibleItems;
    final previous = _currentItemId;
    if (visible.isEmpty) {
      _currentItemId = null;
    } else if (!visible.any((item) => item.id == _currentItemId)) {
      final previousIndex = _items.indexWhere((item) => item.id == previous);
      final after = visible.where(
        (item) => _items.indexOf(item) > previousIndex,
      );
      _currentItemId = after.isEmpty ? visible.last.id : after.first.id;
    }
    if (markVisited && _currentItemId != null) _visited.add(_currentItemId!);
    return previous != _currentItemId;
  }

  static void _assertUniqueItems(List<DQuestionnaireItem> items) {
    final ids = <String>{};
    for (final item in items) {
      if (!ids.add(item.id)) {
        throw ArgumentError.value(item.id, 'items', 'Item IDs must be unique.');
      }
    }
  }
}
