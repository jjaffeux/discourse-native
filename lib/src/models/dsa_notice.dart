import 'package:flutter/foundation.dart';

@immutable
final class DsaNoticeDraft {
  const DsaNoticeDraft({
    required this.contentUrl,
    required this.explanation,
    required this.name,
    required this.email,
    required this.declaration,
  });

  final String contentUrl;
  final String explanation;
  final String name;
  final String email;
  final bool declaration;

  static bool validEmail(String email) =>
      email.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());

  bool valid({required bool useAccountEmail}) {
    final url = Uri.tryParse(contentUrl.trim());
    return url != null &&
        const {'http', 'https'}.contains(url.scheme) &&
        url.host.isNotEmpty &&
        url.userInfo.isEmpty &&
        !RegExp(r'[\s<>]').hasMatch(contentUrl.trim()) &&
        contentUrl.trim().length <= 2048 &&
        explanation.trim().runes.length >= 50 &&
        explanation.trim().runes.length <= 20000 &&
        name.trim().isNotEmpty &&
        name.trim().runes.length <= 200 &&
        (useAccountEmail || validEmail(email)) &&
        declaration;
  }

  Map<String, Object?> toJson({required bool useAccountEmail}) => {
    'content_url': contentUrl.trim(),
    'explanation': explanation.trim(),
    'name': name.trim(),
    if (!useAccountEmail) 'email': email.trim().toLowerCase(),
    'declaration': declaration,
  };
}
