import 'package:flutter/foundation.dart';

import 'json.dart';

@immutable
final class HomepageOption {
  const HomepageOption({required this.id, this.path, this.serverSide = false});

  final String id;
  final String? path;
  final bool serverSide;

  static List<HomepageOption>? read(Object? value, {required bool present}) {
    if (!present) return null;
    return List.unmodifiable([
      for (final row in jsonObjects(value).take(100))
        if (jsonText(row['id']) case final id?
            when id.isNotEmpty && id.length <= 128)
          HomepageOption(
            id: id,
            path: _localPath(jsonText(row['path'])),
            serverSide: row['server_side'] == true,
          ),
    ]);
  }

  static String? _localPath(String? path) {
    if (path == null ||
        path.length > 2048 ||
        !path.startsWith('/') ||
        RegExp(r'[\s\\]').hasMatch(path)) {
      return null;
    }
    final uri = Uri.tryParse(path);
    return uri != null && !uri.hasScheme && !uri.hasAuthority ? path : null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'server_side': serverSide,
  };

  @override
  bool operator ==(Object other) =>
      other is HomepageOption &&
      other.id == id &&
      other.path == path &&
      other.serverSide == serverSide;

  @override
  int get hashCode => Object.hash(id, path, serverSide);
}
