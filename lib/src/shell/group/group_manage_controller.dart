import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../../models/group.dart';
import '../../models/group_route.dart';
import 'group_page_types.dart';

typedef GroupManageErrorMapper = String Function(Object error);

@immutable
final class GroupManageSnapshot {
  const GroupManageSnapshot({
    required this.dirty,
    required this.submitting,
    required this.canSubmit,
    this.fieldErrors = const {},
    this.error,
  });

  final bool dirty;
  final bool submitting;
  final bool canSubmit;
  final Map<String, String> fieldErrors;
  final String? error;
}

final class GroupManageController extends ChangeNotifier {
  GroupManageController({
    required this.group,
    this.subsection = GroupRoute.profile,
    this.onSubmit,
    this.errorMapper = _defaultErrorMessage,
  }) {
    void value(String key, Object? value) =>
        _text[key] = TextEditingController(text: value?.toString() ?? '');

    value('name', group.name);
    value('full_name', group.fullName ?? group.displayName);
    value('bio_raw', group.bioRaw);
    value('title', group.title);
    value('flair_icon', group.flairIcon);
    value('flair_bg_color', group.flairBackgroundColor);
    value('flair_color', group.flairColor);
    value(
      'automatic_membership_email_domains',
      group.automaticMembershipEmailDomains,
    );
    value('membership_request_template', group.membershipRequestTemplate);
    value('associated_group_ids', group.associatedGroupIds.join(','));
    value('grant_trust_level', group.grantTrustLevel);
    value('incoming_email', group.incomingEmail);
    value('smtp_server', group.smtpServer);
    value('smtp_port', group.smtpPort);
    value('smtp_ssl_mode', group.smtpSslMode);
    value('email_username', group.emailUsername);
    value('email_password', '');
    value('email_from_alias', group.emailFromAlias);
    value('watching_category_ids', group.watchingCategoryIds.join(','));
    value('tracking_category_ids', group.trackingCategoryIds.join(','));
    value(
      'watching_first_post_category_ids',
      group.watchingFirstPostCategoryIds.join(','),
    );
    value('regular_category_ids', group.regularCategoryIds.join(','));
    value('muted_category_ids', group.mutedCategoryIds.join(','));
    value('watching_tags', group.watchingTags.map((tag) => tag.name).join(','));
    value('tracking_tags', group.trackingTags.map((tag) => tag.name).join(','));
    value(
      'watching_first_post_tags',
      group.watchingFirstPostTags.map((tag) => tag.name).join(','),
    );
    value('regular_tags', group.regularTags.map((tag) => tag.name).join(','));
    value('muted_tags', group.mutedTags.map((tag) => tag.name).join(','));

    _publicExit = group.publicExit;
    _publishReadState = group.publishReadState;
    _smtpEnabled = group.smtpEnabled;
    _allowUnknownSenderReplies = group.allowUnknownSenderTopicReplies;
    _visibility = group.visibilityLevel;
    _membersVisibility = group.membersVisibilityLevel;
    _mentionable = group.mentionableLevel;
    _messageable = group.messageableLevel;
    _defaultNotification = group.defaultNotificationLevel;
    _admission = group.publicAdmission
        ? 'free'
        : group.allowMembershipRequests
        ? 'request'
        : 'closed';

    for (final controller in _text.values) {
      controller.addListener(_textChanged);
    }
    _savedValues = _valuesForSubsection(subsection);
  }

  final Group group;
  final String subsection;
  final GroupManageSubmit? onSubmit;
  final GroupManageErrorMapper errorMapper;
  final Map<String, TextEditingController> _text = {};
  late bool _publicExit;
  late bool _publishReadState;
  late bool _smtpEnabled;
  late bool _allowUnknownSenderReplies;
  late int _visibility;
  late int _membersVisibility;
  late int _mentionable;
  late int _messageable;
  late int _defaultNotification;
  late String _admission;
  late Map<String, Object?> _savedValues;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  bool _submitting = false;
  bool _disposed = false;
  int _revision = 0;
  int _submissionGeneration = 0;

  Map<String, TextEditingController> get textControllers =>
      Map.unmodifiable(_text);
  bool get publicExit => _publicExit;
  bool get publishReadState => _publishReadState;
  bool get smtpEnabled => _smtpEnabled;
  bool get allowUnknownSenderReplies => _allowUnknownSenderReplies;
  int get visibility => _visibility;
  int get membersVisibility => _membersVisibility;
  int get mentionable => _mentionable;
  int get messageable => _messageable;
  int get defaultNotification => _defaultNotification;
  String get admission => _admission;
  GroupManageSnapshot get snapshot {
    final dirty = !_mapsEqual(_valuesForSubsection(subsection), _savedValues);
    return GroupManageSnapshot(
      dirty: dirty,
      submitting: _submitting,
      canSubmit: onSubmit != null && dirty && !_submitting,
      fieldErrors: Map.unmodifiable(_fieldErrors),
      error: _error,
    );
  }

  TextEditingController textController(String key) => _text[key]!;

  void setAdmission(String value) => _set(() => _admission = value);
  void setPublicExit(bool value) => _set(() => _publicExit = value);
  void setPublishReadState(bool value) => _set(() => _publishReadState = value);
  void setSmtpEnabled(bool value) => _set(() => _smtpEnabled = value);
  void setAllowUnknownSenderReplies(bool value) =>
      _set(() => _allowUnknownSenderReplies = value);
  void setVisibility(int value) => _set(() => _visibility = value);
  void setMembersVisibility(int value) =>
      _set(() => _membersVisibility = value);
  void setMentionable(int value) => _set(() => _mentionable = value);
  void setMessageable(int value) => _set(() => _messageable = value);
  void setDefaultNotification(int value) =>
      _set(() => _defaultNotification = value);

  void _set(VoidCallback update) {
    update();
    _changed();
  }

  void _textChanged() => _changed();

  void _changed() {
    _revision += 1;
    _error = null;
    if (_fieldErrors.isNotEmpty) {
      _fieldErrors = _validationErrors();
    }
    notifyListeners();
  }

  GroupManageUpdate buildUpdate([String? targetSubsection]) =>
      GroupManageUpdate(
        subsection: targetSubsection ?? subsection,
        values: _valuesForSubsection(targetSubsection ?? subsection),
      );

  bool validate() {
    _fieldErrors = _validationErrors();
    notifyListeners();
    return _fieldErrors.isEmpty;
  }

  Future<bool> submit() async {
    final submit = onSubmit;
    if (submit == null || _submitting) return false;

    final errors = _validationErrors();
    if (errors.isNotEmpty) {
      _fieldErrors = errors;
      notifyListeners();
      return false;
    }

    final update = buildUpdate();
    final submittedRevision = _revision;
    final generation = ++_submissionGeneration;
    _fieldErrors = const {};
    _error = null;
    _submitting = true;
    notifyListeners();

    try {
      final saved = await submit(update);
      if (!_isCurrent(generation)) return false;
      if (saved) {
        _savedValues = update.values;
      } else if (_revision == submittedRevision) {
        _error = _saveFailureMessage;
      }
      return saved;
    } catch (error) {
      if (_isCurrent(generation) && _revision == submittedRevision) {
        _error = errorMapper(error);
      }
      return false;
    } finally {
      if (_isCurrent(generation)) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _submissionGeneration;

  Map<String, String> _validationErrors() => switch (subsection) {
    GroupRoute.profile when _value('name').isEmpty => const {
      'name': 'Enter a group name.',
    },
    _ => const {},
  };

  Map<String, Object?> _valuesForSubsection(String subsection) =>
      switch (subsection) {
        GroupRoute.profile => {
          'name': _value('name'),
          'full_name': _value('full_name'),
          'bio_raw': _value('bio_raw'),
          'title': _value('title'),
          'flair_icon': _value('flair_icon'),
          'flair_bg_color': _value('flair_bg_color'),
          'flair_color': _value('flair_color'),
        },
        GroupRoute.membership => {
          'public_admission': _admission == 'free',
          'allow_membership_requests': _admission == 'request',
          'public_exit': _publicExit,
          'visibility_level': _visibility,
          'members_visibility_level': _membersVisibility,
          'membership_request_template': _value('membership_request_template'),
          'automatic_membership_email_domains': _value(
            'automatic_membership_email_domains',
          ),
          'associated_group_ids': _integerList('associated_group_ids'),
          'grant_trust_level': _nullableInt('grant_trust_level'),
        },
        GroupRoute.interaction => {
          'mentionable_level': _mentionable,
          'messageable_level': _messageable,
          'publish_read_state': _publishReadState,
          'default_notification_level': _defaultNotification,
          'incoming_email': _value('incoming_email'),
        },
        GroupRoute.email => {
          'smtp_enabled': _smtpEnabled,
          'smtp_server': _value('smtp_server'),
          'smtp_port': _nullableInt('smtp_port'),
          'smtp_ssl_mode': _nullableInt('smtp_ssl_mode'),
          'email_username': _value('email_username'),
          if (_value('email_password').isNotEmpty)
            'email_password': _value('email_password'),
          'email_from_alias': _value('email_from_alias'),
          'allow_unknown_sender_topic_replies': _allowUnknownSenderReplies,
        },
        GroupRoute.categories => {
          for (final key in groupCategoryKeys) key: _integerList(key),
        },
        GroupRoute.tags => {
          for (final key in groupTagKeys) key: _stringList(key),
        },
        _ => const <String, Object?>{},
      };

  String _value(String key) => textController(key).text.trim();
  int? _nullableInt(String key) => int.tryParse(_value(key));

  List<int> _integerList(String key) => [
    for (final value in _value(key).split(','))
      if (int.tryParse(value.trim()) case final number? when number > 0) number,
  ];

  List<String> _stringList(String key) => [
    for (final value in _value(key).split(','))
      if (value.trim().isNotEmpty) value.trim(),
  ];

  @override
  void dispose() {
    _disposed = true;
    _submissionGeneration += 1;
    for (final controller in _text.values) {
      controller.removeListener(_textChanged);
      controller.dispose();
    }
    super.dispose();
  }
}

String _defaultErrorMessage(Object error) => _saveFailureMessage;

const _saveFailureMessage = "Couldn't save that group change.";

bool _mapsEqual(Map<String, Object?> first, Map<String, Object?> second) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (!second.containsKey(entry.key) ||
        !_valuesEqual(entry.value, second[entry.key])) {
      return false;
    }
  }
  return true;
}

bool _valuesEqual(Object? first, Object? second) {
  if (first is List<Object?> && second is List<Object?>) {
    return listEquals(first, second);
  }
  return first == second;
}

const groupCategoryKeys = [
  'watching_category_ids',
  'tracking_category_ids',
  'watching_first_post_category_ids',
  'regular_category_ids',
  'muted_category_ids',
];

const groupTagKeys = [
  'watching_tags',
  'tracking_tags',
  'watching_first_post_tags',
  'regular_tags',
  'muted_tags',
];
