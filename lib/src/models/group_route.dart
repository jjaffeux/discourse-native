import 'package:flutter/foundation.dart';

@immutable
final class GroupRoute {
  const GroupRoute._({
    this.groupName,
    this.section,
    this.subsection,
    this.pluginOwner,
  });

  const GroupRoute.directory() : this._();

  factory GroupRoute.detail(
    String groupName, {
    String section = members,
    String? subsection,
  }) {
    _validateGroupName(groupName);
    if (!coreSections.contains(section)) {
      throw ArgumentError.value(section, 'section', 'Unknown group section.');
    }
    if (!_validCoreSubsection(section, subsection)) {
      throw ArgumentError.value(
        subsection,
        'subsection',
        'Unknown group subsection.',
      );
    }
    return GroupRoute._(
      groupName: groupName,
      section: section,
      subsection: subsection,
    );
  }

  factory GroupRoute.plugin({
    required String groupName,
    required String owner,
    required String section,
    String? subsection,
  }) {
    _validateGroupName(groupName);
    if (!_isSafeToken(owner) || !_isSafeToken(section)) {
      throw ArgumentError('Plugin group route names must be safe tokens.');
    }
    if (subsection != null && !_isSafeSegment(subsection)) {
      throw ArgumentError.value(subsection, 'subsection');
    }
    return GroupRoute._(
      groupName: groupName,
      section: section,
      subsection: subsection,
      pluginOwner: owner,
    );
  }

  static const String members = 'members';
  static const String activity = 'activity';
  static const String requests = 'requests';
  static const String messages = 'messages';
  static const String manage = 'manage';
  static const String permissions = 'permissions';

  static const String posts = 'posts';
  static const String topics = 'topics';
  static const String mentions = 'mentions';
  static const String inbox = 'inbox';
  static const String archive = 'archive';
  static const String profile = 'profile';
  static const String membership = 'membership';
  static const String interaction = 'interaction';
  static const String email = 'email';
  static const String categories = 'categories';
  static const String tags = 'tags';
  static const String logs = 'logs';

  static const Set<String> coreSections = {
    members,
    activity,
    requests,
    messages,
    manage,
    permissions,
  };

  static const Set<String> activitySubsections = {posts, topics, mentions};
  static const Set<String> messageSubsections = {inbox, archive};
  static const Set<String> manageSubsections = {
    profile,
    membership,
    interaction,
    email,
    categories,
    tags,
    logs,
  };

  static const int maximumUrlLength = 2048;
  static const int maximumGroupNameLength = 255;

  final String? groupName;
  final String? section;
  final String? subsection;

  final String? pluginOwner;

  bool get isDirectory => groupName == null;
  bool get isDetail => groupName != null;
  bool get isPlugin => pluginOwner != null;

  String get id {
    if (isDirectory) return 'groups';
    final segments = <String>[
      'group',
      Uri.encodeComponent(groupName!),
      pluginOwner == null ? 'core' : Uri.encodeComponent(pluginOwner!),
      Uri.encodeComponent(section!),
      if (subsection != null) Uri.encodeComponent(subsection!),
    ];
    return segments.join('-');
  }

  String get path {
    if (isDirectory) return '/g';
    final segments = <String>['g', groupName!];
    if (section != members || subsection != null) segments.add(section!);
    if (subsection != null) segments.add(subsection!);
    return Uri(pathSegments: segments).path;
  }

  String? topicFeedPath(String? username) {
    if (isDirectory || isPlugin) return null;
    final encodedGroup = Uri.encodeComponent(groupName!);
    if (section == activity && subsection == topics) {
      return '/topics/groups/$encodedGroup.json';
    }
    if (section == messages && username != null) {
      final archiveSuffix = subsection == archive ? '/archive' : '';
      return '/topics/private-messages-group/'
          '${Uri.encodeComponent(username)}/$encodedGroup$archiveSuffix.json';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    if (groupName != null) 'group_name': groupName,
    if (section != null) 'section': section,
    if (subsection != null) 'subsection': subsection,
    if (pluginOwner != null) 'plugin_owner': pluginOwner,
  };

  factory GroupRoute.fromJson(Map<String, dynamic> json) {
    final groupName = json['group_name'];
    if (groupName == null) {
      if (json['section'] != null ||
          json['subsection'] != null ||
          json['plugin_owner'] != null) {
        throw const FormatException('Invalid group directory route');
      }
      return const GroupRoute.directory();
    }
    if (groupName is! String) {
      throw const FormatException('Invalid group route name');
    }
    final section = json['section'];
    final subsection = json['subsection'];
    final owner = json['plugin_owner'];
    if (section is! String ||
        (subsection != null && subsection is! String) ||
        (owner != null && owner is! String)) {
      throw const FormatException('Invalid group route');
    }
    try {
      if (owner is String) {
        return GroupRoute.plugin(
          groupName: groupName,
          owner: owner,
          section: section,
          subsection: subsection as String?,
        );
      }
      return GroupRoute.detail(
        groupName,
        section: section,
        subsection: subsection as String?,
      );
    } on ArgumentError {
      throw const FormatException('Invalid group route');
    }
  }

  static GroupRoute? parse(String url) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;
    final segments = [...uri.pathSegments];
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.length == 1 && segments.single == 'g') {
      return const GroupRoute.directory();
    }
    if (segments.length < 2 || segments.length > 4 || segments.first != 'g') {
      return null;
    }
    final groupName = segments[1];
    if (groupName == 'custom' && segments.length > 2) return null;
    final section = segments.length >= 3 ? segments[2] : members;
    final subsection = segments.length == 4 ? segments[3] : null;
    if (!coreSections.contains(section) ||
        !_validCoreSubsection(section, subsection)) {
      return null;
    }
    try {
      return GroupRoute.detail(
        groupName,
        section: section,
        subsection: subsection,
      );
    } on ArgumentError {
      return null;
    }
  }

  static bool _validCoreSubsection(String section, String? subsection) {
    if (subsection == null) return true;
    return switch (section) {
      activity => activitySubsections.contains(subsection),
      messages => messageSubsections.contains(subsection),
      manage => manageSubsections.contains(subsection),
      _ => false,
    };
  }

  static void _validateGroupName(String value) {
    if (!_isSafeSegment(value) || value.length > maximumGroupNameLength) {
      throw ArgumentError.value(value, 'groupName', 'Invalid group name.');
    }
  }

  static bool _isSafeSegment(String value) =>
      value.isNotEmpty &&
      value.trim() == value &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains('\u0000');

  static bool _isSafeToken(String value) =>
      _isSafeSegment(value) &&
      RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$').hasMatch(value);

  @override
  bool operator ==(Object other) =>
      other is GroupRoute &&
      other.groupName == groupName &&
      other.section == section &&
      other.subsection == subsection &&
      other.pluginOwner == pluginOwner;

  @override
  int get hashCode => Object.hash(groupName, section, subsection, pluginOwner);
}
