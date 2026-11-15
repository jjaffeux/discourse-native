import 'json.dart';

/// What the review queue's `status` parameter accepts, by wire name.
enum ReviewStatusFilter {
  pending,
  reviewed,
  approved,
  rejected,
  ignored,
  deleted,
  all,
}

/// The score floor a queue is read at. [any] sends nothing, which leaves the
/// site's own default visibility in force.
enum ReviewPriorityFilter { any, low, medium, high }

enum ReviewSortOrder {
  score('score'),
  scoreAscending('score_asc'),
  newest('created_at'),
  oldest('created_at_asc');

  const ReviewSortOrder(this.wire);
  final String wire;
}

/// One reading of the queue. Equal filters name the same server list, so a
/// response is only ever applied to the filters that asked for it.
final class ReviewFilters {
  const ReviewFilters({
    this.status = ReviewStatusFilter.pending,
    this.type,
    this.priority = ReviewPriorityFilter.any,
    this.categoryId,
    this.username = '',
    this.sortOrder = ReviewSortOrder.score,
  });

  final ReviewStatusFilter status;

  /// A reviewable class name as the site lists it, such as
  /// `ReviewableFlaggedPost`; null for every type.
  final String? type;
  final ReviewPriorityFilter priority;
  final int? categoryId;
  final String username;
  final ReviewSortOrder sortOrder;

  ReviewFilters copyWith({
    ReviewStatusFilter? status,
    String? type,
    bool clearType = false,
    ReviewPriorityFilter? priority,
    int? categoryId,
    bool clearCategory = false,
    String? username,
    ReviewSortOrder? sortOrder,
  }) => ReviewFilters(
    status: status ?? this.status,
    type: clearType ? null : type ?? this.type,
    priority: priority ?? this.priority,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    username: username ?? this.username,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, String> query({int offset = 0}) => {
    'status': status.name,
    if (type case final type? when type.isNotEmpty) 'type': type,
    if (priority != ReviewPriorityFilter.any) 'priority': priority.name,
    if (categoryId case final id? when id > 0) 'category_id': '$id',
    if (username.trim().isNotEmpty) 'username': username.trim(),
    if (sortOrder != ReviewSortOrder.score) 'sort_order': sortOrder.wire,
    if (offset > 0) 'offset': '$offset',
  };

  @override
  bool operator ==(Object other) =>
      other is ReviewFilters &&
      other.status == status &&
      other.type == type &&
      other.priority == priority &&
      other.categoryId == categoryId &&
      other.username.trim() == username.trim() &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(
    status,
    type,
    priority,
    categoryId,
    username.trim(),
    sortOrder,
  );
}

/// The shapes this client draws. Every other class name, including those a
/// plugin registers, is [other] and gets the generic row.
enum ReviewableKind {
  flaggedPost,
  queuedPost,
  user,
  other;

  static ReviewableKind fromType(String type) => switch (type) {
    'ReviewableFlaggedPost' => flaggedPost,
    'ReviewableQueuedPost' => queuedPost,
    'ReviewableUser' => user,
    _ => other,
  };
}

enum ReviewableStatus {
  pending,
  approved,
  rejected,
  ignored,
  deleted,
  unknown;

  static ReviewableStatus fromWire(Object? value) => switch (value) {
    0 => pending,
    1 => approved,
    2 => rejected,
    3 => ignored,
    4 => deleted,
    _ => unknown,
  };
}

enum ReviewableScoreStatus {
  pending,
  agreed,
  disagreed,
  ignored,
  unknown;

  static ReviewableScoreStatus fromWire(Object? value) => switch (value) {
    0 => pending,
    1 => agreed,
    2 => disagreed,
    3 => ignored,
    _ => unknown,
  };
}

final class ReviewablePerson {
  const ReviewablePerson({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
  });

  static ReviewablePerson? tryParse(Object? value) {
    final json = jsonObject(value);
    final username = jsonText(json['username']);
    if (username == null) return null;
    return ReviewablePerson(
      id: jsonInt(json['id']),
      username: username,
      name: jsonText(json['name']),
      avatarTemplate: jsonText(json['avatar_template']),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
}

/// One reason an item is in the queue: a flag, or an automatic rule.
final class ReviewableScore {
  const ReviewableScore({
    required this.id,
    required this.title,
    this.type = '',
    this.status = ReviewableScoreStatus.unknown,
    this.user,
    this.reasonHtml,
    this.createdAt,
  });

  factory ReviewableScore.fromJson(
    Map<String, dynamic> json, {
    Map<int, ReviewablePerson> users = const {},
    Map<int, Map<String, dynamic>> scoreTypes = const {},
  }) {
    final embedded = jsonObject(json['score_type']);
    final scoreType = embedded.isNotEmpty
        ? embedded
        : scoreTypes[jsonIntOrNull(json['score_type_id'])] ?? const {};
    return ReviewableScore(
      id: jsonInt(json['id']),
      title: jsonText(scoreType['title']) ?? '',
      type: jsonText(scoreType['type']) ?? '',
      status: ReviewableScoreStatus.fromWire(json['status']),
      user:
          ReviewablePerson.tryParse(json['user']) ??
          users[jsonIntOrNull(json['user_id'])],
      reasonHtml: jsonText(json['reason']),
      createdAt: jsonDate(json['created_at']),
    );
  }

  final int id;

  /// The site's own wording for the flag type; empty when it named none.
  final String title;
  final String type;
  final ReviewableScoreStatus status;
  final ReviewablePerson? user;

  /// Server-cooked explanation of an automatic rule.
  final String? reasonHtml;
  final DateTime? createdAt;
}

/// How this client carries out one server-provided action.
enum ReviewableActionRoute {
  /// Sent as soon as it is pressed.
  perform,

  /// Sent after the site's own confirmation question.
  confirm,

  /// Removes content or penalises an account, so it is confirmed even when
  /// the site attached no question.
  confirmDestructive,

  /// Needs input this client does not collect; the site's page performs it.
  browser,
}

final class ReviewableAction {
  const ReviewableAction({
    required this.id,
    required this.serverAction,
    required this.label,
    this.description,
    this.icon,
    this.buttonClass,
    this.confirmMessage,
    this.confirmDestructive = false,
    this.clientAction,
    this.requiresRejectReason = false,
    this.requiresClassification = false,
    this.completedMessage,
  });

  /// [classifies] says whether the site offers classification choices; the
  /// web client only asks for one when it does, and the site accepts the
  /// action without one otherwise.
  static ReviewableAction? tryParse(
    Map<String, dynamic> json, {
    bool classifies = true,
  }) {
    final id = jsonText(json['id']);
    if (id == null) return null;
    final separator = id.indexOf('-');
    final serverAction =
        jsonText(json['server_action']) ??
        jsonText(json['action_name']) ??
        (separator < 0 ? id : id.substring(separator + 1));
    // The perform route only matches this alphabet; anything else could not
    // be sent and must not be offered.
    if (!_serverActionPattern.hasMatch(serverAction)) return null;
    return ReviewableAction(
      id: id,
      serverAction: serverAction,
      label: jsonText(json['label']) ?? serverAction,
      description: jsonText(json['description']),
      icon: jsonText(json['icon']),
      buttonClass: jsonText(json['button_class']),
      confirmMessage: jsonText(json['confirm_message']),
      confirmDestructive: json['confirm_destructive'] == true,
      clientAction: jsonText(json['client_action']),
      requiresRejectReason: json['require_reject_reason'] == true,
      requiresClassification:
          classifies && json['dsa_classification_required'] == true,
      completedMessage: jsonText(json['completed_message']),
    );
  }

  static final _serverActionPattern = RegExp(r'^[a-z_]{1,100}$');
  static final _destructivePattern = RegExp(
    r'delete|suspend|silence|block|scrub',
  );

  /// Unique within a response: the reviewable's id, a dash, the action name.
  final String id;

  /// The name the perform endpoint takes.
  final String serverAction;
  final String label;
  final String? description;
  final String? icon;
  final String? buttonClass;
  final String? confirmMessage;
  final bool confirmDestructive;

  /// Names a web-client flow (`edit`, `suspend`, `silence`, `scrub`) that
  /// gathers input before anything is sent.
  final String? clientAction;
  final bool requiresRejectReason;

  /// The site asks for a moderation classification with this action.
  final bool requiresClassification;
  final String? completedMessage;

  bool get isDestructive =>
      confirmDestructive ||
      buttonClass?.contains('danger') == true ||
      _destructivePattern.hasMatch(serverAction);

  ReviewableActionRoute get route {
    if (clientAction != null ||
        requiresRejectReason ||
        requiresClassification ||
        serverAction == 'revise_and_reject_post') {
      return ReviewableActionRoute.browser;
    }
    if (isDestructive) return ReviewableActionRoute.confirmDestructive;
    if (confirmMessage != null) return ReviewableActionRoute.confirm;
    return ReviewableActionRoute.perform;
  }
}

/// A group of related actions the web client draws as one button or menu.
final class ReviewableActionBundle {
  ReviewableActionBundle({
    required this.id,
    this.label,
    this.icon,
    this.secondary = false,
    List<ReviewableAction> actions = const [],
  }) : actions = List.unmodifiable(actions);

  factory ReviewableActionBundle.fromJson(
    Map<String, dynamic> json, {
    Map<String, ReviewableAction> actions = const {},
    bool classifies = true,
  }) => ReviewableActionBundle(
    id: jsonString(json['id']),
    label: jsonText(json['label']),
    icon: jsonText(json['icon']),
    secondary: json['secondary'] == true,
    actions: [
      for (final action in jsonObjects(json['actions']))
        ?ReviewableAction.tryParse(action, classifies: classifies),
      for (final id in jsonArray(json['action_ids'])) ?actions[id],
    ],
  );

  final String id;
  final String? label;
  final String? icon;
  final bool secondary;
  final List<ReviewableAction> actions;
}

final class Reviewable {
  Reviewable({
    required this.id,
    required this.type,
    this.status = ReviewableStatus.unknown,
    this.version = 0,
    this.score = 0,
    this.createdAt,
    this.topicId,
    this.topicTitle,
    this.targetUrl,
    this.categoryId,
    this.cooked,
    this.raw,
    this.title,
    this.targetCreatedBy,
    this.createdBy,
    this.accountUsername,
    this.accountName,
    this.accountEmail,
    this.rejectReason,
    this.targetDeleted = false,
    List<ReviewableScore> scores = const [],
    List<ReviewableActionBundle> bundles = const [],
  }) : scores = List.unmodifiable(scores),
       bundles = List.unmodifiable(bundles);

  /// Reads one row against the records its response side-loads beside it.
  /// Answers null for a row with no positive id, which nothing could act on.
  static Reviewable? tryParse(
    Map<String, dynamic> json,
    ReviewableSideloads sideloads,
  ) {
    final id = jsonInt(json['id']);
    if (id <= 0) return null;
    final payload = jsonObject(json['payload']);
    final topicId = jsonIntOrNull(json['topic_id']);
    final topic = sideloads.topics[topicId] ?? const <String, dynamic>{};
    final topicTitle = jsonTitle(topic['title'], topic['fancy_title']);
    final queuedTitle = jsonTitle(payload['title'], json['fancy_title']);
    final version = jsonInt(json['version']);
    return Reviewable(
      id: id,
      type: jsonString(json['type']),
      status: ReviewableStatus.fromWire(json['status']),
      version: version < 0 ? 0 : version,
      score: switch (json['score']) {
        final num score when score.isFinite => score.toDouble(),
        _ => 0,
      },
      createdAt: jsonDate(json['created_at']),
      topicId: topicId != null && topicId > 0 ? topicId : null,
      topicTitle: topicTitle.isEmpty ? null : topicTitle,
      targetUrl: jsonText(json['target_url']) ?? jsonText(json['topic_url']),
      categoryId: jsonIntOrNull(json['category_id']),
      cooked: jsonText(json['cooked']),
      raw: jsonText(json['raw']) ?? jsonText(payload['raw']),
      title: queuedTitle.isEmpty ? null : queuedTitle,
      targetCreatedBy:
          ReviewablePerson.tryParse(json['target_created_by']) ??
          sideloads.users[jsonIntOrNull(json['target_created_by_id'])],
      createdBy:
          ReviewablePerson.tryParse(json['created_by']) ??
          sideloads.users[jsonIntOrNull(json['created_by_id'])],
      accountUsername:
          jsonText(payload['username']) ?? jsonText(json['username']),
      accountName: jsonText(payload['name']),
      accountEmail: jsonText(payload['email']) ?? jsonText(json['email']),
      rejectReason: jsonText(json['reject_reason']),
      targetDeleted:
          json['blank_post'] == true ||
          json['deleted_at'] != null ||
          json['target_deleted_at'] != null,
      scores: [
        for (final score in jsonObjects(json['reviewable_scores']))
          ReviewableScore.fromJson(
            score,
            users: sideloads.users,
            scoreTypes: sideloads.scoreTypes,
          ),
        for (final scoreId in jsonArray(json['reviewable_score_ids']))
          ?sideloads.scores[jsonIntOrNull(scoreId)],
      ],
      bundles: [
        for (final bundle in jsonObjects(json['bundled_actions']))
          ReviewableActionBundle.fromJson(
            bundle,
            actions: sideloads.actions,
            classifies: sideloads.classifies,
          ),
        for (final bundleId in jsonArray(json['bundled_action_ids']))
          ?sideloads.bundles[bundleId],
      ],
    );
  }

  final int id;

  /// The site's class name, kept for the generic row and the type filter.
  final String type;
  final ReviewableStatus status;

  /// The optimistic lock every perform must echo back.
  final int version;
  final double score;
  final DateTime? createdAt;
  final int? topicId;
  final String? topicTitle;
  final String? targetUrl;
  final int? categoryId;
  final String? cooked;
  final String? raw;

  /// A queued new topic's proposed title.
  final String? title;

  /// Who wrote the content under review, or the account under review.
  final ReviewablePerson? targetCreatedBy;

  /// Who or what put it in the queue.
  final ReviewablePerson? createdBy;
  final String? accountUsername;
  final String? accountName;
  final String? accountEmail;
  final String? rejectReason;
  final bool targetDeleted;
  final List<ReviewableScore> scores;
  final List<ReviewableActionBundle> bundles;

  ReviewableKind get kind => ReviewableKind.fromType(type);

  Iterable<ReviewableAction> get actions =>
      bundles.expand((bundle) => bundle.actions);

  /// How [action] is carried out on this item. A plugin's reviewable can
  /// attach its own input dialog to any action on the web client, and the
  /// payload does not say which, so every action on a type this client does
  /// not know is left to the site.
  ReviewableActionRoute routeFor(ReviewableAction action) =>
      kind == ReviewableKind.other
      ? ReviewableActionRoute.browser
      : action.route;

  /// The reviewable with only its lock and state moved on, as a perform
  /// result reports. A [settled] item offers nothing further until the site
  /// is asked again.
  Reviewable withOutcome({
    ReviewableStatus? status,
    int? version,
    bool settled = false,
  }) => Reviewable(
    id: id,
    type: type,
    status: status ?? this.status,
    version: version ?? this.version,
    score: score,
    createdAt: createdAt,
    topicId: topicId,
    topicTitle: topicTitle,
    targetUrl: targetUrl,
    categoryId: categoryId,
    cooked: cooked,
    raw: raw,
    title: title,
    targetCreatedBy: targetCreatedBy,
    createdBy: createdBy,
    accountUsername: accountUsername,
    accountName: accountName,
    accountEmail: accountEmail,
    rejectReason: rejectReason,
    targetDeleted: targetDeleted,
    scores: scores,
    bundles: settled || (status ?? this.status) != ReviewableStatus.pending
        ? const []
        : bundles,
  );
}

/// The records a review response carries beside its rows, keyed by id.
final class ReviewableSideloads {
  ReviewableSideloads._({
    required this.users,
    required this.topics,
    required this.scoreTypes,
    required this.scores,
    required this.actions,
    required this.bundles,
    required this.classifies,
  });

  factory ReviewableSideloads.fromJson(Map<String, dynamic> json) {
    // The same account can be listed more than once, by different
    // serializers; every copy carries the fields read here.
    final users = <int, ReviewablePerson>{};
    for (final user in jsonObjects(json['users'])) {
      final person = ReviewablePerson.tryParse(user);
      if (person != null) users[person.id] = person;
    }
    final scoreTypes = {
      for (final key in const ['reviewable_score_types', 'score_types'])
        for (final type in jsonObjects(json[key])) jsonInt(type['id']): type,
    };
    final classifies = jsonArray(
      jsonObject(
        jsonObject(json['extras'])['dsa_classification'],
      )['community_rules'],
    ).isNotEmpty;
    final actions = <String, ReviewableAction>{};
    for (final action in jsonObjects(json['actions'])) {
      final parsed = ReviewableAction.tryParse(action, classifies: classifies);
      if (parsed != null) actions[parsed.id] = parsed;
    }
    return ReviewableSideloads._(
      users: users,
      topics: {
        for (final topic in jsonObjects(json['topics']))
          jsonInt(topic['id']): topic,
      },
      scoreTypes: scoreTypes,
      scores: {
        for (final score in jsonObjects(json['reviewable_scores']))
          jsonInt(score['id']): ReviewableScore.fromJson(
            score,
            users: users,
            scoreTypes: scoreTypes,
          ),
      },
      actions: actions,
      bundles: {
        for (final bundle in jsonObjects(json['bundled_actions']))
          bundle['id']: ReviewableActionBundle.fromJson(
            bundle,
            actions: actions,
            classifies: classifies,
          ),
      },
      classifies: classifies,
    );
  }

  final Map<int, ReviewablePerson> users;
  final Map<int, Map<String, dynamic>> topics;
  final Map<int, Map<String, dynamic>> scoreTypes;
  final Map<int, ReviewableScore> scores;
  final Map<String, ReviewableAction> actions;
  final Map<Object?, ReviewableActionBundle> bundles;

  /// Whether the site has moderation classifications to choose from.
  final bool classifies;
}

/// One page of `GET /review.json`.
final class ReviewablePage {
  ReviewablePage({
    List<Reviewable> items = const [],
    this.total = 0,
    this.nextOffset,
    List<String> types = const [],
    this.unseenCount,
  }) : items = List.unmodifiable(items),
       types = List.unmodifiable(types);

  factory ReviewablePage.fromJson(Map<String, dynamic> json, {int offset = 0}) {
    final sideloads = ReviewableSideloads.fromJson(json);
    final meta = jsonObject(json['meta']);
    final rows = jsonObjects(json['reviewables']).toList();
    final more = jsonText(meta['load_more_reviewables']);
    final named = more == null ? null : _offsetIn(more);
    final total = jsonInt(meta['total_rows_reviewables']);
    return ReviewablePage(
      items: [for (final row in rows) ?Reviewable.tryParse(row, sideloads)],
      total: total < 0 ? 0 : total,
      // A next page must move forward, or paging would ask for the same rows
      // without end.
      nextOffset: more == null || rows.isEmpty
          ? null
          : named != null && named > offset
          ? named
          : offset + rows.length,
      types: [
        for (final type in jsonArray(meta['reviewable_types']))
          if (type is String && type.isNotEmpty) type,
      ],
      unseenCount: _count(meta['unseen_reviewable_count']),
    );
  }

  final List<Reviewable> items;
  final int total;

  /// Where the next page starts; null when this was the last one.
  final int? nextOffset;

  /// Every reviewable class the site can filter by, plugins' included.
  final List<String> types;

  /// The account's unseen total as of this read, when the site sent one.
  final int? unseenCount;
}

/// The `offset` a next-page path names. Reading a query decodes it, which
/// throws on a malformed escape.
int? _offsetIn(String path) {
  try {
    return int.tryParse(Uri.parse(path).queryParameters['offset'] ?? '');
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

int? _count(Object? value) {
  final count = jsonIntOrNull(value);
  return count == null || count < 0 ? null : count;
}

/// `GET /review/<id>.json`: one row under `reviewable`, with the same
/// side-loaded records as the list.
Reviewable? reviewableFromDetailJson(Map<String, dynamic> json) =>
    Reviewable.tryParse(
      jsonObject(json['reviewable']),
      ReviewableSideloads.fromJson(json),
    );

/// What the site reports after an action was performed.
final class ReviewablePerformResult {
  ReviewablePerformResult({
    this.success = false,
    this.version,
    Set<int> removedIds = const {},
    Map<int, ReviewableStatus> statuses = const {},
    this.unseenCount,
  }) : removedIds = Set.unmodifiable(removedIds),
       statuses = Map.unmodifiable(statuses);

  factory ReviewablePerformResult.fromJson(Map<String, dynamic> json) {
    final result = jsonObject(json['reviewable_perform_result']);
    return ReviewablePerformResult(
      success: result['success'] == true,
      version: jsonIntOrNull(result['version']),
      removedIds: {
        for (final id in jsonArray(result['remove_reviewable_ids']))
          if (jsonIntOrNull(id) case final id? when id > 0) id,
      },
      statuses: {
        for (final entry in jsonObject(result['reviewable_updates']).entries)
          if (int.tryParse(entry.key) case final id? when id > 0)
            id: ReviewableStatus.fromWire(jsonObject(entry.value)['status']),
      },
      unseenCount: _count(result['unseen_reviewable_count']),
    );
  }

  final bool success;

  /// The performed item's new lock.
  final int? version;

  /// Items that no longer belong in a pending list.
  final Set<int> removedIds;

  /// Other items the action also settled, and what they became.
  final Map<int, ReviewableStatus> statuses;
  final int? unseenCount;
}
