/// One account shown in a reaction's user list.
///
/// Post and Chat reaction endpoints happen to expose the same small user
/// shape, but their records, cache identities, reads, and writes belong to
/// different features. This interface is the neutral presentation boundary
/// both owners implement without sharing either feature's wire model.
abstract interface class ReactionUser {
  int get id;
  String get username;
  String? get name;
  String? get avatarUrl;
  String get reaction;
  String get displayName;
}

/// The page shape consumed by the shared reaction-user presentation.
///
/// Target identifiers and pagination remain in the feature-owned concrete
/// records. The UI needs only the bounded first page and the authoritative
/// total used to describe users not present in that page.
abstract interface class ReactionUsersPage {
  List<ReactionUser> get reactors;
  int get total;
}
