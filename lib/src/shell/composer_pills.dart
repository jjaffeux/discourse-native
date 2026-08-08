import '../models/found_hashtag.dart';

/// What the composer needs to know before it may draw a mention or a hashtag
/// as a pill.
///
/// Injected the way `resolveEmoji` is, and for the same reason: the shell owns
/// the site, the key and the caches, and the field only decides *when* to ask.
/// Null everywhere there is no site behind the composer — which is what leaves
/// every name as plain text in the tests and in a composer with nowhere to
/// send its question.
///
/// The composer asks before it draws, rather than pilling optimistically.
/// `@nobody` and `#TODO` cook as plain text, so a pill over either would be
/// the field claiming something the post will not do — which is the exact
/// failure the document-model composer was taken out for.
typedef ComposerPills = ({
  /// What a ref turned out to be, or null for "not asked yet, or not one".
  ///
  /// The two are deliberately the same answer here: both mean *do not draw a
  /// pill*, and telling them apart is [resolve]'s job, not the painter's.
  FoundHashtag? Function(String ref) hashtag,

  /// Whether the site confirmed this username, or null for "not asked yet".
  /// False is a real answer — nobody by that name — and is remembered.
  bool? Function(String username) mention,

  /// Asks about everything the field can currently see, in one round trip per
  /// kind. Called with what a repaint found unresolved; anything already known
  /// or already in flight is dropped by the implementation rather than here.
  void Function(Set<String> refs, Set<String> usernames) resolve,
});
