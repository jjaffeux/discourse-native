/// Post and Chat reaction endpoints happen to expose the same small user
/// shape without sharing either feature's wire model.
abstract interface class ReactionUser {
  int get id;
  String get username;
  String? get name;
  String? get avatarUrl;
  String get reaction;
  String get displayName;
}

abstract interface class ReactionUsersPage {
  List<ReactionUser> get reactors;
  int get total;
}
