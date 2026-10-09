import 'package:discourse_native/discourse_plugin_sdk.dart';

const solvedPostKey = PluginDataKey<SolvedPost>(
  owner: 'discourse-solved',
  name: 'post',
);

final class SolvedPost {
  const SolvedPost({
    required this.accepted,
    required this.canAccept,
    required this.canUnaccept,
  });
  final bool accepted;
  final bool canAccept;
  final bool canUnaccept;

  static SolvedPost? fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('accepted_answer') &&
        !json.containsKey('can_accept_answer')) {
      return null;
    }
    return SolvedPost(
      accepted: json['accepted_answer'] == true,
      canAccept: json['can_accept_answer'] == true,
      canUnaccept: json['can_unaccept_answer'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SolvedPost &&
      accepted == other.accepted &&
      canAccept == other.canAccept &&
      canUnaccept == other.canUnaccept;
  @override
  int get hashCode => Object.hash(accepted, canAccept, canUnaccept);
}
